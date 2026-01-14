// lib/src/data/models/task.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/data_parsers.dart';

/// TaskItem — upgraded to include:
/// - taskStatus: 'In Progress' | 'On Hold' | 'Pending' | 'Completed'
/// - isStarred: bool
/// - taskCode: optional 4-digit code (e.g., '0201')
///
/// Backwards compatibility:
/// - legacy 'status' is still supported on read and mirrored on write.
///   Old statuses like 'Open'/'In Progress'/'Blocked'/'Done' are mapped to the new taskStatus:
///     Open -> Pending
///     In Progress -> In Progress
///     Blocked -> On Hold
///     Done -> Completed
class TaskItem {
  final String id;
  final String projectId;
  final String ownerUid;

  final String title;
  final String? description;
  final String? assigneeName;
  final DateTime? dueDate;

  // NEW schema
  final String
  taskStatus; // 'In Progress' | 'On Hold' | 'Pending' | 'Completed'
  final bool isStarred; // star marker in lists
  final String? taskCode; // optional 4-digit code like '0101'
  final int? starredOrder; // manual sort index for starred lists
  final int? projectOrder; // manual sort order on project detail page
  final List<SubtaskItem> subtasks;

  // Meta
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ---- Legacy shim (read-only) ----
  /// Legacy 'status' getter derived from taskStatus.
  /// (Kept so old UI code compiles; prefer using taskStatus going forward.)
  String get status => _toLegacyStatus(taskStatus);

  // ----------------- ctor -----------------
  /// Provide either the new names (preferred) or the old legacy 'status'.
  TaskItem({
    required this.id,
    required this.projectId,
    required this.ownerUid,
    required this.title,
    this.description,
    this.assigneeName,
    this.dueDate,

    // NEW
    String? taskStatus,
    bool? isStarred,
    this.taskCode,
    this.starredOrder,
    List<SubtaskItem>? subtasks,
    this.projectOrder,

    // Legacy input (still accepted)
    String? status,

    this.createdAt,
    this.updatedAt,
  }) : taskStatus = taskStatus ?? _fromLegacyStatus(status) ?? 'Pending',
      isStarred = isStarred ?? false,
      subtasks = List.unmodifiable(subtasks ?? const []);

  // ----------------- mapping helpers -----------------
  static String _toLegacyStatus(String taskStatus) {
    switch (taskStatus) {
      case 'In Progress':
        return 'In Progress';
      case 'On Hold':
        return 'Blocked';
      case 'Completed':
        return 'Done';
      case 'Pending':
      default:
        return 'Open';
    }
  }

  static String? _fromLegacyStatus(String? legacy) {
    switch ((legacy ?? '').trim()) {
      case 'In Progress':
        return 'In Progress';
      case 'Blocked':
        return 'On Hold';
      case 'Done':
        return 'Completed';
      case 'Open':
      case '':
      default:
        return 'Pending';
    }
  }

  // ----------------- fromDoc -----------------
  static TaskItem fromDoc(DocumentSnapshot doc) {
    final data = mapFrom(doc.data() as Map<String, dynamic>?);

    final newStatus = parseStringOrNull(data['taskStatus']);
    final legacyStatus = parseStringOrNull(data['status']);
    final resolvedTaskStatus = (newStatus != null && newStatus.isNotEmpty)
        ? newStatus
        : _fromLegacyStatus(legacyStatus) ?? 'Pending';

    return TaskItem(
      id: doc.id,
      projectId: readString(data, 'projectId'),
      ownerUid: readString(data, 'ownerUid'),
      title: readString(data, 'title'),
      description: readStringOrNull(data, 'description'),
      assigneeName: readStringOrNull(data, 'assigneeName'),
      dueDate: readDateTime(data, 'dueDate'),
      taskStatus: resolvedTaskStatus,
      isStarred: readBool(data, 'isStarred'),
      taskCode: readStringOrNull(data, 'taskCode'),
      starredOrder: readIntOrNull(data, 'starredOrder'),
      projectOrder: readIntOrNull(data, 'projectOrder'),
      subtasks: _parseSubtasks(data['subtasks']),
      createdAt: readDateTime(data, 'createdAt'),
      updatedAt: readDateTime(data, 'updatedAt'),
    );
  }

