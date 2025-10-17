// lib/src/data/models/phase_template.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/data_parsers.dart';

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

  static PhaseTemplate fromDoc(DocumentSnapshot doc) {
    final data = mapFrom(doc.data() as Map<String, dynamic>?);
    return PhaseTemplate(
      id: doc.id,
      ownerUid: readString(data, 'ownerUid'),
      phaseCode: readString(data, 'phaseCode'),
      phaseName: readString(data, 'phaseName'),
      sortOrder: readIntOrNull(data, 'sortOrder') ?? 0,
      createdAt: readDateTime(data, 'createdAt'),
      updatedAt: readDateTime(data, 'updatedAt'),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'ownerUid': ownerUid,
      'phaseCode': phaseCode,
      'phaseName': phaseName,
      'sortOrder': sortOrder,
      'createdAt': timestampFromDate(createdAt),
      'updatedAt': timestampFromDate(updatedAt),
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
