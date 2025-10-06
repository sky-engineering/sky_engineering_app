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
  static const _showKey = 'personal_checklist_show_starred';

  final List<PersonalChecklistItem> _items = <PersonalChecklistItem>[];
  bool _showInStarred = false;

  Future<void>? _loadFuture;
  SharedPreferences? _prefs;

  UnmodifiableListView<PersonalChecklistItem> get items =>
      UnmodifiableListView(_items);

  bool get showInStarred => _showInStarred;

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
    _showInStarred = prefs.getBool(_showKey) ?? false;
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
    _items.add(PersonalChecklistItem(id: _nextId(), title: trimmed));
    await _persistItems();
    notifyListeners();
  }

  Future<void> setCompletion(String id, bool isDone) async {
    await ensureLoaded();
    final index = _items.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _items[index] = _items[index].copyWith(isDone: isDone);
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

  Future<void> setShowInStarred(bool value) async {
    await ensureLoaded();
    if (_showInStarred == value) return;
    _showInStarred = value;
    await _persistFlag();
    notifyListeners();
  }

  Future<void> _persistItems() async {
    final prefs = await _ensurePrefs();
    final encoded = _items
        .map((item) => jsonEncode(item.toMap()))
        .toList(growable: false);
    await prefs.setStringList(_itemsKey, encoded);
    await _persistFlag();
  }

  Future<void> _persistFlag() async {
    final prefs = await _ensurePrefs();
    await prefs.setBool(_showKey, _showInStarred);
  }
}


