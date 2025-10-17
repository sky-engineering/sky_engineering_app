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
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ExternalTask({
    required this.id,
    required this.projectId,
    required this.title,
    required this.assigneeKey,
    required this.assigneeName,
    this.isDone = false,
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
      createdAt: readDateTime(map, 'createdAt'),
      updatedAt: readDateTime(map, 'updatedAt'),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'projectId': projectId,
      'title': title,
      'assigneeKey': assigneeKey,
      'assigneeName': assigneeName,
      'isDone': isDone,
      if (createdAt != null) 'createdAt': timestampFromDate(createdAt),
      if (updatedAt != null) 'updatedAt': timestampFromDate(updatedAt),
    };
  }
}
