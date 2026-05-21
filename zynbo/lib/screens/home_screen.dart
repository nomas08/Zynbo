import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zynbo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NewChatScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              if (v == 'logout') {
                await AuthService.instance.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _ProfileCard(uid: uid),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Row(
              children: [
                Text(
                  'Chats',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: ZynboApp.brandInk,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _ChatList(currentUid: uid)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ZynboApp.brandLime,
        foregroundColor: ZynboApp.brandInk,
        elevation: 0,
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NewChatScreen()),
          );
        },
        icon: const Icon(Icons.chat_rounded),
        label: Text(
          'New chat',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String uid;
  const _ProfileCard({required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = data?['name'] as String? ?? '';
        final about = data?['about'] as String? ?? '';
        final photoUrl = data?['photo'] as String?;
        final status = (data?['status'] as String?) ?? 'offline';

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: ZynboApp.brandTeal,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: ZynboApp.brandLime, width: 2),
                  color: Colors.white24,
                ),
                clipBehavior: Clip.antiAlias,
                child: (photoUrl != null && photoUrl.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: photoUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.person, color: Colors.white),
                      )
                    : const Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Welcome' : 'Hi, $name',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      about.isEmpty ? 'Your space for great chats.' : about,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: status == 'online'
                      ? ZynboApp.brandLime
                      : Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status == 'online' ? 'Online' : 'Offline',
                  style: GoogleFonts.spaceGrotesk(
                    color: status == 'online'
                        ? ZynboApp.brandInk
                        : Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatList extends StatelessWidget {
  final String currentUid;
  const _ChatList({required this.currentUid});

  @override
  Widget build(BuildContext context) {
    if (currentUid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChatService.instance.getUserChats(currentUid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(ZynboApp.brandTeal),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const _EmptyChats();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data();
            final participants =
                (data['participants'] as List?)?.cast<String>() ?? [];
            final otherUid = participants.firstWhere(
              (p) => p != currentUid,
              orElse: () => '',
            );
            if (otherUid.isEmpty) return const SizedBox.shrink();

            return _ChatTile(
              chatId: docs[i].id,
              currentUid: currentUid,
              otherUid: otherUid,
              lastMessage: (data['lastMessage'] as String?) ?? '',
              updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
            );
          },
        );
      },
    );
  }
}

class _ChatTile extends StatelessWidget {
  final String chatId;
  final String currentUid;
  final String otherUid;
  final String lastMessage;
  final DateTime? updatedAt;

  const _ChatTile({
    required this.chatId,
    required this.currentUid,
    required this.otherUid,
    required this.lastMessage,
    required this.updatedAt,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(otherUid)
          .snapshots(),
      builder: (context, snap) {
        final u = snap.data?.data();
        final name = (u?['name'] as String?) ?? 'User';
        final photo = u?['photo'] as String?;
        final status = (u?['status'] as String?) ?? 'offline';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    chatId: chatId,
                    currentUid: currentUid,
                    otherUid: otherUid,
                    otherName: name,
                    otherPhoto: photo,
                    otherStatus: status,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: ZynboApp.brandTeal,
                        child: ClipOval(
                          child: (photo != null && photo.isNotEmpty)
                              ? CachedNetworkImage(
                                  imageUrl: photo,
                                  width: 52,
                                  height: 52,
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
                            width: 13,
                            height: 13,
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
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: ZynboApp.brandInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lastMessage.isEmpty
                              ? 'Tap to start chatting'
                              : lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 13,
                            color: ZynboApp.brandInk.withOpacity(0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (updatedAt != null)
                    Text(
                      _formatStamp(updatedAt!),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: ZynboApp.brandInk.withOpacity(0.45),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatStamp(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return DateFormat('HH:mm').format(t);
    }
    if (now.difference(t).inDays < 7) {
      return DateFormat('EEE').format(t); // Mon, Tue…
    }
    return DateFormat('d MMM').format(t);
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: ZynboApp.brandLime.withOpacity(0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.forum_rounded,
                  size: 42, color: ZynboApp.brandTeal),
            ),
            const SizedBox(height: 22),
            Text(
              'No conversations yet',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ZynboApp.brandInk,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "New chat" to find someone and say hello.',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                color: ZynboApp.brandInk.withOpacity(0.55),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
