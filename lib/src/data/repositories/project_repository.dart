// lib/src/data/repositories/project_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/project.dart';

class ProjectRepository {
  final _col = FirebaseFirestore.instance.collection('projects');
  Future<void>? _externalTaskFlagFuture;

  /// Stream all projects ordered by createdAt desc (nulls last).
  Stream<List<Project>> streamAll() {
    // If createdAt is missing on older docs, Firestore can't order; we can fallback client-side.
    return _col
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(_mapSnapshot);
  }

  /// Stream only projects that currently have external tasks.
  Stream<List<Project>> streamWithExternalTasks() {
    return _col
        .where('hasExternalTasks', isEqualTo: true)
        .snapshots()
        .map(_mapSnapshot);
  }

  /// Stream a single project by id (null if deleted/missing).
  Stream<Project?> streamById(String id) {
    return _col
        .doc(id)
        .snapshots()
        .map((d) => d.exists ? Project.fromDoc(d) : null);
  }

  /// NEW: Fetch a single project once by id.
  Future<Project?> getById(String id) async {
    final d = await _col.doc(id).get();
    if (!d.exists) return null;
    return Project.fromDoc(d);
  }

  /// Create a project. Returns the new document id.
  Future<String> add(Project p) async {
    final ref = _col.doc();
    await ref.set({
      ...p.copyWith(id: ref.id).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Partial update with server updatedAt.
  Future<void> update(String id, Map<String, dynamic> partial) async {
    await _col.doc(id).update({
      ...partial,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a project.
  Future<void> delete(String id) => _col.doc(id).delete();

  Future<void> ensureExternalTaskFlagsSeeded() {
    return _externalTaskFlagFuture ??= _backfillExternalTaskFlags();
  }

  List<Project> _mapSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map(Project.fromDoc).toList();
    list.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return list;
  }

  Future<void> _backfillExternalTaskFlags() async {
    const batchSize = 200;
    while (true) {
      final snap = await _col
          .where('hasExternalTasks', isNull: true)
          .limit(batchSize)
          .get();
      if (snap.docs.isEmpty) break;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        final rawTasks = doc.data()['externalTasks'];
        final hasTasks = rawTasks is List && rawTasks.isNotEmpty;
        batch.update(doc.reference, {'hasExternalTasks': hasTasks});
      }
      await batch.commit();
      if (snap.docs.length < batchSize) break;
    }
  }
}
