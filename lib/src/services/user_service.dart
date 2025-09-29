import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> ensureUserDoc(User user) async {
    final docRef = _db.collection('users').doc(user.uid);
    final snap = await docRef.get();
    if (!snap.exists) {
      await docRef.set({
        'uid': user.uid,
        'email': user.email,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await docRef.set({
        'email': user.email,
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
