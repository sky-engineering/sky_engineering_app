import 'package:cloud_firestore/cloud_firestore.dart';

class ClientRecord {
  static const _unset = Object();

  const ClientRecord({
    required this.id,
    required this.code,
    required this.name,
    this.priority = 3,
    this.currentProposals,
    this.notes,
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
  final int priority;
  final List<String>? currentProposals;
  final String? notes;
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

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  static List<String>? _toStringList(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      final cleaned = value
          .map((item) => item?.toString().trim())
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      return cleaned.isEmpty ? null : List.unmodifiable(cleaned);
    }
    if (value is String) {
      return _splitCommaSeparated(value);
    }
    final str = value.toString();
    return _splitCommaSeparated(str);
  }

  static List<String>? _splitCommaSeparated(String input) {
    final cleaned = input
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return cleaned.isEmpty ? null : List.unmodifiable(cleaned);
  }

  static List<String>? _immutableList(List<String>? value) {
    if (value == null) return null;
    final cleaned = value
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return cleaned.isEmpty ? null : List.unmodifiable(cleaned);
  }

  factory ClientRecord.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});
    return ClientRecord(
      id: doc.id,
      code: _clean(data['code'] as String?),
      name: _clean(data['name'] as String?),
      priority: _toInt(data['priority']) ?? 3,
      currentProposals: _toStringList(data['currentProposals']),
      notes: _cleanOptional(data['notes']),
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
      'priority': priority,
      if (currentProposals != null) 'currentProposals': currentProposals,
      if (notes != null) 'notes': notes,
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
    int? priority,
    Object? currentProposals = _unset,
    Object? notes = _unset,
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
      priority: priority ?? this.priority,
      currentProposals: identical(currentProposals, _unset)
          ? this.currentProposals
          : _immutableList(currentProposals as List<String>?),
      notes: identical(notes, _unset) ? this.notes : notes as String?,
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
