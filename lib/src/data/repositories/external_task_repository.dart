// lib/src/data/repositories/external_task_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/external_task.dart';

class ExternalTaskRepository {
  ExternalTaskRepository()
      : _projects = FirebaseFirestore.instance.collection('projects');

  final CollectionReference<Map<String, dynamic>> _projects;

  Future<void> add(String projectId, ExternalTask task) async {
    final docRef = _projects.doc(projectId);
    final id =
        FirebaseFirestore.instance.collection('_external_tasks').doc().id;
    final now = DateTime.now();
    final newTask = task.copyWith(
      id: id,
      projectId: projectId,
      createdAt: now,
      updatedAt: now,
    );

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      if (!snap.exists) {
        throw StateError('Project not found');
      }
      final data = snap.data() ?? <String, dynamic>{};
      final tasks = _readTasks(data['externalTasks'], projectId);
      tasks.add(newTask);
      _sortTasks(tasks);
      txn.update(docRef, {
        'externalTasks': tasks.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'hasExternalTasks': tasks.isNotEmpty,
      });
    });
  }

  Future<void> update(
    String projectId,
    String taskId,
    Map<String, dynamic> partial,
  ) async {
    try {
      await _updateWithStrategy(
        projectId,
        taskId,
        partial,
        useTransaction: true,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'resource-exhausted') {
        await _updateWithStrategy(
          projectId,
          taskId,
          partial,
          useTransaction: false,
        );
      } else {
        rethrow;
      }
    }
  }

  Future<void> setStarred(
    String projectId,
    String taskId,
    bool value, {
    int? starredOrder,
  }) async {
    return update(projectId, taskId, {
      'isStarred': value,
      'starredOrder': value ? starredOrder : null,
    });
  }

  Future<void> reorderStarredTasks(
    String projectId,
    Map<String, int?> ordering,
  ) async {
    final docRef = _projects.doc(projectId);

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      if (!snap.exists) {
        throw StateError('Project not found');
      }
      final data = snap.data() ?? <String, dynamic>{};
      final tasks = _readTasks(data['externalTasks'], projectId);
      var changed = false;
      for (final entry in ordering.entries) {
        final index = tasks.indexWhere((t) => t.id == entry.key);
        if (index == -1) continue;
        final current = tasks[index];
        final next = current.copyWith(
          starredOrder: entry.value,
          isStarred: entry.value != null ? true : current.isStarred,
          updatedAt: DateTime.now(),
        );
        tasks[index] = next;
        changed = true;
      }
      if (!changed) return;
      _sortTasks(tasks);
      txn.update(docRef, {
        'externalTasks': tasks.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'hasExternalTasks': tasks.isNotEmpty,
      });
    });
  }

  Future<void> delete(String projectId, String taskId) async {
    final docRef = _projects.doc(projectId);

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      if (!snap.exists) {
        throw StateError('Project not found');
      }
      final data = snap.data() ?? <String, dynamic>{};
      final tasks = _readTasks(data['externalTasks'], projectId);
      final updated = tasks.where((t) => t.id != taskId).toList();
      if (updated.length == tasks.length) {
        return;
      }
      _sortTasks(updated);
      txn.update(docRef, {
        'externalTasks': updated.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'hasExternalTasks': updated.isNotEmpty,
      });
    });
  }

  List<ExternalTask> _readTasks(dynamic raw, String projectId) {
    if (raw is! List) return <ExternalTask>[];
    final tasks = <ExternalTask>[];
    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        final task = ExternalTask.fromMap(entry).copyWith(projectId: projectId);
        if (task.id.isNotEmpty) {
          tasks.add(task);
        }
      }
    }
    _sortTasks(tasks);
    return tasks;
  }

  void _sortTasks(List<ExternalTask> tasks) {
    tasks.sort((a, b) {
      if (a.isDone != b.isDone) {
        return (a.isDone ? 1 : 0) - (b.isDone ? 1 : 0);
      }
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return ad.compareTo(bd);
    });
  }

  Future<void> _updateWithStrategy(
    String projectId,
    String taskId,
    Map<String, dynamic> partial, {
    required bool useTransaction,
  }) async {
    final docRef = _projects.doc(projectId);

    Future<void> writeTasks(
      List<ExternalTask> tasks,
      Future<void> Function(Map<String, dynamic>) updater,
    ) async {
      _sortTasks(tasks);
      await updater({
        'externalTasks': tasks.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'hasExternalTasks': tasks.isNotEmpty,
      });
    }

    ExternalTask applyChanges(ExternalTask current) {
      var updated = current;
      if (partial.containsKey('title')) {
        final value = partial['title'] as String?;
        if (value != null) {
          updated = updated.copyWith(title: value.trim());
        }
      }
      if (partial.containsKey('assigneeKey')) {
        final value = partial['assigneeKey'] as String?;
        if (value != null) {
          updated = updated.copyWith(assigneeKey: value);
        }
      }
      if (partial.containsKey('assigneeName')) {
        final value = partial['assigneeName'] as String?;
        if (value != null) {
          updated = updated.copyWith(assigneeName: value);
        }
      }
      if (partial.containsKey('isDone')) {
        final value = partial['isDone'];
        if (value is bool) {
          updated = updated.copyWith(isDone: value);
        }
      }
      if (partial.containsKey('isStarred')) {
        final value = partial['isStarred'];
        if (value is bool) {
          updated = updated.copyWith(isStarred: value);
        }
      }
      if (partial.containsKey('starredOrder')) {
        final value = partial['starredOrder'];
        if (value == null || value is num) {
          updated = updated.copyWith(
            starredOrder: value == null ? null : (value as num).toInt(),
          );
        }
      }
      return updated.copyWith(updatedAt: DateTime.now());
    }

    Future<void> mutate(
      List<ExternalTask> tasks,
      Future<void> Function(Map<String, dynamic>) updater,
    ) async {
      final index = tasks.indexWhere((t) => t.id == taskId);
      if (index < 0) {
        throw StateError('External task not found');
      }
      tasks[index] = applyChanges(tasks[index]);
      await writeTasks(tasks, updater);
    }

    if (useTransaction) {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final snap = await txn.get(docRef);
        if (!snap.exists) {
          throw StateError('Project not found');
        }
        final data = snap.data() ?? <String, dynamic>{};
        final tasks = _readTasks(data['externalTasks'], projectId);
        await mutate(tasks, (payload) async {
          txn.update(docRef, payload);
        });
      });
    } else {
      final snap = await docRef.get();
      if (!snap.exists) {
        throw StateError('Project not found');
      }
      final data = snap.data() ?? <String, dynamic>{};
      final tasks = _readTasks(data['externalTasks'], projectId);
      await mutate(tasks, (payload) => docRef.update(payload));
    }
  }
}
