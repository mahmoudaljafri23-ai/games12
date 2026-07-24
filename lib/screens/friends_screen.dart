import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/friends_service.dart';
import '../services/game_service.dart';
import 'game_room_screen.dart';

import 'private_chat_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final FriendsService _friendsService = FriendsService();
  final GameService _gameService = GameService();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  void _onSearch() async {
    String query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final results = await _friendsService.searchUsers(query);
      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('خطأ في البحث: $e')),
      );
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _sendFriendRequest(String uid, String name) async {
    try {
      await _friendsService.sendFriendRequest(uid, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال طلب صداقة إلى $name')),
        );
        setState(() {
          _searchResults.removeWhere((user) => user['uid'] == uid);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إرسال الطلب: $e')),
        );
      }
    }
  }

  void _acceptRequest(String uid, String name) async {
    try {
      await _friendsService.acceptFriendRequest(uid, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('أصبحت صديقاً لـ $name الآن!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل قبول الطلب: $e')),
        );
      }
    }
  }

  void _declineRequest(String uid) async {
    try {
      await _friendsService.declineFriendRequest(uid);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إلغاء الطلب: $e')),
        );
      }
    }
  }

  void _joinFriendRoom(String roomId) async {
    setState(() {
      _isSearching = true; // Show loading
    });
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      // Get current player name
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
        final playerName = userDoc.data()?['name'] ?? 'لاعب';
        
        String? joinedRoomId = await _gameService.joinRoom(roomId, playerName);
        if (joinedRoomId != null) {
          navigator.push(
            MaterialPageRoute(builder: (context) => GameRoomScreen(roomId: joinedRoomId)),
          );
        }
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('فشل الانضمام لغرفة صديقك: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الأصدقاء'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'قائمة الأصدقاء'),
              Tab(icon: Icon(Icons.person_add), text: 'إضافة/طلبات'),
            ],
          ),
        ),
        body: _isSearching
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  // Tab 1: Friends List
                  _buildFriendsList(),
                  
                  // Tab 2: Add Friends & Incoming Requests
                  _buildAddFriendsTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildFriendsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _friendsService.streamFriends(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('ليس لديك أصدقاء بعد. ابحث عنهم في التبويب الثاني!'),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final String friendUid = data['friendUid'];
            final String friendName = data['name'] ?? 'لاعب';

            // Real-time listener for each friend's online status
            return StreamBuilder<DocumentSnapshot>(
              stream: _friendsService.streamUserStatus(friendUid),
              builder: (context, statusSnapshot) {
                Map<String, dynamic>? statusData;
                if (statusSnapshot.hasData && statusSnapshot.data!.exists) {
                  statusData = statusSnapshot.data!.data() as Map<String, dynamic>?;
                }

                final String presenceStatus = FriendsService.formatUserPresenceStatus(statusData);
                final bool isTrulyOnline = presenceStatus.contains('🟢') || presenceStatus.contains('🎮');
                final String currentRoomId = isTrulyOnline ? (statusData?['currentRoomId'] ?? '') : '';

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: Badge(
                      backgroundColor: isTrulyOnline ? Colors.green : Colors.grey,
                      smallSize: 12,
                      child: const CircleAvatar(
                        backgroundColor: Colors.deepPurple,
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                    ),
                    title: Text(friendName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      presenceStatus,
                      style: TextStyle(
                        color: isTrulyOnline ? Colors.greenAccent : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chat_bubble, color: Colors.deepPurpleAccent),
                          tooltip: 'محادثة خاصة',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PrivateChatScreen(
                                  friendUid: friendUid,
                                  friendName: friendName,
                                  avatarSeed: 'Felix',
                                ),
                              ),
                            );
                          },
                        ),
                        if (isTrulyOnline && currentRoomId.isNotEmpty)
                          ElevatedButton.icon(
                            onPressed: () => _joinFriendRoom(currentRoomId),
                            icon: const Icon(Icons.login, size: 16),
                            label: const Text('انضمام'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.grey),
                          onPressed: () => _declineRequest(friendUid),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAddFriendsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'ابحث باسم، بريد، أو رقم الـ ID (#123456)',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _onSearch(),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _onSearch,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
                child: const Icon(Icons.search),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Search Results
          if (_searchResults.isNotEmpty) ...[
            const Text(
              'نتائج البحث:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final user = _searchResults[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(user['name']),
                    subtitle: Text('ID: #${user['serialId']}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    trailing: ElevatedButton(
                      onPressed: () => _sendFriendRequest(user['uid'], user['name']),
                      child: const Text('إضافة'),
                    ),
                  ),
                );
              },
            ),
            const Divider(height: 40),
          ],

          // Incoming Friend Requests
          const Text(
            'طلبات الصداقة الواردة:',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot>(
            stream: _friendsService.streamFriendRequests(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('لا توجد طلبات صداقة معلقة')),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final String friendUid = data['friendUid'];
                  final String friendName = data['name'] ?? 'لاعب';

                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person_add)),
                      title: Text(friendName),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            onPressed: () => _acceptRequest(friendUid, friendName),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () => _declineRequest(friendUid),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
