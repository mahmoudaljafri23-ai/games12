import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/user_service.dart';
import '../services/friends_service.dart';
import 'unlock_emojis_screen.dart';

class PublicProfileDialog extends StatefulWidget {
  final String uid;

  const PublicProfileDialog({super.key, required this.uid});

  @override
  State<PublicProfileDialog> createState() => _PublicProfileDialogState();
}

class _PublicProfileDialogState extends State<PublicProfileDialog> {
  final UserService _userService = UserService();
  final FriendsService _friendsService = FriendsService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  
  String _friendStatus = 'none';
  bool _isLoadingFriendStatus = true;

  @override
  void initState() {
    super.initState();
    _checkFriendStatus();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _playSound(String url) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
    } catch (_) {}
  }

  Future<void> _checkFriendStatus() async {
    if (widget.uid == _currentUserId) {
      setState(() => _isLoadingFriendStatus = false);
      return;
    }

    final status = await _friendsService.getFriendStatus(widget.uid);
    if (mounted) {
      setState(() {
        _friendStatus = status;
        _isLoadingFriendStatus = false;
      });
    }
  }

  void _sendFriendRequest(String name) async {
    setState(() => _isLoadingFriendStatus = true);
    await _friendsService.sendFriendRequest(widget.uid, name);
    if (mounted) {
      setState(() {
        _friendStatus = 'pending';
        _isLoadingFriendStatus = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال طلب صداقة إلى $name')),
      );
    }
  }

  void _acceptFriendRequest(String name) async {
    setState(() => _isLoadingFriendStatus = true);
    await _friendsService.acceptFriendRequest(widget.uid, name);
    if (mounted) {
      setState(() {
        _friendStatus = 'friend';
        _isLoadingFriendStatus = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أصبحت صديقاً لـ $name الآن!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.grey.shade900,
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (!snapshot.hasData || snapshot.data == null || !snapshot.data!.exists) {
            return const SizedBox(
              height: 200,
              child: Center(child: Text('اللاعب غير موجود')),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String name = data['name'] ?? 'لاعب';
          final int points = data['points'] ?? 0;
          final int level = data['level'] ?? 1;
          final int wins = data['wins'] ?? 0;
          final String presenceText = FriendsService.formatUserPresenceStatus(data);
          final bool isOnline = presenceText.contains('🟢') || presenceText.contains('🎮');
          final String avatarSeed = data['avatarSeed'] ?? UserService.availableAvatars[0];
          final String email = (data['email'] ?? '').toString().toLowerCase();
          final bool isCreator = email == 'mahmoud.aljafri23@gmail.com' || (data['isCreator'] ?? false);
          final List<dynamic> unlockedEmojis = data['unlockedEmojis'] ?? [];

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 46,
                        backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                        backgroundImage: UserService.getAvatarImageProvider(seed: avatarSeed, email: data['email']),
                      ),
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      if (isCreator) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade800,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.workspace_premium, color: Colors.amberAccent, size: 13),
                              SizedBox(width: 3),
                              Text(
                                'منشئ اللعبة 👑',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: #${data['serialId'] ?? UserService.generateSerialId(widget.uid)}',
                    style: const TextStyle(fontSize: 12, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'المستوى $level',
                        style: const TextStyle(fontSize: 14, color: Colors.deepPurpleAccent, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          presenceText,
                          style: TextStyle(
                            fontSize: 11,
                            color: isOnline ? Colors.greenAccent : Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          const Icon(Icons.stars, color: Colors.amber, size: 24),
                          const SizedBox(height: 2),
                          const Text('النقاط', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          Text('$points', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
                      Column(
                        children: [
                          const Icon(Icons.emoji_events, color: Colors.green, size: 24),
                          const SizedBox(height: 2),
                          const Text('الانتصارات', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          Text('$wins', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 8),

                  // Unlocked Sound Emojis Section
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '🎭 الإيموجيات الصوتية المكتسبة:',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: allSoundEmojis.map((item) {
                      final bool isUnlocked = isCreator || item.isDefaultFree || unlockedEmojis.contains(item.id);

                      return GestureDetector(
                        onTap: () {
                          if (isUnlocked) {
                            _playSound(item.soundUrl);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isUnlocked ? Colors.deepPurple.shade900.withValues(alpha: 0.5) : Colors.black45,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isUnlocked ? Colors.amberAccent : Colors.grey.shade800,
                              width: isUnlocked ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                children: [
                                  Text(
                                    item.emoji,
                                    style: TextStyle(
                                      fontSize: 26,
                                      color: isUnlocked ? null : Colors.grey,
                                    ),
                                  ),
                                  if (!isUnlocked)
                                    const Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Icon(Icons.lock, size: 12, color: Colors.grey),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.name,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: isUnlocked ? Colors.white : Colors.white38,
                                  fontWeight: isUnlocked ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 18),
                  if (widget.uid != _currentUserId) _buildFriendActionButton(name),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFriendActionButton(String name) {
    if (_isLoadingFriendStatus) {
      return const SizedBox(
        height: 45,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_friendStatus == 'friend') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Text('أصدقاء ✅', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );
    }

    if (_friendStatus == 'pending') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_top, color: Colors.amber, size: 18),
            SizedBox(width: 8),
            Text('طلب الصداقة معلّق ⏳', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );
    }

    if (_friendStatus == 'received') {
      return ElevatedButton.icon(
        onPressed: () => _acceptFriendRequest(name),
        icon: const Icon(Icons.check),
        label: const Text('قبول طلب الصداقة'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: () => _sendFriendRequest(name),
      icon: const Icon(Icons.person_add),
      label: const Text('إضافة كصديق'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