  // ----------------- toMap -----------------
  Map<String, dynamic> toMap() {
    final legacy = _toLegacyStatus(taskStatus);

    return <String, dynamic>{
      'projectId': projectId,
      'ownerUid': ownerUid,
      'title': title,
      'description': description,
      'assigneeName': assigneeName,
      'dueDate': timestampFromDate(dueDate),

      // NEW schema
      'taskStatus': taskStatus,
      'isStarred': isStarred,
      'taskCode': taskCode,
      if (starredOrder != null) 'starredOrder': starredOrder,
      if (projectOrder != null) 'projectOrder': projectOrder,
      'subtasks': subtasks.map((s) => s.toMap()).toList(),

      // Legacy mirror
      'status': legacy,

      // meta is set server-side in repo add/update
    };
  }

  // ----------------- copyWith -----------------
  TaskItem copyWith({
    String? id,
    String? projectId,
    String? ownerUid,
    String? title,
    String? description,
    String? assigneeName,
    DateTime? dueDate,

    // NEW
    String? taskStatus,
    bool? isStarred,
    String? taskCode,
    int? starredOrder,
    int? projectOrder,

    DateTime? createdAt,
    DateTime? updatedAt,

    // legacy input accepted but ignored for storage (we derive it)
    String? status,
    List<SubtaskItem>? subtasks,
  }) {
    return TaskItem(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      ownerUid: ownerUid ?? this.ownerUid,
      title: title ?? this.title,
      description: description ?? this.description,
      assigneeName: assigneeName ?? this.assigneeName,
      dueDate: dueDate ?? this.dueDate,
      taskStatus: taskStatus ?? this.taskStatus,
      isStarred: isStarred ?? this.isStarred,
      taskCode: taskCode ?? this.taskCode,
      starredOrder: starredOrder ?? this.starredOrder,
      projectOrder: projectOrder ?? this.projectOrder,
      subtasks: subtasks ?? this.subtasks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static List<SubtaskItem> _parseSubtasks(Object? raw) {
    if (raw is Iterable) {
      return raw
          .map((entry) {
            if (entry is Map<String, dynamic>) return entry;
            if (entry is Map) return Map<String, dynamic>.from(entry);
            return null;
          })
          .whereType<Map<String, dynamic>>()
          .map(SubtaskItem.fromMap)
          .toList();
    }
    return const [];
  }
}

class SubtaskItem {
  SubtaskItem({
    required this.id,
    required this.title,
    required this.isDone,
    this.createdAt,
    this.completedAt,
  });

  final String id;
  final String title;
  final bool isDone;
  final DateTime? createdAt;
  final DateTime? completedAt;

  factory SubtaskItem.create({required String title}) {
    final now = DateTime.now();
    final id = FirebaseFirestore.instance.collection('tasks').doc().id;
    return SubtaskItem(id: id, title: title, isDone: false, createdAt: now);
  }

  factory SubtaskItem.fromMap(Map<String, dynamic> data) {
    return SubtaskItem(
      id: parseString(data['id'], fallback: ''),
      title: parseString(data['title'], fallback: ''),
      isDone: parseBool(data['isDone'], fallback: false),
      createdAt: parseDateTime(data['createdAt']),
      completedAt: parseDateTime(data['completedAt']),
    );
  }

  SubtaskItem copyWith({
    String? id,
    String? title,
    bool? isDone,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return SubtaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'isDone': isDone,
      'createdAt': timestampFromDate(createdAt),
      if (completedAt != null) 'completedAt': timestampFromDate(completedAt),
    };
  }
}
