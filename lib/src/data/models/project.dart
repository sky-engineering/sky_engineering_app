// lib/src/data/models/project.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'external_task.dart';

const kProjectStatuses = <String>[
  'In Progress',
  'On Hold',
  'Under Construction',
  'Close When Paid',
  'Archive',
];

const kSubphaseStatuses = <String>['In Progress', 'On Hold', 'Completed'];

/// Each project stores the selected subphases + per-project status.
class SelectedSubphase {
  final String code; // 4-digit, e.g. "0201"
  final String name; // snapshot name
  final String? responsibility; // snapshot (optional)
  final bool isDeliverable; // snapshot
  final String status; // 'In Progress' | 'On Hold' | 'Completed'

  const SelectedSubphase({
    required this.code,
    required this.name,
    this.responsibility,
    required this.isDeliverable,
    this.status = 'In Progress',
  });

  factory SelectedSubphase.fromMap(Map<String, dynamic> m) {
    String? _str(dynamic v) => v is String ? v.trim() : null;
    bool _bool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        return s == 'true' || s == 'yes' || s == '1';
      }
      return false;
    }

    final st = _str(m['status']) ?? 'In Progress';
    final saneStatus = kSubphaseStatuses.contains(st) ? st : 'In Progress';

    return SelectedSubphase(
      code: _str(m['code']) ?? '',
      name: _str(m['name']) ?? '',
      responsibility: _str(m['responsibility']),
      isDeliverable: _bool(m['isDeliverable']),
      status: saneStatus,
    );
  }

  Map<String, dynamic> toMap() => {
    'code': code,
    'name': name,
    if (responsibility != null) 'responsibility': responsibility,
    'isDeliverable': isDeliverable,
    'status': status,
  };

  SelectedSubphase copyWith({
    String? code,
    String? name,
    String? responsibility,
    bool? isDeliverable,
    String? status,
  }) {
    return SelectedSubphase(
      code: code ?? this.code,
      name: name ?? this.name,
      responsibility: responsibility ?? this.responsibility,
      isDeliverable: isDeliverable ?? this.isDeliverable,
      status: status ?? this.status,
    );
  }
}

/// Canonical Project model
class Project {
  final String id;
  final String name;
  final String clientName;
  final String status; // Project status
  final double? contractAmount;

  final String? contactName;
  final String? contactEmail;
  final String? contactPhone;

  final String? teamOwner;
  final String? teamContractor;
  final String? teamArchitect;
  final String? teamMechanical;
  final String? teamElectrical;
  final String? teamPlumbing;
  final String? teamLandscape;
  final String? teamGeotechnical;
  final String? teamSurveyor;
  final String? teamEnvironmental;
  final String? teamOther;

  final String? ownerUid;
  final String? projectNumber;
  final String? folderName;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the project is archived (hidden from list by default).
  final bool isArchived;

  /// Selected subphases for this project (with per-project status).
  final List<SelectedSubphase>? selectedSubphases;

  /// External partner todos stored on the project doc.
  final List<ExternalTask>? externalTasks;

  const Project({
    required this.id,
    required this.name,
    required this.clientName,
    required this.status,
    this.contractAmount,
    this.contactName,
    this.contactEmail,
    this.contactPhone,
    this.teamOwner,
    this.teamContractor,
    this.teamArchitect,
    this.teamMechanical,
    this.teamElectrical,
    this.teamPlumbing,
    this.teamLandscape,
    this.teamGeotechnical,
    this.teamSurveyor,
    this.teamEnvironmental,
    this.teamOther,
    this.ownerUid,
    this.projectNumber,
    this.folderName,
    this.createdAt,
    this.updatedAt,
    this.selectedSubphases,
    this.externalTasks,
    this.isArchived = false,
  });

  // -------- mapping helpers --------
  static DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  static String? _str(dynamic v) => v is String ? v.trim() : null;

