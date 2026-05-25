import 'package:cloud_firestore/cloud_firestore.dart';

/// Chat service — supports both 1:1 (`type: 'direct'`) and group (`type: 'group'`) chats.
///
/// Data shapes:
///   /chats/{chatId} = {
///     type: 'direct' | 'group',
///     participants: [uid, ...],            // 2 for direct, N for group
///     groupName: String?,                  // groups only
///     groupPhoto: String?,                 // groups only
///     createdBy: uid,                      // groups only
///     admins: [uid, ...],                  // groups only
///     lastMessage: String,
///     lastMessageType: 'text' | 'image' | 'voice',
///     updatedAt: serverTimestamp,
///     createdAt: serverTimestamp,
///     unreadCount: { uid: int },
///     typing:      { uid: bool },
///   }
///
///   /chats/{chatId}/messages/{messageId} = {
///     senderId, text, type, mediaUrl?, durationMs?, timestamp, readBy:[]
///   }
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Deterministic 1:1 chat ID — same for both participants regardless of order.
  static String chatIdFor(String uidA, String uidB) {
    final pair = [uidA, uidB]..sort();
    return '${pair[0]}_${pair[1]}';
  }

  // ─────────────────── Direct (1:1) ───────────────────

  /// Ensures the parent /chats/{chatId} doc exists for a direct chat. Idempotent.
  Future<String> ensureChat({
    required String currentUid,
    required String otherUid,
  }) async {
    final chatId = chatIdFor(currentUid, otherUid);
    final docRef = _db.collection('chats').doc(chatId);
    final snap = await docRef.get();
    if (!snap.exists) {
      await docRef.set({
        'type': 'direct',
        'participants': [currentUid, otherUid],
        'lastMessage': '',
        'lastMessageType': 'text',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'unreadCount': {currentUid: 0, otherUid: 0},
        'typing': {currentUid: false, otherUid: false},
      });
    }
    return chatId;
  }

  // ─────────────────── Groups ───────────────────

  /// Create a new group chat. Returns the auto-generated chatId.
  Future<String> createGroup({
    required String createdBy,
    required List<String> participants, // must include createdBy
    required String groupName,
    String? groupPhoto,
  }) async {
    assert(participants.contains(createdBy),
        'createdBy must be in participants');
    assert(participants.length >= 2, 'A group needs at least 2 members');

    final docRef = _db.collection('chats').doc();
    final unread = {for (final p in participants) p: 0};
    final typing = {for (final p in participants) p: false};

    await docRef.set({
      'type': 'group',
      'participants': participants,
      'groupName': groupName,
      'groupPhoto': groupPhoto,
      'createdBy': createdBy,
      'admins': [createdBy],
      'lastMessage': '',
      'lastMessageType': 'text',
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'unreadCount': unread,
      'typing': typing,
    });
    return docRef.id;
  }

  // ─────────────────── Messages ───────────────────

  /// Send a message (text/image/voice) into a chat.
  /// [recipientIds] are all participants EXCEPT the sender — their unread
  /// counts get incremented. Works for both direct and group chats.
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required List<String> recipientIds,
    String text = '',
    String type = 'text',
    String? mediaUrl,
    int? durationMs,
  }) async {
    final messagesRef =
        _db.collection('chats').doc(chatId).collection('messages');

    final payload = <String, dynamic>{
      'senderId': senderId,
      'text': text,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
      'readBy': <String>[senderId],
    };
    if (mediaUrl != null) payload['mediaUrl'] = mediaUrl;
    if (durationMs != null) payload['durationMs'] = durationMs;

    await messagesRef.add(payload);

    final preview = _previewFor(text: text, type: type);
    final updates = <String, dynamic>{
      'lastMessage': preview,
      'lastMessageType': type,
      'updatedAt': FieldValue.serverTimestamp(),
      'typing.$senderId': false,
    };
    for (final rid in recipientIds) {
      updates['unreadCount.$rid'] = FieldValue.increment(1);
    }
    await _db.collection('chats').doc(chatId).update(updates);
  }

  String _previewFor({required String text, required String type}) {
    switch (type) {
      case 'image':
        return 'Photo';
      case 'voice':
        return 'Voice message';
      default:
        return text;
    }
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

  /// Stream a single chat doc — used for live typing + presence in headers.
  Stream<DocumentSnapshot<Map<String, dynamic>>> getChatDoc(String chatId) {
    return _db.collection('chats').doc(chatId).snapshots();
  }

  /// Stream every chat the user participates in, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> getUserChats(String uid) {
    return _db
        .collection('chats')
        .where('participants', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .snapshots();
  }

  Future<void> markChatRead({
    required String chatId,
    required String uid,
  }) async {
    try {
      await _db.collection('chats').doc(chatId).update({
        'unreadCount.$uid': 0,
      });
    } catch (_) {/* best-effort */}
  }

  Future<void> setTyping({
    required String chatId,
    required String uid,
    required bool typing,
  }) async {
    try {
      await _db.collection('chats').doc(chatId).update({
        'typing.$uid': typing,
      });
    } catch (_) {/* best-effort */}
  }

  // ─────────────────── Group management ───────────────────

  /// Remove [uid] from a group chat. Also cleans their entries
  /// from unreadCount, typing, and mutedBy.
  Future<void> leaveGroup({
    required String chatId,
    required String uid,
  }) async {
    await _db.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayRemove([uid]),
      'mutedBy': FieldValue.arrayRemove([uid]),
      'unreadCount.$uid': FieldValue.delete(),
      'typing.$uid': FieldValue.delete(),
    });
  }

  Future<void> updateGroupName({
    required String chatId,
    required String name,
  }) async {
    await _db.collection('chats').doc(chatId).update({
      'groupName': name,
    });
  }

  Future<void> updateGroupPhoto({
    required String chatId,
    required String photoUrl,
  }) async {
    await _db.collection('chats').doc(chatId).update({
      'groupPhoto': photoUrl,
    });
  }

  /// Toggle mute for a given user on a chat (works for direct + group).
  /// Stored as a `mutedBy: [uid, ...]` array on the chat doc.
  Future<void> setMuted({
    required String chatId,
    required String uid,
    required bool muted,
  }) async {
    await _db.collection('chats').doc(chatId).update({
      'mutedBy': muted
          ? FieldValue.arrayUnion([uid])
          : FieldValue.arrayRemove([uid]),
    });
  }
}
