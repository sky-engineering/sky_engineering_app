// lib/src/data/repositories/client_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/client.dart';
import '../../utils/phone_utils.dart';

class ClientRepository {
  ClientRepository() : _col = FirebaseFirestore.instance.collection('clients');

  final CollectionReference<Map<String, dynamic>> _col;

  Stream<List<ClientRecord>> streamAll() {
    return _col
        .orderBy('code')
        .snapshots()
        .map(
          (snap) => snap.docs.map((doc) => ClientRecord.fromDoc(doc)).toList(),
        );
  }

  Future<void> add(ClientRecord client, {required String ownerUid}) async {
    final ref = _col.doc();
    final now = FieldValue.serverTimestamp();
    await ref.set({
      ...client.copyWith(id: ref.id, ownerUid: ownerUid).toMap(),
      'ownerUid': ownerUid,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> update(String id, ClientRecord client) async {
    String? sanitize(String? value) {
      final trimmed = value?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    }

    await _col.doc(id).update({
      'code': client.code.trim(),
      'name': client.name.trim(),
      'contactName': sanitize(client.contactName),
      'contactEmail': sanitize(client.contactEmail),
      'contactPhone': normalizePhone(client.contactPhone),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => _col.doc(id).delete();
}
