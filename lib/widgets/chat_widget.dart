import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatWidget extends StatefulWidget {
  final String roomId;
  final String currentUserName;

  const ChatWidget({super.key, required this.roomId, required this.currentUserName});

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends State<ChatWidget> {
  final TextEditingController _controller = TextEditingController();
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    // Fetch real user name
    String realName = widget.currentUserName;
    if (realName == 'لاعب' || realName.isEmpty) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUid).get();
      if (userDoc.exists) {
        realName = userDoc.data()?['name'] ?? 'لاعب';
      }
    }

    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('chat')
        .add({
      'uid': _currentUid,
      'name': realName,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white24)),
            ),
            child: const Center(
              child: Text('الدردشة 💬', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
          SizedBox(
            height: 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rooms')
                  .doc(widget.roomId)
                  .collection('chat')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final bool isMe = data['uid'] == _currentUid;
                    final String name = data['name'] ?? 'لاعب';
                    final String text = data['text'] ?? '';

                    return Align(
                      alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.deepPurpleAccent : Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(12).copyWith(
                            bottomLeft: isMe ? const Radius.circular(0) : const Radius.circular(12),
                            bottomRight: !isMe ? const Radius.circular(0) : const Radius.circular(12),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Text(name, style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold)),
                            Text(text, style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالة...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.deepPurple,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void showChatSheet(BuildContext context, String roomId, String currentUserName) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ChatWidget(roomId: roomId, currentUserName: currentUserName),
  );
}
