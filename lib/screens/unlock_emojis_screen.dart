import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class SoundEmoji {
  final String id;
  final String emoji;
  final String name;
  final String soundUrl;
  final bool isDefaultFree;

  const SoundEmoji({
    required this.id,
    required this.emoji,
    required this.name,
    required this.soundUrl,
    this.isDefaultFree = false,
  });
}

final List<SoundEmoji> allSoundEmojis = const [
  SoundEmoji(
    id: 'laugh',
    emoji: '😂',
    name: 'ضحك ساخر',
    soundUrl: 'https://cdn.freesound.org/previews/538/538151_11861866-lq.mp3',
    isDefaultFree: true,
  ),
  SoundEmoji(
    id: 'angry',
    emoji: '😡',
    name: 'غاضب جدًا',
    soundUrl: 'https://cdn.freesound.org/previews/415/415209_5121236-lq.mp3',
    isDefaultFree: false,
  ),
  SoundEmoji(
    id: 'party',
    emoji: '🎉',
    name: 'احتفال وتصفيق',
    soundUrl: 'https://cdn.freesound.org/previews/456/456966_5121236-lq.mp3',
    isDefaultFree: true,
  ),
  SoundEmoji(
    id: 'shocked',
    emoji: '😮',
    name: 'مصدوم ومندهش',
    soundUrl: 'https://cdn.freesound.org/previews/341/341695_5858296-lq.mp3',
    isDefaultFree: false,
  ),
  SoundEmoji(
    id: 'crying',
    emoji: '😭',
    name: 'باكي وحزين',
    soundUrl: 'https://cdn.freesound.org/previews/517/517173_11308331-lq.mp3',
    isDefaultFree: false,
  ),
  SoundEmoji(
    id: 'poop',
    emoji: '💩',
    name: 'مضحك وسافر',
    soundUrl: 'https://cdn.freesound.org/previews/364/364658_6687700-lq.mp3',
    isDefaultFree: false,
  ),
  SoundEmoji(
    id: 'like',
    emoji: '👍',
    name: 'إعجاب وتشجيع',
    soundUrl: 'https://cdn.freesound.org/previews/270/270404_5121236-lq.mp3',
    isDefaultFree: true,
  ),
  SoundEmoji(
    id: 'crown',
    emoji: '👑',
    name: 'تاج الملك',
    soundUrl: 'https://cdn.freesound.org/previews/274/274178_5121236-lq.mp3',
    isDefaultFree: false,
  ),
];

class UnlockEmojisScreen extends StatefulWidget {
  const UnlockEmojisScreen({super.key});

  @override
  State<UnlockEmojisScreen> createState() => _UnlockEmojisScreenState();
}

class _UnlockEmojisScreenState extends State<UnlockEmojisScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();

  String get _currentUid => _auth.currentUser?.uid ?? '';
  String get _currentEmail => _auth.currentUser?.email ?? '';
  bool get _isCreator => _currentEmail == 'mahmoud.aljafri23@gmail.com';

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _playSound(String url) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      debugPrint("Error playing emoji sound: $e");
    }
  }

  void _watchAdToUnlock(SoundEmoji emoji) async {
    int remaining = 5;
    Timer? timer;

    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (remaining > 1) {
              setDialogState(() {
                remaining--;
              });
            } else {
              t.cancel();
              Navigator.pop(ctx, true);
            }
          });

          return AlertDialog(
            backgroundColor: Colors.grey.shade900,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.ondemand_video, color: Colors.amberAccent),
                const SizedBox(width: 8),
                Text('عرض الإعلان (${emoji.emoji})', style: const TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade900,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(emoji.emoji, style: const TextStyle(fontSize: 54)),
                      const SizedBox(height: 12),
                      Text('جاري عرض الإعلان المكافئ لفتح (${emoji.name})...', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      CircularProgressIndicator(value: (5 - remaining) / 5, color: Colors.amberAccent),
                      const SizedBox(height: 10),
                      Text('$remaining ثوانٍ متبقية', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (unlocked == true) {
      await _firestore.collection('users').doc(_currentUid).update({
        'unlockedEmojis': FieldValue.arrayUnion([emoji.id]),
      });

      _playSound(emoji.soundUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎉 مبروك! تم فتح إيموجي (${emoji.emoji} ${emoji.name}) بنجاح!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎭 متجر الإيموجيات والأصوات'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore.collection('users').doc(_currentUid).snapshots(),
        builder: (context, snapshot) {
          List<dynamic> unlockedList = [];
          if (snapshot.hasData && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            unlockedList = data?['unlockedEmojis'] ?? [];
          }

          return Column(
            children: [
              // Header Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.deepPurple.shade900, Colors.black87],
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      _isCreator ? '👑 حساب المنشئ الملكي' : '🎬 مشاهدة إعلانات لفتح الإيموجيات',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isCreator
                          ? 'حسابك مفعل به جميع الإيموجيات والأصوات مجاناً بدون الحاجة لمشاهدة إعلانات! 👑'
                          : 'شاهد إعلاناً قصيراً مدته 5 ثوانٍ لفتح أي إيموجي بصوت نهائياً واستخدامه باللعبة!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.9,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: allSoundEmojis.length,
                  itemBuilder: (context, index) {
                    final item = allSoundEmojis[index];
                    final bool isUnlocked = _isCreator || item.isDefaultFree || unlockedList.contains(item.id);

                    return Card(
                      color: isUnlocked ? Colors.grey.shade900 : Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isUnlocked ? Colors.amberAccent : Colors.grey.shade800,
                          width: isUnlocked ? 2 : 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () {
                          _playSound(item.soundUrl);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(item.emoji, style: const TextStyle(fontSize: 48)),
                              const SizedBox(height: 8),
                              Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                              const SizedBox(height: 8),
                              if (isUnlocked) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade900,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _isCreator ? '👑 ملكي (مفتوح)' : '✅ متاح واستماع',
                                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ] else ...[
                                ElevatedButton.icon(
                                  onPressed: () => _watchAdToUnlock(item),
                                  icon: const Icon(Icons.ondemand_video, size: 14),
                                  label: const Text('شاهد إعلان 🎬', style: TextStyle(fontSize: 11)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber.shade800,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
