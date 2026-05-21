import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';
import 'chat_screen.dart';

/// Two-step group creation:
///   1. Pick at least 1 other member
///   2. Name the group + optional photo → Create
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final Set<String> _selectedUids = {};
  final Map<String, Map<String, dynamic>> _selectedUserData = {};
  bool _step2 = false;

  final TextEditingController _nameCtrl = TextEditingController();
  File? _photoFile;
  bool _creating = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final xf = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (xf != null && mounted) {
      setState(() => _photoFile = File(xf.path));
    }
  }

  Future<void> _createGroup() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selectedUids.isEmpty) return;
    setState(() => _creating = true);
    try {
      final participants = [currentUid, ..._selectedUids];

      // Create the chat doc first (so we have a chatId for storage path)
      final chatId = await ChatService.instance.createGroup(
        createdBy: currentUid,
        participants: participants,
        groupName: name,
      );

      // Optional photo upload + group doc update
      if (_photoFile != null) {
        final url = await MediaService.instance.uploadGroupPhoto(
          chatId: chatId,
          file: _photoFile!,
        );
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .update({'groupPhoto': url});
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          currentUid: currentUid,
          // For groups, otherUid is not used directly — pass placeholder
          otherUid: '',
          otherName: name,
          otherPhoto: null,
          otherStatus: 'group',
          isGroup: true,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create group: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step2 ? 'Name your group' : 'New group'),
        leading: _step2
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _step2 = false),
              )
            : null,
      ),
      body: _step2 ? _buildStep2() : _buildStep1(),
      floatingActionButton: _step2
          ? null
          : (_selectedUids.isEmpty
              ? null
              : FloatingActionButton.extended(
                  backgroundColor: ZynboApp.brandInk,
                  foregroundColor: ZynboApp.brandLime,
                  onPressed: () => setState(() => _step2 = true),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(
                    'Next (${_selectedUids.length})',
                    style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w700),
                  ),
                )),
    );
  }

  // ───────── Step 1: pick members ─────────

  Widget _buildStep1() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Column(
      children: [
        if (_selectedUids.isNotEmpty)
          SizedBox(
            height: 86,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: _selectedUids.map((uid) {
                final d = _selectedUserData[uid] ?? {};
                final n = (d['name'] as String?) ?? 'User';
                final p = d['photo'] as String?;
                return _SelectedChip(
                  name: n,
                  photo: p,
                  onRemove: () => setState(() {
                    _selectedUids.remove(uid);
                    _selectedUserData.remove(uid);
                  }),
                );
              }).toList(),
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
              final users = (snap.data?.docs ?? [])
                  .where((d) => d.id != currentUid)
                  .toList();
              if (users.isEmpty) {
                return Center(
                  child: Text(
                    'No other Zynbo users yet.',
                    style: GoogleFonts.spaceGrotesk(
                      color: ZynboApp.brandInk.withOpacity(0.55),
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (_, i) {
                  final data = users[i].data();
                  final uid = data['uid'] as String? ?? users[i].id;
                  final name = (data['name'] as String?) ?? 'Unknown';
                  final email = (data['email'] as String?) ?? '';
                  final photo = data['photo'] as String?;
                  final selected = _selectedUids.contains(uid);
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 22,
                      backgroundColor: ZynboApp.brandTeal,
                      child: ClipOval(
                        child: (photo != null && photo.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: photo,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const Icon(
                                    Icons.person,
                                    color: Colors.white),
                              )
                            : const Icon(Icons.person,
                                color: Colors.white),
                      ),
                    ),
                    title: Text(
                      name,
                      style: GoogleFonts.spaceGrotesk(
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
                    trailing: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? ZynboApp.brandLime
                            : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? ZynboApp.brandLime
                              : ZynboApp.brandInk.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded,
                              color: ZynboApp.brandInk, size: 16)
                          : null,
                    ),
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedUids.remove(uid);
                        _selectedUserData.remove(uid);
                      } else {
                        _selectedUids.add(uid);
                        _selectedUserData[uid] = data;
                      }
                    }),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ───────── Step 2: name + photo ─────────

  Widget _buildStep2() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  children: [
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ZynboApp.brandTeal,
                        border: Border.all(
                            color: ZynboApp.brandLime, width: 3),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _photoFile != null
                          ? Image.file(_photoFile!, fit: BoxFit.cover)
                          : const Icon(Icons.group_rounded,
                              color: Colors.white, size: 52),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: ZynboApp.brandLime,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            size: 18, color: ZynboApp.brandInk),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Group name',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ZynboApp.brandInk.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              maxLength: 40,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'e.g. Sunday hike crew',
              ),
            ),
            const Spacer(),
            Text(
              '${_selectedUids.length + 1} members',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                color: ZynboApp.brandInk.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (_creating || _nameCtrl.text.trim().isEmpty)
                  ? null
                  : _createGroup,
              child: _creating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text('Create group'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  final String name;
  final String? photo;
  final VoidCallback onRemove;
  const _SelectedChip(
      {required this.name, required this.photo, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: ZynboApp.brandTeal,
                child: ClipOval(
                  child: (photo != null && photo!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: photo!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const Icon(Icons.person,
                              color: Colors.white),
                        )
                      : const Icon(Icons.person, color: Colors.white),
                ),
              ),
              Positioned(
                right: -2,
                top: -2,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: ZynboApp.brandInk,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: ZynboApp.brandLime, size: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 60,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: ZynboApp.brandInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
