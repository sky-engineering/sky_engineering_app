// lib/src/services/project_task_checklist_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/checklist.dart';
import '../data/models/project.dart';
import '../data/models/project_task_checklist.dart';

class ProjectTaskChecklistService extends ChangeNotifier {
  ProjectTaskChecklistService._() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      unawaited(_onAuthChanged(user));
    });
  }

  static final ProjectTaskChecklistService instance =
      ProjectTaskChecklistService._();

  factory ProjectTaskChecklistService() => instance;

  static const _storageKey = 'project_task_checklists_storage';

  final List<ProjectTaskChecklist> _checklists = <ProjectTaskChecklist>[];
  Future<void>? _loadFuture;
  SharedPreferences? _prefs;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  UnmodifiableListView<ProjectTaskChecklist> get checklists =>
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
        .orderBy('createdAt', descending: true)
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
            debugPrint('Failed to load project task checklists: $error');
          },
        );
  }

  CollectionReference<Map<String, dynamic>> _collection() {
    return FirebaseFirestore.instance.collection('projectTaskChecklists');
  }

  ProjectTaskChecklist _checklistFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
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

    final createdAtRaw = data['createdAt'];
    DateTime createdAt;
    if (createdAtRaw is Timestamp) {
      createdAt = createdAtRaw.toDate();
    } else if (createdAtRaw is String) {
      createdAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    } else if (createdAtRaw is DateTime) {
      createdAt = createdAtRaw;
    } else {
      createdAt = DateTime.now();
    }

    final map = <String, Object?>{
      'id': doc.id,
      'name': data['name'] as String? ?? '',
      'templateId': data['templateId'] as String? ?? '',
      'templateTitle': data['templateTitle'] as String? ?? '',
      'projectId': data['projectId'] as String? ?? '',
      'projectName': data['projectName'] as String? ?? '',
      'projectNumber': data['projectNumber'] as String?,
      'items': normalizedItems,
      'createdAt': createdAt.toIso8601String(),
    };

    return ProjectTaskChecklist.fromMap(map);
  }

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

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
        'User must be signed in to create a project task checklist',
      );
    }

    final sanitizedItems = _sanitizeItems(
      template.items,
      resetCompletion: true,
    );

    final doc = _collection().doc();
    final now = DateTime.now();
    await doc.set({
      'ownerUid': user.uid,
      'name': trimmedName,
      'templateId': template.id,
      'templateTitle': template.title,
      'projectId': project.id,
      'projectName': project.name,
      'projectNumber': project.projectNumber,
      'items': sanitizedItems.map((item) => item.toMap()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final checklist = ProjectTaskChecklist(
      id: doc.id,
      name: trimmedName,
      templateId: template.id,
      templateTitle: template.title,
      projectId: project.id,
      projectName: project.name,
      projectNumber: project.projectNumber,
      items: sanitizedItems,
      createdAt: now,
    );

    _upsertLocal(checklist);
    return checklist;
  }

  void _upsertLocal(ProjectTaskChecklist checklist) {
    final index = _checklists.indexWhere(
      (element) => element.id == checklist.id,
    );
    if (index >= 0) {
      _checklists[index] = checklist;
    } else {
      _checklists.add(checklist);
    }
    notifyListeners();
  }

  void _removeLocal(String id) {
    final originalLength = _checklists.length;
    _checklists.removeWhere((element) => element.id == id);
    if (_checklists.length != originalLength) {
      notifyListeners();
    }
  }

  Future<void> toggleItem({
    required String checklistId,
    required String itemId,
  }) async {
    await ensureLoaded();

    final index = _checklists.indexWhere(
      (element) => element.id == checklistId,
    );
    if (index == -1) return;

    final current = _checklists[index];
    final items = current.items
        .map((item) {
          if (item.id == itemId) {
            return item.copyWith(isDone: !item.isDone);
          }
          return item;
        })
        .toList(growable: false);

    final sanitizedItems = _sanitizeItems(items);
    final updated = current.copyWith(items: sanitizedItems);
    _checklists[index] = updated;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
        'User must be signed in to edit a project task checklist',
      );
    }

    await _collection().doc(checklistId).set({
      'ownerUid': user.uid,
      'items': sanitizedItems.map((item) => item.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await ensureLoaded();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
        'User must be signed in to delete a project task checklist',
      );
    }

    _removeLocal(id);
    await _collection().doc(id).delete();
  }

  Future<void> updateMetadata({
    required String id,
    required String name,
    required String projectId,
    required String projectName,
    String? projectNumber,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Checklist name cannot be empty');
    }

    await ensureLoaded();

    final index = _checklists.indexWhere((element) => element.id == id);
    if (index == -1) return;

    final current = _checklists[index];
    final updated = current.copyWith(
      name: trimmed,
      projectId: projectId,
      projectName: projectName,
      projectNumber: projectNumber,
    );
    _checklists[index] = updated;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(
        'User must be signed in to edit a project task checklist',
      );
    }

    await _collection().doc(id).set({
      'ownerUid': user.uid,
      'name': trimmed,
      'projectId': projectId,
      'projectName': projectName,
      'projectNumber': projectNumber,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> rename(String id, String name) async {
    final index = _checklists.indexWhere((element) => element.id == id);
    if (index == -1) return;
    final current = _checklists[index];
    await updateMetadata(
      id: id,
      name: name,
      projectId: current.projectId,
      projectName: current.projectName,
      projectNumber: current.projectNumber,
    );
  }

  List<ChecklistItem> _sanitizeItems(
    List<ChecklistItem> raw, {
    bool resetCompletion = false,
  }) {
    final result = <ChecklistItem>[];
    final seen = <String>{};
    for (final item in raw) {
      final trimmedTitle = item.title.trim();
      if (trimmedTitle.isEmpty) {
        continue;
      }
      final id = item.id.isEmpty ? _nextId() : item.id;
      if (seen.add(id)) {
        result.add(
          item.copyWith(
            id: id,
            title: trimmedTitle,
            isDone: resetCompletion ? false : item.isDone,
          ),
        );
      }
    }
    return result;
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
        final parsed = ProjectTaskChecklist.fromMap(map);
        final sanitizedItems = _sanitizeItems(
          parsed.items,
          resetCompletion: false,
        );
        final docId = parsed.id.isNotEmpty ? parsed.id : collection.doc().id;
        final docRef = collection.doc(docId);
        batch.set(docRef, {
          'ownerUid': uid,
          'name': parsed.name.trim(),
          'templateId': parsed.templateId,
          'templateTitle': parsed.templateTitle,
          'projectId': parsed.projectId,
          'projectName': parsed.projectName,
          'projectNumber': parsed.projectNumber,
          'items': sanitizedItems.map((item) => item.toMap()).toList(),
          'createdAt': parsed.createdAt,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (error) {
        debugPrint('Failed to migrate project task checklist: $error');
      }
    }

    await batch.commit();
    await prefs.remove(_storageKey);
  }

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String _nextId() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  void dispose() {
    _subscription?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
