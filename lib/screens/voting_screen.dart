import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/content_service.dart';
import '../services/friends_service.dart';
import '../services/user_service.dart';
import '../services/voice_service.dart';
import 'admin_words_screen.dart';
import 'home_screen.dart';
import 'friends_screen.dart';
import 'game_screen.dart';
import 'game_room_screen.dart';

class VotingScreen extends StatefulWidget {
  final String roomId;
  const VotingScreen({super.key, required this.roomId});

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  final ContentService _contentService = ContentService();
  final FriendsService _friendsService = FriendsService();
  final String _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  String? _myVote;
  bool _hasVoted = false;
  bool _showResult = false;
  List<String>? _spyOptions;
  String? _spySelectedGuess;
  bool? _spyGuessCorrect;

  // Submit vote
  Future<void> _vote(String votedForUid) async {
    if (_hasVoted) return;
    setState(() {
      _myVote = votedForUid;
      _hasVoted = true;
    });

    final docRef = FirebaseFirestore.instance.collection('rooms').doc(widget.roomId);
    await docRef.update({
      'votes.$_myUid': votedForUid,
    });
  }

  // Determine winner
  Map<String, dynamic> _calculateResult(
    List<dynamic> players,
    Map<String, dynamic> votes,
    String spyUid,
  ) {
    final Map<String, int> voteCount = {};
    for (var uid in votes.values) {
      voteCount[uid as String] = (voteCount[uid] ?? 0) + 1;
    }

    String mostVotedUid = '';
    int maxVotes = 0;
    voteCount.forEach((uid, voteNum) {
      if (voteNum > maxVotes) {
        maxVotes = voteNum;
        mostVotedUid = uid;
      }
    });

    final spyPlayer = players.firstWhere((p) => p['uid'] == spyUid, orElse: () => null);
    final mostVotedPlayer = players.firstWhere((p) => p['uid'] == mostVotedUid, orElse: () => null);

    final bool spyWasCaught = mostVotedUid == spyUid;

    return {
      'spyWasCaught': spyWasCaught,
      'spyName': spyPlayer?['name'] ?? 'الجاسوس',
      'mostVotedName': mostVotedPlayer?['name'] ?? '؟',
      'spyWon': !spyWasCaught,
      'voteCount': voteCount,
    };
  }

  bool _hasAwardedPoints = false;

  void _awardPointsLocally(List<dynamic> players, Map<String, dynamic> votes, String spyUid, bool? spyGuessSuccess) async {
    if (_hasAwardedPoints) return;
    _hasAwardedPoints = true;

    final result = _calculateResult(players, votes, spyUid);
    final bool spyWasCaught = result['spyWasCaught'] as bool;
    final bool iAmSpy = _myUid == spyUid;

    bool spyWinsTotal = !spyWasCaught || (spyGuessSuccess == true);
    bool iWon = iAmSpy ? spyWinsTotal : !spyWinsTotal;

    if (iWon) {
      try {
        await UserService().addPoints(_myUid, 15, true);
        debugPrint("Awarded 15 points to winner $_myUid");
      } catch (e) {
        debugPrint("Error awarding points: $e");
      }
    }
  }

  Future<void> _loadSpyOptions(String secretWord, String category) async {
    if (_spyOptions != null) return;
    final options = await _contentService.generateSpyGuessOptions(secretWord, category);
    if (mounted) {
      setState(() {
        _spyOptions = options;
      });
    }
  }

