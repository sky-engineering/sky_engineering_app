// lib/src/services/project_task_checklist_service.dart
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/checklist.dart';
import '../data/models/project.dart';
import '../data/models/project_task_checklist.dart';

class ProjectTaskChecklistService extends ChangeNotifier {
  ProjectTaskChecklistService._();

  static final ProjectTaskChecklistService instance =
      ProjectTaskChecklistService._();

  factory ProjectTaskChecklistService() => instance;

  static const _storageKey = 'project_task_checklists_storage';

  final List<ProjectTaskChecklist> _checklists = <ProjectTaskChecklist>[];
  Future<void>? _loadFuture;
  SharedPreferences? _prefs;

  UnmodifiableListView<ProjectTaskChecklist> get checklists =>
      UnmodifiableListView(_checklists);

  Future<void> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final prefs = await _ensurePrefs();
    final stored = prefs.getStringList(_storageKey) ?? const <String>[];
    final decoded = <ProjectTaskChecklist>[];
    for (final entry in stored) {
      try {
        final map = jsonDecode(entry) as Map<String, Object?>;
        decoded.add(ProjectTaskChecklist.fromMap(map));
      } catch (_) {
        // ignore malformed entries
      }
    }
    _checklists
      ..clear()
      ..addAll(decoded);
    notifyListeners();
  }

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String _nextId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<ProjectTaskChecklist> createFromTemplate({
    required String name,
    required Checklist template,
    required Project project,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Checklist name cannot be empty');
    }
    await ensureLoaded();

    final sanitizedItems = _cloneItems(template.items);
    final checklist = ProjectTaskChecklist(
      id: _nextId(),
      name: trimmedName,
      templateId: template.id,
      templateTitle: template.title,
      projectId: project.id,
      projectName: project.name,
      projectNumber: project.projectNumber,
      items: sanitizedItems,
      createdAt: DateTime.now(),
    );
    _checklists.add(checklist);
    await _persist();
    notifyListeners();
    return checklist;
  }

  Future<void> toggleItem({
    required String checklistId,
    required String itemId,
  }) async {
    await ensureLoaded();
    final checklistIndex = _checklists.indexWhere(
      (element) => element.id == checklistId,
    );
    if (checklistIndex == -1) return;
    final checklist = _checklists[checklistIndex];
    final itemIndex = checklist.items.indexWhere(
      (element) => element.id == itemId,
    );
    if (itemIndex == -1) return;

    final items = List<ChecklistItem>.from(checklist.items);
    final current = items[itemIndex];
    items[itemIndex] = current.copyWith(isDone: !current.isDone);
    _checklists[checklistIndex] = checklist.copyWith(items: items);
    await _persist();
    notifyListeners();
  }

  Future<void> delete(String id) async {
    await ensureLoaded();
    final originalLength = _checklists.length;
    _checklists.removeWhere((element) => element.id == id);
    if (_checklists.length == originalLength) return;
    await _persist();
    notifyListeners();
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Checklist name cannot be empty');
    }
    await ensureLoaded();
    final index = _checklists.indexWhere((element) => element.id == id);
    if (index == -1) return;
    final current = _checklists[index];
    if (current.name == trimmed) return;
    _checklists[index] = current.copyWith(name: trimmed);
    await _persist();
    notifyListeners();
  }

  List<ChecklistItem> _cloneItems(List<ChecklistItem> raw) {
    final result = <ChecklistItem>[];
    final seen = <String>{};
    for (final item in raw) {
      final id = item.id.isEmpty ? _nextId() : item.id;
      if (!seen.add(id)) continue;
      result.add(item.copyWith(id: id, isDone: false));
    }
    return result;
  }

  Future<void> _persist() async {
    final prefs = await _ensurePrefs();
    final encoded = _checklists
        .map((item) => jsonEncode(item.toMap()))
        .toList(growable: false);
    await prefs.setStringList(_storageKey, encoded);
  }
}
