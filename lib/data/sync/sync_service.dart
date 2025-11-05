// lib/data/sync/sync_service.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/providers/firebase_providers.dart';
import '../../core/state/db_providers.dart';
import '../db/app_database.dart';
import '../repositories/user_profile_repository.dart';

/// Provee una instancia del servicio de sincronización.
final syncServiceProvider = Provider<SyncService>((ref) {
  final fs = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
  // Asumimos que ya tienes un provider para la DB inyectado en tu app:
  final db = ref.watch(databaseProvider);
  final userRepo = ref.watch(userProfileRepositoryProvider);
  return SyncService(
    fs: fs,
    auth: auth,
    db: db,
    userRepo: userRepo,
    now: () => DateTime.now().millisecondsSinceEpoch,
  );
});

/// Servicio de sincronización Drift (local) ↔ Firestore (cloud).
class SyncService {
  final FirebaseFirestore fs;
  final FirebaseAuth auth;
  final AppDatabase db;
  final UserProfileRepository userRepo;
  final int Function() now;

  SyncService({
    required this.fs,
    required this.auth,
    required this.db,
    required this.userRepo,
    required this.now,
  });

  /// Ejecuta un ciclo de sync (pull → push → actualizar cursor).
  Future<void> syncOnce() async {
    final user = auth.currentUser;
    if (user == null) return;
    final uid = user.uid;

    // 1) Leer cursor de /users/{uid}.lastSyncAt; si no hay, 0.
    final profSnap = await fs.collection('users').doc(uid).get();
    final lastSyncAt = (profSnap.data()?['lastSyncAt'] as int?) ?? 0;
    final ts = now();

    // 2) PULL: bajar cambios remotos más nuevos que lastSyncAt
    await _pullCollection(
      uid: uid,
      collection: 'categories',
      lastSyncAt: lastSyncAt,
      applyRemote: _applyRemoteCategory,
    );
    await _pullCollection(
      uid: uid,
      collection: 'transactions',
      lastSyncAt: lastSyncAt,
      applyRemote: _applyRemoteTransaction,
    );

    // 3) PUSH: subir locales pendientes (isDirty == true)
    await _pushDirtyCategories(uid);
    await _pushDirtyTransactions(uid);

    // 4) Guardar nuevo cursor
    await userRepo.setLastSync(uid, ts);
  }

  // ------------------------- PULL -------------------------

  Future<void> _pullCollection({
    required String uid,
    required String collection,
    required int lastSyncAt,
    required Future<void> Function(String remoteId, Map<String, dynamic> data)
    applyRemote,
  }) async {
    final q = fs
        .collection('users')
        .doc(uid)
        .collection(collection)
        .where('updatedAt', isGreaterThan: lastSyncAt);

    final snaps = await q.get();
    for (final d in snaps.docs) {
      await applyRemote(d.id, d.data());
    }
  }

  Future<void> _applyRemoteCategory(
      String remoteId, Map<String, dynamic> m) async {
    final remoteUpdated = (m['updatedAt'] as int?) ?? 0;
    final remoteDeleted = (m['isDeleted'] as bool?) ?? false;

    final local = await db.findCategoryByRemoteId(remoteId);

    if (local == null) {
      if (!remoteDeleted) {
        await db.insertCategoryFromRemote(remoteId, m);
      }
      return;
    }

    if (remoteUpdated > local.updatedAt) {
      if (remoteDeleted) {
        await db.markCategoryDeletedById(local.id, remoteUpdated);
      } else {
        await db.updateCategoryFromRemote(local.id, m);
      }
    }
    // Si local es más nuevo, lo subiremos en PUSH (isDirty debería estar en true).
  }

  Future<void> _applyRemoteTransaction(
      String remoteId, Map<String, dynamic> m) async {
    final remoteUpdated = (m['updatedAt'] as int?) ?? 0;
    final remoteDeleted = (m['isDeleted'] as bool?) ?? false;

    final local = await db.findTxByRemoteId(remoteId);

    if (local == null) {
      if (!remoteDeleted) {
        await db.insertTxFromRemote(remoteId, m);
      }
      return;
    }

    if (remoteUpdated > local.updatedAt) {
      if (remoteDeleted) {
        await db.markTxDeletedById(local.id, remoteUpdated);
      } else {
        await db.updateTxFromRemote(local.id, m);
      }
    }
  }

  // ------------------------- PUSH -------------------------

  Future<void> _pushDirtyCategories(String uid) async {
    final dirty = await db.findDirtyCategories();
    if (dirty.isEmpty) return;

    final batch = fs.batch();
    final col =
    fs.collection('users').doc(uid).collection('categories');

    for (final c in dirty) {
      final docRef =
      (c.remoteId != null && c.remoteId!.isNotEmpty) ? col.doc(c.remoteId!) : col.doc();

      // Si no tenía remoteId, lo enlazamos localmente ahora.
      if (c.remoteId == null || c.remoteId!.isEmpty) {
        await db.attachCategoryRemoteId(c.id, docRef.id);
      }

      batch.set(docRef, {
        'name': c.name,
        'type': c.type,
        'updatedAt': c.updatedAt,
        'isDeleted': c.isDeleted,
      }, SetOptions(merge: true));
    }

    await batch.commit();
    await db.clearDirtyCategories(dirty.map((e) => e.id).toList());
  }

  Future<void> _pushDirtyTransactions(String uid) async {
    final dirty = await db.findDirtyTx();
    if (dirty.isEmpty) return;

    final batch = fs.batch();
    final col =
    fs.collection('users').doc(uid).collection('transactions');

    for (final t in dirty) {
      final docRef =
      (t.remoteId != null && t.remoteId!.isNotEmpty) ? col.doc(t.remoteId!) : col.doc();

      // Enlaza remoteId si no tenía.
      if (t.remoteId == null || t.remoteId!.isEmpty) {
        await db.attachTxRemoteId(t.id, docRef.id);
      }

      // Obtener remoteId de la categoría local (si existe)
      final cat = await (db.select(db.categories)
        ..where((c) => c.id.equals(t.categoryId)))
          .getSingleOrNull();
      final catRemoteId = cat?.remoteId;

      batch.set(docRef, {
        'amount': t.amount,
        'date': t.date.millisecondsSinceEpoch, // DateTime → epoch ms
        'note': t.note,
        'categoryId': catRemoteId, // puede ser null si categoría aún no está en cloud
        'updatedAt': t.updatedAt,
        'isDeleted': t.isDeleted,
      }, SetOptions(merge: true));
    }

    await batch.commit();
    await db.clearDirtyTx(dirty.map((e) => e.id).toList());
  }
}
