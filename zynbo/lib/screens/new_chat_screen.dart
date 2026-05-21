import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';
import 'create_group_screen.dart';

/// Lets the user find another Zynbo member by email or name
/// and start a 1:1 chat with them.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final TextEditingController _query = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Start a new chat')),
      body: Column(
        children: [
          // "New group" entry
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Material(
              color: ZynboApp.brandTeal,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const CreateGroupScreen()),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: ZynboApp.brandLime,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.group_add_rounded,
                            color: ZynboApp.brandInk, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'New group',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Create a group chat with friends',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_rounded,
                          color: ZynboApp.brandLime),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: TextField(
              controller: _query,
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search by name or email',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('profileCompleted', isEqualTo: true)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(ZynboApp.brandTeal),
                    ),
                  );
                }
                final all = (snap.data?.docs ?? [])
                    .where((d) => d.id != currentUid)
                    .toList();

                final filtered = _q.isEmpty
                    ? all
                    : all.where((d) {
                        final data = d.data();
                        final name =
                            (data['name'] as String? ?? '').toLowerCase();
                        final email =
                            (data['email'] as String? ?? '').toLowerCase();
                        return name.contains(_q) || email.contains(_q);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      _q.isEmpty
                          ? 'No other Zynbo users yet.'
                          : 'No matches for "$_q".',
                      style: GoogleFonts.spaceGrotesk(
                        color: ZynboApp.brandInk.withOpacity(0.55),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final data = filtered[i].data();
                    final uid = data['uid'] as String? ?? filtered[i].id;
                    final name = (data['name'] as String?) ?? 'Unknown';
                    final email = (data['email'] as String?) ?? '';
                    final photo = data['photo'] as String?;
                    final status = (data['status'] as String?) ?? 'offline';

                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: ZynboApp.brandTeal,
                            child: ClipOval(
                              child: (photo != null && photo.isNotEmpty)
                                  ? CachedNetworkImage(
                                      imageUrl: photo,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          const Icon(Icons.person,
                                              color: Colors.white),
                                    )
                                  : const Icon(Icons.person,
                                      color: Colors.white),
                            ),
                          ),
                          if (status == 'online')
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.green.shade400,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: ZynboApp.brandCream, width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(
                        name,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: ZynboApp.brandInk,
                        ),
                      ),
                      subtitle: Text(
                        email,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          color: ZynboApp.brandInk.withOpacity(0.55),
                        ),
                      ),
                      onTap: () async {
                        final chatId =
                            await ChatService.instance.ensureChat(
                          currentUid: currentUid,
                          otherUid: uid,
                        );
                        if (!context.mounted) return;
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              chatId: chatId,
                              currentUid: currentUid,
                              otherUid: uid,
                              otherName: name,
                              otherPhoto: photo,
                              otherStatus: status,
                            ),
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
    );
  }
}
