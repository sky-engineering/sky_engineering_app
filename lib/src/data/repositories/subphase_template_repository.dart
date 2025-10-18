// lib/src/data/repositories/subphase_template_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/subphase_template.dart';

/// Works over the same collection as your old templates (`task_templates`),
/// just returns/writes SubphaseTemplate objects.
class SubphaseTemplateRepository {
  final _col = FirebaseFirestore.instance.collection('task_templates');

  /// Stream all subphases for a user (client-side sorted by code).
  Stream<List<SubphaseTemplate>> streamForUser(String ownerUid) {
    return _col.where('ownerUid', isEqualTo: ownerUid).snapshots().map((snap) {
      final list = snap.docs.map(SubphaseTemplate.fromDoc).toList();
      list.sort((a, b) => a.subphaseCode.compareTo(b.subphaseCode));
      return list;
    });
  }

  /// One-shot fetch (used by project subphase selector).
  Future<List<SubphaseTemplate>> getAllForUser(String ownerUid) async {
    final qs = await _col.where('ownerUid', isEqualTo: ownerUid).get();
    final list = qs.docs.map(SubphaseTemplate.fromDoc).toList();
    list.sort((a, b) => a.subphaseCode.compareTo(b.subphaseCode));
    return list;
  }

  /// Convenience: fetch a single template for a given owner + 4-digit code.
  /// Tries the canonical key `subphaseCode` first, then falls back to legacy `taskCode`.
  Future<SubphaseTemplate?> getByOwnerAndCode(
    String ownerUid,
    String subphaseCode,
  ) async {
    // Try new schema key
    var qs = await _col
        .where('ownerUid', isEqualTo: ownerUid)
        .where('subphaseCode', isEqualTo: subphaseCode)
        .limit(1)
        .get();

    if (qs.docs.isNotEmpty) {
      return SubphaseTemplate.fromDoc(qs.docs.first);
    }

    // Fallback to legacy key
    qs = await _col
        .where('ownerUid', isEqualTo: ownerUid)
        .where('taskCode', isEqualTo: subphaseCode)
        .limit(1)
        .get();

    if (qs.docs.isNotEmpty) {
      return SubphaseTemplate.fromDoc(qs.docs.first);
    }

    return null;
  }

  /// Create
  Future<String> add(SubphaseTemplate t) async {
    final ref = _col.doc();
    await ref.set({
      ...t.copyWith(id: ref.id).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Update (partial)
  Future<void> update(String id, Map<String, dynamic> partial) async {
    await _col.doc(id).update({
      ...partial,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete
  Future<void> delete(String id) => _col.doc(id).delete();
}
