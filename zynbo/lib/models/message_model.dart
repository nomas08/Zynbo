import 'package:cloud_firestore/cloud_firestore.dart';

/// Message types supported in Zynbo chats.
enum MessageType { text, image, voice }

MessageType messageTypeFrom(String? raw) {
  switch (raw) {
    case 'image':
      return MessageType.image;
    case 'voice':
      return MessageType.voice;
    default:
      return MessageType.text;
  }
}

class Message {
  final String id;
  final String senderId;
  final String text;
  final MessageType type;
  final String? mediaUrl;
  final int? durationMs; // for voice messages
  final DateTime? timestamp;
  final List<String> readBy;

  Message({
    required this.id,
    required this.senderId,
    required this.text,
    this.type = MessageType.text,
    this.mediaUrl,
    this.durationMs,
    this.timestamp,
    this.readBy = const [],
  });

  factory Message.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Message(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      type: messageTypeFrom(data['type'] as String?),
      mediaUrl: data['mediaUrl'] as String?,
      durationMs: (data['durationMs'] as num?)?.toInt(),
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
      readBy: (data['readBy'] as List?)?.cast<String>() ?? const [],
    );
  }
}
