// lib/src/data/models/client.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientRecord {
  static const _unset = Object();

  const ClientRecord({
    required this.id,
    required this.code,
    required this.name,
    this.contactName,
    this.contactEmail,
    this.contactPhone,
    this.ownerUid,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String code;
  final String name;
  final String? contactName;
  final String? contactEmail;
  final String? contactPhone;
  final String? ownerUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static String _clean(String? value) => value?.trim() ?? '';

  static String? _cleanOptional(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    final asString = value.toString().trim();
    return asString.isEmpty ? null : asString;
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  factory ClientRecord.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});
    return ClientRecord(
      id: doc.id,
      code: _clean(data['code'] as String?),
      name: _clean(data['name'] as String?),
      contactName: _cleanOptional(data['contactName']),
      contactEmail: _cleanOptional(data['contactEmail']),
      contactPhone: _cleanOptional(data['contactPhone']),
      ownerUid: _cleanOptional(data['ownerUid']),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    Timestamp? timestampOrNull(DateTime? value) =>
        value != null ? Timestamp.fromDate(value) : null;
    return {
      'code': code,
      'name': name,
      if (contactName != null) 'contactName': contactName,
      if (contactEmail != null) 'contactEmail': contactEmail,
      if (contactPhone != null) 'contactPhone': contactPhone,
      if (ownerUid != null) 'ownerUid': ownerUid,
      if (createdAt != null) 'createdAt': timestampOrNull(createdAt),
      if (updatedAt != null) 'updatedAt': timestampOrNull(updatedAt),
    };
  }

  ClientRecord copyWith({
    String? id,
    String? code,
    String? name,
    Object? contactName = _unset,
    Object? contactEmail = _unset,
    Object? contactPhone = _unset,
    Object? ownerUid = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ClientRecord(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      contactName: identical(contactName, _unset)
          ? this.contactName
          : contactName as String?,
      contactEmail: identical(contactEmail, _unset)
          ? this.contactEmail
          : contactEmail as String?,
      contactPhone: identical(contactPhone, _unset)
          ? this.contactPhone
          : contactPhone as String?,
      ownerUid: identical(ownerUid, _unset)
          ? this.ownerUid
          : ownerUid as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
