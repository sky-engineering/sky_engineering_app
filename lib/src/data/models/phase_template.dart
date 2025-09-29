// lib/src/data/models/phase_template.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class PhaseTemplate {
  final String id;
  final String ownerUid;

  /// Two-digit string, e.g. "01", "02"
  final String phaseCode;

  /// Human-readable name, e.g. "Preliminary Design"
  final String phaseName;

  /// Order in which phases are displayed (0-based)
  final int sortOrder;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  PhaseTemplate({
    required this.id,
    required this.ownerUid,
    required this.phaseCode,
    required this.phaseName,
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  static bool isValidCode(String? code) {
    if (code == null) return false;
    final s = code.trim();
    return s.length == 2 && int.tryParse(s) != null;
  }

  // ---------- Mapping helpers ----------
  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static String _str(dynamic v) => (v is String) ? v.trim() : '';
  static int _toInt(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  static PhaseTemplate fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});
    return PhaseTemplate(
      id: doc.id,
      ownerUid: _str(data['ownerUid']),
      phaseCode: _str(data['phaseCode']),
      phaseName: _str(data['phaseName']),
      sortOrder: _toInt(data['sortOrder'], 0),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    Timestamp? _ts(DateTime? d) => d != null ? Timestamp.fromDate(d) : null;
    return <String, dynamic>{
      'ownerUid': ownerUid,
      'phaseCode': phaseCode,
      'phaseName': phaseName,
      'sortOrder': sortOrder,
      'createdAt': _ts(createdAt),
      'updatedAt': _ts(updatedAt),
    };
  }

  PhaseTemplate copyWith({
    String? id,
    String? ownerUid,
    String? phaseCode,
    String? phaseName,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PhaseTemplate(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      phaseCode: phaseCode ?? this.phaseCode,
      phaseName: phaseName ?? this.phaseName,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}