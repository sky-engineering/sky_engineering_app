// lib/src/data/models/client.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientRecord {
  const ClientRecord({
    required this.id,
    required this.code,
    required this.name,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String code;
  final String name;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static String _clean(String? value) => value?.trim() ?? '';

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  factory ClientRecord.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});
    return ClientRecord(
      id: doc.id,
      code: _clean(data['code']),
      name: _clean(data['name']),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    Timestamp? _ts(DateTime? value) =>
        value != null ? Timestamp.fromDate(value) : null;
    return {
      'code': code,
      'name': name,
      if (createdAt != null) 'createdAt': _ts(createdAt),
      if (updatedAt != null) 'updatedAt': _ts(updatedAt),
    };
  }

  ClientRecord copyWith({
    String? id,
    String? code,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ClientRecord(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
