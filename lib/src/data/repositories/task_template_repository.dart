// lib/src/data/repositories/task_template_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_template.dart';

class TaskTemplateRepository {
  final _col = FirebaseFirestore.instance.collection('task_templates');

  /// Current user's templates (sorted client-side by taskCode).
  Stream<List<TaskTemplate>> streamForUser(String ownerUid) {
    return _col.where('ownerUid', isEqualTo: ownerUid).snapshots().map((snap) {
      final list = snap.docs.map(TaskTemplate.fromDoc).toList();
      list.sort((a, b) => a.taskCode.compareTo(b.taskCode));
      return list;
    });
  }

  /// NEW: One-shot fetch for auto-populating a project.
  Future<List<TaskTemplate>> getAllForUser(String ownerUid) async {
    final qs = await _col.where('ownerUid', isEqualTo: ownerUid).get();
    final list = qs.docs.map(TaskTemplate.fromDoc).toList();
    list.sort((a, b) => a.taskCode.compareTo(b.taskCode));
    return list;
  }

  Future<String> add(TaskTemplate t) async {
    final ref = _col.doc();
    await ref.set({
      ...t.copyWith(id: ref.id).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> update(String id, Map<String, dynamic> partial) async {
    await _col.doc(id).update({
      ...partial,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => _col.doc(id).delete();
}
