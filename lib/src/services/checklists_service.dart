// lib/src/services/checklists_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/checklist.dart';

class ChecklistsService extends ChangeNotifier {
  ChecklistsService._() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(_onAuthChanged(user));
    });
  }

  static final ChecklistsService instance = ChecklistsService._();

  factory ChecklistsService() => instance;

  static const _storageKey = 'custom_checklists_storage';

  final List<Checklist> _checklists = <Checklist>[];
  Future<void>? _loadFuture;
  SharedPreferences? _prefs;
  void _upsertLocal(Checklist checklist) {
    final index = _checklists.indexWhere((c) => c.id == checklist.id);
    if (index >= 0) {
      _checklists[index] = checklist;
    } else {
      _checklists.add(checklist);
    }
    _checklists.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    notifyListeners();
  }

  void _removeLocal(String id) {
    var removed = false;
    _checklists.removeWhere((c) {
      if (c.id == id) {
        removed = true;
        return true;
      }
      return false;
    });
    if (removed) {
      notifyListeners();
    }
  }

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  UnmodifiableListView<Checklist> get checklists =>
      UnmodifiableListView(_checklists);

  Future<void> ensureLoaded() {
    return _loadFuture ??= _load();
  }

  Future<void> _onAuthChanged(User? user) async {
    await _subscription?.cancel();
    _subscription = null;
    _loadFuture = null;

    if (user == null) {
      _checklists.clear();
      notifyListeners();
      return;
    }

    await _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _checklists.clear();
      notifyListeners();
      return;
    }

    await _subscription?.cancel();

    await _maybeMigrateLegacy(user.uid);

    final collection = _collection();

    _subscription = collection
        .where('ownerUid', isEqualTo: user.uid)
        .orderBy('title')
        .snapshots()
        .listen(
          (snapshot) {
            final next = snapshot.docs.map(_checklistFromDoc).toList();
            _checklists
              ..clear()
              ..addAll(next);
            notifyListeners();
          },
          onError: (error, stackTrace) {
            debugPrint('Failed to load reusable checklists: $error');
          },
        );
  }

  Checklist _checklistFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final normalizedItems = <Map<String, Object?>>[];
    final rawItems = data['items'];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map<String, dynamic>) {
          normalizedItems.add(Map<String, Object?>.from(entry));
        } else if (entry is Map) {
          final typed = <String, Object?>{};
          entry.forEach((key, value) {
            typed[key.toString()] = value;
          });
          normalizedItems.add(typed);
        }
      }
    }

    final map = <String, Object?>{
      'id': doc.id,
      'title': data['title'],
      'items': normalizedItems,
    };

    return Checklist.fromMap(map);
  }

  CollectionReference<Map<String, dynamic>> _collection() {
    return FirebaseFirestore.instance.collection('checklistTemplates');
  }

  Future<void> _maybeMigrateLegacy(String uid) async {
    final prefs = await _ensurePrefs();
    final stored = prefs.getStringList(_storageKey);
    if (stored == null || stored.isEmpty) {
      return;
    }

    final collection = _collection();
    final hasExisting = await collection
        .where('ownerUid', isEqualTo: uid)
        .limit(1)
        .get()
        .then((value) => value.docs.isNotEmpty);
    if (hasExisting) {
      await prefs.remove(_storageKey);
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (final entry in stored) {
      try {
        final map = jsonDecode(entry) as Map<String, Object?>;
        final parsed = Checklist.fromMap(map);
        final sanitizedItems = _sanitizeItems(parsed.items);
        final docId = parsed.id.isNotEmpty ? parsed.id : collection.doc().id;
        final docRef = collection.doc(docId);
        batch.set(docRef, {
          'ownerUid': uid,
          'title': parsed.title.trim(),
          'items': sanitizedItems.map((item) => item.toMap()).toList(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        debugPrint('Failed to migrate checklist: $error');
      }
    }

    await batch.commit();
    await prefs.remove(_storageKey);
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

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to create a checklist');
    }

    final sanitizedItems = _sanitizeItems(items);
    final doc = _collection().doc();
    await doc.set({
      'ownerUid': user.uid,
      'title': trimmedTitle,
      'items': sanitizedItems.map((item) => item.toMap()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final created = Checklist(
      id: doc.id,
      title: trimmedTitle,
      items: sanitizedItems,
    );
    _upsertLocal(created);
    return created;
  }

  Future<void> updateChecklist(Checklist updated) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to update a checklist');
    }
    final sanitizedItems = _sanitizeItems(updated.items);
    final trimmedTitle = updated.title.trim();
    await _collection().doc(updated.id).set({
      'ownerUid': user.uid,
      'title': trimmedTitle,
      'items': sanitizedItems.map((item) => item.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _upsertLocal(updated.copyWith(title: trimmedTitle, items: sanitizedItems));
  }

  Future<void> renameChecklist(String id, String title) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Checklist title cannot be empty');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to rename a checklist');
    }
    await _collection().doc(id).set({
      'ownerUid': user.uid,
      'title': trimmedTitle,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final existing = _checklists.firstWhere(
      (c) => c.id == id,
      orElse: () => Checklist(
        id: id,
        title: trimmedTitle,
        items: const <ChecklistItem>[],
      ),
    );
    _upsertLocal(existing.copyWith(title: trimmedTitle));
  }

  Future<void> deleteChecklist(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to delete a checklist');
    }
    await _collection().doc(id).delete();
    _removeLocal(id);
  }

  Future<void> setItemCompletion(
    String checklistId,
    String itemId,
    bool isDone,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to edit a checklist');
    }

    final current = _checklists.firstWhere(
      (element) => element.id == checklistId,
      orElse: () => throw ArgumentError('Checklist not found: $checklistId'),
    );

    final updatedItems = current.items.map((item) {
      if (item.id == itemId) {
        return item.copyWith(isDone: isDone);
      }
      return item;
    }).toList();

    final sanitizedItems = _sanitizeItems(updatedItems);
    await _collection().doc(checklistId).set({
      'ownerUid': user.uid,
      'items': sanitizedItems.map((item) => item.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _upsertLocal(current.copyWith(items: sanitizedItems));
  }

  Future<void> replaceChecklistItems(
    String checklistId,
    List<ChecklistItem> items,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('User must be signed in to edit a checklist');
    }

    final sanitizedItems = _sanitizeItems(items);
    await _collection().doc(checklistId).set({
      'ownerUid': user.uid,
      'items': sanitizedItems.map((item) => item.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    final existing = _checklists.firstWhere(
      (element) => element.id == checklistId,
      orElse: () =>
          Checklist(id: checklistId, title: '', items: const <ChecklistItem>[]),
    );
    _upsertLocal(existing.copyWith(items: sanitizedItems));
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

  @override
  void dispose() {
    _subscription?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
