import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Uploads chat media (images, voice notes) to Firebase Storage and
/// returns the public download URL.
///
/// Files live at:
///   /chats/{chatId}/{filename}
class MediaService {
  MediaService._();
  static final MediaService instance = MediaService._();

  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadChatMedia({
    required String chatId,
    required File file,
    required String filename,
    String? contentType,
  }) async {
    final ref = _storage.ref().child('chats').child(chatId).child(filename);
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: contentType),
    );
    return task.ref.getDownloadURL();
  }

  /// Upload a group photo (or user avatar) — stored under /users/{uid}/...
  Future<String> uploadGroupPhoto({
    required String chatId,
    required File file,
  }) {
    return uploadChatMedia(
      chatId: chatId,
      file: file,
      filename: 'group_photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
      contentType: 'image/jpeg',
    );
  }
}
