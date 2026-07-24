import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/friends_service.dart';
import '../services/user_service.dart';

class PrivateChatScreen extends StatefulWidget {
  final String friendUid;
  final String friendName;
  final String avatarSeed;

  const PrivateChatScreen({
    super.key,
    required this.friendUid,
    required this.friendName,
    required this.avatarSeed,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late String _chatRoomId;

  @override
  void initState() {
    super.initState();
    // Generate consistent 1-to-1 chat room ID regardless of who initiates
    final uids = [_currentUid, widget.friendUid]..sort();
    _chatRoomId = 'chat_${uids[0]}_${uids[1]}';
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    await _firestore
        .collection('private_chats')
        .doc(_chatRoomId)
        .collection('messages')
        .add({
      'senderUid': _currentUid,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'deletedFor': [], // UIDs who deleted this message
    });

    // Get current user profile name
    final userDoc = await _firestore.collection('users').doc(_currentUid).get();
    final myName = userDoc.data()?['name'] ?? 'صديق';

    // Update last message summary for both friends
    await _firestore.collection('private_chats').doc(_chatRoomId).set({
      'lastMessage': text,
      'lastSenderUid': _currentUid,
      'lastSenderName': myName,
      'lastUpdated': FieldValue.serverTimestamp(),
      'participants': [_currentUid, widget.friendUid],
    }, SetOptions(merge: true));
  }

  void _deleteMessage(String messageId, List<dynamic> currentDeletedFor) async {
    final updatedDeletedFor = List<String>.from(currentDeletedFor)..add(_currentUid);
    await _firestore
        .collection('private_chats')
        .doc(_chatRoomId)
        .collection('messages')
        .doc(messageId)
        .update({
      'deletedFor': updatedDeletedFor,
    });
  }

  void _clearChatHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح الدردشة؟'),
        content: const Text('هل أنت متأكد من مسح المحادثة من حسابك؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final messages = await _firestore
          .collection('private_chats')
          .doc(_chatRoomId)
          .collection('messages')
          .get();

      for (var doc in messages.docs) {
        final List<dynamic> deletedFor = doc.data()['deletedFor'] ?? [];
        if (!deletedFor.contains(_currentUid)) {
          final updated = List<String>.from(deletedFor)..add(_currentUid);
          await doc.reference.update({'deletedFor': updated});
        }
      }

      await _firestore.collection('private_chats').doc(_chatRoomId).set({
        'clearedBy': {
          _currentUid: FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: NetworkImage(UserService.getAvatarUrl(widget.avatarSeed)),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.friendName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                StreamBuilder<DocumentSnapshot>(
                  stream: FriendsService().streamUserStatus(widget.friendUid),
                  builder: (context, snapshot) {
                    final userData = (snapshot.hasData && snapshot.data!.exists)
                        ? snapshot.data!.data() as Map<String, dynamic>?
                        : null;
                    final presenceText = FriendsService.formatUserPresenceStatus(userData);
                    final bool isOnline = presenceText.contains('🟢') || presenceText.contains('🎮');

                    return Text(
                      presenceText,
                      style: TextStyle(
                        fontSize: 11,
                        color: isOnline ? Colors.greenAccent : Colors.grey,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            tooltip: 'مسح الدردشة من حسابي',
            onPressed: _clearChatHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('private_chats')
                  .doc(_chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                final visibleDocs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final List<dynamic> deletedFor = data['deletedFor'] ?? [];
                  return !deletedFor.contains(_currentUid);
                }).toList();

                if (visibleDocs.isEmpty) {
                  return const Center(
                    child: Text('لا توجد رسائل بعد. أرسل تحية لصديقك! 👋'),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: visibleDocs.length,
                  itemBuilder: (context, index) {
                    final doc = visibleDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String senderUid = data['senderUid'] ?? '';
                    final String text = data['text'] ?? '';
                    final List<dynamic> deletedFor = data['deletedFor'] ?? [];
                    final bool isMe = senderUid == _currentUid;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (ctx) => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.delete, color: Colors.red),
                                  title: const Text('حذف الرسالة من عندي'),
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _deleteMessage(doc.id, deletedFor);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.deepPurple : Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            text,
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالة خاصة...',
                      filled: true,
                      fillColor: Colors.black26,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                  style: IconButton.styleFrom(backgroundColor: Colors.deepPurple),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
