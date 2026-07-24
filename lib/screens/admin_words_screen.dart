import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/content_service.dart';

Widget buildAdminImageWidget(String? url, {double? width, double? height, BoxFit fit = BoxFit.cover}) {
  if (url == null || url.trim().isEmpty) {
    return Image.asset('assets/duo_1.jpg', width: width, height: height, fit: fit);
  }

  final String cleanUrl = url.trim();

  if (cleanUrl.startsWith('assets/')) {
    return Image.asset(
      cleanUrl,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => Image.asset('assets/duo_1.jpg', width: width, height: height, fit: fit),
    );
  } else if (cleanUrl.startsWith('data:image/') || cleanUrl.contains('base64,')) {
    try {
      final base64Str = cleanUrl.split('base64,').last.replaceAll(RegExp(r'\s+'), '');
      return Image.memory(
        base64Decode(base64Str),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Image.asset('assets/duo_1.jpg', width: width, height: height, fit: fit),
      );
    } catch (_) {
      return Image.asset('assets/duo_1.jpg', width: width, height: height, fit: fit);
    }
  } else {
    return Image.network(
      cleanUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return Container(
          width: width,
          height: height,
          color: Colors.black26,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => Image.asset('assets/duo_1.jpg', width: width, height: height, fit: fit),
    );
  }
}

class AdminWordsScreen extends StatelessWidget {
  const AdminWordsScreen({super.key});

  void _showEditImageTitleDialog(BuildContext context, ContentService contentService, String docId, String currentTitle) {
    final TextEditingController controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('✏️ تعديل اسم/عنوان الصورة', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('اكتب الاسم الجديد للصورة:'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'اسم الصورة...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                Navigator.pop(dialogCtx);
                await contentService.updateCustomImageTitle(docId, newTitle);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ تم تعديل اسم الصورة إلى "$newTitle" بنجاح!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            child: const Text('حفظ التعديل'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ContentService contentService = ContentService();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة المحتوى المرفوع 👑'),
          backgroundColor: Colors.deepPurple.shade900,
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.text_fields), text: 'الكلمات المعلقة'),
              Tab(icon: Icon(Icons.pending_actions), text: 'الصور المعلقة'),
              Tab(icon: Icon(Icons.photo_library), text: 'الصور الحالية بالنظام'),
            ],
            indicatorColor: Colors.amberAccent,
            labelColor: Colors.amberAccent,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        body: TabBarView(
          children: [
            // ===== TAB 1: PENDING WORDS =====
            StreamBuilder<QuerySnapshot>(
              stream: contentService.streamPendingWords(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                        SizedBox(height: 16),
                        Text(
                          'لا توجد كلمات جديدة معلقة تنتظر الموافقة!',
                          style: TextStyle(fontSize: 16, color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String word = data['word'] ?? '';
                    final String category = data['category'] ?? 'فئة عشوائية';
                    final String submitter = data['submittedByName'] ?? 'لاعب';
                    final String submitterId = data['submittedBySerialId'] ?? '';
                    final String submitterEmail = data['submittedByEmail'] ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: Colors.grey.shade900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Colors.deepPurple, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  word,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '📁 $category',
                                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.shade800, width: 1),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '👤 مقدم الكلمة: $submitter',
                                    style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                  if (submitterId.isNotEmpty)
                                    Text(
                                      '🆔 الرقم التسلسلي: #$submitterId',
                                      style: const TextStyle(fontSize: 12, color: Colors.amberAccent),
                                    ),
                                  if (submitterEmail.isNotEmpty)
                                    Text(
                                      '✉️ البريد الإلكتروني: $submitterEmail',
                                      style: const TextStyle(fontSize: 12, color: Colors.cyanAccent),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      await contentService.approveCustomWord(doc.id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('✅ تم قبول ونشر كلمة "$word" للجميع!'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.check_circle),
                                    label: const Text('موافقة ونشر'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      await contentService.deleteCustomWord(doc.id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('❌ تم رفض وحذف كلمة "$word"'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.delete),
                                    label: const Text('رفض وحذف'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade900,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            // ===== TAB 2: PENDING IMAGES =====
            StreamBuilder<QuerySnapshot>(
              stream: contentService.streamPendingImages(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library_outlined, size: 80, color: Colors.green),
                        SizedBox(height: 16),
                        Text(
                          'لا توجد صور جديدة معلقة تنتظر الموافقة!',
                          style: TextStyle(fontSize: 16, color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String url = data['url'] ?? '';
                    final String title = data['title'] ?? 'صورة خفية';
                    final String submitter = data['submittedByName'] ?? 'لاعب';
                    final String submitterId = data['submittedBySerialId'] ?? '';
                    final String submitterEmail = data['submittedByEmail'] ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: Colors.grey.shade900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Colors.amber, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Interactive Zoomable Image Preview
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
                                              Text(
                                                title,
                                                style: const TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.amberAccent,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(16),
                                                child: Container(
                                                  constraints: const BoxConstraints(maxHeight: 380),
                                                  child: buildAdminImageWidget(url, fit: BoxFit.contain),
                                                ),
                                              ),
                                              const SizedBox(height: 14),
                                              Text(
                                                '👤 المقدم: $submitter ${submitterId.isNotEmpty ? "(#$submitterId)" : ""}',
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                              if (submitterEmail.isNotEmpty)
                                                Text(
                                                  '✉️ البريد: $submitterEmail',
                                                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
                                                ),
                                              const SizedBox(height: 16),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: ElevatedButton.icon(
                                                      onPressed: () async {
                                                        Navigator.pop(context);
                                                        await contentService.approveCustomImage(doc.id);
                                                      },
                                                      icon: const Icon(Icons.check_circle),
                                                      label: const Text('موافقة ونشر'),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.green.shade700,
                                                        foregroundColor: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: ElevatedButton.icon(
                                                      onPressed: () async {
                                                        Navigator.pop(context);
                                                        await contentService.deleteCustomImage(doc.id);
                                                      },
                                                      icon: const Icon(Icons.delete),
                                                      label: const Text('رفض وحذف'),
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor: Colors.red.shade900,
                                                        foregroundColor: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          width: 85,
                                          height: 85,
                                          color: Colors.black,
                                          child: buildAdminImageWidget(url, fit: BoxFit.cover),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 2,
                                        right: 2,
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: Colors.black87,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.amberAccent, width: 0.5),
                                          ),
                                          child: const Icon(Icons.zoom_in, color: Colors.amberAccent, size: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amberAccent,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
                                            tooltip: 'تعديل اسم الصورة',
                                            onPressed: () => _showEditImageTitleDialog(context, contentService, doc.id, title),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        '👤 المرفق: $submitter',
                                        style: const TextStyle(fontSize: 12, color: Colors.white),
                                      ),
                                      if (submitterId.isNotEmpty)
                                        Text(
                                          '🆔 الرقم: #$submitterId',
                                          style: const TextStyle(fontSize: 11, color: Colors.amber),
                                        ),
                                      if (submitterEmail.isNotEmpty)
                                        Text(
                                          '✉️ البريد: $submitterEmail',
                                          style: const TextStyle(fontSize: 11, color: Colors.cyanAccent),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      await contentService.approveCustomImage(doc.id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('✅ تم قبول ونشر الصورة للعبة الشخصين!'),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.check_circle),
                                    label: const Text('موافقة ونشر'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () => _showEditImageTitleDialog(context, contentService, doc.id, title),
                                  icon: const Icon(Icons.edit, size: 18),
                                  label: const Text('تعديل'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade800,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      await contentService.deleteCustomImage(doc.id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('❌ تم رفض وحذف الصورة'),
                                            backgroundColor: Colors.red,
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.delete),
                                    label: const Text('رفض وحذف'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade900,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),

            // ===== TAB 3: APPROVED SYSTEM IMAGES =====
            StreamBuilder<QuerySnapshot>(
              stream: contentService.streamApprovedImages(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.photo_library, size: 80, color: Colors.amber),
                        SizedBox(height: 16),
                        Text(
                          'لا توجد صور مضافة حالياً في قاعدة البيانات.',
                          style: TextStyle(fontSize: 16, color: Colors.white70),
                        ),
                      ],
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String url = data['url'] ?? '';
                    final String title = data['title'] ?? 'صورة اللعبة';
                    final String submitter = data['submittedByName'] ?? 'منشئ اللعبة';
                    final String submitterId = data['submittedBySerialId'] ?? '';
                    final String submitterEmail = data['submittedByEmail'] ?? '';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: Colors.grey.shade900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Colors.teal, width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Row(
                          children: [
                            // Tap to Zoom Image
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
                                          Text(
                                            title,
                                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                          ),
                                          const SizedBox(height: 12),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(16),
                                            child: Container(
                                              constraints: const BoxConstraints(maxHeight: 380),
                                              child: buildAdminImageWidget(url, fit: BoxFit.contain),
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            '👤 الناشر: $submitter ${submitterId.isNotEmpty ? "(#$submitterId)" : ""}',
                                            style: const TextStyle(color: Colors.white),
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
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 75,
                                  height: 75,
                                  color: Colors.black,
                                  child: buildAdminImageWidget(url, fit: BoxFit.cover),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amberAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '👤 الناشر: $submitter',
                                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                                  ),
                                  if (submitterId.isNotEmpty)
                                    Text(
                                      '🆔 الرقم: #$submitterId',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.cyanAccent),
                                  tooltip: 'تعديل اسم الصورة',
                                  onPressed: () => _showEditImageTitleDialog(context, contentService, doc.id, title),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                                  tooltip: 'حذف الصورة من اللعبة',
                                  onPressed: () async {
                                    await contentService.deleteCustomImage(doc.id);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('🗑️ تم حذف صورة "$title" من اللعبة.'),
                                          backgroundColor: Colors.orange.shade900,
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
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
      ),
    );
  }
}
