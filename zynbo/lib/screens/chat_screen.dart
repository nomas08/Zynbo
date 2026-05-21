import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../main.dart';
import '../services/chat_service.dart';
import '../services/media_service.dart';

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

  /// Cached participants list (for group recipient computation).
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

  // ───────────── Typing ─────────────

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
    setState(() {}); // refresh composer (mic ↔ send swap)
  }

  // ───────────── Recipients (1:1 + groups) ─────────────

  List<String> _recipients() {
    return _participants.where((p) => p != widget.currentUid).toList();
  }

  // ───────────── Send text ─────────────

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

  // ───────────── Send image ─────────────

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
      backgroundColor: ZynboApp.brandCream,
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

  // ───────────── Voice notes ─────────────

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
          setState(() => _recordElapsed =
              DateTime.now().difference(_recordStart!));
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

  // ───────────── Helpers ─────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  // ───────────── Build ─────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZynboApp.brandCream,
      appBar: AppBar(
        titleSpacing: 0,
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
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ChatService.instance.getMessages(widget.chatId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(ZynboApp.brandTeal),
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
                      if (ts != null) divider = _DayDivider(date: ts);
                    }

                    final bubble = _MessageBubble(
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
        // Push participants up so screen can compute recipients/read-by-all.
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
              _GroupAvatar(photo: photo, fallback: name),
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
                        color: ZynboApp.brandInk,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (typers.isNotEmpty)
                      _TypingLine(
                          uids: typers, suffix: typers.length == 1 ? 'is typing…' : 'are typing…')
                    else
                      Text(
                        '$memberCount members',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 11,
                          color: ZynboApp.brandInk.withOpacity(0.55),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }

        // ── Direct chat ──
        final otherTyping = typingMap[otherUid] == true;
        return Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: ZynboApp.brandTeal,
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
                    subtitleColor = ZynboApp.brandTeal;
                  } else if (status == 'online') {
                    subtitle = 'Online';
                    subtitleColor = Colors.green.shade700;
                  } else {
                    subtitle = 'Offline';
                    subtitleColor = ZynboApp.brandInk.withOpacity(0.45);
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fallbackName,
                        style: GoogleFonts.spaceGrotesk(
                          color: ZynboApp.brandInk,
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

class _GroupAvatar extends StatelessWidget {
  final String? photo;
  final String fallback;
  const _GroupAvatar({required this.photo, required this.fallback});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: ZynboApp.brandTeal,
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: (photo != null && photo!.isNotEmpty)
          ? CachedNetworkImage(
              imageUrl: photo!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) =>
                  const Icon(Icons.group_rounded, color: Colors.white, size: 20),
            )
          : const Icon(Icons.group_rounded, color: Colors.white, size: 20),
    );
  }
}

class _TypingLine extends StatelessWidget {
  final List<String> uids;
  final String suffix;
  const _TypingLine({required this.uids, required this.suffix});

  @override
  Widget build(BuildContext context) {
    final first = uids.first;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(first)
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
            color: ZynboApp.brandTeal,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
          ),
        );
      },
    );
  }
}

// ─────────────────────────── Message bubble ───────────────────────────

class _MessageBubble extends StatelessWidget {
  final bool isMe;
  final String type;
  final String text;
  final String? mediaUrl;
  final int durationMs;
  final DateTime? timestamp;
  final bool readByOther;
  final String senderId;
  final bool showSender;

