import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import '../theme/zynbo_colors.dart';

/// ─────────────────────────── Day divider ───────────────────────────

class DayDivider extends StatelessWidget {
  final DateTime date;
  const DayDivider({super.key, required this.date});

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
            color: ZynboColors.surfaceHi.withOpacity(0.85),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ZynboColors.text.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }
}

/// ─────────────────────────── Read receipts ───────────────────────────

class ReadTicks extends StatelessWidget {
  final bool read;
  const ReadTicks({super.key, required this.read});

  @override
  Widget build(BuildContext context) {
    final tickColor =
        read ? ZynboColors.lime : ZynboColors.text.withOpacity(0.55);
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

/// ─────────────────────────── Sender name (groups) ───────────────────────────

class SenderName extends StatelessWidget {
  final String uid;
  const SenderName({super.key, required this.uid});

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
            color: ZynboColors.lime,
          ),
        );
      },
    );
  }
}

/// ─────────────────────────── Message bubble (all types) ───────────────────────────

class MessageBubble extends StatelessWidget {
  final bool isMe;
  final String type;
  final String text;
  final String? mediaUrl;
  final int durationMs;
  final DateTime? timestamp;
  final bool readByOther;
  final String senderId;
  final bool showSender;

  const MessageBubble({
    super.key,
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
    final bg = isMe ? ZynboColors.teal : ZynboColors.surfaceHi;
    final fg = ZynboColors.text;
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
      'image' => _ImageContent(mediaUrl: mediaUrl),
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 6,
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
                padding:
                    const EdgeInsets.only(bottom: 4, right: 4, left: 4),
                child: SenderName(uid: senderId),
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
                    ReadTicks(read: readByOther),
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

class _ImageContent extends StatelessWidget {
  final String? mediaUrl;
  const _ImageContent({required this.mediaUrl});

  @override
  Widget build(BuildContext context) {
    if (mediaUrl == null) {
      return Container(
        width: 200,
        height: 200,
        color: Colors.black26,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(ZynboColors.lime),
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
          color: Colors.black26,
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(ZynboColors.lime),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          width: 240,
          height: 180,
          color: Colors.black26,
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
      final isPlaying =
          s.playing && s.processingState != ProcessingState.completed;
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
    final accent = widget.isMe ? ZynboColors.lime : ZynboColors.lime;
    final fg = ZynboColors.text;
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
                  color: ZynboColors.deepInk,
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