  Future<void> _submitSpyGuess(String selectedOption, String secretWord) async {
    final bool isCorrect = selectedOption == secretWord;
    setState(() {
      _spySelectedGuess = selectedOption;
      _spyGuessCorrect = isCorrect;
    });

    await FirebaseFirestore.instance.collection('rooms').doc(widget.roomId).update({
      'spyGuessCorrect': isCorrect,
    });
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
        final String status = roomData['status'] ?? 'voting';
        final List<dynamic> players = roomData['players'] ?? [];
        final String hostId = roomData['hostId'] ?? '';
        final bool isHost = _myUid == hostId;
        final String spyUid = roomData['spyUid'] ?? '';
        final String gameMode = roomData['gameMode'] ?? 'group_word';
        final Map<String, dynamic>? playerImages = roomData['playerImages'] as Map<String, dynamic>?;
        final Map<String, dynamic> votes = roomData['votes'] as Map<String, dynamic>? ?? {};
        final Map<String, dynamic>? content = roomData['content'] as Map<String, dynamic>?;

        final String secretWord = content?['value'] ?? '';
        final String category = content?['category'] ?? 'عام';
        final bool? spyGuessSuccess = roomData['spyGuessCorrect'] as bool?;

        final bool allVoted = votes.length >= players.length;

        if (allVoted && !_showResult) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _showResult = true;
              });
            }
          });
        }

        if (gameMode == 'group_word' && (allVoted || _showResult)) {
          _awardPointsLocally(players, votes, spyUid, spyGuessSuccess);
        }

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

        if (status == 'waiting') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => GameRoomScreen(roomId: widget.roomId)),
              );
            }
          });
        }

        if (status == 'finished' || status == 'closed') {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (mounted) {
              await FriendsService().setUserOnlineStatus(true, currentRoomId: '');
              VoiceService().leaveChannel();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            }
          });
        }

        if (gameMode == 'group_word' && _myUid == spyUid && secretWord.isNotEmpty) {
          _loadSpyOptions(secretWord, category);
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(gameMode == 'duo_image' ? 'نتائج تخمين الصور 🖼️' : 'نتيجة التصويت 🕵️'),
            automaticallyImplyLeading: false,
            actions: [
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
          body: gameMode == 'duo_image'
              ? _buildDuoImageResultsView(players, votes, playerImages, isHost)
              : ((allVoted || _showResult)
                  ? _buildResultView(players, votes, spyUid, content, secretWord, category, spyGuessSuccess)
                  : _buildVotingView(players, votes)),
        );
      },
    );
  }

  // ===== Duo Image Results View (No Spy wording) =====
  Widget _buildDuoImageResultsView(
    List<dynamic> players,
    Map<String, dynamic> votes,
    Map<String, dynamic>? playerImages,
    bool isHost,
  ) {
    String winnerUid = '';
    int maxVotes = 0;
    final Map<String, int> voteCount = {};
    for (var uid in votes.values) {
      voteCount[uid as String] = (voteCount[uid] ?? 0) + 1;
    }
    voteCount.forEach((uid, cnt) {
      if (cnt > maxVotes) {
        maxVotes = cnt;
        winnerUid = uid;
      }
    });

    final winnerPlayer = players.firstWhere(
      (p) => p['uid'] == winnerUid,
      orElse: () => null,
    );
    final String winnerName = winnerPlayer?['name'] ?? '';
    final bool hasWinner = winnerName.isNotEmpty;

    if (winnerUid.isNotEmpty && !_hasAwardedPoints) {
      _hasAwardedPoints = true;
      if (winnerUid == _myUid) {
        UserService().addPoints(_myUid, 15, true);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amberAccent, width: 2),
            ),
            child: Column(
              children: const [
                Text(
                  '🖼️ كشف الصور السرية',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.amberAccent,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'إليكم الصورة السرية لكل لاعب! اختارا من الفائز بالتخمين 🏆',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Both Players' Secret Photos Card
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: players.map((player) {
              final String uid = player['uid'];
              final String name = player['name'] ?? 'لاعب';
              final bool isMe = uid == _myUid;
              final Map<String, dynamic>? imgData = playerImages != null ? playerImages[uid] as Map<String, dynamic>? : null;
              final String imgTitle = imgData?['title'] ?? 'صورة خفية';
              final String imgUrl = imgData?['url'] ?? '';

              return Expanded(
                child: Card(
                  color: Colors.grey.shade900,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.deepPurple, width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Text(
                          name + (isMe ? ' (أنت)' : ''),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.amberAccent),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 110,
                            height: 110,
                            color: Colors.black,
                            child: buildAdminImageWidget(imgUrl, fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          imgTitle,
                          style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Winner Reveal or Winner Selection
          if (winnerName.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade900.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.greenAccent, width: 2),
              ),
              child: Column(
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 6),
                  Text(
                    'الفائز في هذه الجولة: $winnerName 🏆',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                  ),
                  const SizedBox(height: 4),
                  const Text('تم إضافة +15 نقطة لرصيد الفائز!', style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber, width: 1.5),
              ),
              child: Column(
                children: [
                  const Text(
                    '🏆 من الشخص الذي نجح في تخمين صورة خصمه أولاً؟',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: players.map((p) {
                      final String pUid = p['uid'];
                      final String pName = p['name'] ?? 'لاعب';
                      final bool isSelected = _myVote == pUid;

                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isSelected ? Colors.amber.shade700 : Colors.deepPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: isSelected ? Colors.amberAccent : Colors.transparent, width: 2),
                              ),
                            ),
                            onPressed: () => _vote(pUid),
                            child: Text(
                              '👑 $pName',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Return to Room / Home Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (!hasWinner) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('⚠️ يجب تحديد الشخص الفائز بالضغط على اسمه أولاً قبل الجولة التالية!'),
                          backgroundColor: Colors.amber,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }

                    await FirebaseFirestore.instance.collection('rooms').doc(widget.roomId).update({
                      'status': 'waiting',
                      'votes': {},
                      'spyGuessCorrect': null,
                    });
                    if (mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => GameRoomScreen(roomId: widget.roomId)),
                      );
                    }
                  },
                  icon: Icon(hasWinner ? Icons.replay : Icons.lock),
                  label: Text(hasWinner ? 'العودة للغرفة (الجولة التالية)' : 'حدد الفائز أولاً 🔒'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasWinner ? Colors.amber.shade800 : Colors.grey.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () async {
                  await FriendsService().setUserOnlineStatus(true, currentRoomId: '');
                  await FirebaseFirestore.instance.collection('rooms').doc(widget.roomId).update({
                    'status': 'finished',
                  });
                  await VoiceService().leaveChannel();
                  if (mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    );
                  }
                },
                icon: const Icon(Icons.home),
                label: const Text('الرئيسية'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===== Voting View for Group Word Spy Game =====
  Widget _buildVotingView(List<dynamic> players, Map<String, dynamic> votes) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.orange.withValues(alpha: 0.2),
          child: Column(
            children: [
              const Text(
                '🕵️ من هو الجاسوس؟',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '🔒 الأصوات مخفية حتى يصوّت الجميع!\n(${votes.length}/${players.length} صوّتوا حتى الآن)',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: players.length,
            itemBuilder: (context, index) {
              final player = players[index] as Map<String, dynamic>;
              final String uid = player['uid'];
              final String name = player['name'] ?? 'لاعب';
              final bool isMe = uid == _myUid;
              final bool isVotedFor = _myVote == uid;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: isVotedFor
                    ? Colors.orange.withValues(alpha: 0.3)
                    : Colors.grey.shade900,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isVotedFor ? Colors.orange : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isVotedFor ? Colors.orange : Colors.deepPurple,
                    child: Text(
                      name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    name + (isMe ? ' (أنت)' : ''),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('🔒 تصويت سرّي', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  trailing: isMe || _hasVoted
                      ? (isVotedFor ? const Icon(Icons.how_to_vote, color: Colors.orange) : null)
                      : ElevatedButton(
                          onPressed: () => _vote(uid),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('صوّت'),
                        ),
                ),
              );
            },
          ),
        ),
        if (_hasVoted)
          Container(
            padding: const EdgeInsets.all(16),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.orange, strokeWidth: 2),
                SizedBox(width: 12),
                Text('في انتظار تصويت باقي الأصدقاء...', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
      ],
    );
  }

  // ===== Result View for Group Spy Game =====
  Widget _buildResultView(
    List<dynamic> players,
    Map<String, dynamic> votes,
    String spyUid,
    Map<String, dynamic>? content,
    String secretWord,
    String category,
    bool? spyGuessSuccess,
  ) {
    final result = _calculateResult(players, votes, spyUid);
    final bool spyWasCaught = result['spyWasCaught'] as bool;
    final String spyName = result['spyName'] as String;
    final bool iAmSpy = _myUid == spyUid;
    final bool spyWonOverall = !spyWasCaught || (spyGuessSuccess == true);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Winner Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: spyWonOverall
                    ? [Colors.red.shade900, Colors.red.shade700]
                    : [Colors.green.shade900, Colors.green.shade700],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  spyWonOverall ? '💀' : '🎉',
                  style: const TextStyle(fontSize: 64),
                ),
                const SizedBox(height: 12),
                Text(
                  spyWonOverall ? 'الجاسوس يفوز!' : 'تم كشف الجاسوس!',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  spyGuessSuccess == true
                      ? '🎯 الجاسوس خمن الكلمة السرية وسرق الفوز! 🏆'
                      : (spyWasCaught ? 'اللاعبون يفوزون! 🏆' : 'الجاسوس نجا دون أن يُكتشف! 🕵️'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'الجاسوس كان: $spyName ${iAmSpy ? "(أنت)" : ""}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Multiple Choice Spy Guess Box
          if (iAmSpy && _spyOptions != null && _spySelectedGuess == null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber, width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    '🎯 فرصة الجاسوس! حزر الكلمة من فئة ($category) لسرقة الفوز:',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _spyOptions!.map((option) {
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onPressed: () => _submitSpyGuess(option, secretWord),
                        child: Text(option, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          if (_spySelectedGuess != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _spyGuessCorrect == true ? Colors.green.shade900 : Colors.red.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _spyGuessCorrect == true
                    ? '🎯 خيارك ("$_spySelectedGuess") صحيح 100%! فزت باللعبة!'
                    : '❌ خيارك ("$_spySelectedGuess") غير صحيح! الكلمة كانت: "$secretWord"',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Return to Room / Home Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => GameRoomScreen(roomId: widget.roomId)),
                    );
                  },
                  icon: const Icon(Icons.replay),
                  label: const Text('العودة للغرفة'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.amber.shade800,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await VoiceService().leaveChannel();
                    if (mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
                      );
                    }
                  },
                  icon: const Icon(Icons.home),
                  label: const Text('الرئيسية'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
