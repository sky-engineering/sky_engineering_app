// lib/src/data/models/task.dart
import 'package:cloud_firestore/cloud_firestore.dart';

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
  final String taskStatus; // 'In Progress' | 'On Hold' | 'Pending' | 'Completed'
  final bool isStarred;    // star marker in lists
  final String? taskCode;  // optional 4-digit code like '0101'

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

    // Legacy input (still accepted)
    String? status,

    this.createdAt,
    this.updatedAt,
  })  : taskStatus = taskStatus ?? _fromLegacyStatus(status) ?? 'Pending',
        isStarred  = isStarred ?? false;

  // ----------------- mapping helpers -----------------
  static String _toLegacyStatus(String taskStatus) {
    switch (taskStatus) {
      case 'In Progress': return 'In Progress';
      case 'On Hold':     return 'Blocked';
      case 'Completed':   return 'Done';
      case 'Pending':
      default:            return 'Open';
    }
  }

  static String? _fromLegacyStatus(String? legacy) {
    switch ((legacy ?? '').trim()) {
      case 'In Progress': return 'In Progress';
      case 'Blocked':     return 'On Hold';
      case 'Done':        return 'Completed';
      case 'Open':
      case '':
      default:            return 'Pending';
    }
  }

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

  // ----------------- fromDoc -----------------
  static TaskItem fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});

    final newStatus = (data['taskStatus'] as String?)?.trim();
    final legacyStatus = (data['status'] as String?)?.trim();
    final resolvedTaskStatus = (newStatus != null && newStatus.isNotEmpty)
        ? newStatus
        : _fromLegacyStatus(legacyStatus) ?? 'Pending';

    return TaskItem(
      id: doc.id,
      projectId: (data['projectId'] as String? ?? ''),
      ownerUid: (data['ownerUid'] as String? ?? ''),
      title: (data['title'] as String? ?? '').trim(),
      description: (data['description'] as String?)?.trim(),
      assigneeName: (data['assigneeName'] as String?)?.trim(),
      dueDate: _toDate(data['dueDate']),
      taskStatus: resolvedTaskStatus,
      isStarred: _toBool(data['isStarred']),
      taskCode: (data['taskCode'] as String?)?.trim(),
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  // ----------------- toMap -----------------
  Map<String, dynamic> toMap() {
    Timestamp? _ts(DateTime? d) => d != null ? Timestamp.fromDate(d) : null;

    final legacy = _toLegacyStatus(taskStatus);

    return <String, dynamic>{
      'projectId': projectId,
      'ownerUid': ownerUid,
      'title': title,
      'description': description,
      'assigneeName': assigneeName,
      'dueDate': _ts(dueDate),

      // NEW schema
      'taskStatus': taskStatus,
      'isStarred': isStarred,
      'taskCode': taskCode,

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

    DateTime? createdAt,
    DateTime? updatedAt,

    // legacy input accepted but ignored for storage (we derive it)
    String? status,
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
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
