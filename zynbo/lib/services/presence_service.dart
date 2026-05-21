import 'package:cloud_firestore/cloud_firestore.dart';

/// Lightweight presence helper.
/// Writes to /users/{uid} { status, lastSeen }.
/// Higher-level wiring (lifecycle observer + auth listener) lives in main.dart.
class PresenceService {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> goOnline(String uid) async {
    try {
      await _db.collection('users').doc(uid).set({
        'status': 'online',
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {/* best-effort */}
  }

  Future<void> goOffline(String uid) async {
    try {
      await _db.collection('users').doc(uid).set({
        'status': 'offline',
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {/* best-effort */}
  }
}
