import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';

class UserRepository {
  final _col = FirebaseFirestore.instance.collection('users');

  Future<UserProfile?> getByUid(String uid) async {
    final doc = await _col.doc(uid).get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return UserProfile.fromMap(data);
  }

  Stream<UserProfile?> streamByUid(String uid) {
    return _col.doc(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      final data = snap.data();
      if (data == null) return null;
      return UserProfile.fromMap(data);
    });
  }

  /// Create a minimal user doc if it doesn't exist.
  Future<void> createIfMissing(String uid) async {
    final ref = _col.doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'uid': uid,
        'userType': 'Other',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Upsert profile with server timestamps.
  Future<void> save(UserProfile profile) async {
    final ref = _col.doc(profile.uid);
    final exists = (await ref.get()).exists;

    final data = profile.toMap()
      ..remove('createdAt') // we set these with server timestamps
      ..remove('updatedAt')
      ..addAll({
        if (!exists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

    await ref.set(data, SetOptions(merge: true));
  }
}
