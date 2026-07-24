import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../services/content_service.dart';
import '../services/voice_service.dart';
import '../services/friends_service.dart';
import '../services/user_service.dart';
import 'voting_screen.dart';
import 'friends_screen.dart';
import 'home_screen.dart';
import 'public_profile_dialog.dart';
import '../widgets/chat_widget.dart';
import 'admin_words_screen.dart';
import 'unlock_emojis_screen.dart';

class GameScreen extends StatefulWidget {
  final String roomId;
  const GameScreen({super.key, required this.roomId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  final ContentService _contentService = ContentService();
  final VoiceService _voiceService = VoiceService();
  final FriendsService _friendsService = FriendsService();
  final String _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  static const _vibrateChannel = MethodChannel('com.example.projectgoogl/vibrate');

  // Track turn & voice state changes
  int _lastTurnIndex = -1;
  int _lastRound = -1;
  bool? _lastVoiceState;

  // Emoji Overlay & Audio
  String? _lastEmojiId;
  String? _displayedEmoji;
  String? _displayedEmojiSender;
  bool _showEmojiOverlay = false;
  final AudioPlayer _emojiAudioPlayer = AudioPlayer();

  StreamSubscription<QuerySnapshot>? _chatSubscription;

  @override
  void initState() {
    super.initState();
    _friendsService.setUserOnlineStatus(true, currentRoomId: widget.roomId);
    _listenToChat();
  }

  void _listenToChat() {
    _chatSubscription = FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('chat')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final senderUid = data['uid'] ?? '';
          if (senderUid != _myUid) {
            _showQuickChatNotification(data['name'] ?? 'لاعب', data['text'] ?? '');
          }
        }
      }
    });
  }

  void _showQuickChatNotification(String name, String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.chat_bubble_outline, color: Colors.amberAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$name: $text',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.deepPurple.shade900,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _syncVoiceChat(bool hasVoiceChat) async {
    if (hasVoiceChat) {
      if (!_voiceService.isJoined) {
        try {
          await _voiceService.initialize();
          await _voiceService.joinChannel(widget.roomId, _myUid);
        } catch (e) {
          debugPrint('Error syncing voice chat in game: $e');
        }
      }
    } else {
      if (_voiceService.isJoined) {
        await _voiceService.leaveChannel();
      }
    }
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _emojiAudioPlayer.dispose();
    super.dispose();
  }

  Future<void> _sendHintChatMessage(String hintText) async {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(_myUid).get();
    final String name = userDoc.data()?['name'] ?? 'لاعب';

    await FirebaseFirestore.instance
        .collection('rooms')
        .doc(widget.roomId)
        .collection('chat')
        .add({
      'uid': _myUid,
      'name': name,
      'text': '💡 تلميح: $hintText',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _notifyMyTurn(bool hasVoiceChat) async {
    try {
      for (int i = 0; i < 4; i++) {
        await _vibrateChannel.invokeMethod('vibrate', {'duration': 400});
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (hasVoiceChat) {
        await _voiceService.forceLoudspeaker();
      }
    } catch (e) {
      debugPrint("Error vibrating: $e");
    }
  }

  void _handleIncomingEmoji(Map<String, dynamic>? activeEmoji) {
    if (activeEmoji == null) return;
    final String id = activeEmoji['id']?.toString() ?? '';
    final String emoji = activeEmoji['emoji'] ?? '';
    final String soundUrl = activeEmoji['soundUrl'] ?? '';
    final String senderName = activeEmoji['senderName'] ?? 'لاعب';

    if (id.isNotEmpty && id != _lastEmojiId) {
      _lastEmojiId = id;
      _displayedEmoji = emoji;
      _displayedEmojiSender = senderName;
      _showEmojiOverlay = true;

      if (soundUrl.isNotEmpty) {
        try {
          _emojiAudioPlayer.stop();
          _emojiAudioPlayer.play(UrlSource(soundUrl));
        } catch (e) {
          debugPrint("Error playing emoji audio: $e");
        }
      }

      if (mounted) setState(() {});

      Timer(const Duration(milliseconds: 2800), () {
        if (mounted) {
          setState(() {
            _showEmojiOverlay = false;
          });
        }
      });
    }
  }

  Future<void> _endMyTurn() async {
    await _contentService.advanceTurn(widget.roomId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('rooms').doc(widget.roomId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1E1E2C),
            body: Center(child: CircularProgressIndicator(color: Colors.amber)),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null || !snapshot.data!.exists) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('⚠️ تم إنهاء اللعبة أو إغلاق الغرفة')),
              );
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            }
          });
          return const Scaffold(
            backgroundColor: Color(0xFF1E1E2C),
            body: Center(child: CircularProgressIndicator(color: Colors.amber)),
          );
        }

        final roomData = snapshot.data!.data() as Map<String, dynamic>;
        final String status = roomData['status'] ?? 'playing';

        if (status == 'voting') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => VotingScreen(roomId: widget.roomId)),
              );
            }
          });
        }

        final List<dynamic> players = roomData['players'] ?? [];
        final String spyUid = roomData['spyUid'] ?? '';
        final bool iAmSpy = _myUid == spyUid;
        final int currentTurnIndex = roomData['currentTurnIndex'] ?? 0;
        final int currentRound = roomData['currentRound'] ?? 1;
        final int totalRounds = roomData['totalRounds'] ?? 5;
        final bool hasVoiceChat = roomData['hasVoiceChat'] ?? false;
        final int turnDuration = roomData['turnDurationSeconds'] ?? 60;
        final Map<String, dynamic>? content = roomData['content'] as Map<String, dynamic>?;
        final List<dynamic> activeMicPlayers = roomData['activeMicPlayers'] ?? [];
        final String gameMode = roomData['gameMode'] ?? 'group_word';
        final Map<String, dynamic>? playerImages = roomData['playerImages'] as Map<String, dynamic>?;
        final Map<String, dynamic>? activeEmoji = roomData['activeEmoji'] as Map<String, dynamic>?;

        _handleIncomingEmoji(activeEmoji);

        if (_lastVoiceState != hasVoiceChat) {
          _lastVoiceState = hasVoiceChat;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncVoiceChat(hasVoiceChat);
          });
        }

        final currentTurnPlayer = currentTurnIndex < players.length
            ? players[currentTurnIndex] as Map<String, dynamic>
            : null;
        final bool isMyTurn = currentTurnPlayer?['uid'] == _myUid;

        final bool turnChanged =
            currentTurnIndex != _lastTurnIndex || currentRound != _lastRound;
        if (turnChanged) {
          _lastTurnIndex = currentTurnIndex;
          _lastRound = currentRound;
          if (isMyTurn) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _notifyMyTurn(hasVoiceChat);
            });
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(gameMode == 'duo_image' ? 'لعبة الصور (شخصين) 📸' : 'غرفة: ${widget.roomId}'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.emoji_emotions, color: Colors.amberAccent),
                onPressed: () => _showEmojiSelectorBottomSheet(context),
                tooltip: 'إرسال إيموجي صوتي 🎭',
              ),
              IconButton(
                icon: const Icon(Icons.chat, color: Colors.blueAccent),
                onPressed: () {
                  showChatSheet(context, widget.roomId, 'لاعب');
                },
              ),
              IconButton(
                icon: const Icon(Icons.person_add, color: Colors.amber),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FriendsScreen()),
                ),
                tooltip: 'إضافة صديق',
              ),
            ],
          ),
          body: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/game_bg.jpg'),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(Colors.black54, BlendMode.darken),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      _buildTurnBanner(currentTurnPlayer, isMyTurn, turnDuration, currentRound, totalRounds, gameMode, currentTurnIndex),
                      const Divider(height: 1),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              if (gameMode == 'duo_image')
                                _buildDuoContentView(playerImages)
                              else
                                _buildContentView(iAmSpy, content),

                              const SizedBox(height: 24),

                              if (hasVoiceChat && activeMicPlayers.isNotEmpty && !isMyTurn)
                                _buildMicStatusBanner(players, activeMicPlayers),

                              const SizedBox(height: 16),
                              _buildPlayerList(players, currentTurnIndex, activeMicPlayers, spyUid),
                            ],
                          ),
                        ),
                      ),
                      _buildBottomBar(isMyTurn, hasVoiceChat, gameMode),
                    ],
                  ),
                ),
              ),

              // Animated Sound Emoji Floating Overlay
              if (_showEmojiOverlay)
                Positioned(
                  top: 180,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.amberAccent, width: 2.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black87, blurRadius: 20, spreadRadius: 2),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_displayedEmojiSender أرسل:',
                              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _displayedEmoji ?? '😂',
                              style: const TextStyle(fontSize: 72),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showEmojiSelectorBottomSheet(BuildContext context) {
    final String myEmail = (FirebaseAuth.instance.currentUser?.email ?? '').toLowerCase();
    final bool isCreator = myEmail == 'mahmoud.aljafri23@gmail.com';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(_myUid).snapshots(),
          builder: (context, snapshot) {
            List<dynamic> unlockedList = [];
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              unlockedList = data?['unlockedEmojis'] ?? [];
            }

            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🎭 اختيار إيموجي بصوت',
                        style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: allSoundEmojis.map((item) {
                      final bool isUnlocked = isCreator || item.isDefaultFree || unlockedList.contains(item.id);

                      return GestureDetector(
                        onTap: () async {
                          if (isUnlocked) {
                            Navigator.pop(ctx);
                            final userDoc = await FirebaseFirestore.instance.collection('users').doc(_myUid).get();
                            final String myName = userDoc.data()?['name'] ?? 'لاعب';

                            await FirebaseFirestore.instance.collection('rooms').doc(widget.roomId).update({
                              'activeEmoji': {
                                'id': DateTime.now().millisecondsSinceEpoch.toString(),
                                'emoji': item.emoji,
                                'soundUrl': item.soundUrl,
                                'senderName': myName,
                              },
                            });
                          } else {
                            Navigator.pop(ctx);
                            _showUnlockEmojiPromptDialog(item);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isUnlocked ? Colors.deepPurple.shade900 : Colors.black45,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isUnlocked ? Colors.amberAccent : Colors.grey.shade800,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                children: [
                                  Text(item.emoji, style: const TextStyle(fontSize: 36)),
                                  if (!isUnlocked)
                                    const Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: CircleAvatar(
                                        radius: 10,
                                        backgroundColor: Colors.black87,
                                        child: Icon(Icons.lock, size: 12, color: Colors.amber),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(item.name, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showUnlockEmojiPromptDialog(SoundEmoji item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: Text('🎬 فتح إيموجي (${item.emoji} ${item.name})'),
        content: const Text('هذا الإيموجي مقفل! يمكنك مشاهدة إعلان مدته 5 ثوانٍ لفتحه واستخدامه دائماً!'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UnlockEmojisScreen()),
              );
            },
            icon: const Icon(Icons.ondemand_video),
            label: const Text('فتح في مركز الإعلانات 🎬'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnBanner(
    Map<String, dynamic>? currentTurnPlayer,
    bool isMyTurn,
    int turnDuration,
    int currentRound,
    int totalRounds,
    String gameMode,
    int currentTurnIndex,
  ) {
    final String turnName = currentTurnPlayer?['name'] ?? '...';
    final Color bgColor = isMyTurn ? Colors.deepPurple : Colors.grey.shade800;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: bgColor,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'الجولة $currentRound',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isMyTurn ? '🎯 دورك الآن!' : 'دور: $turnName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!isMyTurn)
                Text(
                  'استعد للإجابة...',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                ),
            ],
          ),
          _CountdownTimerWidget(
            key: ValueKey('timer_${currentTurnIndex}_$currentRound'),
            duration: turnDuration,
            turnKey: currentTurnIndex + (currentRound * 1000),
            onTimerEnded: () {
              if (isMyTurn) {
                _endMyTurn();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDuoContentView(Map<String, dynamic>? playerImages) {
    Map<String, dynamic>? myImageData;

    if (playerImages != null) {
      if (playerImages[_myUid] != null) {
        myImageData = playerImages[_myUid] as Map<String, dynamic>?;
      } else if (playerImages.isNotEmpty) {
        myImageData = playerImages.values.first as Map<String, dynamic>?;
      }
    }

    final String title = myImageData?['title'] ?? 'صورتك السرية';
    final String url = (myImageData?['url'] != null && myImageData!['url'].toString().isNotEmpty)
        ? myImageData['url'].toString()
        : 'assets/duo_1.jpg';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amberAccent, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.lock, color: Colors.amberAccent, size: 20),
              SizedBox(width: 6),
              Text(
                'صورتك السرية (لا تظهر للخصم):',
                style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.grey.shade900,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.amberAccent)),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            constraints: const BoxConstraints(maxHeight: 380),
                            child: buildAdminImageWidget(url, fit: BoxFit.contain),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إغلاق والمعاينة'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 8),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: buildAdminImageWidget(url, width: 130, height: 130, fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          const Text(
            '💡 اسأل شريكك وتحدثا لتكشف ما هي صورته قبل أن يعرف صورتك!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildContentView(bool iAmSpy, Map<String, dynamic>? content) {
    if (iAmSpy) {
      final TextEditingController hintController = TextEditingController();

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent, width: 2),
        ),
        child: Column(
          children: [
            const Icon(Icons.security, color: Colors.redAccent, size: 48),
            const SizedBox(height: 8),
            const Text(
              '🕵️ أنت الجاسوس!',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'حاول اكتشاف الكلمة الخفية من تلميحات الآخرين دون أن يعرفوا أنك الجاسوس!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    '💡 إرسال تلميح مموّه:',
                    style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hintController,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'اكتب تلميحاً زائفاً...',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          final text = hintController.text.trim();
                          if (text.isNotEmpty) {
                            _sendHintChatMessage(text);
                            hintController.clear();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم إرسال التلميح في الشات 💡')),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
                        child: const Text('إرسال'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (content == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple, width: 2),
      ),
      child: Column(
        children: [
          Text(
            content['type'] == 'image' ? '🖼️ الصورة الخفية:' : '💬 الكلمة الخفية:',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          if (content['type'] == 'image')
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                content['value'],
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image, size: 80),
              ),
            )
          else
            Text(
              content['value'] ?? '',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          if (content['category'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'الفئة: ${content['category']}',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'لا تقل الكلمة بصراحة!\nأجب باستخدام التلميحات فقط.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMicStatusBanner(List<dynamic> players, List<dynamic> activeMicPlayers) {
    final speakingNames = players
        .where((p) => activeMicPlayers.contains(p['uid']))
        .map((p) => p['name'] ?? 'لاعب')
        .join(', ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade900.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green, width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.volume_up, color: Colors.greenAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '🔊 يتحدثون الآن: $speakingNames',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerList(
    List<dynamic> players,
    int currentTurnIndex,
    List<dynamic> activeMicPlayers,
    String spyUid,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'اللاعبون:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...players.asMap().entries.map((entry) {
          final int index = entry.key;
          final Map<String, dynamic> player = entry.value;
          final String uid = player['uid'];
          final String name = player['name'] ?? 'لاعب';
          final bool isCurrentTurn = index == currentTurnIndex;
          final bool isSpeaking = activeMicPlayers.contains(uid);
          final bool isMe = uid == _myUid;
          final String avatarSeed = player['avatarSeed'] ?? 'Felix';
          final bool showSenderReaction = _showEmojiOverlay && (_displayedEmojiSender == name || _displayedEmojiSender == uid);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: isCurrentTurn
                ? Colors.deepPurple.withValues(alpha: 0.3)
                : Colors.grey.shade900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: isCurrentTurn ? Colors.amber : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: ListTile(
              dense: true,
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => PublicProfileDialog(uid: uid),
                );
              },
              leading: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isCurrentTurn ? Colors.amber : Colors.deepPurple,
                    backgroundImage: NetworkImage(UserService.getAvatarUrl(avatarSeed)),
                  ),
                  if (showSenderReaction)
                    Positioned(
                      right: -10,
                      top: -20,
                      child: AnimatedScale(
                        scale: showSenderReaction ? 1.25 : 0.0,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.elasticOut,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.amberAccent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Colors.amber, blurRadius: 10, spreadRadius: 2),
                            ],
                          ),
                          child: Text(_displayedEmoji ?? '😂', style: const TextStyle(fontSize: 24)),
                        ),
                      ),
                    ),
                ],
              ),
              title: Text(
                name + (isMe ? ' (أنت)' : ''),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: isCurrentTurn
                  ? const Text('▶ دوره الآن', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isSpeaking)
                    const Icon(Icons.mic, color: Colors.green, size: 18),
                  if (!isSpeaking && activeMicPlayers.isNotEmpty)
                    const Icon(Icons.mic_off, color: Colors.grey, size: 18),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _triggerVoting(String gameMode) async {
    final bool isDuo = gameMode == 'duo_image';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDuo ? '🏆 كشف الصور وتحديد الفائز' : '🗳️ بدأ التصويت؟'),
        content: Text(isDuo
            ? 'هل انتهيتم من الحديث وتودون كشف الصور السرية الآن واختيار الفائز بالتخمين؟'
            : 'هل أنت متأكد أنك تريد بدء التصويت الآن لكشف الجاسوس؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: isDuo ? Colors.amber.shade800 : Colors.orange),
            child: Text(isDuo ? '🏆 كشف الصور الآن' : 'نعم، ابدأ التصويت'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _voiceService.closeAllMics(widget.roomId);
      await FirebaseFirestore.instance
          .collection('rooms')
          .doc(widget.roomId)
          .update({
        'status': 'voting',
        'activeMicPlayers': [],
      });
    }
  }

  Widget _buildBottomBar(bool isMyTurn, bool hasVoiceChat, String gameMode) {
    final bool isDuo = gameMode == 'duo_image';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        border: Border(top: BorderSide(color: Colors.grey.shade700)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: ElevatedButton.icon(
              onPressed: isMyTurn ? _endMyTurn : null,
              icon: const Icon(Icons.skip_next),
              label: const Text('انتهى دوري', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: isMyTurn ? Colors.deepPurple : Colors.grey.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: ElevatedButton.icon(
              onPressed: () => _triggerVoting(gameMode),
              icon: Icon(isDuo ? Icons.emoji_events : Icons.how_to_vote, size: 18),
              label: Text(isDuo ? '🏆 كشف الصور' : 'تصويت', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: isDuo ? Colors.amber.shade800 : Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountdownTimerWidget extends StatefulWidget {
  final int duration;
  final int turnKey;
  final VoidCallback onTimerEnded;

  const _CountdownTimerWidget({
    super.key,
    required this.duration,
    required this.turnKey,
    required this.onTimerEnded,
  });

  @override
  State<_CountdownTimerWidget> createState() => _CountdownTimerWidgetState();
}

class _CountdownTimerWidgetState extends State<_CountdownTimerWidget> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.duration;
    _startTimer();
  }

  @override
  void didUpdateWidget(_CountdownTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turnKey != widget.turnKey) {
      _timer?.cancel();
      _remainingSeconds = widget.duration;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        widget.onTimerEnded();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double progress = widget.duration > 0 ? _remainingSeconds / widget.duration : 0.0;
    final Color timerColor = _remainingSeconds > 15
        ? Colors.green
        : _remainingSeconds > 5
            ? Colors.orange
            : Colors.red;

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 50,
          height: 50,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 4,
            backgroundColor: Colors.white24,
            color: timerColor,
          ),
        ),
        Text(
          '$_remainingSeconds',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: timerColor,
          ),
        ),
      ],
    );
  }
}
