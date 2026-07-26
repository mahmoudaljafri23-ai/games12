import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';
import '../services/game_service.dart';
import '../services/friends_service.dart';
import '../services/user_service.dart';
import '../services/content_service.dart';
import 'game_room_screen.dart';
import 'login_screen.dart';
import 'friends_screen.dart';
import 'unlock_emojis_screen.dart';
import 'profile_screen.dart';
import 'leaderboard_screen.dart';
import 'private_chat_screen.dart';
import 'admin_words_screen.dart';
import 'package:audioplayers/audioplayers.dart';

class HomeScreen extends StatefulWidget {
  final String? initialRoomId;
  const HomeScreen({super.key, this.initialRoomId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final GameService _gameService = GameService();
  final FriendsService _friendsService = FriendsService();
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  
  String _playerName = 'لاعب';
  bool _isLoading = false;
  StreamSubscription<QuerySnapshot>? _invitationsSubscription;

  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchPlayerName();
    _friendsService.setUserOnlineStatus(true); // Set online
    _listenToInvitations();

    // Refresh presence timestamp every 25 seconds while app is open
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (timer) {
      if (mounted) {
        _friendsService.setUserOnlineStatus(true);
      }
    });
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _invitationsSubscription?.cancel();
    _privateChatsSubscription?.cancel();
    _friendsService.setUserOnlineStatus(false); // Set offline when leaving app
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.hidden) {
      _friendsService.setUserOnlineStatus(false);
    } else if (state == AppLifecycleState.resumed) {
      _friendsService.setUserOnlineStatus(true);
    }
  }

  void _fetchPlayerName() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_currentUid).get();
      if (doc.exists && doc.data() != null) {
        setState(() {
          _playerName = doc.data()!['name'] ?? 'لاعب';
        });
      }
    } catch (e) {
      // Keep fallback name 'لاعب'
    }
  }

  StreamSubscription<QuerySnapshot>? _privateChatsSubscription;
  final Map<String, Timestamp> _lastNotifiedTimestamps = {};

  // Listen to incoming game invitations
  void _listenToInvitations() {
    _invitationsSubscription = _friendsService.streamInvitations().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final String roomId = data['roomId'];
          final String inviterName = data['invitedBy'] ?? 'صديق';

          _showInvitationDialog(roomId, inviterName);
        }
      }
    });

    // Listen to incoming private chat messages
    bool isFirstSnapshot = true;
    _privateChatsSubscription = FirebaseFirestore.instance
        .collection('private_chats')
        .where('participants', arrayContains: _currentUid)
        .snapshots()
        .listen((snapshot) {
      if (isFirstSnapshot) {
        // Seed initial timestamps on first load so old messages don't trigger SnackBar!
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final Timestamp? lastUpdated = data['lastUpdated'] as Timestamp?;
          if (lastUpdated != null) {
            _lastNotifiedTimestamps[doc.id] = lastUpdated;
          }
        }
        isFirstSnapshot = false;
        return; // Do NOT notify for old messages existing prior to app launch!
      }

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified || change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>?;
          if (data == null) continue;

          final String chatRoomId = change.doc.id;
          final String lastSenderUid = data['lastSenderUid'] ?? '';
          final String lastMessage = data['lastMessage'] ?? '';
          final String senderName = data['lastSenderName'] ?? 'صديق';
          final Timestamp? lastUpdated = data['lastUpdated'] as Timestamp?;

          final Map<String, dynamic>? clearedBy = data['clearedBy'] as Map<String, dynamic>?;
          final Timestamp? myClearedAt = clearedBy?[_currentUid] as Timestamp?;

          if (lastSenderUid.isNotEmpty && lastSenderUid != _currentUid && lastUpdated != null) {
            // Check if user cleared chat AFTER last message timestamp
            if (myClearedAt != null && myClearedAt.millisecondsSinceEpoch >= lastUpdated.millisecondsSinceEpoch) {
              continue; // Skip because user deleted/cleared chat after this message!
            }

            // Only notify if message timestamp is newer than last notified timestamp
            final Timestamp? prevTime = _lastNotifiedTimestamps[chatRoomId];
            if (prevTime == null || lastUpdated.millisecondsSinceEpoch > prevTime.millisecondsSinceEpoch) {
              _lastNotifiedTimestamps[chatRoomId] = lastUpdated;
              _showPrivateMessageNotification(senderName, lastMessage, lastSenderUid);
            }
          }
        }
      }
    });
  }

  void _showPrivateMessageNotification(String senderName, String message, String senderUid) {
    if (!mounted) return;
    try {
      AudioPlayer().play(UrlSource('https://actions.google.com/sounds/v1/alarms/beep_short.ogg'));
    } catch (_) {}

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.chat_bubble, color: Colors.amberAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('💬 رسالة جديدة من $senderName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Text(message, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'فتح',
          textColor: Colors.amberAccent,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PrivateChatScreen(
                  friendUid: senderUid,
                  friendName: senderName,
                  avatarSeed: 'Felix',
                ),
              ),
            );
          },
        ),
        backgroundColor: Colors.deepPurple.shade900,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // Show a dialog for incoming room invitations
  void _showInvitationDialog(String roomId, String inviterName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.mail_outline, color: Colors.amber),
            SizedBox(width: 10),
            Text('دعوة انضمام للعبة'),
          ],
        ),
        content: Text('لقد دعاك صديقك $inviterName للانضمام إلى الغرفة: $roomId'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _friendsService.declineInvitation(roomId); // Dismiss invitation
            },
            child: const Text('رفض', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _friendsService.declineInvitation(roomId); // Dismiss invitation first
              
              setState(() {
                _isLoading = true;
              });

              try {
                String? joinedRoomId = await _gameService.joinRoom(roomId, _playerName);
                if (joinedRoomId != null && mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => GameRoomScreen(roomId: joinedRoomId)),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('فشل الانضمام للغرفة: $e')),
                  );
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              }
            },
            child: const Text('قبول'),
          ),
        ],
      ),
    );
  }

  void _signOut() async {
    await _friendsService.setUserOnlineStatus(false);
    await AuthService().signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _onCreateRoom() {
    int selectedMaxPlayers = 4;
    bool selectedVoiceChat = true;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('إعداد الغرفة', textAlign: TextAlign.center),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Player count selector
                  const Text('عدد اللاعبين:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: selectedMaxPlayers > 3
                            ? () => setDialogState(() => selectedMaxPlayers--)
                            : null,
                      ),
                      Text(
                        '$selectedMaxPlayers',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: selectedMaxPlayers < 10
                            ? () => setDialogState(() => selectedMaxPlayers++)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),
                  // Room type selector
                  const Text('نوع الغرفة:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedVoiceChat = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: selectedVoiceChat
                                  ? Colors.deepPurple
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.deepPurple),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.mic,
                                    color: selectedVoiceChat ? Colors.white : Colors.deepPurple),
                                const SizedBox(height: 4),
                                Text(
                                  'بصوت\n(أونلاين)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: selectedVoiceChat ? Colors.white : Colors.deepPurple,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(() => selectedVoiceChat = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: !selectedVoiceChat
                                  ? Colors.teal
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.teal),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.people,
                                    color: !selectedVoiceChat ? Colors.white : Colors.teal),
                                const SizedBox(height: 4),
                                Text(
                                  'بدون صوت\n(جمب بعض)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: !selectedVoiceChat ? Colors.white : Colors.teal,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() {
                      _isLoading = true;
                    });
                    try {
                      String roomId = await _gameService.createRoom(
                        _playerName,
                        maxPlayers: selectedMaxPlayers,
                        hasVoiceChat: selectedVoiceChat,
                      );
                      navigator.push(
                        MaterialPageRoute(builder: (context) => GameRoomScreen(roomId: roomId)),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('فشل إنشاء الغرفة: $e')),
                      );
                    } finally {
                      if (mounted) {
                        setState(() {
                          _isLoading = false;
                        });
                      }
                    }
                  },

                  child: const Text('إنشاء الغرفة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onJoinRoomByCode() {

    final TextEditingController codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('دخول غرفة بالكود', textAlign: TextAlign.center),
        content: TextField(
          controller: codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: 'أدخل كود الغرفة المكون من 6 أرقام',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              String code = codeController.text.trim();
              if (code.length != 6) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('الرجاء إدخال كود صحيح من 6 أرقام')),
                );
                return;
              }

              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              
              Navigator.pop(dialogContext); // Close dialog
              
              setState(() {
                _isLoading = true;
              });

              try {
                String? joinedRoomId = await _gameService.joinRoom(code, _playerName);
                if (joinedRoomId != null) {
                  navigator.push(
                    MaterialPageRoute(builder: (context) => GameRoomScreen(roomId: joinedRoomId)),
                  );
                }
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('فشل الدخول للغرفة: $e')),
                );
              } finally {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              }
            },
            child: const Text('دخول'),
          ),
        ],
      ),
    );
  }

  void _onJoinRandomRoom() async {
    setState(() {
      _isLoading = true;
    });
    try {
      String? roomId = await _gameService.joinRandomRoom(_playerName);
      if (roomId != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => GameRoomScreen(roomId: roomId)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل العثور على غرفة عشوائية: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showAddWordDialog() {
    final TextEditingController wordController = TextEditingController();
    String selectedCategory = 'فئة عشوائية (كلمات المستخدمين)';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('➕ إضافة كلمة جديدة للجميع', textAlign: TextAlign.center),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الكلمة الجديدة:'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: wordController,
                    decoration: const InputDecoration(
                      hintText: 'اكتب الكلمة هنا...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('الفئة / التصنيف:'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    isExpanded: true,
                    items: ContentService.categories
                        .where((c) => c != 'الكل (عشوائي)')
                        .map((cat) => DropdownMenuItem(
                              value: cat,
                              child: Text(cat, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedCategory = val);
                    },
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final text = wordController.text.trim();
                    if (text.isEmpty) return;

                    if (ContentService.isProfaneOrInappropriate(text)) {
                      Navigator.pop(dialogContext);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⚠️ لا يُسمح بإضافة كلمات غير لائقة أو بذيئة!'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                      return;
                    }

                    Navigator.pop(dialogContext);
                    final isCreator = (FirebaseAuth.instance.currentUser?.email ?? '').toLowerCase() == 'mahmoud.aljafri23@gmail.com';
                    final resultStatus = await ContentService().addGlobalCustomWord(
                      text,
                      selectedCategory,
                      isCreator: isCreator,
                      submittedByName: _playerName,
                      submittedBySerialId: UserService.generateSerialId(_currentUid),
                      submittedByEmail: FirebaseAuth.instance.currentUser?.email ?? '',
                    );

                    if (mounted) {
                      if (resultStatus == 'duplicate') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('⚠️ الكلمة "$text" موجودة بالفعل في السيرفر أو اللعبة!'),
                            backgroundColor: Colors.orange.shade900,
                          ),
                        );
                      } else if (resultStatus == 'profane') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⚠️ لا يُسمح بإضافة كلمات غير لائقة أو بذيئة!'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } else if (resultStatus == 'success') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isCreator
                                  ? '✅ تم إضافة ونشر الكلمة "$text" للجميع فوراً!'
                                  : '✅ تم إرسال الكلمة "$text" للمراجعة، وسوف تظهر للجميع بعد موافقتك! 👑',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('إضافة للعبة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onCreateDuoRoom() async {
    setState(() => _isLoading = true);
    try {
      final roomId = await _gameService.createDuoRoom(_playerName);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GameRoomScreen(roomId: roomId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء غرفة الشخصين: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showAddImageDialog() {
    final TextEditingController urlController = TextEditingController();
    final TextEditingController titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('🖼️ إضافة صورة جديدة للعبة الشخصين', textAlign: TextAlign.center),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Button to pick image from Phone Gallery (Auto crops & resizes)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final ImagePicker picker = ImagePicker();
                          final XFile? image = await picker.pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 500,
                            maxHeight: 500,
                            imageQuality: 80,
                          );
                          if (image != null) {
                            final bytes = await image.readAsBytes();
                            final String base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
                            urlController.text = base64Image;
                            setDialogState(() {});
                          }
                        },
                        icon: const Icon(Icons.photo_library, color: Colors.amberAccent),
                        label: const Text('📱 اختيار صورة من جهازك (المعرض)', style: TextStyle(fontSize: 14)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Center(child: Text('أو ضع رابط صورة مباشر', style: TextStyle(color: Colors.grey, fontSize: 12))),
                    const SizedBox(height: 8),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        hintText: 'https://...',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (urlController.text.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('معاينة الصورة المختارة:'),
                      const SizedBox(height: 6),
                      Center(
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amberAccent, width: 1.5),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: urlController.text.startsWith('data:image/')
                                ? Image.memory(
                                    base64Decode(urlController.text.split('base64,').last),
                                    fit: BoxFit.cover,
                                  )
                                : Image.network(
                                    urlController.text,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 40),
                                  ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text('عنوان أو اسم الصورة (اختياري):'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        hintText: 'مثال: سيارة رياضية، شاطئ البحر...',
                        border: OutlineInputBorder(),
                      ),
                    ),
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
                    final url = urlController.text.trim();
                    final title = titleController.text.trim();
                    if (url.isEmpty) return;

                    Navigator.pop(dialogContext);
                    final isCreator = (FirebaseAuth.instance.currentUser?.email ?? '').toLowerCase() == 'mahmoud.aljafri23@gmail.com';

                    final resultStatus = await ContentService().addGlobalCustomImage(
                      url,
                      title: title.isEmpty ? 'صورة شخصية' : title,
                      isCreator: isCreator,
                      submittedByName: _playerName,
                      submittedBySerialId: UserService.generateSerialId(_currentUid),
                      submittedByEmail: FirebaseAuth.instance.currentUser?.email ?? '',
                    );

                    if (mounted) {
                      if (resultStatus == 'size_limit_exceeded') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⚠️ حجم الصورة كبير جداً! الحد الأقصى المسموح هو 2MB.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } else if (resultStatus == 'profane') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⚠️ لا يُسمح بإضافة عنوان أو صورة غير لائقة!'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } else if (resultStatus == 'success') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isCreator
                                  ? '✅ تم رفع ونشر الصورة للعبة الشخصين فوراً!'
                                  : '✅ تم إرسال الصورة للمراجعة، وسوف تظهر للجميع بعد موافقتك! 👑',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('رفع الصورة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isCreator = (FirebaseAuth.instance.currentUser?.email ?? '').toLowerCase() == 'mahmoud.aljafri23@gmail.com';

    return Scaffold(
      appBar: AppBar(
        title: const Text('تحدي الملوك 👑'),
        leading: IconButton(
          icon: const Icon(Icons.people, color: Colors.deepPurpleAccent),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const FriendsScreen()),
            );
          },
        ),
        actions: [
          if (isCreator)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings, color: Colors.amberAccent),
              tooltip: 'إدارة الكلمات والصور 👑',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminWordsScreen()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.emoji_emotions, color: Colors.amberAccent),
            tooltip: 'متجر الإيموجيات والأصوات 🎭',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UnlockEmojisScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_photo_alternate, color: Colors.cyanAccent),
            tooltip: 'إضافة صورة جديدة للعبة الشخصين',
            onPressed: _showAddImageDialog,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: Colors.amber),
            tooltip: 'إضافة كلمة جديدة',
            onPressed: _showAddWordDialog,
          ),
          IconButton(
            icon: const Icon(Icons.leaderboard, color: Colors.amber),
            tooltip: 'المتصدرون 🏆',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.person, color: Colors.deepPurple),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: _signOut,
          )
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Column(
              children: [
                // ===== Large Cover Banner Card =====
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withValues(alpha: 0.4),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        // Large Cover Image
                        Image.asset(
                          'assets/app_cover.jpg',
                          width: double.infinity,
                          height: 180,
                          fit: BoxFit.cover,
                        ),
                        // Dark Overlay Gradient
                        Container(
                          height: 180,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.85),
                              ],
                            ),
                          ),
                        ),
                        // Profile Avatar + Name overlay
                        Positioned(
                          bottom: 12,
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: Colors.amber,
                                child: CircleAvatar(
                                  radius: 33,
                                  backgroundImage: UserService.getAvatarImageProvider(
                                    seed: 'Felix',
                                    email: FirebaseAuth.instance.currentUser?.email,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    _playerName,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (isCreator) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade800,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'منشئ اللعبة 👑',
                                        style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.amber.shade600, width: 1),
                                ),
                                child: Text(
                                  'ID: #${UserService.generateSerialId(_currentUid)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                  
                  // 1. Play Duo Image Game (Button on Main Screen)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _onCreateDuoRoom,
                      icon: const Icon(Icons.style, color: Colors.amberAccent, size: 28),
                      label: const Text('📸 لعب لعبة الصور (شخصين 👥)', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        elevation: 5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: Colors.amber, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Create Room Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _onCreateRoom,
                      icon: const Icon(Icons.add_box),
                      label: const Text('إنشاء غرفة جديدة', style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Join Room by Code Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _onJoinRoomByCode,
                      icon: const Icon(Icons.vpn_key),
                      label: const Text('دخول غرفة بالكود', style: TextStyle(fontSize: 18)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  // Random Matchmaking Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _onJoinRandomRoom,
                      icon: const Icon(Icons.search),
                      label: const Text('بحث عشوائي عن لعبة', style: TextStyle(fontSize: 18)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
