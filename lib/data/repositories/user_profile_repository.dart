import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/providers/firebase_providers.dart';
import '../models/user_profile.dart';


final userProfileRepositoryProvider = Provider((ref) {
  final fs = ref.watch(firestoreProvider);
  return UserProfileRepository(fs);
});

class UserProfileRepository {
  final FirebaseFirestore _fs;
  UserProfileRepository(this._fs);

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _fs.collection('users').doc(uid);

  Future<void> ensureExists({
    required String uid,
    required String email,
    String? displayName,
    String locale = 'es-EC',
    String currency = 'USD',
  }) async {
    final doc = await _doc(uid).get();
    if (!doc.exists) {
      await _doc(uid).set({
        'email': email,
        'displayName': displayName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'settings': {
          'currency': currency,
          'locale': locale,
          'predictionEnabled': true,
          'backupEnabled': true,
        },
        'lastSyncAt': null,
        'appVersion': null,
      }, SetOptions(merge: true));
    }
  }

  Stream<UserProfile?> watch(String uid) {
    return _doc(uid).snapshots().map((s) {
      if (!s.exists) return null;
      return UserProfile.fromMap(uid, s.data()!);
    });
  }

  Future<void> updateSettings(String uid, Map<String, dynamic> partial) async {
    await _doc(uid).set({
      'settings': partial,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setLastSync(String uid, int epochMs) async {
    await _doc(uid).set({'lastSyncAt': epochMs}, SetOptions(merge: true));
  }
}
