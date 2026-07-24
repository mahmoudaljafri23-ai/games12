import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ContentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ===== Default 2-Player Game Real Photos Database =====
  static const List<Map<String, String>> defaultDuoImages = [
    {'title': 'قطة منزلية 🐱', 'url': 'https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=600&q=80'},
    {'title': 'بيتزا طازجة 🍕', 'url': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=600&q=80'},
    {'title': 'سيارة رياضية حمراء 🏎️', 'url': 'https://images.unsplash.com/photo-1503376780353-7e6692767b70?w=600&q=80'},
    {'title': 'شاطئ البحر 🏖️', 'url': 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&q=80'},
    {'title': 'ملعب كرة قدم ⚽', 'url': 'https://images.unsplash.com/photo-1522778119026-d647f0596c20?w=600&q=80'},
    {'title': 'طائرة ركاب ✈️', 'url': 'https://images.unsplash.com/photo-1436491865332-7a61a109cc05?w=600&q=80'},
    {'title': 'أهرامات مصر 🐫', 'url': 'https://images.unsplash.com/photo-1503177119275-0aa32b3a9368?w=600&q=80'},
  ];

  // ===== Available Categories List =====
  static const List<String> categories = [
    'الكل (عشوائي)',
    'فئة عشوائية (كلمات المستخدمين)',
    'ألعاب الأطفال',
    'شخصيات وكارتون',
    'دول وبلدان',
    'أماكن',
    'مواصلات',
    'معالم',
    'حيوانات',
    'طعام',
    'رياضة',
    'موسيقى',
    'طبيعة',
    'فضاء',
    'أجهزة',
    'مهن',
    'ماركات',
  ];

  // ===== Profanity & Inappropriate Content Filter =====
  static bool isProfaneOrInappropriate(String text) {
    final String cleanText = text.trim().toLowerCase();
    
    final List<String> forbiddenTerms = [
      'كلب', 'حمار', 'خنزير', 'عرص', 'شرموط', 'قحبة', 'عاهر', 'منيوك',
      'زب', 'كس', 'طيز', 'طيزك', 'زبك', 'كسك', 'ياعرص', 'خول', 'بضان',
      'احا', 'أحا', 'قذر', 'حقير', 'يا كلب', 'يا حمار', 'تفه', 'تفوه',
      'fuck', 'shit', 'bitch', 'asshole', 'dick', 'pussy', 'bastard', 'cunt', 'slut', 'whore',
    ];

    for (var term in forbiddenTerms) {
      if (cleanText.contains(term)) {
        return true;
      }
    }
    return false;
  }

  // ===== Massive default word database =====
  static const List<Map<String, String>> defaultWords = [
    // ===== ألعاب الأطفال =====
    {'word': 'غميضة (استغباية)', 'category': 'ألعاب الأطفال'},
    {'word': 'صيد السمك', 'category': 'ألعاب الأطفال'},
    {'word': 'نط الحبل', 'category': 'ألعاب الأطفال'},
    {'word': 'مكعبات ليغو', 'category': 'ألعاب الأطفال'},
    {'word': 'سيارات بالريموت', 'category': 'ألعاب الأطفال'},
    {'word': 'شطرنج', 'category': 'ألعاب الأطفال'},
    {'word': 'لودو (Ludo)', 'category': 'ألعاب الأطفال'},
    {'word': 'مونوبولي', 'category': 'ألعاب الأطفال'},
    {'word': 'الدمية الكبيرة', 'category': 'ألعاب الأطفال'},
    {'word': 'الزحليقة', 'category': 'ألعاب الأطفال'},
    {'word': 'المريحانة (المرجوحة)', 'category': 'ألعاب الأطفال'},
    {'word': 'صلصال ملون', 'category': 'ألعاب الأطفال'},
    {'word': 'طائرة ورقية', 'category': 'ألعاب الأطفال'},
    {'word': 'مسدس ماء', 'category': 'ألعاب الأطفال'},

    // ===== شخصيات وكارتون =====
    {'word': 'سبونج بوب', 'category': 'شخصيات وكارتون'},
    {'word': 'ميكي ماوس', 'category': 'شخصيات وكارتون'},
    {'word': 'سبايدرمان', 'category': 'شخصيات وكارتون'},
    {'word': 'باتمان', 'category': 'شخصيات وكارتون'},
    {'word': 'توم وجيري', 'category': 'شخصيات وكارتون'},
    {'word': 'المحقق كونان', 'category': 'شخصيات وكارتون'},
    {'word': 'لوفي (ون بيس)', 'category': 'شخصيات وكارتون'},
    {'word': 'غوكو (دراغون بول)', 'category': 'شخصيات وكارتون'},
    {'word': 'سيمبا (الأسد الملك)', 'category': 'شخصيات وكارتون'},
    {'word': 'بينك بانثر (المنمر الوردي)', 'category': 'شخصيات وكارتون'},
    {'word': 'ليونيل ميسي', 'category': 'شخصيات وكارتون'},
    {'word': 'كريستيانو رونالدو', 'category': 'شخصيات وكارتون'},
    {'word': 'عادل إمام', 'category': 'شخصيات وكارتون'},
    {'word': 'مستر بن', 'category': 'شخصيات وكارتون'},

    // ===== دول وبلدان (مع فلسطين) =====
    {'word': 'فلسطين 🇵🇸', 'category': 'دول وبلدان'},
    {'word': 'الأردن', 'category': 'دول وبلدان'},
    {'word': 'مصر', 'category': 'دول وبلدان'},
    {'word': 'السعودية', 'category': 'دول وبلدان'},
    {'word': 'الإمارات', 'category': 'دول وبلدان'},
    {'word': 'قطر', 'category': 'دول وبلدان'},
    {'word': 'الكويت', 'category': 'دول وبلدان'},
    {'word': 'عُمان', 'category': 'دول وبلدان'},
    {'word': 'الجزائر', 'category': 'دول وبلدان'},
    {'word': 'المغرب', 'category': 'دول وبلدان'},
    {'word': 'تونس', 'category': 'دول وبلدان'},
    {'word': 'لبنان', 'category': 'دول وبلدان'},
    {'word': 'سوريا', 'category': 'دول وبلدان'},
    {'word': 'العراق', 'category': 'دول وبلدان'},
    {'word': 'تركيا', 'category': 'دول وبلدان'},
    {'word': 'إيطاليا', 'category': 'دول وبلدان'},
    {'word': 'إسبانيا', 'category': 'دول وبلدان'},
    {'word': 'ألمانيا', 'category': 'دول وبلدان'},
    {'word': 'اليابان', 'category': 'دول وبلدان'},
    {'word': 'البرازيل', 'category': 'دول وبلدان'},

    // ===== أماكن =====
    {'word': 'شاطئ', 'category': 'أماكن'},
    {'word': 'مطار', 'category': 'أماكن'},
    {'word': 'مستشفى', 'category': 'أماكن'},
    {'word': 'مدرسة', 'category': 'أماكن'},
    {'word': 'سوق', 'category': 'أماكن'},
    {'word': 'متحف', 'category': 'أماكن'},
    {'word': 'سينما', 'category': 'أماكن'},
    {'word': 'مطعم', 'category': 'أماكن'},
    {'word': 'ملعب كرة قدم', 'category': 'أماكن'},
    {'word': 'مكتبة', 'category': 'أماكن'},
    {'word': 'حديقة حيوان', 'category': 'أماكن'},
    {'word': 'مسجد', 'category': 'أماكن'},
    {'word': 'قصر', 'category': 'أماكن'},
    {'word': 'فندق 5 نجوم', 'category': 'أماكن'},
    {'word': 'مجمع تجاري', 'category': 'أماكن'},

    // ===== مواصلات =====
    {'word': 'قطار', 'category': 'مواصلات'},
    {'word': 'طائرة', 'category': 'مواصلات'},
    {'word': 'سيارة سباق', 'category': 'مواصلات'},
    {'word': 'غواصة', 'category': 'مواصلات'},
    {'word': 'دراجة نارية', 'category': 'مواصلات'},
    {'word': 'سفينة بضائع', 'category': 'مواصلات'},
    {'word': 'حافلة مدرسية', 'category': 'مواصلات'},
    {'word': 'منطاد', 'category': 'مواصلات'},
    {'word': 'تلفريك', 'category': 'مواصلات'},
    {'word': 'شاحنة كبيرة', 'category': 'مواصلات'},

    // ===== معالم =====
    {'word': 'القدس الشريف', 'category': 'معالم'},
    {'word': 'برج إيفل', 'category': 'معالم'},
    {'word': 'الأهرامات', 'category': 'معالم'},
    {'word': 'تمثال الحرية', 'category': 'معالم'},
    {'word': 'سور الصين العظيم', 'category': 'معالم'},
    {'word': 'برج خليفة', 'category': 'معالم'},
    {'word': 'تاج محل', 'category': 'معالم'},
    {'word': 'ساعة بيغ بين', 'category': 'معالم'},
    {'word': 'الكولوسيوم', 'category': 'معالم'},

    // ===== حيوانات =====
    {'word': 'قطة', 'category': 'حيوانات'},
    {'word': 'أسد', 'category': 'حيوانات'},
    {'word': 'دلفين', 'category': 'حيوانات'},
    {'word': 'فيل', 'category': 'حيوانات'},
    {'word': 'صقر', 'category': 'حيوانات'},
    {'word': 'بطريق', 'category': 'حيوانات'},
    {'word': 'زرافة', 'category': 'حيوانات'},
    {'word': 'نمر', 'category': 'حيوانات'},
    {'word': 'قرش', 'category': 'حيوانات'},
    {'word': 'ذئب', 'category': 'حيوانات'},

    // ===== طعام =====
    {'word': 'بيتزا', 'category': 'طعام'},
    {'word': 'سوشي', 'category': 'طعام'},
    {'word': 'برغر', 'category': 'طعام'},
    {'word': 'كعكة عيد ميلاد', 'category': 'طعام'},
    {'word': 'شاورما', 'category': 'طعام'},
    {'word': 'فلافل', 'category': 'طعام'},
    {'word': 'منسف', 'category': 'طعام'},
    {'word': 'كبسة', 'category': 'طعام'},
    {'word': 'باستا', 'category': 'طعام'},
    {'word': 'آيس كريم', 'category': 'طعام'},

    // ===== رياضة =====
    {'word': 'كرة القدم', 'category': 'رياضة'},
    {'word': 'السباحة', 'category': 'رياضة'},
    {'word': 'الملاكمة', 'category': 'رياضة'},
    {'word': 'كرة السلة', 'category': 'رياضة'},
    {'word': 'كرة الطائرة', 'category': 'رياضة'},
    {'word': 'التنس', 'category': 'رياضة'},
    {'word': 'الكاراتيه', 'category': 'رياضة'},
    {'word': 'فروسية', 'category': 'رياضة'},

    // ===== أجهزة =====
    {'word': 'ثلاجة', 'category': 'أجهزة'},
    {'word': 'تلفزيون', 'category': 'أجهزة'},
    {'word': 'هاتف', 'category': 'أجهزة'},
    {'word': 'حاسوب محمول', 'category': 'أجهزة'},
    {'word': 'غسالة', 'category': 'أجهزة'},
    {'word': 'مكيف هوائي', 'category': 'أجهزة'},
    {'word': 'ساعة ذكية', 'category': 'أجهزة'},

    // ===== مهن =====
    {'word': 'طبيب', 'category': 'مهن'},
    {'word': 'مهندس', 'category': 'مهن'},
    {'word': 'طيار', 'category': 'مهن'},
    {'word': 'رائد فضاء', 'category': 'مهن'},
    {'word': 'طباخ', 'category': 'مهن'},
    {'word': 'شرطي', 'category': 'مهن'},
    {'word': 'رجل إطفاء', 'category': 'مهن'},
  ];

  // ===== Get all approved images (Default + Firestore Custom Images) =====
  Future<List<Map<String, String>>> getAllApprovedImages() async {
    final List<Map<String, String>> images = List.from(defaultDuoImages);
    try {
      final customDocs = await _firestore
          .collection('custom_images')
          .where('status', isEqualTo: 'approved')
          .get();

      for (var doc in customDocs.docs) {
        final data = doc.data();
        if (data['url'] != null) {
          images.add({
            'title': data['title']?.toString() ?? 'صورة جديدة',
            'url': data['url'].toString(),
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching custom images: $e");
    }
    return images;
  }

  // ===== Upload Custom Image (Requires Creator approval unless submitted by creator) =====
  Future<String> addGlobalCustomImage(
    String url, {
    String title = 'صورة خفية',
    bool isCreator = false,
    String submittedByName = 'لاعب',
    String submittedBySerialId = '',
    String submittedByEmail = '',
  }) async {
    final String cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return 'empty';

    // File payload limit validation (URL length / base64 max size 2MB)
    if (cleanUrl.length > 2500000) {
      return 'size_limit_exceeded'; // Enforce max 2MB size limit
    }

    if (isProfaneOrInappropriate(title)) {
      return 'profane';
    }

    await _firestore.collection('custom_images').add({
      'url': cleanUrl,
      'title': title.trim().isEmpty ? 'صورة جديدة' : title.trim(),
      'status': isCreator ? 'approved' : 'pending',
      'submittedByName': submittedByName,
      'submittedBySerialId': submittedBySerialId,
      'submittedByEmail': submittedByEmail,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return 'success';
  }

  // ===== Stream pending images for Creator Moderation Panel =====
  Stream<QuerySnapshot> streamPendingImages() {
    return _firestore
        .collection('custom_images')
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  // ===== Stream approved images for Creator Moderation Panel =====
  Stream<QuerySnapshot> streamApprovedImages() {
    return _firestore
        .collection('custom_images')
        .where('status', isEqualTo: 'approved')
        .snapshots();
  }

  // ===== Approve Custom Image =====
  Future<void> approveCustomImage(String docId, {String? updatedTitle}) async {
    final Map<String, dynamic> updateData = {
      'status': 'approved',
      'approvedAt': FieldValue.serverTimestamp(),
    };
    if (updatedTitle != null && updatedTitle.trim().isNotEmpty) {
      updateData['title'] = updatedTitle.trim();
    }
    await _firestore.collection('custom_images').doc(docId).update(updateData);
  }

  // ===== Update Custom Image Title =====
  Future<void> updateCustomImageTitle(String docId, String newTitle) async {
    final String clean = newTitle.trim();
    if (clean.isEmpty) return;
    await _firestore.collection('custom_images').doc(docId).update({
      'title': clean,
    });
  }

  // ===== Delete Custom Image =====
  Future<void> deleteCustomImage(String docId) async {
    await _firestore.collection('custom_images').doc(docId).delete();
  }

  // ===== Get all words (Defaults + Approved Custom Words from Firestore) =====
  Future<List<Map<String, String>>> getAllWords() async {
    final List<Map<String, String>> words = List.from(defaultWords);
    try {
      final customDocs = await _firestore
          .collection('custom_words')
          .where('status', isEqualTo: 'approved')
          .get();

      for (var doc in customDocs.docs) {
        final data = doc.data();
        if (data['word'] != null) {
          final String cat = (data['category'] != null && data['category'].toString().isNotEmpty)
              ? data['category'].toString()
              : 'فئة عشوائية (كلمات المستخدمين)';
          
          words.add({
            'word': data['word'].toString(),
            'category': cat,
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching custom words: $e");
    }
    return words;
  }

  // ===== Check if word already exists =====
  Future<bool> wordAlreadyExists(String word) async {
    final String clean = word.trim().toLowerCase();
    
    for (var item in defaultWords) {
      if (item['word']!.trim().toLowerCase() == clean) {
        return true;
      }
    }

    try {
      final customDocs = await _firestore.collection('custom_words').get();
      for (var doc in customDocs.docs) {
        final data = doc.data();
        if (data['word'] != null && data['word'].toString().trim().toLowerCase() == clean) {
          return true;
        }
      }
    } catch (e) {
      debugPrint("Error checking duplicate words: $e");
    }

    return false;
  }

  // ===== Add custom word =====
  Future<String> addGlobalCustomWord(
    String word,
    String category, {
    bool isCreator = false,
    String submittedByName = 'لاعب',
    String submittedBySerialId = '',
    String submittedByEmail = '',
  }) async {
    final String trimmed = word.trim();
    if (trimmed.isEmpty) return 'empty';

    if (isProfaneOrInappropriate(trimmed)) {
      return 'profane';
    }

    if (await wordAlreadyExists(trimmed)) {
      return 'duplicate';
    }

    final String finalCat = category.trim().isEmpty ? 'فئة عشوائية (كلمات المستخدمين)' : category.trim();

    await _firestore.collection('custom_words').add({
      'word': trimmed,
      'category': finalCat,
      'status': isCreator ? 'approved' : 'pending',
      'submittedByName': submittedByName,
      'submittedBySerialId': submittedBySerialId,
      'submittedByEmail': submittedByEmail,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return 'success';
  }

  // ===== Stream pending words for Admin Moderation Panel =====
  Stream<QuerySnapshot> streamPendingWords() {
    return _firestore
        .collection('custom_words')
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  // ===== Approve Pending Word =====
  Future<void> approveCustomWord(String docId) async {
    await _firestore.collection('custom_words').doc(docId).update({
      'status': 'approved',
      'approvedAt': FieldValue.serverTimestamp(),
    });
  }

  // ===== Delete/Reject Pending Word =====
  Future<void> deleteCustomWord(String docId) async {
    await _firestore.collection('custom_words').doc(docId).delete();
  }

  // ===== Get a random word by category =====
  Future<Map<String, String>> getRandomWordByCategory(String category) async {
    final all = await getAllWords();
    final List<Map<String, String>> filtered;

    if (category.isEmpty || category == 'الكل (عشوائي)' || category == 'auto') {
      filtered = all;
    } else {
      filtered = all.where((w) => w['category'] == category).toList();
    }

    if (filtered.isEmpty) {
      return all[Random().nextInt(all.length)];
    }

    return filtered[Random().nextInt(filtered.length)];
  }

  // ===== Save random content by selected category to room =====
  Future<void> saveContentByCategory(String roomId, String selectedCategory) async {
    final wordData = await getRandomWordByCategory(selectedCategory);
    await _firestore.collection('rooms').doc(roomId).update({
      'selectedCategory': selectedCategory,
      'content': {
        'type': 'text',
        'value': wordData['word'],
        'category': wordData['category'],
      },
    });
  }

  // ===== Save custom text content to room =====
  Future<void> saveTextContent(String roomId, String text) async {
    if (isProfaneOrInappropriate(text)) return;
    await _firestore.collection('rooms').doc(roomId).update({
      'content': {
        'type': 'text',
        'value': text,
        'category': 'فئة عشوائية (كلمات المستخدمين)',
      },
    });
  }

  // ===== Generate 4 multiple-choice options for the Spy from the same category =====
  Future<List<String>> generateSpyGuessOptions(String secretWord, String category) async {
    final allWords = await getAllWords();
    final sameCategoryWords = allWords
        .where((w) => w['category'] == category && w['word'] != secretWord)
        .map((w) => w['word']!)
        .toList()..shuffle();

    final List<String> decoys = sameCategoryWords.take(3).toList();
    
    if (decoys.length < 3) {
      final otherWords = allWords
          .where((w) => w['word'] != secretWord && !decoys.contains(w['word']))
          .map((w) => w['word']!)
          .toList()..shuffle();
      while (decoys.length < 3 && otherWords.isNotEmpty) {
        decoys.add(otherWords.removeAt(0));
      }
    }

    final List<String> options = [secretWord, ...decoys]..shuffle();
    return options;
  }

  // ===== Assign Spy & Start Group Game =====
  Future<void> startGameWithRoles(String roomId) async {
    final roomDoc = await _firestore.collection('rooms').doc(roomId).get();
    if (!roomDoc.exists) return;

    final roomData = roomDoc.data()!;
    final List<dynamic> players = roomData['players'] ?? [];
    final String selectedCategory = roomData['selectedCategory'] ?? 'الكل (عشوائي)';
    final Map<String, dynamic>? currentContent = roomData['content'] as Map<String, dynamic>?;

    if (players.isEmpty) return;

    // Pick random spy
    final random = Random();
    final int spyIndex = random.nextInt(players.length);
    final String spyUid = players[spyIndex]['uid'];

    if (currentContent == null || currentContent['value'] == null || currentContent['value'].toString().isEmpty) {
      final wordData = await getRandomWordByCategory(selectedCategory);
      await _firestore.collection('rooms').doc(roomId).update({
        'gameMode': 'group_word',
        'spyUid': spyUid,
        'status': 'playing',
        'currentRound': 1,
        'currentTurnIndex': 0,
        'votes': {},
        'spyGuessCorrect': null,
        'content': {
          'type': 'text',
          'value': wordData['word'],
          'category': wordData['category'],
        },
      });
    } else {
      await _firestore.collection('rooms').doc(roomId).update({
        'gameMode': 'group_word',
        'spyUid': spyUid,
        'status': 'playing',
        'currentRound': 1,
        'currentTurnIndex': 0,
        'votes': {},
        'spyGuessCorrect': null,
      });
    }
  }

  // ===== Start 2-Player Duo Game (Each player gets a distinct secret image) =====
  Future<void> startDuoImageGame(String roomId) async {
    final roomDoc = await _firestore.collection('rooms').doc(roomId).get();
    if (!roomDoc.exists) return;

    final roomData = roomDoc.data()!;
    final List<dynamic> players = roomData['players'] ?? [];
    if (players.length < 2) return;

    List<Map<String, String>> approvedImages = await getAllApprovedImages();
    if (approvedImages.isEmpty) {
      approvedImages = List.from(defaultDuoImages);
    }
    approvedImages.shuffle();

    final Map<String, dynamic> playerImages = {};

    // Assign 2 distinct images to the 2 players
    for (int i = 0; i < players.length; i++) {
      final String uid = players[i]['uid'] ?? '';
      if (uid.isNotEmpty) {
        final image = approvedImages[i % approvedImages.length];
        playerImages[uid] = {
          'title': image['title'] ?? 'صورة سرية',
          'url': image['url'] ?? 'assets/duo_1.jpg',
        };
      }
    }

    await _firestore.collection('rooms').doc(roomId).update({
      'gameMode': 'duo_image',
      'playerImages': playerImages,
      'status': 'playing',
      'currentRound': 1,
      'currentTurnIndex': 0,
      'votes': {},
    });
  }

  // ===== Advance Turn =====
  // ===== Advance Turn (Endless rounds until players choose to vote/reveal) =====
  Future<void> advanceTurn(String roomId) async {
    final roomDoc = await _firestore.collection('rooms').doc(roomId).get();
    if (!roomDoc.exists) return;

    final roomData = roomDoc.data()!;
    final List<dynamic> players = roomData['players'] ?? [];
    int currentTurnIndex = roomData['currentTurnIndex'] ?? 0;
    int currentRound = roomData['currentRound'] ?? 1;

    currentTurnIndex++;
    if (players.isNotEmpty && currentTurnIndex >= players.length) {
      currentTurnIndex = 0;
      currentRound++;
    }

    await _firestore.collection('rooms').doc(roomId).update({
      'currentTurnIndex': currentTurnIndex,
      'currentRound': currentRound,
    });
  }

  // ===== Play Again Directly with Same Room =====
  Future<void> playAgainDirectly(String roomId) async {
    final roomDoc = await _firestore.collection('rooms').doc(roomId).get();
    if (!roomDoc.exists) return;

    final roomData = roomDoc.data()!;
    final String gameMode = roomData['gameMode'] ?? 'group_word';
    final List<dynamic> players = roomData['players'] ?? [];

    if (gameMode == 'duo_image') {
      await startDuoImageGame(roomId);
    } else {
      final String selectedCategory = roomData['selectedCategory'] ?? 'الكل (عشوائي)';
      if (players.isEmpty) return;

      final random = Random();
      final int spyIndex = random.nextInt(players.length);
      final String newSpyUid = players[spyIndex]['uid'];

      final newWordData = await getRandomWordByCategory(selectedCategory);

      await _firestore.collection('rooms').doc(roomId).update({
        'gameMode': 'group_word',
        'spyUid': newSpyUid,
        'status': 'playing',
        'currentRound': 1,
        'currentTurnIndex': 0,
        'votes': {},
        'spyGuessCorrect': null,
        'activeMicPlayers': [],
        'content': {
          'type': 'text',
          'value': newWordData['word'],
          'category': newWordData['category'],
        },
      });
    }
  }
}
