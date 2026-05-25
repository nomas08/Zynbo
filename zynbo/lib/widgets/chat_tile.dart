import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../screens/chat_screen.dart';
import '../theme/zynbo_colors.dart';
import 'unread_badge.dart';

/// A single row in the chats list — works for both direct and group chats.
/// Reactive: streams the other user's live profile + presence for direct chats.
class ChatTile extends StatelessWidget {
  final String chatId;
  final String currentUid;
  final String otherUid; // empty for groups
  final bool isGroup;
  final String? groupName;
  final String? groupPhoto;
  final int memberCount;
  final String lastMessage;
  final String lastMessageType; // 'text' | 'image' | 'voice'
  final DateTime? updatedAt;
  final int unread;
  final bool otherTyping;
  final bool muted;
  final String query;

  const ChatTile({
    super.key,
    required this.chatId,
    required this.currentUid,
    required this.otherUid,
    required this.isGroup,
    required this.groupName,
    required this.groupPhoto,
    required this.memberCount,
    required this.lastMessage,
    required this.lastMessageType,
    required this.updatedAt,
    required this.unread,
    required this.otherTyping,
    required this.muted,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    if (isGroup) {
      return _buildTile(
        context,
        name: groupName ?? 'Group',
        photo: groupPhoto,
        status: 'group',
        subtitleSuffix: '$memberCount members',
      );
    }
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
        return _buildTile(
          context,
          name: name,
          photo: photo,
          status: status,
          subtitleSuffix: null,
        );
      },
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required String name,
    required String? photo,
    required String status,
    required String? subtitleSuffix,
  }) {
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
                isGroup: isGroup,
              ),
            ),
          );
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(
                photo: photo,
                name: name,
                isGroup: isGroup,
                isOnline: isOnline,
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
                              color: ZynboColors.text,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        if (muted)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.volume_off_rounded,
                                size: 14, color: ZynboColors.muted),
                          ),
                        if (updatedAt != null)
                          Text(
                            _formatStamp(updatedAt!),
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: (hasUnread && !muted)
                                  ? ZynboColors.lime
                                  : ZynboColors.muted,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    _SubtitleRow(
                      otherTyping: otherTyping,
                      lastMessage: lastMessage,
                      lastMessageType: lastMessageType,
                      subtitleSuffix: subtitleSuffix,
                      hasUnread: hasUnread,
                      unread: unread,
                      muted: muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

class _Avatar extends StatelessWidget {
  final String? photo;
  final String name;
  final bool isGroup;
  final bool isOnline;

  const _Avatar({
    required this.photo,
    required this.name,
    required this.isGroup,
    required this.isOnline,
  });

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ZynboColors.teal,
            border: Border.all(
                color: ZynboColors.text.withOpacity(0.06), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: (photo != null && photo!.isNotEmpty)
              ? CachedNetworkImage(
                  imageUrl: photo!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Icon(
                    isGroup ? Icons.group_rounded : Icons.person,
                    color: Colors.white,
                  ),
                )
              : (isGroup
                  ? const Icon(Icons.group_rounded,
                      color: Colors.white, size: 28)
                  : Center(
                      child: Text(
                        _initials(name),
                        style: GoogleFonts.spaceGrotesk(
                          color: ZynboColors.lime,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )),
        ),
        if (!isGroup && isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: ZynboColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: ZynboColors.bg, width: 2.4),
              ),
            ),
          ),
      ],
    );
  }
}

class _SubtitleRow extends StatelessWidget {
  final bool otherTyping;
  final String lastMessage;
  final String lastMessageType;
  final String? subtitleSuffix;
  final bool hasUnread;
  final int unread;
  final bool muted;

  const _SubtitleRow({
    required this.otherTyping,
    required this.lastMessage,
    required this.lastMessageType,
    required this.subtitleSuffix,
    required this.hasUnread,
    required this.unread,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final showMediaIcon = !otherTyping && lastMessage.isNotEmpty;
    return Row(
      children: [
        if (showMediaIcon && lastMessageType == 'image')
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.photo_camera_outlined,
                size: 14, color: ZynboColors.muted),
          ),
        if (showMediaIcon && lastMessageType == 'voice')
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Icon(Icons.mic_none_rounded,
                size: 14, color: ZynboColors.muted),
          ),
        Expanded(
          child: Text(
            otherTyping
                ? 'typing…'
                : (lastMessage.isEmpty
                    ? (subtitleSuffix ?? 'Tap to start chatting')
                    : lastMessage),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13,
              color: otherTyping
                  ? ZynboColors.lime
                  : (hasUnread
                      ? ZynboColors.text.withOpacity(0.85)
                      : ZynboColors.muted),
              fontStyle: (otherTyping || lastMessage.isEmpty)
                  ? FontStyle.italic
                  : FontStyle.normal,
              fontWeight: (otherTyping || hasUnread)
                  ? FontWeight.w700
                  : FontWeight.w400,
            ),
          ),
        ),
        if (hasUnread) ...[
          const SizedBox(width: 8),
          // Muted chats use a subdued badge color
          muted
              ? Container(
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: ZynboColors.surfaceHi,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Center(
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: GoogleFonts.spaceGrotesk(
                        color: ZynboColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                )
              : UnreadBadge(count: unread),
        ],
      ],
    );
  }
}
