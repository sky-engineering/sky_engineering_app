// lib/src/data/repositories/phase_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/phase.dart';

class PhaseRepository {
  final _col = FirebaseFirestore.instance.collection('phases');

  /// Stream phases for a user, ordered by `order` then `phaseCode`.
  Stream<List<Phase>> streamForUser(String ownerUid) {
    return _col
        .where('ownerUid', isEqualTo: ownerUid)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Phase.fromDoc).toList();
      list.sort((a, b) {
        final ao = a.order ?? 9999;
        final bo = b.order ?? 9999;
        final byOrder = ao.compareTo(bo);
        if (byOrder != 0) return byOrder;
        return a.phaseCode.compareTo(b.phaseCode);
      });
      return list;
    });
  }

  Future<List<Phase>> getAllForUser(String ownerUid) async {
    final q = await _col.where('ownerUid', isEqualTo: ownerUid).get();
    final list = q.docs.map(Phase.fromDoc).toList();
    list.sort((a, b) {
      final ao = a.order ?? 9999;
      final bo = b.order ?? 9999;
      final byOrder = ao.compareTo(bo);
      if (byOrder != 0) return byOrder;
      return a.phaseCode.compareTo(b.phaseCode);
    });
    return list;
  }

  Future<String> add(Phase p) async {
    final ref = _col.doc();
    await ref.set({
      ...p.copyWith(id: ref.id).toMap(),
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
