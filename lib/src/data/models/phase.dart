// lib/src/data/models/phase.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/data_parsers.dart';

class Phase {
  final String id;
  final String ownerUid;
  final String phaseCode; // e.g., "01"
  final String phaseName; // e.g., "Land Use"
  final int? order; // optional explicit ordering
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Phase({
    required this.id,
    required this.ownerUid,
    required this.phaseCode,
    required this.phaseName,
    this.order,
    this.createdAt,
    this.updatedAt,
  });

  Phase copyWith({
    String? id,
    String? ownerUid,
    String? phaseCode,
    String? phaseName,
    int? order,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Phase(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      phaseCode: phaseCode ?? this.phaseCode,
      phaseName: phaseName ?? this.phaseName,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static Phase fromDoc(DocumentSnapshot doc) {
    final data = mapFrom(doc.data() as Map<String, dynamic>?);
    return Phase(
      id: doc.id,
      ownerUid: readString(data, 'ownerUid'),
      phaseCode: readString(data, 'phaseCode'),
      phaseName: readString(data, 'phaseName'),
      order: readIntOrNull(data, 'order'),
      createdAt: readDateTime(data, 'createdAt'),
      updatedAt: readDateTime(data, 'updatedAt'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerUid': ownerUid,
      'phaseCode': phaseCode,
      'phaseName': phaseName,
      if (order != null) 'order': order,
      // createdAt/updatedAt set in repository to serverTimestamp
    };
  }
}
