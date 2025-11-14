// lib/src/data/models/project.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'external_task.dart';

import '../../utils/data_parsers.dart';

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

  factory SelectedSubphase.fromMap(Map<String, dynamic> data) {
    final map = mapFrom(data);
    final status = parseString(map['status'], fallback: 'In Progress');
    final normalizedStatus =
        kSubphaseStatuses.contains(status) ? status : 'In Progress';

    return SelectedSubphase(
      code: parseString(map['code']),
      name: parseString(map['name']),
      responsibility: parseStringOrNull(map['responsibility']),
      isDeliverable: parseBool(map['isDeliverable'], fallback: false),
      status: normalizedStatus,
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

  /// Whether this project currently has any external tasks.
  final bool hasExternalTasks;

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
    this.hasExternalTasks = false,
  });

  static String _resolveStatus(String? rawStatus, bool archivedFlag) {
    final status = rawStatus?.trim();
    if (status == null || status.isEmpty) {
      return archivedFlag ? 'Archive' : 'In Progress';
    }
    if (kProjectStatuses.contains(status)) {
      return status;
    }
    return archivedFlag ? 'Archive' : 'In Progress';
  }

  // -------- factory from Firestore --------
  static Project fromDoc(DocumentSnapshot doc) {
    final data = mapFrom(doc.data() as Map<String, dynamic>?);

    final archivedFlag = parseBool(data['isArchived'], fallback: false);
    final resolvedStatus = _resolveStatus(
      parseStringOrNull(data['status']),
      archivedFlag,
    );

    final selectedList = readListOrNull<SelectedSubphase>(
      data,
      'selectedSubphases',
      (value) {
        if (value is Map<String, dynamic>) {
          return SelectedSubphase.fromMap(value);
        }
        return null;
      },
    );
    final selectedSubphases =
        (selectedList == null || selectedList.isEmpty) ? null : selectedList;

    final externalList = readListOrNull<ExternalTask>(data, 'externalTasks', (
      value,
    ) {
      if (value is Map<String, dynamic>) {
        final task = ExternalTask.fromMap(value);
        return task.id.isEmpty ? null : task;
      }
      return null;
    });
    final externalTasks =
        (externalList == null || externalList.isEmpty) ? null : externalList;
    final hasExternalTasksFlag = parseBool(
      data['hasExternalTasks'],
      fallback: externalTasks != null && externalTasks.isNotEmpty,
    );

    return Project(
      id: doc.id,
      name: readString(data, 'name'),
      clientName: readString(data, 'clientName'),
      status: resolvedStatus,
      contractAmount: readDoubleOrNull(data, 'contractAmount'),
      contactName: readStringOrNull(data, 'contactName'),
      contactEmail: readStringOrNull(data, 'contactEmail'),
      contactPhone: readStringOrNull(data, 'contactPhone'),
      teamOwner: readStringOrNull(data, 'teamOwner'),
      teamContractor: readStringOrNull(data, 'teamContractor'),
      teamArchitect: readStringOrNull(data, 'teamArchitect'),
      teamMechanical: readStringOrNull(data, 'teamMechanical'),
      teamElectrical: readStringOrNull(data, 'teamElectrical'),
      teamPlumbing: readStringOrNull(data, 'teamPlumbing'),
      teamLandscape: readStringOrNull(data, 'teamLandscape'),
      teamGeotechnical: readStringOrNull(data, 'teamGeotechnical'),
      teamSurveyor: readStringOrNull(data, 'teamSurveyor'),
      teamEnvironmental: readStringOrNull(data, 'teamEnvironmental'),
      teamOther: readStringOrNull(data, 'teamOther'),
      ownerUid: readStringOrNull(data, 'ownerUid'),
      projectNumber: readStringOrNull(data, 'projectNumber'),
      folderName: readStringOrNull(data, 'folderName'),
      createdAt: readDateTime(data, 'createdAt'),
      updatedAt: readDateTime(data, 'updatedAt'),
      selectedSubphases: selectedSubphases,
      externalTasks: externalTasks,
      isArchived: archivedFlag || resolvedStatus == 'Archive',
      hasExternalTasks: hasExternalTasksFlag,
    );
  }

  // -------- to Firestore map --------
  Map<String, dynamic> toMap() {
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
      'hasExternalTasks': hasExternalTasks,

      if (createdAt != null) 'createdAt': timestampFromDate(createdAt),
      if (updatedAt != null) 'updatedAt': timestampFromDate(updatedAt),
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
    bool? hasExternalTasks,
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
      hasExternalTasks: hasExternalTasks ?? this.hasExternalTasks,
    );
  }
}
