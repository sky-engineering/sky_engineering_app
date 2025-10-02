// lib/src/data/repositories/client_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/client.dart';

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

  Future<void> add(ClientRecord client) async {
    final ref = _col.doc();
    await ref.set({
      ...client.copyWith(id: ref.id).toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> update(String id, ClientRecord client) async {
    await _col.doc(id).update({
      'code': client.code,
      'name': client.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => _col.doc(id).delete();
}
