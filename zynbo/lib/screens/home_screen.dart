import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/auth_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zynbo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {},
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
          _ProfileCard(uid: user?.uid ?? ''),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                Text(
                  'Coming soon',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ZynboApp.brandInk.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
          const Expanded(child: _EmptyChats()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: ZynboApp.brandLime,
        foregroundColor: ZynboApp.brandInk,
        elevation: 0,
        onPressed: () {},
        child: const Icon(Icons.chat_rounded),
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
              'Once you start chatting, your conversations will appear here.',
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
