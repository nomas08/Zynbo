import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/user_model.dart';

/// Centralized authentication service for Zynbo.
/// Handles Google Sign-In, Firestore user document creation, and sign-out.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: const ['email', 'profile']);

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Trigger Google Sign-In and link with Firebase Auth.
  /// Returns the signed-in [User] or null if user cancels.
  Future<User?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final UserCredential result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user != null) {
      await _ensureUserDocument(user);
    }
    return user;
  }

  /// Creates the Firestore /users/{uid} document on first sign-in (idempotent).
  Future<void> _ensureUserDocument(User user) async {
    final docRef = _db.collection('users').doc(user.uid);
    final snap = await docRef.get();
    if (!snap.exists) {
      final newUser = ZynboUser(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? '',
        photoUrl: user.photoURL,
        about: 'Hey there! I am using Zynbo.',
        phoneNumber: user.phoneNumber,
        createdAt: DateTime.now(),
        lastSeen: DateTime.now(),
        profileCompleted: false,
      );
      await docRef.set(newUser.toMap(), SetOptions(merge: true));
    } else {
      await docRef.set({'lastSeen': Timestamp.now()}, SetOptions(merge: true));
    }
  }

  /// Returns true if the user has completed initial profile setup.
  Future<bool> hasCompletedProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    return (doc.data()?['profileCompleted'] as bool?) ?? false;
  }

  /// Save profile fields and mark profile as completed.
  Future<void> saveProfile({
    required String uid,
    required String displayName,
    String? about,
    String? phoneNumber,
    String? photoUrl,
  }) async {
    await _db.collection('users').doc(uid).set({
      'displayName': displayName,
      'about': about,
      'phoneNumber': phoneNumber,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'profileCompleted': true,
      'lastSeen': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<ZynboUser?> fetchUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return ZynboUser.fromMap(doc.data()!);
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
