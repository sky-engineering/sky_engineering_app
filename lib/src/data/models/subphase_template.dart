// lib/src/data/models/subphase_template.dart
import 'package:cloud_firestore/cloud_firestore.dart';

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

  // -------- Mapping helpers --------
  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      return s == 'true' || s == 'yes' || s == '1';
    }
    return false;
  }

  static String _str(dynamic v) => (v is String) ? v.trim() : '';

  static List<String> _toStringList(dynamic v) {
    if (v == null) return const <String>[];
    if (v is List) {
      return v
          .map((e) => e is String ? e.trim() : (e?.toString() ?? ''))
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  // Read with BC: accept both new keys and legacy keys
  static SubphaseTemplate fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});

    final code = _str(data['subphaseCode']).isNotEmpty
        ? _str(data['subphaseCode'])
        : _str(data['taskCode']);

    final name = _str(data['subphaseName']).isNotEmpty
        ? _str(data['subphaseName'])
        : _str(data['taskName']);

    // NEW: read phaseCode; if missing, derive from subphaseCode
    final pc = _str(data['phaseCode']);
    final derivedPhase = (code.length >= 2) ? code.substring(0, 2) : '';
    final phaseCode = pc.isNotEmpty ? pc : derivedPhase;

    // NEW: defaultTasks list
    final defaults = _toStringList(data['defaultTasks']);

    final note = (data['subphaseNote'] as String?) ?? (data['taskNote'] as String?);
    final resp = (data['responsibility'] as String?) ??
        (data['taskResponsibility'] as String?) ??
        'Other';

    return SubphaseTemplate(
      id: doc.id,
      ownerUid: _str(data['ownerUid']),
      subphaseCode: code,
      subphaseName: name,
      phaseCode: phaseCode,
      defaultTasks: defaults,
      subphaseNote: note?.trim().isEmpty == true ? null : note,
      responsibility: resp,
      isDeliverable: _toBool(data['isDeliverable']),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  // Write both new keys and legacy mirrors for BC.
  Map<String, dynamic> toMap() {
    Timestamp? _ts(DateTime? d) => d != null ? Timestamp.fromDate(d) : null;

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

      'createdAt': _ts(createdAt),
      'updatedAt': _ts(updatedAt),
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
