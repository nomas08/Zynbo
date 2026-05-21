import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String currentUid;
  final String otherUid;
  final String otherName;
  final String? otherPhoto;
  final String otherStatus;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.currentUid,
    required this.otherUid,
    required this.otherName,
    this.otherPhoto,
    this.otherStatus = 'offline',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  // Read-receipt bookkeeping
  final Set<String> _markedRead = <String>{};

  // Typing-indicator bookkeeping
  Timer? _typingDebounce;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    // Clear unread badge for this chat as soon as the user opens it.
    ChatService.instance.markChatRead(
      chatId: widget.chatId,
      uid: widget.currentUid,
    );
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    // Make sure we don't leave a stale "typing…" flag behind.
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
    super.dispose();
  }

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
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    // Sending implies done typing; suppress further writes.
    _typingDebounce?.cancel();
    _isTyping = false;
    try {
      await ChatService.instance.sendMessage(
        chatId: widget.chatId,
        senderId: widget.currentUid,
        recipientId: widget.otherUid,
        text: text,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Side-effect: mark incoming unread messages as read by current user.
  /// Idempotent — we cache marked IDs locally.
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
    if (any) {
      // Fire-and-forget; rule allows participants to update only readBy.
      batch.commit().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZynboApp.brandCream,
      appBar: AppBar(
        titleSpacing: 0,
        title: _ChatHeader(
          chatId: widget.chatId,
          otherUid: widget.otherUid,
          otherName: widget.otherName,
          otherPhoto: widget.otherPhoto,
          initialStatus: widget.otherStatus,
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
                // Mark anything we don't own that we haven't already marked.
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
                    final readByOther = readBy.contains(widget.otherUid);

                    Widget? divider;
                    if (index == 0 ||
                        !_sameDay(
                            (docs[index - 1]['timestamp'] as Timestamp?)
                                ?.toDate(),
                            ts)) {
                      if (ts != null) divider = _DayDivider(date: ts);
                    }

                    final bubble = buildMessage(
                      data['text'],
                      isMe,
                      timestamp: ts,
                      readByOther: readByOther,
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
            onSend: _send,
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ──────────────────────── Reactive header ────────────────────────

class _ChatHeader extends StatelessWidget {
  final String chatId;
  final String otherUid;
  final String otherName;
  final String? otherPhoto;
  final String initialStatus;

  const _ChatHeader({
    required this.chatId,
    required this.otherUid,
    required this.otherName,
    required this.otherPhoto,
    required this.initialStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: ZynboApp.brandTeal,
          child: ClipOval(
            child: (otherPhoto != null && otherPhoto!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: otherPhoto!,
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
            stream: ChatService.instance.getChatDoc(chatId),
            builder: (context, chatSnap) {
              final typingMap =
                  (chatSnap.data?.data()?['typing'] as Map?)?.cast<String, dynamic>() ?? {};
              final otherTyping = typingMap[otherUid] == true;

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
                        otherName,
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
                          fontStyle:
                              otherTyping ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ──────────────────────── Bubble + checks ────────────────────────

/// Builds a single chat bubble.
/// Signature mirrors the canonical `buildMessage(text, isMe)` pattern.
/// For outgoing messages, [readByOther] drives the check-mark state:
///   • false → single grey check (sent)
///   • true  → double lime check on teal (read)
Widget buildMessage(
  String text,
  bool isMe, {
  DateTime? timestamp,
  bool readByOther = false,
}) {
  return Builder(
    builder: (context) {
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

      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76,
          ),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              Text(
                text,
                style: GoogleFonts.spaceGrotesk(
                  color: fg,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timestamp == null
                        ? 'sending…'
                        : DateFormat('HH:mm').format(timestamp),
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
            ],
          ),
        ),
      );
    },
  );
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

// ──────────────────────── Misc ────────────────────────

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

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: ZynboApp.brandInk.withOpacity(0.08)),
                ),
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
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: ZynboApp.brandInk,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
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
                      : const Icon(Icons.send_rounded,
                          color: ZynboApp.brandLime, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
