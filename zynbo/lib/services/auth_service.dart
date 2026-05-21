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
      await createUserIfNotExists(user);
    }
    return user;
  }

  /// Creates the Firestore /users/{uid} document on first sign-in.
  /// On subsequent sign-ins it only refreshes presence (status + lastSeen).
  Future<void> createUserIfNotExists(User user) async {
    final doc = _db.collection('users').doc(user.uid);
    final snapshot = await doc.get();

    if (!snapshot.exists) {
      await doc.set({
        'uid': user.uid,
        'name': user.displayName,
        'email': user.email,
        'photo': user.photoURL,
        'about': 'Hey there! I am using Zynbo.',
        'phoneNumber': user.phoneNumber,
        'status': 'online',
        'lastSeen': DateTime.now(),
        'createdAt': DateTime.now(),
        'profileCompleted': false,
      });
    } else {
      await doc.update({
        'status': 'online',
        'lastSeen': DateTime.now(),
      });
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
    required String name,
    String? about,
    String? phoneNumber,
    String? photo,
  }) async {
    await _db.collection('users').doc(uid).set({
      'name': name,
      'about': about,
      'phoneNumber': phoneNumber,
      if (photo != null) 'photo': photo,
      'profileCompleted': true,
      'status': 'online',
      'lastSeen': DateTime.now(),
    }, SetOptions(merge: true));
  }

  Future<ZynboUser?> fetchUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return ZynboUser.fromMap(doc.data()!);
  }

  /// Flip status to offline before tearing down auth.
  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      try {
        await _db.collection('users').doc(uid).update({
          'status': 'offline',
          'lastSeen': DateTime.now(),
        });
      } catch (_) {
        // best-effort; ignore if doc doesn't exist or write fails
      }
    }
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
