// lib/src/data/models/external_task.dart
import 'package:cloud_firestore/cloud_firestore.dart';

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
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});
    return ExternalTask.fromMap({...data, 'id': doc.id});
  }

  factory ExternalTask.fromMap(Map<String, dynamic> data) {
    DateTime? _toDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    String _str(dynamic value) {
      if (value == null) return '';
      return value.toString().trim();
    }

    return ExternalTask(
      id: _str(data['id']),
      projectId: _str(data['projectId']),
      title: _str(data['title']),
      assigneeKey: _str(data['assigneeKey']),
      assigneeName: _str(data['assigneeName']),
      isDone: data['isDone'] == true,
      createdAt: _toDate(data['createdAt']),
      updatedAt: _toDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    Timestamp? _ts(DateTime? value) =>
        value != null ? Timestamp.fromDate(value) : null;

    return <String, dynamic>{
      'id': id,
      'projectId': projectId,
      'title': title,
      'assigneeKey': assigneeKey,
      'assigneeName': assigneeName,
      'isDone': isDone,
      if (createdAt != null) 'createdAt': _ts(createdAt),
      if (updatedAt != null) 'updatedAt': _ts(updatedAt),
    };
  }
}
