// lib/src/data/repositories/task_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task.dart';

class TaskRepository {
  final _col = FirebaseFirestore.instance.collection('tasks');

  /// Stream tasks for a project, primarily ordered by dueDate ASC.
  /// Requires composite index: projectId ASC, dueDate ASC.
  ///
  /// We also apply a client-side stable sort to ensure:
  /// - earlier due dates first
  /// - null due dates last
  /// - then title A???Z
  Stream<List<TaskItem>> streamByProject(String projectId) {
    final qs = _col
        .where('projectId', isEqualTo: projectId)
        .orderBy('dueDate', descending: false);

    return qs.snapshots().map((snap) {
      final items = snap.docs.map(TaskItem.fromDoc).toList();
      items.sort(_byDueThenTitle);
      return items;
    });
  }

  /// Stream all starred tasks regardless of owner.
  Stream<List<TaskItem>> streamStarred() {
    return _col
        .where('isStarred', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map(TaskItem.fromDoc).toList());
  }

  /// Stream tasks for a user filtered by status.
  Stream<List<TaskItem>> streamByStatuses(
    String ownerUid,
    List<String> statuses,
  ) {
    assert(statuses.isNotEmpty, 'statuses cannot be empty');
    return _col
        .where('ownerUid', isEqualTo: ownerUid)
        .where('taskStatus', whereIn: statuses)
        .snapshots()
        .map((snap) => snap.docs.map(TaskItem.fromDoc).toList());
  }

  /// Fetch a single task by id.
  Future<TaskItem?> getById(String id) async {
    final d = await _col.doc(id).get();
    if (!d.exists) return null;
    return TaskItem.fromDoc(d);
  }

  /// Returns the new document id.
  Future<String> add(TaskItem t) async {
    final ref = _col.doc();
    await ref.set({
      ...t.copyWith(id: ref.id).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Partial update; stamps updatedAt and safely encodes dueDate if needed.
  Future<void> update(String id, Map<String, dynamic> partial) async {
    final encoded = <String, dynamic>{...partial};

    // If caller passed a DateTime for dueDate, encode to Timestamp.
    if (encoded.containsKey('dueDate')) {
      final v = encoded['dueDate'];
      if (v is DateTime) {
        encoded['dueDate'] = Timestamp.fromDate(v);
      } else if (v == null || v is Timestamp) {
        // leave as-is (null clears the field; Timestamp is already correct)
      } else {
        // attempt best-effort conversion (e.g., millisecondsSinceEpoch)
        if (v is int) {
          encoded['dueDate'] = Timestamp.fromMillisecondsSinceEpoch(v);
        }
      }
    }

    if (encoded.containsKey('subtasks')) {
      final value = encoded['subtasks'];
      if (value is List<SubtaskItem>) {
        encoded['subtasks'] = value.map((s) => s.toMap()).toList();
      } else if (value is Iterable) {
        encoded['subtasks'] = value
            .map((item) {
              if (item is SubtaskItem) return item.toMap();
              if (item is Map<String, dynamic>) return item;
              if (item is Map) return Map<String, dynamic>.from(item);
              return null;
            })
            .whereType<Map<String, dynamic>>()
            .toList();
      } else if (value == null) {
        encoded['subtasks'] = FieldValue.delete();
      }
    }

    encoded['updatedAt'] = FieldValue.serverTimestamp();
    await _col.doc(id).update(encoded);
  }

  Future<SubtaskItem> addSubtask(String taskId, SubtaskItem subtask) async {
    await _col.doc(taskId).update({
      'subtasks': FieldValue.arrayUnion([subtask.toMap()]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return subtask;
  }

  Future<void> setStarred(TaskItem task, bool value, {int? order}) async {
    final data = <String, dynamic>{
      'isStarred': value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (value) {
      data['starredOrder'] =
          order ?? task.starredOrder ?? DateTime.now().millisecondsSinceEpoch;
    } else {
      data['starredOrder'] = FieldValue.delete();
    }
    await _col.doc(task.id).update(data);
  }

  Future<void> reorderStarredTasks(List<TaskItem> tasks) async {
    final batch = FirebaseFirestore.instance.batch();
    for (var i = 0; i < tasks.length; i++) {
      batch.update(_col.doc(tasks[i].id), {
        'starredOrder': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> delete(String id) => _col.doc(id).delete();

  // ----------------- helpers -----------------

  static int _byDueThenTitle(TaskItem a, TaskItem b) {
    final ad = a.dueDate, bd = b.dueDate;
    if (ad != null && bd != null) {
      final c = ad.compareTo(bd);
      if (c != 0) return c;
    } else if (ad == null && bd != null) {
      return 1; // nulls last
    } else if (ad != null && bd == null) {
      return -1;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }
}
