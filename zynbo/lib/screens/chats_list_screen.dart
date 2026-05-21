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

/// WhatsApp-style chat list — Zynbo edition.
/// Recent chats stream from /chats where participants array-contains me,
/// ordered by updatedAt desc. Each tile shows the other participant's
/// live name/photo/status, last message preview, smart timestamp, and
/// an unread badge sourced from the chat doc's unreadCount.{currentUid}.
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
      backgroundColor: ZynboApp.brandCream,
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
            Expanded(
              child: _ChatList(currentUid: uid, query: _query),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: ZynboApp.brandLime,
        foregroundColor: ZynboApp.brandInk,
        elevation: 6,
        onPressed: _openNewChat,
        child: const Icon(Icons.chat_rounded),
      ),
    );
  }
}

// ─────────────────────────── Header ───────────────────────────

class _HeaderBar extends StatelessWidget {
  final VoidCallback onAvatarTap;
  final String currentUid;
  const _HeaderBar({
    required this.onAvatarTap,
    required this.currentUid,
  });

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
              color: ZynboApp.brandTeal,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.chat_bubble_rounded,
                color: ZynboApp.brandLime, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            'Zynbo',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: ZynboApp.brandInk,
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
                      color: ZynboApp.brandTeal,
                      border: Border.all(
                          color: ZynboApp.brandLime, width: 1.6),
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

// ─────────────────────────── Search ───────────────────────────

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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ZynboApp.brandInk.withOpacity(0.06)),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: GoogleFonts.spaceGrotesk(
              fontSize: 15, color: ZynboApp.brandInk),
          decoration: InputDecoration(
            hintText: 'Search chats',
            hintStyle: GoogleFonts.spaceGrotesk(
              color: ZynboApp.brandInk.withOpacity(0.4),
              fontSize: 15,
            ),
            prefixIcon: Icon(Icons.search_rounded,
                color: ZynboApp.brandInk.withOpacity(0.45), size: 22),
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

// ─────────────────────────── Chat list ───────────────────────────

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
              valueColor: AlwaysStoppedAnimation(ZynboApp.brandTeal),
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
            color: ZynboApp.brandInk.withOpacity(0.06),
          ),
          itemBuilder: (_, i) {
            final data = docs[i].data();
            final participants =
                (data['participants'] as List?)?.cast<String>() ?? [];
            final otherUid = participants.firstWhere(
              (p) => p != currentUid,
              orElse: () => '',
            );
            if (otherUid.isEmpty) return const SizedBox.shrink();

            final unreadMap =
                (data['unreadCount'] as Map?)?.cast<String, dynamic>() ?? {};
            final unread = (unreadMap[currentUid] as num?)?.toInt() ?? 0;

            return _ChatTile(
              chatId: docs[i].id,
              currentUid: currentUid,
              otherUid: otherUid,
              lastMessage: (data['lastMessage'] as String?) ?? '',
              updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
              unread: unread,
              query: query,
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
  final int unread;
  final String query;

  const _ChatTile({
    required this.chatId,
    required this.currentUid,
    required this.otherUid,
    required this.lastMessage,
    required this.updatedAt,
    required this.unread,
    required this.query,
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
        final isOnline = status == 'online';
        final hasUnread = unread > 0;

        if (query.isNotEmpty &&
            !name.toLowerCase().contains(query) &&
            !lastMessage.toLowerCase().contains(query)) {
          return const SizedBox.shrink();
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
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
                  horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ZynboApp.brandTeal,
                          border: Border.all(
                              color: ZynboApp.brandInk.withOpacity(0.05),
                              width: 1),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: (photo != null && photo.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: photo,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const Icon(
                                    Icons.person,
                                    color: Colors.white),
                              )
                            : Center(
                                child: Text(
                                  _initials(name),
                                  style: GoogleFonts.spaceGrotesk(
                                    color: ZynboApp.brandLime,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                      ),
                      if (isOnline)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFF34D399),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: ZynboApp.brandCream, width: 2.4),
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 16,
                                  fontWeight: hasUnread
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  color: ZynboApp.brandInk,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (updatedAt != null)
                              Text(
                                _formatStamp(updatedAt!),
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: hasUnread
                                      ? ZynboApp.brandTeal
                                      : ZynboApp.brandInk.withOpacity(0.45),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (isOnline)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: ZynboApp.brandLime,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'online',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: ZynboApp.brandInk,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                lastMessage.isEmpty
                                    ? 'Tap to start chatting'
                                    : lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 13,
                                  color: hasUnread
                                      ? ZynboApp.brandInk.withOpacity(0.85)
                                      : (lastMessage.isEmpty
                                          ? ZynboApp.brandInk
                                              .withOpacity(0.4)
                                          : ZynboApp.brandInk
                                              .withOpacity(0.6)),
                                  fontStyle: lastMessage.isEmpty
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  fontWeight: hasUnread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (hasUnread) ...[
                              const SizedBox(width: 8),
                              _UnreadBadge(count: unread),
                            ],
                          ],
                        ),
                      ],
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

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  String _formatStamp(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return DateFormat('HH:mm').format(t);
    }
    if (now.difference(t).inDays == 1) return 'Yesterday';
    if (now.difference(t).inDays < 7) return DateFormat('EEE').format(t);
    return DateFormat('d MMM').format(t);
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;
  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: const BoxDecoration(
        color: ZynboApp.brandTeal,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.all(Radius.circular(22)),
      ),
      child: Center(
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            color: ZynboApp.brandLime,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Empty state ───────────────────────────

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
                color: ZynboApp.brandLime.withOpacity(0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.forum_rounded,
                  size: 50, color: ZynboApp.brandTeal),
            ),
            const SizedBox(height: 24),
            Text(
              'Your chats live here',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: ZynboApp.brandInk,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the chat button below to find a friend\nand send your first hello.',
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

// ─────────────────────────── Profile sheet ───────────────────────────

class _ProfileSheet extends StatelessWidget {
  final String uid;
  const _ProfileSheet({required this.uid});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ZynboApp.brandCream,
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
                  color: ZynboApp.brandInk.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ZynboApp.brandTeal,
                  border: Border.all(color: ZynboApp.brandLime, width: 3),
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
                  color: ZynboApp.brandInk,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                email,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  color: ZynboApp.brandInk.withOpacity(0.55),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: status == 'online'
                      ? ZynboApp.brandLime
                      : ZynboApp.brandInk.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status == 'online' ? 'Online' : 'Offline',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: status == 'online'
                        ? ZynboApp.brandInk
                        : ZynboApp.brandInk.withOpacity(0.6),
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
                    color: ZynboApp.brandInk.withOpacity(0.7),
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
