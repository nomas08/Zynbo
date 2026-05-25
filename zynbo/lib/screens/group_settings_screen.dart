import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../theme/zynbo_colors.dart';

/// Group settings — members list, leave group, change photo, mute.
/// For direct chats, only the mute toggle is shown.
class GroupSettingsScreen extends StatefulWidget {
  final String chatId;
  final String currentUid;
  final bool isGroup;

  const GroupSettingsScreen({
    super.key,
    required this.chatId,
    required this.currentUid,
    required this.isGroup,
  });

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  bool _busy = false;

  Future<void> _changePhoto(BuildContext context) async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (xf == null) return;
    setState(() => _busy = true);
    try {
      final url = await MediaService.instance.uploadGroupPhoto(
        chatId: widget.chatId,
        file: File(xf.path),
      );
      await ChatService.instance.updateGroupPhoto(
        chatId: widget.chatId,
        photoUrl: url,
      );
    } catch (e) {
      if (mounted) _snack('Could not update photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renameGroup(BuildContext context, String current) async {
    final ctrl = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ZynboColors.surface,
        title: Text(
          'Rename group',
          style: GoogleFonts.spaceGrotesk(
              color: ZynboColors.text, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          maxLength: 40,
          autofocus: true,
          style: GoogleFonts.spaceGrotesk(color: ZynboColors.text),
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.spaceGrotesk(color: ZynboColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == current) return;
    try {
      await ChatService.instance.updateGroupName(
        chatId: widget.chatId,
        name: newName,
      );
    } catch (e) {
      if (mounted) _snack('Could not rename: $e');
    }
  }

  Future<void> _leaveGroup() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: ZynboColors.surface,
        title: Text(
          'Leave group?',
          style: GoogleFonts.spaceGrotesk(
              color: ZynboColors.text, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'You will stop receiving messages from this group.',
          style: GoogleFonts.spaceGrotesk(color: ZynboColors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.spaceGrotesk(color: ZynboColors.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ZynboColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ChatService.instance.leaveGroup(
        chatId: widget.chatId,
        uid: widget.currentUid,
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('Could not leave: $e');
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZynboColors.bg,
      appBar: AppBar(
        title: Text(widget.isGroup ? 'Group info' : 'Chat info'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ChatService.instance.getChatDoc(widget.chatId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(ZynboColors.lime),
              ),
            );
          }
          final data = snap.data!.data();
          if (data == null) {
            return Center(
              child: Text('Chat unavailable',
                  style:
                      GoogleFonts.spaceGrotesk(color: ZynboColors.muted)),
            );
          }
          final isGroup = (data['type'] as String?) == 'group';
          final name = (data['groupName'] as String?) ?? 'Chat';
          final photo = data['groupPhoto'] as String?;
          final participants =
              (data['participants'] as List?)?.cast<String>() ?? const [];
          final createdBy = data['createdBy'] as String? ?? '';
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
          final mutedBy =
              (data['mutedBy'] as List?)?.cast<String>() ?? const [];
          final muted = mutedBy.contains(widget.currentUid);

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              const SizedBox(height: 16),
              _Hero(
                isGroup: isGroup,
                name: name,
                photo: photo,
                memberCount: participants.length,
                createdAt: createdAt,
                onEditPhoto: isGroup && !_busy ? () => _changePhoto(context) : null,
                onEditName:
                    isGroup && !_busy ? () => _renameGroup(context, name) : null,
              ),
              const SizedBox(height: 16),
              _SectionCard(
                children: [
                  _SettingTile(
                    icon: muted
                        ? Icons.notifications_off_rounded
                        : Icons.notifications_rounded,
                    title: muted ? 'Muted' : 'Notifications',
                    subtitle: muted ? 'You won\'t be notified' : 'On',
                    trailing: Switch.adaptive(
                      value: !muted,
                      activeColor: ZynboColors.lime,
                      onChanged: (on) async {
                        await ChatService.instance.setMuted(
                          chatId: widget.chatId,
                          uid: widget.currentUid,
                          muted: !on,
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (isGroup) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: Text(
                    '${participants.length} members',
                    style: GoogleFonts.spaceGrotesk(
                      color: ZynboColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                _SectionCard(
                  children: [
                    for (final uid in participants)
                      _MemberRow(
                        uid: uid,
                        isYou: uid == widget.currentUid,
                        isAdmin: uid == createdBy,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _SectionCard(
                  children: [
                    _SettingTile(
                      icon: Icons.exit_to_app_rounded,
                      title: 'Leave group',
                      subtitle: 'You will stop receiving messages',
                      iconColor: ZynboColors.danger,
                      titleColor: ZynboColors.danger,
                      onTap: _busy ? null : _leaveGroup,
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ───────────── Hero ─────────────

class _Hero extends StatelessWidget {
  final bool isGroup;
  final String name;
  final String? photo;
  final int memberCount;
  final DateTime? createdAt;
  final VoidCallback? onEditPhoto;
  final VoidCallback? onEditName;

  const _Hero({
    required this.isGroup,
    required this.name,
    required this.photo,
    required this.memberCount,
    required this.createdAt,
    required this.onEditPhoto,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: onEditPhoto,
            child: Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ZynboColors.teal,
                    border: Border.all(color: ZynboColors.lime, width: 3),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (photo != null && photo!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: photo!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(
                              isGroup ? Icons.group_rounded : Icons.person,
                              color: Colors.white,
                              size: 50),
                        )
                      : Icon(
                          isGroup ? Icons.group_rounded : Icons.person,
                          color: Colors.white,
                          size: 50,
                        ),
                ),
                if (onEditPhoto != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: ZynboColors.lime,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          size: 18, color: ZynboColors.deepInk),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: onEditName,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    color: ZynboColors.text,
                  ),
                ),
                if (onEditName != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.edit_rounded,
                      size: 16, color: ZynboColors.muted),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isGroup
                ? '$memberCount members${createdAt != null ? '  ·  created ${DateFormat('d MMM yyyy').format(createdAt!)}' : ''}'
                : 'Direct chat',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              color: ZynboColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────── Section card ─────────────

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: ZynboColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }
}

// ───────────── Setting tile ─────────────

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(icon,
                  color: iconColor ?? ZynboColors.lime, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: titleColor ?? ZynboColors.text,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          color: ZynboColors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────── Member row ─────────────

class _MemberRow extends StatelessWidget {
  final String uid;
  final bool isYou;
  final bool isAdmin;
  const _MemberRow(
      {required this.uid, required this.isYou, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = (data?['name'] as String?) ?? 'Unknown';
        final email = (data?['email'] as String?) ?? '';
        final photo = data?['photo'] as String?;
        final status = (data?['status'] as String?) ?? 'offline';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: ZynboColors.teal,
                    child: ClipOval(
                      child: (photo != null && photo.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: photo,
                              fit: BoxFit.cover,
                              width: 44,
                              height: 44,
                              errorWidget: (_, __, ___) => const Icon(
                                  Icons.person,
                                  color: Colors.white),
                            )
                          : const Icon(Icons.person, color: Colors.white),
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
                          color: ZynboColors.online,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: ZynboColors.surface, width: 2),
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
                        Flexible(
                          child: Text(
                            isYou ? 'You' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: ZynboColors.text,
                            ),
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: ZynboColors.lime.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'admin',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: ZynboColors.lime,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        color: ZynboColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
