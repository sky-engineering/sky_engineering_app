// lib/src/data/models/task_template.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/data_parsers.dart';

class TaskTemplate {
  final String id;
  final String taskCode; // 4 digits: "0101" etc.
  final String? projectNumber; // optional default
  final String taskName;
  final String? taskNote;
  final String
  taskResponsibility; // Civil, Owner, Surveyor, Architect, MEP, Structural, Geotechnical, Landscape, Other
  final bool isDeliverable;
  final String? ownerUid; // who owns/edits this template
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TaskTemplate({
    required this.id,
    required this.taskCode,
    required this.taskName,
    required this.taskResponsibility,
    required this.isDeliverable,
    this.projectNumber,
    this.taskNote,
    this.ownerUid,
    this.createdAt,
    this.updatedAt,
  });

  static TaskTemplate fromDoc(DocumentSnapshot doc) {
    final data = mapFrom(doc.data() as Map<String, dynamic>?);

    return TaskTemplate(
      id: doc.id,
      taskCode: readString(data, 'taskCode'),
      projectNumber: readStringOrNull(data, 'projectNumber'),
      taskName: readString(data, 'taskName'),
      taskNote: readStringOrNull(data, 'taskNote'),
      taskResponsibility: readString(
        data,
        'taskResponsibility',
        fallback: 'Civil',
      ),
      isDeliverable: readBool(data, 'isDeliverable'),
      ownerUid: readStringOrNull(data, 'ownerUid'),
      createdAt: readDateTime(data, 'createdAt'),
      updatedAt: readDateTime(data, 'updatedAt'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'taskCode': taskCode,
      'projectNumber': projectNumber,
      'taskName': taskName,
      'taskNote': taskNote,
      'taskResponsibility': taskResponsibility,
      'isDeliverable': isDeliverable,
      'ownerUid': ownerUid,
    };
  }

  TaskTemplate copyWith({
    String? id,
    String? taskCode,
    String? projectNumber,
    String? taskName,
    String? taskNote,
    String? taskResponsibility,
    bool? isDeliverable,
    String? ownerUid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TaskTemplate(
      id: id ?? this.id,
      taskCode: taskCode ?? this.taskCode,
      projectNumber: projectNumber ?? this.projectNumber,
      taskName: taskName ?? this.taskName,
      taskNote: taskNote ?? this.taskNote,
      taskResponsibility: taskResponsibility ?? this.taskResponsibility,
      isDeliverable: isDeliverable ?? this.isDeliverable,
      ownerUid: ownerUid ?? this.ownerUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
