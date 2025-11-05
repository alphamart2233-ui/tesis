
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> testFirestoreWrite() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw Exception('No hay usuario autenticado');
  await FirebaseFirestore.instance
      .collection('users').doc(uid)
      .collection('debug').doc('hello')
      .set({
    'message': 'Hola Firestore',
    'ts': DateTime.now().toIso8601String(),
  });
  // Si no lanza excepción: todo OK
}