  const _MessageBubble({
    required this.isMe,
    required this.type,
    required this.text,
    required this.mediaUrl,
    required this.durationMs,
    required this.timestamp,
    required this.readByOther,
    required this.senderId,
    required this.showSender,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMe ? ZynboApp.brandTeal : Colors.white;
    final fg = isMe ? Colors.white : ZynboApp.brandInk;
    final radius = isMe
        ? const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          );

    final bubbleChild = switch (type) {
      'image' => _ImageContent(mediaUrl: mediaUrl, fg: fg),
      'voice' => _VoiceContent(
          mediaUrl: mediaUrl,
          durationMs: durationMs,
          isMe: isMe,
        ),
      _ => Text(
          text,
          style: GoogleFonts.spaceGrotesk(
            color: fg,
            fontSize: 15,
            height: 1.35,
          ),
        ),
    };

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: type == 'image'
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: radius,
          boxShadow: isMe
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSender)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, right: 4, left: 4),
                child: _SenderName(uid: senderId),
              ),
            bubbleChild,
            Padding(
              padding: EdgeInsets.only(
                top: type == 'image' ? 6 : 2,
                right: type == 'image' ? 8 : 0,
                bottom: type == 'image' ? 4 : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timestamp == null
                        ? 'sending…'
                        : DateFormat('HH:mm').format(timestamp!),
                    style: GoogleFonts.spaceGrotesk(
                      color: fg.withOpacity(0.55),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _ReadTicks(read: readByOther),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SenderName extends StatelessWidget {
  final String uid;
  const _SenderName({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        final name = (snap.data?.data()?['name'] as String?) ?? '';
        if (name.isEmpty) return const SizedBox.shrink();
        return Text(
          name,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: ZynboApp.brandTeal,
          ),
        );
      },
    );
  }
}

class _ImageContent extends StatelessWidget {
  final String? mediaUrl;
  final Color fg;
  const _ImageContent({required this.mediaUrl, required this.fg});

  @override
  Widget build(BuildContext context) {
    if (mediaUrl == null) {
      return Container(
        width: 200,
        height: 200,
        color: Colors.black12,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(ZynboApp.brandLime),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CachedNetworkImage(
        imageUrl: mediaUrl!,
        width: 260,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 240,
          height: 180,
          color: Colors.black12,
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(ZynboApp.brandLime),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          width: 240,
          height: 180,
          color: Colors.black12,
          child: const Icon(Icons.broken_image_rounded,
              color: Colors.white70),
        ),
      ),
    );
  }
}

class _VoiceContent extends StatefulWidget {
  final String? mediaUrl;
  final int durationMs;
  final bool isMe;
  const _VoiceContent({
    required this.mediaUrl,
    required this.durationMs,
    required this.isMe,
  });

  @override
  State<_VoiceContent> createState() => _VoiceContentState();
}

class _VoiceContentState extends State<_VoiceContent> {
  late final AudioPlayer _player;
  bool _ready = false;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _stateSub = _player.playerStateStream.listen((s) {
      if (!mounted) return;
      final isPlaying = s.playing && s.processingState != ProcessingState.completed;
      setState(() => _playing = isPlaying);
      if (s.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
    _posSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _prepare();
  }

  Future<void> _prepare() async {
    if (widget.mediaUrl == null) return;
    try {
      await _player.setUrl(widget.mediaUrl!);
      if (mounted) setState(() => _ready = true);
    } catch (_) {/* swallow */}
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        widget.isMe ? ZynboApp.brandLime : ZynboApp.brandTeal;
    final fg = widget.isMe ? Colors.white : ZynboApp.brandInk;
    final total = Duration(milliseconds: widget.durationMs);
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return SizedBox(
      width: 220,
      child: Row(
        children: [
          Material(
            color: accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _toggle,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: widget.isMe ? ZynboApp.brandInk : Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: fg.withOpacity(0.18),
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _playing ? _fmt(_position) : _fmt(total),
                  style: GoogleFonts.spaceGrotesk(
                    color: fg.withOpacity(0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadTicks extends StatelessWidget {
  final bool read;
  const _ReadTicks({required this.read});

  @override
  Widget build(BuildContext context) {
    final tickColor =
        read ? ZynboApp.brandLime : Colors.white.withOpacity(0.55);
    return SizedBox(
      width: 16,
      height: 12,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: read ? 0 : 2,
            child: Icon(Icons.check_rounded, size: 12, color: tickColor),
          ),
          if (read)
            Positioned(
              left: 5,
              child: Icon(Icons.check_rounded, size: 12, color: tickColor),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Misc UI ───────────────────────────

class _DayDivider extends StatelessWidget {
  final DateTime date;
  const _DayDivider({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      label = 'Today';
    } else if (now.difference(date).inDays == 1) {
      label = 'Yesterday';
    } else {
      label = DateFormat('d MMM yyyy').format(date);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: ZynboApp.brandInk.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ZynboApp.brandInk.withOpacity(0.65),
            ),
          ),
        ),
      ),
    );
  }
}

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
                color: ZynboApp.brandLime.withOpacity(0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.waving_hand_rounded,
                  size: 38, color: ZynboApp.brandTeal),
            ),
            const SizedBox(height: 18),
            Text(
              'Say hi to $name',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ZynboApp.brandInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Be the first to break the ice.',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                color: ZynboApp.brandInk.withOpacity(0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Composer ───────────────────────────

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
          color: ZynboApp.brandCream,
          border: Border(
            top: BorderSide(color: ZynboApp.brandInk.withOpacity(0.06)),
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                  color: ZynboApp.brandInk.withOpacity(0.08)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_rounded,
                      color: ZynboApp.brandInk, size: 22),
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
                        fontSize: 15, color: ZynboApp.brandInk),
                    decoration: InputDecoration(
                      hintText: 'Message…',
                      hintStyle: GoogleFonts.spaceGrotesk(
                        color: ZynboApp.brandInk.withOpacity(0.4),
                      ),
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
          color: ZynboApp.brandInk,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: sending
                ? null
                : (hasText ? onSend : onMicStart),
            child: SizedBox(
              width: 50,
              height: 50,
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation(ZynboApp.brandLime),
                      ),
                    )
                  : Icon(
                      hasText ? Icons.send_rounded : Icons.mic_rounded,
                      color: ZynboApp.brandLime,
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
            color: Colors.redAccent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Recording  ${_fmt(recordElapsed)}',
          style: GoogleFonts.spaceGrotesk(
            color: ZynboApp.brandInk,
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
              color: ZynboApp.brandInk.withOpacity(0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Material(
          color: ZynboApp.brandInk,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onMicStop,
            child: const SizedBox(
              width: 50,
              height: 50,
              child: Icon(Icons.send_rounded,
                  color: ZynboApp.brandLime, size: 22),
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
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: ZynboApp.brandTeal,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(icon, color: ZynboApp.brandLime, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ZynboApp.brandInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
