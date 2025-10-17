// lib/src/data/models/subphase_template.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/data_parsers.dart';

class SubphaseTemplate {
  final String id;
  final String ownerUid;

  /// Canonical codes/names
  final String subphaseCode;   // "0101", "0204", ...
  final String subphaseName;   // display name

  /// NEW: explicit parent phase code (e.g., "01")
  /// If absent on disk, we derive from the first 2 digits of subphaseCode.
  final String phaseCode;

  /// NEW: default tasks for this subphase (each string is a task title)
  final List<String> defaultTasks;

  // Legacy/optional (kept for BC, not used in UI):
  final String? subphaseNote;
  final String responsibility; // default 'Other'
  final bool isDeliverable;    // default false

  final DateTime? createdAt;
  final DateTime? updatedAt;

  SubphaseTemplate({
    required this.id,
    required this.ownerUid,
    required this.subphaseCode,
    required this.subphaseName,
    required this.phaseCode,
    this.defaultTasks = const <String>[],
    this.subphaseNote,
    this.responsibility = 'Other',
    this.isDeliverable = false,
    this.createdAt,
    this.updatedAt,
  });

  // -------- Derived helpers (keep for convenience) --------
  String get subCode   => subphaseCode.length == 4 ? subphaseCode.substring(2, 4) : '';

  static bool isValidCode(String? code) {
    if (code == null) return false;
    final s = code.trim();
    return s.length == 4 && int.tryParse(s) != null;
  }

  // Read with BC: accept both new keys and legacy keys
  static SubphaseTemplate fromDoc(DocumentSnapshot doc) {
    final data = mapFrom(doc.data() as Map<String, dynamic>?);

    final code = parseString(data['subphaseCode']).isNotEmpty
        ? parseString(data['subphaseCode'])
        : parseString(data['taskCode']);

    final name = parseString(data['subphaseName']).isNotEmpty
        ? parseString(data['subphaseName'])
        : parseString(data['taskName']);

    // NEW: read phaseCode; if missing, derive from subphaseCode
    final storedPhase = parseString(data['phaseCode']);
    final derivedPhase = (code.length >= 2) ? code.substring(0, 2) : '';
    final phaseCode = storedPhase.isNotEmpty ? storedPhase : derivedPhase;

    // NEW: defaultTasks list
    final defaults = readStringListOrNull(data, 'defaultTasks') ?? const <String>[];

    final note = parseStringOrNull(data['subphaseNote']) ?? parseStringOrNull(data['taskNote']);
    final responsibility = parseString(
      data['responsibility'] ?? data['taskResponsibility'],
      fallback: 'Other',
    );

    return SubphaseTemplate(
      id: doc.id,
      ownerUid: parseString(data['ownerUid']),
      subphaseCode: code,
      subphaseName: name,
      phaseCode: phaseCode,
      defaultTasks: defaults,
      subphaseNote: note,
      responsibility: responsibility,
      isDeliverable: parseBool(data['isDeliverable'], fallback: false),
      createdAt: parseDateTime(data['createdAt']),
      updatedAt: parseDateTime(data['updatedAt']),
    );
  }

  // Write both new keys and legacy mirrors for BC.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'ownerUid': ownerUid,
      'subphaseCode': subphaseCode,
      'subphaseName': subphaseName,

      // NEW canonical fields
      'phaseCode': phaseCode,
      'defaultTasks': defaultTasks,

      'subphaseNote': subphaseNote,
      'responsibility': responsibility,
      'isDeliverable': isDeliverable,

      // Legacy mirrors
      'taskCode': subphaseCode,
      'taskName': subphaseName,
      'taskNote': subphaseNote,
      'taskResponsibility': responsibility,

      'createdAt': timestampFromDate(createdAt),
      'updatedAt': timestampFromDate(updatedAt),
    };
  }

  SubphaseTemplate copyWith({
    String? id,
    String? ownerUid,
    String? subphaseCode,
    String? subphaseName,
    String? phaseCode,
    List<String>? defaultTasks,
    String? subphaseNote,
    String? responsibility,
    bool? isDeliverable,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SubphaseTemplate(
      id: id ?? this.id,
      ownerUid: ownerUid ?? this.ownerUid,
      subphaseCode: subphaseCode ?? this.subphaseCode,
      subphaseName: subphaseName ?? this.subphaseName,
      phaseCode: phaseCode ?? this.phaseCode,
      defaultTasks: defaultTasks ?? this.defaultTasks,
      subphaseNote: subphaseNote ?? this.subphaseNote,
      responsibility: responsibility ?? this.responsibility,
      isDeliverable: isDeliverable ?? this.isDeliverable,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
