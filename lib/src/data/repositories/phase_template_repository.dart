// lib/src/data/repositories/phase_template_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/phase_template.dart';

/// Repository for managing user-defined phases (collection: `phases`).
class PhaseTemplateRepository {
  final _col = FirebaseFirestore.instance.collection('phases');

  /// Fetch all phases for a user, ordered by sortOrder then phaseCode.
  Future<List<PhaseTemplate>> getAllForUser(String ownerUid) async {
    final baseQuery = _col.where('ownerUid', isEqualTo: ownerUid);
    QuerySnapshot<Map<String, dynamic>> qs;
    try {
      qs = await baseQuery.orderBy('sortOrder').get();
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        qs = await baseQuery.get();
      } else {
        rethrow;
      }
    }

    final list = qs.docs.map(PhaseTemplate.fromDoc).toList();

    // Stable sort ensures predictable order even when Firestore fallback is used.
    list.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      if (c != 0) return c;
      return a.phaseCode.compareTo(b.phaseCode);
    });
    return list;
  }

  /// Create and return new document id.
  Future<String> add(PhaseTemplate p) async {
    final ref = _col.doc();
    await ref.set({
      ...p.copyWith(id: ref.id).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Partial update by id.
  Future<void> update(String id, Map<String, dynamic> partial) async {
    await _col.doc(id).update({
      ...partial,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete by id.
  Future<void> delete(String id) => _col.doc(id).delete();
}
