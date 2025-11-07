import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../providers/firebase_providers.dart';

final lastSyncAtProvider = StreamProvider<int?>((ref) {
  final fs = ref.watch(firestoreProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();

  return fs.collection('users').doc(uid).snapshots().map((s) {
    final data = s.data();
    return data == null ? null : (data['lastSyncAt'] as int?);
  });
});
