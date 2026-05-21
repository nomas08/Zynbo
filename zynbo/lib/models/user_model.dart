import 'package:cloud_firestore/cloud_firestore.dart';

class ZynboUser {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? about;
  final String? phoneNumber;
  final DateTime createdAt;
  final DateTime lastSeen;
  final bool profileCompleted;

  ZynboUser({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.about,
    this.phoneNumber,
    required this.createdAt,
    required this.lastSeen,
    required this.profileCompleted,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'about': about,
      'phoneNumber': phoneNumber,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastSeen': Timestamp.fromDate(lastSeen),
      'profileCompleted': profileCompleted,
    };
  }

  factory ZynboUser.fromMap(Map<String, dynamic> data) {
    return ZynboUser(
      uid: data['uid'] as String,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      about: data['about'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      profileCompleted: data['profileCompleted'] as bool? ?? false,
    );
  }
}
