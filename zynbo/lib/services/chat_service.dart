import 'package:cloud_firestore/cloud_firestore.dart';

/// All chat read/write logic lives here.
/// Chats are 1:1 with deterministic IDs derived from sorted UID pairs:
///   chatId = "uidA_uidB" (lexicographically sorted)
/// Each chat doc holds participants + lastMessage metadata.
/// Messages live in /chats/{chatId}/messages/{messageId}.
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Deterministic 1:1 chat ID — same for both participants regardless of order.
  static String chatIdFor(String uidA, String uidB) {
    final pair = [uidA, uidB]..sort();
    return '${pair[0]}_${pair[1]}';
  }

  /// Ensures the parent /chats/{chatId} doc exists with participants list.
  /// Idempotent — safe to call before every send.
  Future<String> ensureChat({
    required String currentUid,
    required String otherUid,
  }) async {
    final chatId = chatIdFor(currentUid, otherUid);
    final docRef = _db.collection('chats').doc(chatId);
    final snap = await docRef.get();
    if (!snap.exists) {
      await docRef.set({
        'participants': [currentUid, otherUid],
        'lastMessage': '',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return chatId;
  }

  /// Send a text message into a chat. Also bumps the parent doc's
  /// lastMessage + updatedAt so the chat list can sort by recency.
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) async {
    final messagesRef =
        _db.collection('chats').doc(chatId).collection('messages');

    await messagesRef.add({
      'senderId': senderId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await _db.collection('chats').doc(chatId).update({
      'lastMessage': text,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream all messages in a chat, oldest → newest.
  Stream<QuerySnapshot<Map<String, dynamic>>> getMessages(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots();
  }

  /// Stream every chat that the current user participates in, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> getUserChats(String uid) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }
}
