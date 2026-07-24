import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_service.dart';
import 'public_profile_dialog.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final UserService userService = UserService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('نجم الشهر 🌟'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: userService.streamLeaderboard(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('لا يوجد لاعبين بعد.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final String uid = docs[index].id;
              final String name = data['name'] ?? 'لاعب';
              final int monthlyPoints = data['monthlyPoints'] ?? 0;
              final int level = data['level'] ?? 1;
              final String avatarSeed = data['avatarSeed'] ?? UserService.availableAvatars[0];

              // Styling for top 3
              Color? tileColor;
              if (index == 0) tileColor = Colors.amber.withValues(alpha: 0.3);
              else if (index == 1) tileColor = Colors.grey.shade300;
              else if (index == 2) tileColor = Colors.brown.withValues(alpha: 0.3);

              return Card(
                color: tileColor,
                margin: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '#${index + 1}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: index < 3 ? Colors.deepPurple : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      CircleAvatar(
                        backgroundImage: NetworkImage(UserService.getAvatarUrl(avatarSeed)),
                      ),
                    ],
                  ),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('مستوى $level'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$monthlyPoints',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                      ),
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                    ],
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => PublicProfileDialog(uid: uid),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
