import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/chat_service.dart';
import '../services/media_service.dart';
import '../theme/zynbo_colors.dart';
import '../widgets/chat_background.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String currentUid;
  final String otherUid; // empty for groups
  final String otherName;
  final String? otherPhoto;
  final String otherStatus;
  final bool isGroup;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.currentUid,
    required this.otherUid,
    required this.otherName,
    this.otherPhoto,
    this.otherStatus = 'offline',
    this.isGroup = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final AudioRecorder _recorder = AudioRecorder();
  final ImagePicker _picker = ImagePicker();

  bool _sending = false;
  bool _recording = false;
  DateTime? _recordStart;
  String? _recordingPath;
  Timer? _recordTicker;
  Duration _recordElapsed = Duration.zero;

  final Set<String> _markedRead = <String>{};
  Timer? _typingDebounce;
  bool _isTyping = false;

  List<String> _participants = [];

  @override
  void initState() {
    super.initState();
    ChatService.instance.markChatRead(
      chatId: widget.chatId,
      uid: widget.currentUid,
    );
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _recordTicker?.cancel();
    if (_isTyping) {
      ChatService.instance.setTyping(
        chatId: widget.chatId,
        uid: widget.currentUid,
        typing: false,
      );
    }
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ───── Typing debounce ─────
  void _onInputChanged() {
    final hasText = _input.text.trim().isNotEmpty;
    if (hasText && !_isTyping) {
      _isTyping = true;
      ChatService.instance.setTyping(
        chatId: widget.chatId,
        uid: widget.currentUid,
        typing: true,
      );
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 3), () {
      if (_isTyping) {
        _isTyping = false;
        ChatService.instance.setTyping(
          chatId: widget.chatId,
          uid: widget.currentUid,
          typing: false,
        );
      }
    });
    if (!hasText && _isTyping) {
      _typingDebounce?.cancel();
      _isTyping = false;
      ChatService.instance.setTyping(
        chatId: widget.chatId,
        uid: widget.currentUid,
        typing: false,
      );
    }
    setState(() {});
  }

  List<String> _recipients() =>
      _participants.where((p) => p != widget.currentUid).toList();

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    _typingDebounce?.cancel();
    _isTyping = false;
    try {
      await ChatService.instance.sendMessage(
        chatId: widget.chatId,
        senderId: widget.currentUid,
        recipientIds: _recipients(),
        text: text,
        type: 'text',
      );
      _scrollToBottom();
    } catch (e) {
      _snack('Send failed: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final xf = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 82,
      );
      if (xf == null) return;
      setState(() => _sending = true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final url = await MediaService.instance.uploadChatMedia(
        chatId: widget.chatId,
        file: File(xf.path),
        filename: 'img_$ts.jpg',
        contentType: 'image/jpeg',
      );
      await ChatService.instance.sendMessage(
        chatId: widget.chatId,
        senderId: widget.currentUid,
        recipientIds: _recipients(),
        type: 'image',
        mediaUrl: url,
      );
      _scrollToBottom();
    } catch (e) {
      _snack('Could not send image: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: ZynboColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImage(ImageSource.gallery);
                },
              ),
              _AttachOption(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                onTap: () {
                  Navigator.pop(context);
                  _pickAndSendImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───── Voice notes ─────
  Future<void> _startRecording() async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _snack('Microphone permission denied');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/zynbo_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 96000),
        path: path,
      );
      _recordingPath = path;
      _recordStart = DateTime.now();
      _recordElapsed = Duration.zero;
      _recordTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && _recordStart != null) {
          setState(() =>
              _recordElapsed = DateTime.now().difference(_recordStart!));
        }
      });
      setState(() => _recording = true);
    } catch (e) {
      _snack('Could not start recording: $e');
    }
  }

  Future<void> _cancelRecording() async {
    _recordTicker?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    final p = _recordingPath;
    if (p != null) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingPath = null;
      _recordStart = null;
      _recordElapsed = Duration.zero;
    });
  }

  Future<void> _stopAndSendRecording() async {
    _recordTicker?.cancel();
    final durationMs = _recordElapsed.inMilliseconds;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      _snack('Could not stop recorder: $e');
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingPath = null;
      _recordStart = null;
      _recordElapsed = Duration.zero;
    });
    if (path == null || durationMs < 800) {
      _snack('Hold longer to record');
      return;
    }
    try {
      setState(() => _sending = true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final url = await MediaService.instance.uploadChatMedia(
        chatId: widget.chatId,
        file: File(path),
        filename: 'voice_$ts.m4a',
        contentType: 'audio/m4a',
      );
      await ChatService.instance.sendMessage(
        chatId: widget.chatId,
        senderId: widget.currentUid,
        recipientIds: _recipients(),
        type: 'voice',
        mediaUrl: url,
        durationMs: durationMs,
      );
      _scrollToBottom();
    } catch (e) {
      _snack('Could not send voice note: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ───── Misc ─────
  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _markVisibleMessagesRead(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final batch = FirebaseFirestore.instance.batch();
    var any = false;
    for (final doc in docs) {
      if (_markedRead.contains(doc.id)) continue;
      final data = doc.data();
      if (data['senderId'] == widget.currentUid) {
        _markedRead.add(doc.id);
        continue;
      }
      final readBy = (data['readBy'] as List?)?.cast<String>() ?? const [];
      if (readBy.contains(widget.currentUid)) {
        _markedRead.add(doc.id);
        continue;
      }
      batch.update(doc.reference, {
        'readBy': FieldValue.arrayUnion([widget.currentUid]),
      });
      _markedRead.add(doc.id);
      any = true;
    }
    if (any) batch.commit().catchError((_) {});
  }

  bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ───── Build ─────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZynboColors.bg,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: ZynboColors.bg,
        elevation: 0,
        shape: Border(
          bottom: BorderSide(
            color: ZynboColors.text.withOpacity(0.06),
            width: 0.6,
          ),
        ),
        title: _ChatHeader(
          chatId: widget.chatId,
          currentUid: widget.currentUid,
          otherUid: widget.otherUid,
          fallbackName: widget.otherName,
          fallbackPhoto: widget.otherPhoto,
          initialStatus: widget.otherStatus,
          isGroup: widget.isGroup,
          onParticipants: (p) => _participants = p,
        ),
      ),
      body: ChatBackground(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: ChatService.instance.getMessages(widget.chatId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(ZynboColors.lime),
                      ),
                    );
                  }
                  final docs = snapshot.data!.docs;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _markVisibleMessagesRead(docs);
                  });
                  if (docs.isEmpty) {
                    return _EmptyConvo(name: widget.otherName);
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index];
                      final isMe = data['senderId'] == widget.currentUid;
                      final ts = (data['timestamp'] as Timestamp?)?.toDate();
                      final readBy =
                          (data['readBy'] as List?)?.cast<String>() ??
                              const [];
                      final readByAllOthers = widget.isGroup
                          ? (_participants.isNotEmpty &&
                              _participants
                                  .where((p) => p != widget.currentUid)
                                  .every(readBy.contains))
                          : (widget.otherUid.isNotEmpty &&
                              readBy.contains(widget.otherUid));
                      final type = (data['type'] as String?) ?? 'text';
                      final mediaUrl = data['mediaUrl'] as String?;
                      final durationMs =
                          (data['durationMs'] as num?)?.toInt() ?? 0;
                      final senderId = data['senderId'] as String? ?? '';

                      Widget? divider;
                      if (index == 0 ||
                          !_sameDay(
                              (docs[index - 1]['timestamp'] as Timestamp?)
                                  ?.toDate(),
                              ts)) {
                        if (ts != null) divider = DayDivider(date: ts);
                      }

                      final bubble = MessageBubble(
                        isMe: isMe,
                        type: type,
                        text: data['text'] as String? ?? '',
                        mediaUrl: mediaUrl,
                        durationMs: durationMs,
                        timestamp: ts,
                        readByOther: readByAllOthers,
                        senderId: senderId,
                        showSender: widget.isGroup && !isMe,
                      );

                      if (divider == null) return bubble;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [divider, bubble],
                      );
                    },
                  );
                },
              ),
            ),
            _Composer(
              controller: _input,
              sending: _sending,
              recording: _recording,
              recordElapsed: _recordElapsed,
              hasText: _input.text.trim().isNotEmpty,
              onSend: _sendText,
              onAttach: _showAttachmentSheet,
              onMicStart: _startRecording,
              onMicStop: _stopAndSendRecording,
              onMicCancel: _cancelRecording,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Header ───────────────────────────

class _ChatHeader extends StatelessWidget {
  final String chatId;
  final String currentUid;
  final String otherUid;
  final String fallbackName;
  final String? fallbackPhoto;
  final String initialStatus;
  final bool isGroup;
  final ValueChanged<List<String>> onParticipants;

  const _ChatHeader({
    required this.chatId,
    required this.currentUid,
    required this.otherUid,
    required this.fallbackName,
    required this.fallbackPhoto,
    required this.initialStatus,
    required this.isGroup,
    required this.onParticipants,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ChatService.instance.getChatDoc(chatId),
      builder: (context, chatSnap) {
        final chatData = chatSnap.data?.data() ?? const {};
        final participants =
            (chatData['participants'] as List?)?.cast<String>() ?? const [];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onParticipants(participants);
        });
        final typingMap =
            (chatData['typing'] as Map?)?.cast<String, dynamic>() ?? {};

        if (isGroup) {
          final name = (chatData['groupName'] as String?) ?? fallbackName;
          final photo = chatData['groupPhoto'] as String?;
          final memberCount = participants.length;
          final typers = typingMap.entries
              .where((e) => e.key != currentUid && e.value == true)
              .map((e) => e.key)
              .toList();
          return Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: ZynboColors.teal,
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: (photo != null && photo.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: photo,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const Icon(
                            Icons.group_rounded,
                            color: Colors.white,
                            size: 20),
                      )
                    : const Icon(Icons.group_rounded,
                        color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        color: ZynboColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (typers.isNotEmpty)
                      _TypingLine(
                          uids: typers,
                          suffix: typers.length == 1
                              ? 'is typing…'
                              : 'are typing…')
                    else
                      Text(
                        '$memberCount members',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          color: ZynboColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }

        // Direct
        final otherTyping = typingMap[otherUid] == true;
        return Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: ZynboColors.teal,
              child: ClipOval(
                child: (fallbackPhoto != null && fallbackPhoto!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: fallbackPhoto!,
                        fit: BoxFit.cover,
                        width: 36,
                        height: 36,
                        errorWidget: (_, __, ___) => const Icon(Icons.person,
                            color: Colors.white, size: 20),
                      )
                    : const Icon(Icons.person,
                        color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherUid)
                    .snapshots(),
                builder: (context, userSnap) {
                  final status =
                      (userSnap.data?.data()?['status'] as String?) ??
                          initialStatus;
                  String subtitle;
                  Color subtitleColor;
                  if (otherTyping) {
                    subtitle = 'typing…';
                    subtitleColor = ZynboColors.lime;
                  } else if (status == 'online') {
                    subtitle = 'Online';
                    subtitleColor = ZynboColors.online;
                  } else {
                    subtitle = 'Offline';
                    subtitleColor = ZynboColors.muted;
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fallbackName,
                        style: GoogleFonts.spaceGrotesk(
                          color: ZynboColors.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          color: subtitleColor,
                          fontWeight: FontWeight.w600,
                          fontStyle: otherTyping
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TypingLine extends StatelessWidget {
  final List<String> uids;
  final String suffix;
  const _TypingLine({required this.uids, required this.suffix});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uids.first)
          .snapshots(),
      builder: (context, snap) {
        final name = (snap.data?.data()?['name'] as String?) ?? 'Someone';
        final label = uids.length == 1
            ? '$name $suffix'
            : '$name +${uids.length - 1} $suffix';
        return Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 11,
            color: ZynboColors.lime,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
          ),
        );
      },
    );
  }
}

// ─────────────────────────── Empty + composer ───────────────────────────

class _EmptyConvo extends StatelessWidget {
  final String name;
  const _EmptyConvo({required this.name});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: ZynboColors.lime.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.waving_hand_rounded,
                  size: 38, color: ZynboColors.lime),
            ),
            const SizedBox(height: 18),
            Text(
              'Say hi to $name',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ZynboColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Be the first to break the ice.',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                color: ZynboColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final bool recording;
  final Duration recordElapsed;
  final bool hasText;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onMicStart;
  final VoidCallback onMicStop;
  final VoidCallback onMicCancel;

  const _Composer({
    required this.controller,
    required this.sending,
    required this.recording,
    required this.recordElapsed,
    required this.hasText,
    required this.onSend,
    required this.onAttach,
    required this.onMicStart,
    required this.onMicStop,
    required this.onMicCancel,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: ZynboColors.bg,
          border: Border(
            top: BorderSide(color: ZynboColors.text.withOpacity(0.06)),
          ),
        ),
        child: recording ? _recordingRow() : _normalRow(),
      ),
    );
  }

  Widget _normalRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: ZynboColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: ZynboColors.text.withOpacity(0.06)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_rounded,
                      color: ZynboColors.muted, size: 22),
                  onPressed: onAttach,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 15, color: ZynboColors.text),
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      hintStyle: GoogleFonts.spaceGrotesk(
                          color: ZynboColors.muted),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: ZynboColors.lime,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: sending ? null : (hasText ? onSend : onMicStart),
            child: SizedBox(
              width: 50,
              height: 50,
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation(ZynboColors.deepInk),
                      ),
                    )
                  : Icon(
                      hasText ? Icons.send_rounded : Icons.mic_rounded,
                      color: ZynboColors.deepInk,
                      size: 22,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _recordingRow() {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: ZynboColors.danger,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Recording  ${_fmt(recordElapsed)}',
          style: GoogleFonts.spaceGrotesk(
            color: ZynboColors.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: onMicCancel,
          child: Text(
            'Cancel',
            style: GoogleFonts.spaceGrotesk(
              color: ZynboColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Material(
          color: ZynboColors.lime,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onMicStop,
            child: const SizedBox(
              width: 50,
              height: 50,
              child: Icon(Icons.send_rounded,
                  color: ZynboColors.deepInk, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AttachOption(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: ZynboColors.surfaceHi,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: ZynboColors.lime, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ZynboColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
