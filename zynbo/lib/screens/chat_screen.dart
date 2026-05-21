import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/message_model.dart';
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

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      await ChatService.instance.sendMessage(
        chatId: widget.chatId,
        senderId: widget.currentUid,
        text: text,
      );
      // scroll to newest
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ZynboApp.brandCream,
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: ZynboApp.brandTeal,
              child: ClipOval(
                child: (widget.otherPhoto != null &&
                        widget.otherPhoto!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: widget.otherPhoto!,
                        fit: BoxFit.cover,
                        width: 36,
                        height: 36,
                        errorWidget: (_, __, ___) =>
                            const Icon(Icons.person, color: Colors.white, size: 20),
                      )
                    : const Icon(Icons.person,
                        color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.otherName,
                    style: GoogleFonts.spaceGrotesk(
                      color: ZynboApp.brandInk,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    widget.otherStatus == 'online' ? 'Online' : 'Offline',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: widget.otherStatus == 'online'
                          ? Colors.green.shade700
                          : ZynboApp.brandInk.withOpacity(0.45),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ChatService.instance.getMessages(widget.chatId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(ZynboApp.brandTeal),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _EmptyConvo(name: widget.otherName);
                }
                final messages = docs.map(Message.fromDoc).toList();
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final m = messages[i];
                    final mine = m.senderId == widget.currentUid;
                    final showStamp = i == 0 ||
                        !_sameDay(messages[i - 1].timestamp, m.timestamp);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showStamp && m.timestamp != null)
                          _DayDivider(date: m.timestamp!),
                        _Bubble(message: m, mine: mine),
                      ],
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

class _Bubble extends StatelessWidget {
  final Message message;
  final bool mine;
  const _Bubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final bg = mine ? ZynboApp.brandTeal : Colors.white;
    final fg = mine ? Colors.white : ZynboApp.brandInk;
    final radius = mine
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
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
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
          boxShadow: mine
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
              message.text,
              style: GoogleFonts.spaceGrotesk(
                color: fg,
                fontSize: 15,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              message.timestamp == null
                  ? 'sending…'
                  : DateFormat('HH:mm').format(message.timestamp!),
              style: GoogleFonts.spaceGrotesk(
                color: fg.withOpacity(0.55),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
