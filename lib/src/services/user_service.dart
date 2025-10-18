import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<void> ensureUserDoc(User user) async {
    final docRef = _db.collection('users').doc(user.uid);

    try {
      await docRef.set({
        'uid': user.uid,
        'email': user.email,
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      // ignore: avoid_print
      print('ensureUserDoc set failed: $e');
    }
  }
}
