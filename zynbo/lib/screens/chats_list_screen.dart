import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../theme/zynbo_colors.dart';
import '../widgets/chat_tile.dart';
import 'new_chat_screen.dart';

/// WhatsApp/Telegram-style chat list — Zynbo dark edition.
class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openNewChat() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NewChatScreen()),
    );
  }

  void _openProfileSheet() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ProfileSheet(uid: uid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: ZynboColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _HeaderBar(
              onAvatarTap: _openProfileSheet,
              currentUid: uid,
            ),
            _SearchBar(
              controller: _searchCtrl,
              onChanged: (v) =>
                  setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 4),
            Expanded(child: _ChatList(currentUid: uid, query: _query)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: ZynboColors.lime,
        foregroundColor: ZynboColors.deepInk,
        elevation: 6,
        onPressed: _openNewChat,
        child: const Icon(Icons.chat_rounded),
      ),
    );
  }
}

// ─────────────────────── Header ───────────────────────

class _HeaderBar extends StatelessWidget {
  final VoidCallback onAvatarTap;
  final String currentUid;
  const _HeaderBar(
      {required this.onAvatarTap, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: ZynboColors.lime,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_bubble_rounded,
                color: ZynboColors.deepInk, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            'Zynbo',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: ZynboColors.text,
            ),
          ),
          const Spacer(),
          if (currentUid.isNotEmpty)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUid)
                  .snapshots(),
              builder: (context, snap) {
                final photo = snap.data?.data()?['photo'] as String?;
                return GestureDetector(
                  onTap: onAvatarTap,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ZynboColors.teal,
                      border: Border.all(
                          color: ZynboColors.lime, width: 1.6),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: (photo != null && photo.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: photo,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 20),
                          )
                        : const Icon(Icons.person,
                            color: Colors.white, size: 20),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─────────────────────── Search ───────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          color: ZynboColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZynboColors.text.withOpacity(0.05)),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 15, color: ZynboColors.text),
          decoration: InputDecoration(
            hintText: 'Search chats',
            hintStyle:
                GoogleFonts.spaceGrotesk(color: ZynboColors.muted, fontSize: 15),
            prefixIcon: const Icon(Icons.search_rounded,
                color: ZynboColors.muted, size: 22),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────── Chat list ───────────────────────

class _ChatList extends StatelessWidget {
  final String currentUid;
  final String query;
  const _ChatList({required this.currentUid, required this.query});

  @override
  Widget build(BuildContext context) {
    if (currentUid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChatService.instance.getUserChats(currentUid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(ZynboColors.lime),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const _EmptyChats();

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
          itemCount: docs.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 84,
            color: ZynboColors.text.withOpacity(0.04),
          ),
          itemBuilder: (_, i) {
            final data = docs[i].data();
            final participants =
                (data['participants'] as List?)?.cast<String>() ?? [];
            final type = (data['type'] as String?) ?? 'direct';
            final isGroup = type == 'group';

            final otherUid = isGroup
                ? ''
                : participants.firstWhere(
                    (p) => p != currentUid,
                    orElse: () => '',
                  );
            if (!isGroup && otherUid.isEmpty) {
              return const SizedBox.shrink();
            }

            final unreadMap =
                (data['unreadCount'] as Map?)?.cast<String, dynamic>() ?? {};
            final unread = (unreadMap[currentUid] as num?)?.toInt() ?? 0;

            final typingMap =
                (data['typing'] as Map?)?.cast<String, dynamic>() ?? {};
            final otherTyping = isGroup
                ? typingMap.entries
                    .any((e) => e.key != currentUid && e.value == true)
                : (typingMap[otherUid] == true);

            return ChatTile(
              chatId: docs[i].id,
              currentUid: currentUid,
              otherUid: otherUid,
              isGroup: isGroup,
              groupName: data['groupName'] as String?,
              groupPhoto: data['groupPhoto'] as String?,
              memberCount: participants.length,
              lastMessage: (data['lastMessage'] as String?) ?? '',
              lastMessageType:
                  (data['lastMessageType'] as String?) ?? 'text',
              updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
              unread: unread,
              otherTyping: otherTyping,
              query: query,
            );
          },
        );
      },
    );
  }
}

// ─────────────────────── Empty state ───────────────────────

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
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: ZynboColors.lime.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.forum_rounded,
                  size: 50, color: ZynboColors.lime),
            ),
            const SizedBox(height: 24),
            Text(
              'Your chats live here',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: ZynboColors.text,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the chat button below to find a friend\nand send your first hello.',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                color: ZynboColors.muted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────── Profile sheet ───────────────────────

class _ProfileSheet extends StatelessWidget {
  final String uid;
  const _ProfileSheet({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ZynboColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, snap) {
          final data = snap.data?.data();
          final name = (data?['name'] as String?) ?? '';
          final email = (data?['email'] as String?) ?? '';
          final about = (data?['about'] as String?) ?? '';
          final photo = data?['photo'] as String?;
          final status = (data?['status'] as String?) ?? 'offline';

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: ZynboColors.text.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZynboColors.teal,
                  border: Border.all(color: ZynboColors.lime, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                child: (photo != null && photo.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: photo, fit: BoxFit.cover)
                    : const Icon(Icons.person,
                        color: Colors.white, size: 44),
              ),
              const SizedBox(height: 14),
              Text(
                name.isEmpty ? 'Zynbo user' : name,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: ZynboColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  color: ZynboColors.muted,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: status == 'online'
                      ? ZynboColors.lime
                      : ZynboColors.surfaceHi,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status == 'online' ? 'Online' : 'Offline',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: status == 'online'
                        ? ZynboColors.deepInk
                        : ZynboColors.muted,
                  ),
                ),
              ),
              if (about.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  about,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    color: ZynboColors.text.withOpacity(0.75),
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await AuthService.instance.signOut();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
