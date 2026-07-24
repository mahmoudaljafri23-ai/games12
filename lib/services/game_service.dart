import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GameService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Generate a random 6-digit room code
  String _generateRoomCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  // 1. Create a Room
  Future<String> createRoom(
    String hostName, {
    int maxPlayers = 4,
    bool hasVoiceChat = false,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('المستخدم غير سجل دخول');

    // Clamp between 2 and 10
    maxPlayers = maxPlayers.clamp(2, 10);

    String roomId = _generateRoomCode();

    // Ensure roomId is unique in Firestore
    DocumentSnapshot doc = await _firestore.collection('rooms').doc(roomId).get();
    while (doc.exists) {
      roomId = _generateRoomCode();
      doc = await _firestore.collection('rooms').doc(roomId).get();
    }

    // Fetch host profile data
    int level = 1;
    String avatarSeed = 'Felix';
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      final userData = userDoc.data() as Map<String, dynamic>;
      level = userData['level'] ?? 1;
      avatarSeed = userData['avatarSeed'] ?? 'Felix';
    }

    final playerData = {
      'uid': user.uid,
      'name': hostName,
      'isHost': true,
      'isReady': true,
      'isMuted': false,
      'level': level,
      'avatarSeed': avatarSeed,
    };

    await _firestore.collection('rooms').doc(roomId).set({
      'roomId': roomId,
      'hostId': user.uid,
      'hostName': hostName,
      'status': 'waiting', // waiting, playing, finished
      'maxPlayers': maxPlayers,
      'hasVoiceChat': hasVoiceChat,
      'createdAt': FieldValue.serverTimestamp(),
      'players': [playerData],
      'activeMicPlayers': [],
    });

    return roomId;
  }

  // Create a 2-Player Duo Game Room directly
  Future<String> createDuoRoom(String hostName) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل دخول');

    String roomId = _generateRoomCode();
    DocumentSnapshot doc = await _firestore.collection('rooms').doc(roomId).get();
    while (doc.exists) {
      roomId = _generateRoomCode();
      doc = await _firestore.collection('rooms').doc(roomId).get();
    }

    int level = 1;
    String avatarSeed = 'Felix';
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      final userData = userDoc.data() as Map<String, dynamic>;
      level = userData['level'] ?? 1;
      avatarSeed = userData['avatarSeed'] ?? 'Felix';
    }

    final playerData = {
      'uid': user.uid,
      'name': hostName,
      'isHost': true,
      'isReady': true,
      'isMuted': false,
      'level': level,
      'avatarSeed': avatarSeed,
    };

    await _firestore.collection('rooms').doc(roomId).set({
      'roomId': roomId,
      'hostId': user.uid,
      'hostName': hostName,
      'status': 'waiting',
      'maxPlayers': 2,
      'gameMode': 'duo_image',
      'hasVoiceChat': false,
      'createdAt': FieldValue.serverTimestamp(),
      'players': [playerData],
      'activeMicPlayers': [],
    });

    return roomId;
  }

  // 2. Join Room by Code
  Future<String?> joinRoom(String roomId, String playerName) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('المستخدم غير سجل دخول');

    // Fetch user profile data
    int level = 1;
    String avatarSeed = 'Felix';
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      final userData = userDoc.data() as Map<String, dynamic>;
      level = userData['level'] ?? 1;
      avatarSeed = userData['avatarSeed'] ?? 'Felix';
    }

    final roomDocRef = _firestore.collection('rooms').doc(roomId);

    return await _firestore.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(roomDocRef);

      if (!snapshot.exists) {
        throw Exception('الغرفة غير موجودة');
      }

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
      String status = data['status'];
      List<dynamic> players = List.from(data['players']);
      int maxPlayers = data['maxPlayers'] ?? 4;

      if (status != 'waiting') {
        throw Exception('اللعبة بدأت بالفعل في هذه الغرفة');
      }

      // Check if player is already in the room
      bool isAlreadyIn = players.any((p) => p['uid'] == user.uid);
      if (isAlreadyIn) {
        return roomId; // Already in the room, just return roomId
      }

      if (players.length >= maxPlayers) {
        throw Exception('الغرفة ممتلئة (الحد الأقصى $maxPlayers لاعبين)');
      }

      final newPlayer = {
        'uid': user.uid,
        'name': playerName,
        'isHost': false,
        'isReady': false,
        'isMuted': false,
        'level': level,
        'avatarSeed': avatarSeed,
      };

      players.add(newPlayer);
      transaction.update(roomDocRef, {'players': players});

      return roomId;
    });
  }

  // 3. Join Random Room
  Future<String?> joinRandomRoom(String playerName) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('المستخدم غير سجل دخول');

    // Query for rooms in 'waiting' status
    QuerySnapshot querySnapshot = await _firestore
        .collection('rooms')
        .where('status', isEqualTo: 'waiting')
        .limit(10)
        .get();

    for (var doc in querySnapshot.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      List<dynamic> players = data['players'];
      int maxPlayers = data['maxPlayers'] ?? 4;

      if (players.length < maxPlayers) {
        try {
          String roomId = doc.id;
          await joinRoom(roomId, playerName);
          return roomId;
        } catch (e) {
          // If transaction fails, try next room
          continue;
        }
      }
    }

    // No available room, create a new one as host
    return await createRoom(playerName);
  }

  // 4. Leave Room (supports targetUid for auto-evicting inactive players after 3 minutes)
  Future<void> leaveRoom(String roomId, {String? targetUid}) async {
    final String uidToRemove = targetUid ?? _auth.currentUser?.uid ?? '';
    if (uidToRemove.isEmpty) return;

    final roomDocRef = _firestore.collection('rooms').doc(roomId);

    await _firestore.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(roomDocRef);
      if (!snapshot.exists) return;

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
      List<dynamic> players = List.from(data['players']);
      String hostId = data['hostId'];

      // Remove player
      players.removeWhere((p) => p['uid'] == uidToRemove);

      if (players.isEmpty) {
        // If room is empty, delete it
        transaction.delete(roomDocRef);
      } else {
        // If host leaves, assign next player as host
        if (hostId == uidToRemove) {
          final nextPlayer = players.first;
          nextPlayer['isHost'] = true;
          nextPlayer['isReady'] = true;

          transaction.update(roomDocRef, {
            'players': players,
            'hostId': nextPlayer['uid'],
            'hostName': nextPlayer['name'],
          });
        } else {
          transaction.update(roomDocRef, {'players': players});
        }
      }
    });
  }

  // Stream Room State
  Stream<DocumentSnapshot> streamRoom(String roomId) {
    return _firestore.collection('rooms').doc(roomId).snapshots();
  }

  // Toggle Ready Status
  Future<void> toggleReady(String roomId, bool isReady) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final roomDocRef = _firestore.collection('rooms').doc(roomId);

    await _firestore.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(roomDocRef);
      if (!snapshot.exists) return;

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
      List<dynamic> players = List.from(data['players']);

      for (var player in players) {
        if (player['uid'] == user.uid) {
          player['isReady'] = isReady;
          break;
        }
      }

      transaction.update(roomDocRef, {'players': players});
    });
  }

  // Toggle Mute Status
  Future<void> toggleMute(String roomId, bool isMuted) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final roomDocRef = _firestore.collection('rooms').doc(roomId);

    await _firestore.runTransaction((transaction) async {
      DocumentSnapshot snapshot = await transaction.get(roomDocRef);
      if (!snapshot.exists) return;

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
      List<dynamic> players = List.from(data['players']);

      for (var player in players) {
        if (player['uid'] == user.uid) {
          player['isMuted'] = isMuted;
          break;
        }
      }

      transaction.update(roomDocRef, {'players': players});
    });
  }
}
