import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/game_service.dart';
import '../services/friends_service.dart';
import '../services/content_service.dart';
import '../services/voice_service.dart';
import 'game_screen.dart';
import 'home_screen.dart';
import 'friends_screen.dart';
import 'public_profile_dialog.dart';
import '../widgets/chat_widget.dart';

class GameRoomScreen extends StatefulWidget {
  final String roomId;
  const GameRoomScreen({super.key, required this.roomId});

  @override
  State<GameRoomScreen> createState() => _GameRoomScreenState();
}

class _GameRoomScreenState extends State<GameRoomScreen> with WidgetsBindingObserver {
  final GameService _gameService = GameService();
  final FriendsService _friendsService = FriendsService();
  final ContentService _contentService = ContentService();
  final VoiceService _voiceService = VoiceService();
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  bool _isReady = false;

  StreamSubscription<QuerySnapshot>? _chatSubscription;
  Timer? _autoLeaveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Update online status with current roomId
    _friendsService.setUserOnlineStatus(true, currentRoomId: widget.roomId);
    _listenToChat();
  }

  @override
  void dispose() {
    _autoLeaveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _chatSubscription?.cancel();
    // Preserve voice connection when navigating to GameScreen
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.hidden) {
      _friendsService.setUserOnlineStatus(false, currentRoomId: widget.roomId);
      // Start 3-minute timer to auto leave room if app remains closed/paused for 3 minutes
      _autoLeaveTimer?.cancel();
      _autoLeaveTimer = Timer(const Duration(minutes: 3), () {
        _leaveRoom();
      });
    } else if (state == AppLifecycleState.resumed) {
      _autoLeaveTimer?.cancel();
      _friendsService.setUserOnlineStatus(true, currentRoomId: widget.roomId);
    }
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
      if (snapshot.docs.isNotEmpty) {
        // Only trigger if it's a new message
        final doc = snapshot.docs.first;
        final data = doc.data() as Map<String, dynamic>;
        
        // Skip if message was sent by me
        if (data['uid'] == _currentUid) return;
        
        // Check if message was just created (within last 3 seconds)
        final timestamp = data['timestamp'] as Timestamp?;
        if (timestamp != null) {
          final timeDiff = DateTime.now().difference(timestamp.toDate()).inSeconds;
          if (timeDiff <= 3) {
            _showChatNotification(data['name'] ?? 'لاعب', data['text'] ?? '');
          }
        }
      }
    });
  }

  void _showChatNotification(String name, String text) {
    SystemSound.play(SystemSoundType.alert); // Play notification sound
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.chat, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text('$name: $text', maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          backgroundColor: Colors.blueAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.only(top: 50, left: 16, right: 16), // Show at top
          duration: const Duration(seconds: 3),
          dismissDirection: DismissDirection.up,
        ),
      );
    }
  }

  Future<void> _syncVoiceChat(bool hasVoiceChat) async {
    if (hasVoiceChat) {
      if (!_voiceService.isJoined) {
        try {
          await _voiceService.initialize();
          await _voiceService.joinChannel(widget.roomId, _currentUid);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ تم الاتصال بالصوت والمايك بنجاح!'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          debugPrint('Error syncing voice chat in lobby: $e');
        }
      }
    } else {
      if (_voiceService.isJoined) {
        await _voiceService.leaveChannel();
      }
    }
  }

  void _leaveRoom() async {
    await _friendsService.setUserOnlineStatus(true, currentRoomId: '');
    await _gameService.leaveRoom(widget.roomId);
    await _voiceService.leaveChannel();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  void _toggleReady() async {
    setState(() {
      _isReady = !_isReady;
    });
    await _gameService.toggleReady(widget.roomId, _isReady);
  }

  void _startGame(List<dynamic> players) {
    // Always show setup dialog (min 3 players, no auto-start)
    _showGameSetupDialog(players);
  }

  void _showGameSetupDialog(List<dynamic> players) {
    String selectedGameMode = players.length == 2 ? 'duo_image' : 'group_word';
    bool selectedHasVoice = false;
    String contentMode = 'auto'; // 'auto' or 'manual_text'
    String selectedCategory = 'الكل (عشوائي)';
    String manualText = '';
    int selectedTimer = 60; // seconds
    int selectedRounds = 5; // minimum 5 rounds
    final TextEditingController textController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('إعداد اللعبة', textAlign: TextAlign.center),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Game Mode Selection
                    const Text('🎮 نمط اللعبة:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'duo_image',
                          label: Text('👥 شخصين (صورة)'),
                        ),
                        ButtonSegment(
                          value: 'group_word',
                          label: Text('🕵️ جماعة (جاسوس)'),
                        ),
                      ],
                      selected: {selectedGameMode},
                      onSelectionChanged: (val) => setDialogState(() => selectedGameMode = val.first),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 10),

                    // Voice Mode Selection
                    const Text('🎙️ نمط الصوت والمايك:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('🎙️ بصوت')),
                        ButtonSegment(value: false, label: Text('🔇 بدون صوت')),
                      ],
                      selected: {selectedHasVoice},
                      onSelectionChanged: (val) => setDialogState(() => selectedHasVoice = val.first),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 10),

                    if (selectedGameMode == 'group_word') ...[
                      // Category Selection
                      const Text('📁 اختيار الفئة / التصنيف:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        isExpanded: true,
                        items: ContentService.categories
                            .map((cat) => DropdownMenuItem(
                                  value: cat,
                                  child: Text(cat),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedCategory = val);
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 10),
                    ],
                    
                    // Timer selection
                    const Text('⏱️ مدة كل دور:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 30, label: Text('30 ث')),
                        ButtonSegment(value: 60, label: Text('60 ث')),
                        ButtonSegment(value: 90, label: Text('90 ث')),
                      ],
                      selected: {selectedTimer},
                      onSelectionChanged: (val) => setDialogState(() => selectedTimer = val.first),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 10),
                    // Unlimited Rounds Indicator
                    const Text('🔄 عدد الجولات:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade900.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.amberAccent, width: 1.5),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.all_inclusive, color: Colors.amberAccent, size: 28),
                          SizedBox(width: 8),
                          Text(
                            'جولات مفتوحة بدون حد أقصى ♾️',
                            style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 10),
                    // Content mode
                    if (selectedGameMode == 'group_word') ...[
                      const Text('🎴 نوع المحتوى:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => contentMode = 'auto'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: contentMode == 'auto' ? Colors.deepPurple : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.deepPurple),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.auto_awesome,
                                        color: contentMode == 'auto' ? Colors.white : Colors.deepPurple),
                                    const SizedBox(height: 4),
                                    Text('عشوائي', style: TextStyle(
                                      color: contentMode == 'auto' ? Colors.white : Colors.deepPurple,
                                      fontSize: 13,
                                    )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => contentMode = 'manual_text'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: contentMode == 'manual_text' ? Colors.teal : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.teal),
                                ),
                                child: Column(
                                  children: [
                                    Icon(Icons.text_fields,
                                        color: contentMode == 'manual_text' ? Colors.white : Colors.teal),
                                    const SizedBox(height: 4),
                                    Text('كلمة', style: TextStyle(
                                      color: contentMode == 'manual_text' ? Colors.white : Colors.teal,
                                      fontSize: 13,
                                    )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Manual text input
                      if (contentMode == 'manual_text') ...[                     
                        const SizedBox(height: 12),
                        TextField(
                          controller: textController,
                          decoration: const InputDecoration(
                            labelText: 'اكتب الكلمة أو الجملة',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => manualText = v,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    Navigator.pop(dialogContext);

                    // Save timer duration + rounds
                    await FirebaseFirestore.instance
                        .collection('rooms')
                        .doc(widget.roomId)
                        .update({
                          'turnDurationSeconds': selectedTimer,
                          'totalRounds': selectedRounds,
                          'selectedCategory': selectedCategory,
                          'gameMode': selectedGameMode,
                          'hasVoiceChat': selectedHasVoice,
                        });

                    if (selectedGameMode == 'duo_image') {
                      await _contentService.startDuoImageGame(widget.roomId);
                    } else {
                      // Save content
                      if (contentMode == 'manual_text' && manualText.isNotEmpty) {
                        await _contentService.saveTextContent(widget.roomId, manualText);
                      } else {
                        await _contentService.saveContentByCategory(widget.roomId, selectedCategory);
                      }

                      await _contentService.startGameWithRoles(widget.roomId);
                    }

                    navigator.pushReplacement(
                      MaterialPageRoute(builder: (_) => GameScreen(roomId: widget.roomId)),
                    );
                  },
                  child: const Text('ابدأ اللعبة! 🚀'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showInviteBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) => Container(
        padding: const EdgeInsets.all(20),
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'دعوة الأصدقاء للغرفة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _friendsService.streamFriends(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(child: Text('ليس لديك أصدقاء بعد.'));
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final String friendUid = data['friendUid'];
                      final String friendName = data['name'] ?? 'لاعب';

                      return StreamBuilder<DocumentSnapshot>(
                        stream: _friendsService.streamUserStatus(friendUid),
                        builder: (context, statusSnapshot) {
                          Map<String, dynamic>? statusData;
                          if (statusSnapshot.hasData && statusSnapshot.data!.exists) {
                            statusData = statusSnapshot.data!.data() as Map<String, dynamic>?;
                          }

                          final String presenceStatus = FriendsService.formatUserPresenceStatus(statusData);
                          final bool isTrulyOnline = presenceStatus.contains('🟢');
                          final bool isInAnotherRoom = presenceStatus.contains('🎮');
                          final bool canInvite = isTrulyOnline && !isInAnotherRoom;

                          return ListTile(
                            leading: Badge(
                              backgroundColor: isTrulyOnline ? Colors.green : Colors.grey,
                              smallSize: 10,
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
                            trailing: ElevatedButton(
                              onPressed: canInvite
                                  ? () async {
                                      final messenger = ScaffoldMessenger.of(context);
                                      await _friendsService.inviteFriendToRoom(friendUid, widget.roomId);
                                      messenger.showSnackBar(
                                        SnackBar(content: Text('تم إرسال دعوة إلى $friendName 📩')),
                                      );
                                    }
                                  : null,
                              child: const Text('دعوة'),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _leaveRoom();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('غرفة: ${widget.roomId}'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leaveRoom,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.chat, color: Colors.blueAccent),
              onPressed: () {
                showChatSheet(context, widget.roomId, 'لاعب');
              },
            ),
            IconButton(
              icon: const Icon(Icons.person_add, color: Colors.amber),
              onPressed: _showInviteBottomSheet,
              tooltip: 'دعوة صديق',
            ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: _gameService.streamRoom(widget.roomId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || !snapshot.data!.exists) {
              // Room was deleted or closed
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('⚠️ تم إغلاق الغرفة أو خروج اللاعبين منها')),
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
            final players = roomData['players'] as List<dynamic>;
            final status = roomData['status'] as String;

            // If game status changes to playing, navigate to the GameScreen
            if (status == 'playing') {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => GameScreen(roomId: widget.roomId)),
                  );
                }
              });
            }

            // Find current player data
            final currentPlayer = players.firstWhere(
              (p) => p['uid'] == _currentUid,
              orElse: () => null,
            );

            if (currentPlayer == null) {
              return const Center(child: Text('جاري مغادرة الغرفة...'));
            }

            final bool isHost = currentPlayer['isHost'] ?? false;
            final bool allReady = players.every((p) => p['isReady'] == true);
            final int maxPlayers = roomData['maxPlayers'] ?? 4;
            final bool hasVoiceChat = roomData['hasVoiceChat'] ?? false;
            final String gameMode = roomData['gameMode'] ?? 'group_word';
            final int minRequired = (gameMode == 'duo_image' || maxPlayers == 2) ? 2 : 3;
            final bool canStart = players.length >= minRequired && players.length <= maxPlayers && allReady;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _syncVoiceChat(hasVoiceChat);
              }
            });

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  // Room Code Display
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.deepPurple, width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'كود الغرفة للمشاركة:',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        SelectableText(
                          widget.roomId,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurpleAccent,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'عدد اللاعبين: ${players.length} / $maxPlayers',
                        style: const TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: isHost
                            ? () async {
                                final bool nextState = !hasVoiceChat;
                                await FirebaseFirestore.instance
                                    .collection('rooms')
                                    .doc(widget.roomId)
                                    .update({'hasVoiceChat': nextState});

                                if (!nextState) {
                                  await _voiceService.leaveChannel();
                                } else {
                                  await _voiceService.initialize();
                                  await _voiceService.joinChannel(widget.roomId, _currentUid);
                                }

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        nextState ? '🎙️ تم تفعيل الصوت والمايك للغرفة' : '🔇 تم إيقاف الصوت والمايك نهائياً (مغلق)',
                                      ),
                                      backgroundColor: nextState ? Colors.deepPurple : Colors.teal,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: hasVoiceChat ? Colors.deepPurple.withValues(alpha: 0.3) : Colors.teal.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isHost ? (hasVoiceChat ? Colors.amberAccent : Colors.tealAccent) : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasVoiceChat ? Icons.mic : Icons.mic_off,
                                size: 16,
                                color: hasVoiceChat ? Colors.amberAccent : Colors.tealAccent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isHost
                                    ? (hasVoiceChat ? '🎙️ بصوت (اضغط للتغيير)' : '🔇 بدون صوت (اضغط للتغيير)')
                                    : (hasVoiceChat ? '🎙️ بصوت' : '🔇 بدون صوت'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hasVoiceChat ? Colors.amberAccent : Colors.tealAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  // Player List
                  Expanded(
                    child: ListView.builder(
                      itemCount: players.length,
                      itemBuilder: (context, index) {
                        final player = players[index];
                        final bool pIsHost = player['isHost'] ?? false;
                        final bool pIsReady = player['isReady'] ?? false;
                        final bool pIsMuted = player['isMuted'] ?? false;
                        final bool isMe = player['uid'] == _currentUid;

                        final String avatarSeed = player['avatarSeed'] ?? 'Felix';
                        final int level = player['level'] ?? 1;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isMe ? Colors.deepPurpleAccent : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: ListTile(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => PublicProfileDialog(uid: player['uid']),
                              );
                            },
                            leading: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: pIsHost ? Colors.amber.withValues(alpha: 0.3) : Colors.deepPurple.withValues(alpha: 0.1),
                                  backgroundImage: NetworkImage(
                                      'https://api.dicebear.com/7.x/adventurer/png?seed=$avatarSeed&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf'),
                                ),
                                if (pIsHost)
                                  const Icon(Icons.star, color: Colors.amber, size: 18),
                              ],
                            ),
                            title: Text(
                              player['name'] + (isMe ? ' (أنت)' : ''),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'مستوى $level - ${pIsHost ? 'منشئ الغرفة' : (pIsReady ? 'مستعد' : 'غير مستعد')}',
                              style: TextStyle(
                                color: pIsHost
                                    ? Colors.amber
                                    : (pIsReady ? Colors.green : Colors.red),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Mic Icon Placeholder
                                IconButton(
                                  icon: Icon(
                                    pIsMuted ? Icons.mic_off : Icons.mic,
                                    color: pIsMuted ? Colors.red : Colors.green,
                                  ),
                                  onPressed: isMe
                                      ? () async {
                                          final bool nextMuteState = !pIsMuted;
                                          await _gameService.toggleMute(widget.roomId, nextMuteState);
                                          if (hasVoiceChat) {
                                            await _voiceService.setMuted(nextMuteState);
                                          }
                                        }
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                pIsHost
                                    ? const Icon(Icons.check_circle, color: Colors.amber)
                                    : Icon(
                                        pIsReady ? Icons.check_circle : Icons.radio_button_unchecked,
                                        color: pIsReady ? Colors.green : Colors.grey,
                                      ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Bottom Controls
                  if (!isHost)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _toggleReady,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: _isReady ? Colors.red : Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isReady ? 'إلغاء الاستعداد' : 'أنا مستعد',
                          style: const TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canStart ? () => _startGame(players) : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.amber,
                          disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          canStart ? '🚀 ابدأ اللعبة!' : 'بانتظار استعداد الجميع ($maxPlayers لاعبين)',
                          style: TextStyle(
                            fontSize: 18,
                            color: canStart ? Colors.black : Colors.white60,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
