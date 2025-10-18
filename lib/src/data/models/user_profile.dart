import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String
  userType; // Admin, Civil, Owner, Surveyor, Architect, MEP, Structural, Geotechnical, Landscape, Other
  final String? clientNumber;
  final String? userName;
  final String? userPhone;
  final String? userAddress;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const allowedUserTypes = <String>[
    'Admin',
    'Civil',
    'Owner',
    'Surveyor',
    'Architect',
    'MEP',
    'Structural',
    'Geotechnical',
    'Landscape',
    'Other',
  ];

  UserProfile({
    required this.uid,
    required this.userType,
    this.clientNumber,
    this.userName,
    this.userPhone,
    this.userAddress,
    this.createdAt,
    this.updatedAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      uid: data['uid'] as String,
      userType: (data['userType'] as String?) ?? 'Other',
      clientNumber: data['clientNumber'] as String?,
      userName: data['userName'] as String?,
      userPhone: data['userPhone'] as String?,
      userAddress: data['userAddress'] as String?,
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'userType': userType,
      'clientNumber': clientNumber,
      'userName': userName,
      'userPhone': userPhone,
      'userAddress': userAddress,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  UserProfile copyWith({
    String? userType,
    String? clientNumber,
    String? userName,
    String? userPhone,
    String? userAddress,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid,
      userType: userType ?? this.userType,
      clientNumber: clientNumber ?? this.clientNumber,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      userAddress: userAddress ?? this.userAddress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
