import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_service.dart';

class FriendsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _currentUid => _auth.currentUser?.uid ?? '';

  // 1. Set User Online/Offline Status
  Future<void> setUserOnlineStatus(bool isOnline, {String currentRoomId = ''}) async {
    if (_currentUid.isEmpty) return;
    await _firestore.collection('users').doc(_currentUid).update({
      'isOnline': isOnline,
      'currentRoomId': currentRoomId,
      'lastActive': FieldValue.serverTimestamp(),
    });
  }

  // Helper to format presence status with accurate relative offline time
  static String formatUserPresenceStatus(Map<String, dynamic>? userData) {
    if (userData == null) return '🔴 مغلق';

    final bool isOnline = userData['isOnline'] ?? false;
    final String currentRoomId = userData['currentRoomId'] ?? '';
    final Timestamp? lastActive = userData['lastActive'] as Timestamp?;

    if (lastActive == null) {
      return '🔴 مغلق';
    }

    final DateTime lastActiveTime = lastActive.toDate();
    final Duration diff = DateTime.now().difference(lastActiveTime);

    // Truly online ONLY if isOnline flag is true AND refreshed within 90 seconds
    if (isOnline && diff.inSeconds < 90) {
      if (currentRoomId.isNotEmpty) {
        return '🎮 في لعبة (روم: $currentRoomId)';
      }
      return '🟢 متصل الآن';
    }

    // Accurate relative offline status
    if (diff.inSeconds < 60) {
      return '🔴 مغلق (منذ لحظات)';
    } else if (diff.inMinutes < 60) {
      final int mins = diff.inMinutes;
      return '🔴 مغلق منذ $mins ${mins == 1 ? 'دقيقة' : (mins == 2 ? 'دقيقتين' : 'دقائق')}';
    } else if (diff.inHours < 24) {
      final int hrs = diff.inHours;
      return '🔴 مغلق منذ $hrs ${hrs == 1 ? 'ساعة' : (hrs == 2 ? 'ساعتين' : 'ساعات')}';
    } else {
      final int days = diff.inDays;
      return '🔴 مغلق منذ $days ${days == 1 ? 'يوم' : (days == 2 ? 'يومين' : 'أيام')}';
    }
  }

  // 2. Search Users by Name, Email, or Serial ID
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.isEmpty) return [];
    
    // Clean query (remove # if user typed #123456)
    final String cleanQuery = query.replaceAll('#', '').trim();
    final String lowercaseQuery = cleanQuery.toLowerCase();

    // Query by Serial ID
    final serialQuery = await _firestore
        .collection('users')
        .where('serialId', isEqualTo: cleanQuery)
        .get();

    // Query by Name
    final nameQuery = await _firestore
        .collection('users')
        .where('name', isGreaterThanOrEqualTo: cleanQuery)
        .where('name', isLessThanOrEqualTo: '$cleanQuery\uf8ff')
        .get();

    // Query by Email
    final emailQuery = await _firestore
        .collection('users')
        .where('email', isGreaterThanOrEqualTo: lowercaseQuery)
        .where('email', isLessThanOrEqualTo: '$lowercaseQuery\uf8ff')
        .get();

    final List<Map<String, dynamic>> results = [];
    final Set<String> uids = {};

    void addResults(QuerySnapshot snapshot) {
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final uid = data['uid'];
        if (uid != _currentUid && !uids.contains(uid)) {
          uids.add(uid);
          results.add({
            'uid': uid,
            'name': data['name'] ?? 'لاعب',
            'email': data['email'] ?? '',
            'serialId': data['serialId'] ?? UserService.generateSerialId(uid),
          });
        }
      }
    }

    addResults(serialQuery);
    addResults(nameQuery);
    addResults(emailQuery);

    return results;
  }

  // 3. Send Friend Request
  Future<void> sendFriendRequest(String targetUid, String targetName) async {
    if (_currentUid.isEmpty || targetUid.isEmpty) return;

    // Get current user's name
    final currentUserDoc = await _firestore.collection('users').doc(_currentUid).get();
    final currentUserName = currentUserDoc.data()?['name'] ?? 'لاعب';

    // Write to sender's outgoing list
    await _firestore
        .collection('users')
        .doc(_currentUid)
        .collection('friends')
        .doc(targetUid)
        .set({
      'friendUid': targetUid,
      'name': targetName,
      'status': 'pending', // sent request
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Write to receiver's incoming list
    await _firestore
        .collection('users')
        .doc(targetUid)
        .collection('friends')
        .doc(_currentUid)
        .set({
      'friendUid': _currentUid,
      'name': currentUserName,
      'status': 'received', // received request
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // 4. Stream Incoming Friend Requests
  Stream<QuerySnapshot> streamFriendRequests() {
    return _firestore
        .collection('users')
        .doc(_currentUid)
        .collection('friends')
        .where('status', isEqualTo: 'received')
        .snapshots();
  }

  // 5. Accept Friend Request
  Future<void> acceptFriendRequest(String friendUid, String friendName) async {
    if (_currentUid.isEmpty) return;

    // Update current user's friend doc
    await _firestore
        .collection('users')
        .doc(_currentUid)
        .collection('friends')
        .doc(friendUid)
        .update({
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update friend's friend doc
    await _firestore
        .collection('users')
        .doc(friendUid)
        .collection('friends')
        .doc(_currentUid)
        .update({
      'status': 'accepted',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // 6. Decline or Cancel Friend Request
  Future<void> declineFriendRequest(String friendUid) async {
    if (_currentUid.isEmpty) return;

    await _firestore
        .collection('users')
        .doc(_currentUid)
        .collection('friends')
        .doc(friendUid)
        .delete();

    await _firestore
        .collection('users')
        .doc(friendUid)
        .collection('friends')
        .doc(_currentUid)
        .delete();
  }

  // 7. Stream Accepted Friends List
  Stream<QuerySnapshot> streamFriends() {
    return _firestore
        .collection('users')
        .doc(_currentUid)
        .collection('friends')
        .where('status', isEqualTo: 'accepted')
        .snapshots();
  }

  // 8. Stream Realtime User Online Status (since users collection contains isOnline & currentRoomId)
  Stream<DocumentSnapshot> streamUserStatus(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  // 9. Send Invitation to Room
  Future<void> inviteFriendToRoom(String friendUid, String roomId) async {
    if (_currentUid.isEmpty) return;

    final currentUserDoc = await _firestore.collection('users').doc(_currentUid).get();
    final currentUserName = currentUserDoc.data()?['name'] ?? 'لاعب';

    await _firestore
        .collection('users')
        .doc(friendUid)
        .collection('invitations')
        .doc(roomId)
        .set({
      'roomId': roomId,
      'invitedBy': currentUserName,
      'invitedByUid': _currentUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // 10. Stream Current User's Game Room Invitations
  Stream<QuerySnapshot> streamInvitations() {
    return _firestore
        .collection('users')
        .doc(_currentUid)
        .collection('invitations')
        .snapshots();
  }

  // 11. Decline / Dismiss Game Invitation
  Future<void> declineInvitation(String roomId) async {
    if (_currentUid.isEmpty) return;
    await _firestore
        .collection('users')
        .doc(_currentUid)
        .collection('invitations')
        .doc(roomId)
        .delete();
  }

  // 12. Check Relationship Status with another User
  Future<String> getFriendStatus(String targetUid) async {
    if (_currentUid.isEmpty || targetUid.isEmpty) return 'none';
    try {
      final doc = await _firestore
          .collection('users')
          .doc(_currentUid)
          .collection('friends')
          .doc(targetUid)
          .get();

      if (!doc.exists) return 'none';
      final status = doc.data()?['status'];
      if (status == 'accepted') return 'friend';
      if (status == 'pending') return 'pending';
      if (status == 'received') return 'received';
      return 'none';
    } catch (_) {
      return 'none';
    }
  }
}
