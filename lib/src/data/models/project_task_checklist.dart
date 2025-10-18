// lib/src/data/models/project_task_checklist.dart
import 'checklist.dart';

class ProjectTaskChecklist {
  ProjectTaskChecklist({
    required this.id,
    required this.name,
    required this.templateId,
    required this.templateTitle,
    required this.projectId,
    required this.projectName,
    required this.projectNumber,
    required this.items,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String templateId;
  final String templateTitle;
  final String projectId;
  final String projectName;
  final String? projectNumber;
  final List<ChecklistItem> items;
  final DateTime createdAt;

  ProjectTaskChecklist copyWith({
    String? id,
    String? name,
    String? templateId,
    String? templateTitle,
    String? projectId,
    String? projectName,
    String? projectNumber,
    List<ChecklistItem>? items,
    DateTime? createdAt,
  }) {
    return ProjectTaskChecklist(
      id: id ?? this.id,
      name: name ?? this.name,
      templateId: templateId ?? this.templateId,
      templateTitle: templateTitle ?? this.templateTitle,
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      projectNumber: projectNumber ?? this.projectNumber,
      items: items ?? this.items,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'templateId': templateId,
      'templateTitle': templateTitle,
      'projectId': projectId,
      'projectName': projectName,
      'projectNumber': projectNumber,
      'items': items.map((item) => item.toMap()).toList(growable: false),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ProjectTaskChecklist.fromMap(Map<String, Object?> map) {
    final rawItems = map['items'];
    final parsedItems = <ChecklistItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map) {
          final typed = <String, Object?>{};
          entry.forEach((key, value) {
            typed[key.toString()] = value;
          });
          parsedItems.add(ChecklistItem.fromMap(typed));
        }
      }
    }

    final createdAtRaw = map['createdAt'];
    DateTime createdAt;
    if (createdAtRaw is String) {
      createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    return ProjectTaskChecklist(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      templateId: map['templateId'] as String? ?? '',
      templateTitle: map['templateTitle'] as String? ?? '',
      projectId: map['projectId'] as String? ?? '',
      projectName: map['projectName'] as String? ?? '',
      projectNumber: map['projectNumber'] as String?,
      items: parsedItems,
      createdAt: createdAt,
    );
  }
}
