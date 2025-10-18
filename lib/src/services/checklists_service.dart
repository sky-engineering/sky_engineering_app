// lib/src/services/checklists_service.dart
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/checklist.dart';

class ChecklistsService extends ChangeNotifier {
  ChecklistsService._();

  static final ChecklistsService instance = ChecklistsService._();

  factory ChecklistsService() => instance;

  static const _storageKey = 'custom_checklists_storage';

  final List<Checklist> _checklists = <Checklist>[];
  Future<void>? _loadFuture;
  SharedPreferences? _prefs;

  UnmodifiableListView<Checklist> get checklists =>
      UnmodifiableListView(_checklists);

  Future<void> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final prefs = await _ensurePrefs();
    final stored = prefs.getStringList(_storageKey) ?? const <String>[];
    final decoded = <Checklist>[];
    for (final entry in stored) {
      try {
        final map = jsonDecode(entry) as Map<String, Object?>;
        decoded.add(Checklist.fromMap(map));
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

  Future<Checklist> createChecklist({
    required String title,
    required List<ChecklistItem> items,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError.value(
        title,
        'title',
        'Checklist title cannot be empty',
      );
    }
    await ensureLoaded();
    final sanitizedItems = _sanitizeItems(items);
    final checklist = Checklist(
      id: _nextId(),
      title: trimmedTitle,
      items: sanitizedItems,
    );
    _checklists.add(checklist);
    await _persist();
    notifyListeners();
    return checklist;
  }

  Future<void> updateChecklist(Checklist updated) async {
    await ensureLoaded();
    final index = _checklists.indexWhere((item) => item.id == updated.id);
    if (index == -1) {
      throw ArgumentError('Checklist not found: ${updated.id}');
    }
    final sanitizedItems = _sanitizeItems(updated.items);
    _checklists[index] = updated.copyWith(items: sanitizedItems);
    await _persist();
    notifyListeners();
  }

  Future<void> renameChecklist(String id, String title) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Checklist title cannot be empty');
    }
    await ensureLoaded();
    final index = _checklists.indexWhere((item) => item.id == id);
    if (index == -1) {
      return;
    }
    final current = _checklists[index];
    if (current.title == trimmedTitle) return;
    _checklists[index] = current.copyWith(title: trimmedTitle);
    await _persist();
    notifyListeners();
  }

  Future<void> deleteChecklist(String id) async {
    await ensureLoaded();
    final originalLength = _checklists.length;
    _checklists.removeWhere((item) => item.id == id);
    if (_checklists.length == originalLength) return;
    await _persist();
    notifyListeners();
  }

  Future<void> setItemCompletion(
    String checklistId,
    String itemId,
    bool isDone,
  ) async {
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
    final updatedItems = List<ChecklistItem>.from(checklist.items);
    updatedItems[itemIndex] = updatedItems[itemIndex].copyWith(isDone: isDone);
    _checklists[checklistIndex] = checklist.copyWith(
      items: _sanitizeItems(updatedItems),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> replaceChecklistItems(
    String checklistId,
    List<ChecklistItem> items,
  ) async {
    await ensureLoaded();
    final index = _checklists.indexWhere((item) => item.id == checklistId);
    if (index == -1) return;
    _checklists[index] = _checklists[index].copyWith(
      items: _sanitizeItems(items),
    );
    await _persist();
    notifyListeners();
  }

  List<ChecklistItem> _sanitizeItems(List<ChecklistItem> items) {
    final result = <ChecklistItem>[];
    final seen = <String>{};
    for (final item in items) {
      final trimmedTitle = item.title.trim();
      if (trimmedTitle.isEmpty) {
        continue;
      }
      final id = item.id.isEmpty ? _nextId() : item.id;
      if (seen.add(id)) {
        result.add(item.copyWith(id: id, title: trimmedTitle));
      }
    }
    return result;
  }

  Future<void> _persist() async {
    final prefs = await _ensurePrefs();
    final encoded = _checklists
        .map((checklist) => jsonEncode(checklist.toMap()))
        .toList(growable: false);
    await prefs.setStringList(_storageKey, encoded);
  }
}