  static bool _bool(dynamic v, {bool fallback = false}) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == 'yes' || s == '1') return true;
      if (s == 'false' || s == 'no' || s == '0') return false;
    }
    return fallback;
  }

  // -------- factory from Firestore --------
  static Project fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});

    List<SelectedSubphase>? _readSelected(dynamic v) {
      if (v is List) {
        final out = <SelectedSubphase>[];
        for (final e in v) {
          if (e is Map<String, dynamic>) {
            out.add(SelectedSubphase.fromMap(e));
          }
        }
        return out.isEmpty ? null : out;
      }
      return null;
    }

    List<ExternalTask>? _readExternalTasks(dynamic v) {
      if (v is! List) return null;
      final out = <ExternalTask>[];
      for (final e in v) {
        if (e is Map<String, dynamic>) {
          final task = ExternalTask.fromMap(e);
          if (task.id.isNotEmpty) {
            out.add(task);
          }
        }
      }
      return out.isEmpty ? null : out;
    }

    final rawStatus = _str(data['status']);
    final archivedFlag = _bool(data['isArchived'], fallback: false);
    final resolvedStatus = (rawStatus != null && rawStatus.isNotEmpty)
        ? (kProjectStatuses.contains(rawStatus)
              ? rawStatus
              : (archivedFlag ? 'Archive' : 'In Progress'))
        : (archivedFlag ? 'Archive' : 'In Progress');

    return Project(
      id: doc.id,
      name: _str(data['name']) ?? '',
      clientName: _str(data['clientName']) ?? '',
      status: resolvedStatus,
      contractAmount: _toDoubleOrNull(data['contractAmount']),
      contactName: _str(data['contactName']),
      contactEmail: _str(data['contactEmail']),
      contactPhone: _str(data['contactPhone']),
      teamOwner: _str(data['teamOwner']),
      teamContractor: _str(data['teamContractor']),
      teamArchitect: _str(data['teamArchitect']),
      teamMechanical: _str(data['teamMechanical']),
      teamElectrical: _str(data['teamElectrical']),
      teamPlumbing: _str(data['teamPlumbing']),
      teamLandscape: _str(data['teamLandscape']),
      teamGeotechnical: _str(data['teamGeotechnical']),
      teamSurveyor: _str(data['teamSurveyor']),
      teamEnvironmental: _str(data['teamEnvironmental']),
      teamOther: _str(data['teamOther']),
      ownerUid: _str(data['ownerUid']),
      projectNumber: _str(data['projectNumber']),
      folderName: _str(data['folderName']),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
      selectedSubphases: _readSelected(data['selectedSubphases']),
      externalTasks: _readExternalTasks(data['externalTasks']),
      isArchived: archivedFlag || resolvedStatus == 'Archive',
    );
  }

  // -------- to Firestore map --------
  Map<String, dynamic> toMap() {
    Timestamp? _ts(DateTime? d) => d != null ? Timestamp.fromDate(d) : null;

    return <String, dynamic>{
      'name': name,
      'clientName': clientName,
      'status': status,
      if (contractAmount != null) 'contractAmount': contractAmount,
      if (contactName != null && contactName!.isNotEmpty)
        'contactName': contactName,
      if (contactEmail != null && contactEmail!.isNotEmpty)
        'contactEmail': contactEmail,
      if (contactPhone != null && contactPhone!.isNotEmpty)
        'contactPhone': contactPhone,
      if (teamOwner != null && teamOwner!.isNotEmpty) 'teamOwner': teamOwner,
      if (teamContractor != null && teamContractor!.isNotEmpty)
        'teamContractor': teamContractor,
      if (teamArchitect != null && teamArchitect!.isNotEmpty)
        'teamArchitect': teamArchitect,
      if (teamMechanical != null && teamMechanical!.isNotEmpty)
        'teamMechanical': teamMechanical,
      if (teamElectrical != null && teamElectrical!.isNotEmpty)
        'teamElectrical': teamElectrical,
      if (teamPlumbing != null && teamPlumbing!.isNotEmpty)
        'teamPlumbing': teamPlumbing,
      if (teamLandscape != null && teamLandscape!.isNotEmpty)
        'teamLandscape': teamLandscape,
      if (teamGeotechnical != null && teamGeotechnical!.isNotEmpty)
        'teamGeotechnical': teamGeotechnical,
      if (teamSurveyor != null && teamSurveyor!.isNotEmpty)
        'teamSurveyor': teamSurveyor,
      if (teamEnvironmental != null && teamEnvironmental!.isNotEmpty)
        'teamEnvironmental': teamEnvironmental,
      if (teamOther != null && teamOther!.isNotEmpty) 'teamOther': teamOther,
      if (ownerUid != null) 'ownerUid': ownerUid,
      if (projectNumber != null && projectNumber!.isNotEmpty)
        'projectNumber': projectNumber,
      if (folderName != null && folderName!.isNotEmpty)
        'folderName': folderName,

      if (selectedSubphases != null)
        'selectedSubphases': selectedSubphases!.map((s) => s.toMap()).toList(),
      if (externalTasks != null)
        'externalTasks': externalTasks!.map((t) => t.toMap()).toList(),

      // Persist archived flag (always include so new docs default false explicitly)
      'isArchived': isArchived,

      if (createdAt != null) 'createdAt': _ts(createdAt),
      if (updatedAt != null) 'updatedAt': _ts(updatedAt),
    };
  }

  Project copyWith({
    String? id,
    String? name,
    String? clientName,
    String? status,
    double? contractAmount,
    String? contactName,
    String? contactEmail,
    String? contactPhone,
    String? teamOwner,
    String? teamContractor,
    String? teamArchitect,
    String? teamMechanical,
    String? teamElectrical,
    String? teamPlumbing,
    String? teamLandscape,
    String? teamGeotechnical,
    String? teamSurveyor,
    String? teamEnvironmental,
    String? teamOther,
    String? ownerUid,
    String? projectNumber,
    String? folderName,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<SelectedSubphase>? selectedSubphases,
    List<ExternalTask>? externalTasks,
    bool? isArchived,
  }) {
    final resolvedStatus = status ?? this.status;
    final resolvedIsArchived = isArchived ?? (resolvedStatus == 'Archive');

    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      clientName: clientName ?? this.clientName,
      status: resolvedStatus,
      contractAmount: contractAmount ?? this.contractAmount,
      contactName: contactName ?? this.contactName,
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      teamOwner: teamOwner ?? this.teamOwner,
      teamContractor: teamContractor ?? this.teamContractor,
      teamArchitect: teamArchitect ?? this.teamArchitect,
      teamMechanical: teamMechanical ?? this.teamMechanical,
      teamElectrical: teamElectrical ?? this.teamElectrical,
      teamPlumbing: teamPlumbing ?? this.teamPlumbing,
      teamLandscape: teamLandscape ?? this.teamLandscape,
      teamGeotechnical: teamGeotechnical ?? this.teamGeotechnical,
      teamSurveyor: teamSurveyor ?? this.teamSurveyor,
      teamEnvironmental: teamEnvironmental ?? this.teamEnvironmental,
      teamOther: teamOther ?? this.teamOther,
      ownerUid: ownerUid ?? this.ownerUid,
      projectNumber: projectNumber ?? this.projectNumber,
      folderName: folderName ?? this.folderName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      selectedSubphases: selectedSubphases ?? this.selectedSubphases,
      externalTasks: externalTasks ?? this.externalTasks,
      isArchived: resolvedIsArchived,
    );
  }
}
