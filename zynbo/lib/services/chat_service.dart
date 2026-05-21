import 'package:cloud_firestore/cloud_firestore.dart';

/// All chat read/write logic lives here.
/// Chats are 1:1 with deterministic IDs derived from sorted UID pairs:
///   chatId = "uidA_uidB" (lexicographically sorted)
/// Each chat doc holds participants + lastMessage metadata + per-user unread counts.
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

  /// Ensures the parent /chats/{chatId} doc exists with participants list
  /// and a zeroed unreadCount map for both participants. Idempotent.
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
        'unreadCount': {
          currentUid: 0,
          otherUid: 0,
        },
      });
    }
    return chatId;
  }

  /// Send a text message into a chat. Bumps the parent doc's
  /// lastMessage + updatedAt + increments the recipient's unreadCount.
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String recipientId,
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
      'unreadCount.$recipientId': FieldValue.increment(1),
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

  /// Resets the unread counter for [uid] in [chatId] to zero.
  /// Called when the user opens a chat screen.
  Future<void> markChatRead({
    required String chatId,
    required String uid,
  }) async {
    try {
      await _db.collection('chats').doc(chatId).update({
        'unreadCount.$uid': 0,
      });
    } catch (_) {
      // best-effort; ignore if doc doesn't exist or field is missing
    }
  }
}
