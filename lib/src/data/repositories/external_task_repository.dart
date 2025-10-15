// lib/src/data/repositories/external_task_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/external_task.dart';

class ExternalTaskRepository {
  ExternalTaskRepository()
    : _projects = FirebaseFirestore.instance.collection('projects');

  final CollectionReference<Map<String, dynamic>> _projects;

  Future<void> add(String projectId, ExternalTask task) async {
    final docRef = _projects.doc(projectId);
    final id = FirebaseFirestore.instance
        .collection('_external_tasks')
        .doc()
        .id;
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
      });
    });
  }

  Future<void> update(
    String projectId,
    String taskId,
    Map<String, dynamic> partial,
  ) async {
    final docRef = _projects.doc(projectId);

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(docRef);
      if (!snap.exists) {
        throw StateError('Project not found');
      }
      final data = snap.data() ?? <String, dynamic>{};
      final tasks = _readTasks(data['externalTasks'], projectId);
      final index = tasks.indexWhere((t) => t.id == taskId);
      if (index < 0) {
        throw StateError('External task not found');
      }
      var updated = tasks[index];

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

      updated = updated.copyWith(updatedAt: DateTime.now());
      tasks[index] = updated;
      _sortTasks(tasks);

      txn.update(docRef, {
        'externalTasks': tasks.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
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
}
