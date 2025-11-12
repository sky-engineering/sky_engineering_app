// lib/src/services/personal_checklist_service.dart
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/personal_checklist_item.dart';

class PersonalChecklistService extends ChangeNotifier {
  PersonalChecklistService._();

  static final PersonalChecklistService instance = PersonalChecklistService._();

  factory PersonalChecklistService() => instance;

  static const _itemsKey = 'personal_checklist_items';

  final List<PersonalChecklistItem> _items = <PersonalChecklistItem>[];

  Future<void>? _loadFuture;
  SharedPreferences? _prefs;

  UnmodifiableListView<PersonalChecklistItem> get items =>
      UnmodifiableListView(_items);

  Future<void> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final prefs = await _ensurePrefs();
    final stored = prefs.getStringList(_itemsKey) ?? const <String>[];
    _items
      ..clear()
      ..addAll(
        stored.map((entry) {
          try {
            final map = jsonDecode(entry) as Map<String, dynamic>;
            return PersonalChecklistItem.fromMap(map);
          } catch (_) {
            return null;
          }
        }).whereType<PersonalChecklistItem>(),
      );
    notifyListeners();
  }

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String _nextId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> addItem(String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    await ensureLoaded();
    _items.add(
      PersonalChecklistItem(id: _nextId(), title: trimmed),
    );
    await _persistItems();
    notifyListeners();
  }

  Future<void> setCompletion(String id, bool isDone) {
    return _updateItemFields(id, isDone: isDone);
  }

  Future<void> setStarred(String id, bool isStarred) {
    return _updateItemFields(id, isStarred: isStarred);
  }

  Future<void> updateItem({
    required String id,
    String? title,
    bool? isDone,
    bool? isStarred,
  }) {
    return _updateItemFields(
      id,
      title: title,
      isDone: isDone,
      isStarred: isStarred,
    );
  }

  Future<void> reorderItems(List<String> orderedIds) async {
    await ensureLoaded();
    if (orderedIds.isEmpty) return;

    final lookup = {for (final item in _items) item.id: item};
    final reordered = <PersonalChecklistItem>[];
    final seen = <String>{};

    for (final id in orderedIds) {
      final item = lookup[id];
      if (item != null && seen.add(id)) {
        reordered.add(item);
      }
    }

    for (final item in _items) {
      if (seen.add(item.id)) {
        reordered.add(item);
      }
    }

    final currentOrder = _items.map((item) => item.id).toList(growable: false);
    final nextOrder = reordered.map((item) => item.id).toList(growable: false);
    if (listEquals(currentOrder, nextOrder)) return;

    _items
      ..clear()
      ..addAll(reordered);
    await _persistItems();
    notifyListeners();
  }

  Future<void> removeItem(String id) async {
    await ensureLoaded();
    final originalLength = _items.length;
    _items.removeWhere((item) => item.id == id);
    if (_items.length == originalLength) return;
    await _persistItems();
    notifyListeners();
  }

  Future<void> clearCompleted() async {
    await ensureLoaded();
    final originalLength = _items.length;
    _items.removeWhere((item) => item.isDone);
    if (_items.length == originalLength) return;
    await _persistItems();
    notifyListeners();
  }

  Future<void> _updateItemFields(
    String id, {
    String? title,
    bool? isDone,
    bool? isStarred,
  }) async {
    await ensureLoaded();
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final trimmedTitle = title?.trim();
    if (trimmedTitle?.isEmpty ?? false) {
      return;
    }
    final current = _items[index];
    final updated = current.copyWith(
      title: trimmedTitle ?? current.title,
      isDone: isDone ?? current.isDone,
      isStarred: isStarred ?? current.isStarred,
    );
    final changed = updated.title != current.title ||
        updated.isDone != current.isDone ||
        updated.isStarred != current.isStarred;
    if (!changed) return;
    _items[index] = updated;
    await _persistItems();
    notifyListeners();
  }

  Future<void> _persistItems() async {
    final prefs = await _ensurePrefs();
    final encoded =
        _items.map((item) => jsonEncode(item.toMap())).toList(growable: false);
    await prefs.setStringList(_itemsKey, encoded);
  }
}
