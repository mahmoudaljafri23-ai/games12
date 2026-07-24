import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Predefined Avatar seeds for DiceBear API
  static const List<String> availableAvatars = [
    'Felix', 'Aneka', 'Jack', 'Jude', 'Leo', 'Mia', 'Nala', 'Oliver', 'Salem', 'Sasha'
  ];

  static String getAvatarUrl(String seed) {
    return 'https://api.dicebear.com/7.x/adventurer/png?seed=$seed&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf';
  }

  // Get Avatar ImageProvider (Returns royal Creator Avatar asset for creator account)
  static dynamic getAvatarImageProvider({required String seed, String? email}) {
    if ((email ?? '').toLowerCase() == 'mahmoud.aljafri23@gmail.com' || seed == 'Creator') {
      return const AssetImage('assets/creator_avatar.jpg');
    }
    return NetworkImage(getAvatarUrl(seed));
  }

  // Generate deterministic 6-digit serial ID for a user if missing
  static String generateSerialId(String uid) {
    final int hash = uid.hashCode.abs();
    final int serialNum = (hash % 900000) + 100000; // Guaranteed 6-digit number
    return serialNum.toString();
  }

  // Ensure current user profile has a serialId
  Future<void> ensureUserSerialId(String uid) async {
    if (uid.isEmpty) return;
    final docRef = _firestore.collection('users').doc(uid);
    final doc = await docRef.get();
    if (doc.exists) {
      final data = doc.data();
      if (data != null && (data['serialId'] == null || (data['serialId'] as String).isEmpty)) {
        final serialId = generateSerialId(uid);
        await docRef.update({'serialId': serialId});
      }
    }
  }

  // Get current user profile stream
  Stream<DocumentSnapshot> streamCurrentUserProfile() {
    final user = _auth.currentUser;
    if (user == null) throw Exception('المستخدم غير مسجل الدخول');
    ensureUserSerialId(user.uid);
    return _firestore.collection('users').doc(user.uid).snapshots();
  }

  // Get any user profile stream
  Stream<DocumentSnapshot> streamUserProfile(String uid) {
    return _firestore.collection('users').doc(uid).snapshots();
  }

  // Get user profile Future
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['serialId'] == null) {
        data['serialId'] = generateSerialId(uid);
      }
      return data;
    }
    return null;
  }

  // Update Avatar
  Future<void> updateAvatar(String avatarSeed) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('users').doc(user.uid).update({
      'avatarSeed': avatarSeed,
    });
  }

  // Calculate Level based on points
  int calculateLevel(int points) {
    return (points ~/ 100) + 1;
  }

  // Add Points (ONLY called for winners at game end)
  Future<void> addPoints(String uid, int pointsToAdd, bool isWin) async {
    final docRef = _firestore.collection('users').doc(uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>;
      int currentPoints = data['points'] ?? 0;
      int currentMonthlyPoints = data['monthlyPoints'] ?? 0;
      int currentWins = data['wins'] ?? 0;
      int currentGamesPlayed = data['gamesPlayed'] ?? 0;

      int newPoints = currentPoints + pointsToAdd;
      int newLevel = calculateLevel(newPoints);

      transaction.update(docRef, {
        'points': newPoints,
        'monthlyPoints': currentMonthlyPoints + pointsToAdd,
        'level': newLevel,
        'wins': isWin ? currentWins + 1 : currentWins,
        'gamesPlayed': currentGamesPlayed + 1,
      });
    });
  }

  // Get Leaderboard (Top 50)
  Stream<QuerySnapshot> streamLeaderboard() {
    return _firestore
        .collection('users')
        .orderBy('monthlyPoints', descending: true)
        .limit(50)
        .snapshots();
  }
}
