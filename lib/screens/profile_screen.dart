import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/user_service.dart';
import 'unlock_emojis_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  final AudioPlayer _audioPlayer = AudioPlayer();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الملف الشخصي'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _userService.streamCurrentUserProfile(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final String name = data['name'] ?? 'لاعب';
          final int points = data['points'] ?? 0;
          final int level = data['level'] ?? 1;
          final int wins = data['wins'] ?? 0;
          final String avatarSeed = data['avatarSeed'] ?? UserService.availableAvatars[0];
          final String email = (data['email'] ?? '').toString().toLowerCase();
          final bool isCreator = email == 'mahmoud.aljafri23@gmail.com';
          final List<dynamic> unlockedEmojis = data['unlockedEmojis'] ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                  backgroundImage: UserService.getAvatarImageProvider(seed: avatarSeed, email: data['email']),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                Text(
                  'المستوى $level',
                  style: const TextStyle(fontSize: 18, color: Colors.deepPurple),
                ),
                const SizedBox(height: 30),

                // Stats Cards
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatCard(Icons.stars, 'النقاط', '$points', Colors.amber),
                    _buildStatCard(Icons.emoji_events, 'الانتصارات', '$wins', Colors.green),
                  ],
                ),
                const SizedBox(height: 30),

                // Change Avatar Section
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'تغيير الصورة الشخصية:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: UserService.availableAvatars.length,
                    itemBuilder: (context, index) {
                      final seed = UserService.availableAvatars[index];
                      final isSelected = seed == avatarSeed;
                      return GestureDetector(
                        onTap: () {
                          _userService.updateAvatar(seed);
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.deepPurple : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 35,
                            backgroundColor: Colors.grey.withValues(alpha: 0.1),
                            backgroundImage: NetworkImage(UserService.getAvatarUrl(seed)),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 30),

                // Unlocked Sound Emojis Section
                _buildEmojisSection(unlockedEmojis, isCreator),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String title, String value, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 16, color: Colors.grey)),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojisSection(List<dynamic> unlockedList, bool isCreator) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '🎭 الإيموجيات الصوتية المكتسبة:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (isCreator)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('👑 كافّة الإيموجيات مفعّلة', style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: allSoundEmojis.map((item) {
            final bool isUnlocked = isCreator || item.isDefaultFree || unlockedList.contains(item.id);

            return GestureDetector(
              onTap: () {
                if (isUnlocked) {
                  _playSound(item.soundUrl);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isUnlocked ? Colors.deepPurple.shade900.withValues(alpha: 0.4) : Colors.black38,
                  borderRadius: BorderRadius.circular(14),
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
                            fontSize: 34,
                            color: isUnlocked ? null : Colors.grey,
                          ),
                        ),
                        if (!isUnlocked)
                          const Positioned(
                            right: 0,
                            bottom: 0,
                            child: Icon(Icons.lock, size: 14, color: Colors.grey),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 10,
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
      ],
    );
  }
}
