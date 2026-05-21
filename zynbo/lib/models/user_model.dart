import 'package:cloud_firestore/cloud_firestore.dart';

class ZynboUser {
  final String uid;
  final String email;
  final String name;
  final String? photo;
  final String? about;
  final String? phoneNumber;
  final String status; // 'online' | 'offline'
  final DateTime createdAt;
  final DateTime lastSeen;
  final bool profileCompleted;

  ZynboUser({
    required this.uid,
    required this.email,
    required this.name,
    this.photo,
    this.about,
    this.phoneNumber,
    required this.status,
    required this.createdAt,
    required this.lastSeen,
    required this.profileCompleted,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'photo': photo,
      'about': about,
      'phoneNumber': phoneNumber,
      'status': status,
      'createdAt': createdAt,
      'lastSeen': lastSeen,
      'profileCompleted': profileCompleted,
    };
  }

  factory ZynboUser.fromMap(Map<String, dynamic> data) {
    DateTime _toDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return DateTime.now();
    }

    return ZynboUser(
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      name: data['name'] as String? ?? '',
      photo: data['photo'] as String?,
      about: data['about'] as String?,
      phoneNumber: data['phoneNumber'] as String?,
      status: data['status'] as String? ?? 'offline',
      createdAt: _toDate(data['createdAt']),
      lastSeen: _toDate(data['lastSeen']),
      profileCompleted: data['profileCompleted'] as bool? ?? false,
    );
  }
}
