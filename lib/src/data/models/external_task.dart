// lib/src/data/models/external_task.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/data_parsers.dart';

class ExternalTask {
  final String id;
  final String projectId;
  final String title;
  final String assigneeKey;
  final String assigneeName;
  final bool isDone;
  final bool isStarred;
  final int? starredOrder;
  final int? sortOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ExternalTask({
    required this.id,
    required this.projectId,
    required this.title,
    required this.assigneeKey,
    required this.assigneeName,
    this.isDone = false,
    this.isStarred = false,
    this.starredOrder,
    this.sortOrder,
    this.createdAt,
    this.updatedAt,
  });

  ExternalTask copyWith({
    String? id,
    String? projectId,
    String? title,
    String? assigneeKey,
    String? assigneeName,
    bool? isDone,
    bool? isStarred,
    int? starredOrder,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExternalTask(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      assigneeKey: assigneeKey ?? this.assigneeKey,
      assigneeName: assigneeName ?? this.assigneeName,
      isDone: isDone ?? this.isDone,
      isStarred: isStarred ?? this.isStarred,
      starredOrder: starredOrder ?? this.starredOrder,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ExternalTask.fromDoc(DocumentSnapshot doc) {
    final data = mapFrom(doc.data() as Map<String, dynamic>?);
    data['id'] = doc.id;
    return ExternalTask.fromMap(data);
  }

  factory ExternalTask.fromMap(Map<String, dynamic> data) {
    final map = mapFrom(data);
    return ExternalTask(
      id: readString(map, 'id'),
      projectId: readString(map, 'projectId'),
      title: readString(map, 'title'),
      assigneeKey: readString(map, 'assigneeKey'),
      assigneeName: readString(map, 'assigneeName'),
      isDone: readBool(map, 'isDone'),
      isStarred: readBool(map, 'isStarred'),
      starredOrder: map['starredOrder'] is num
          ? (map['starredOrder'] as num).toInt()
          : null,
      sortOrder: map['sortOrder'] is num
          ? (map['sortOrder'] as num).toInt()
          : null,
      createdAt: _readTimestamp(map['createdAt']),
      updatedAt: _readTimestamp(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'projectId': projectId,
      'title': title,
      'assigneeKey': assigneeKey,
      'assigneeName': assigneeName,
      'isDone': isDone,
      'isStarred': isStarred,
      'starredOrder': starredOrder,
      'sortOrder': sortOrder,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }
}

DateTime? _readTimestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  return null;
}

extension ExternalTaskDisplay on ExternalTask {
  static const String _fallbackAssigneeLabel = 'No Team Member Assigned';

  String get displayAssigneeLabel {
    final trimmed = assigneeName.trim();
    return trimmed.isEmpty ? _fallbackAssigneeLabel : trimmed;
  }

  bool get hasAssignedTeamMember => assigneeName.trim().isNotEmpty;
}
