//lib/data/sync/sync_service.dart
import 'package:flutter/cupertino.dart' show debugPrint;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/providers/firebase_providers.dart';
import '../../core/state/db_providers.dart';
import '../db/app_database.dart';
import '../repositories/user_profile_repository.dart';

/// Proveedor de SyncService
final syncServiceProvider = Provider<SyncService>((ref) {
  final fs = ref.watch(firestoreProvider);
  final auth = ref.watch(firebaseAuthProvider);
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

  /// Un ciclo: PULL → PUSH → actualizar cursor
  Future<void> syncOnce() async {
    final user = auth.currentUser;
    if (user == null) return;
    debugPrint('[sync] start → uid=${user.uid}');

    final uid = user.uid;
    final profSnap = await fs.collection('users').doc(uid).get();
    final lastSyncAt = (profSnap.data()?['lastSyncAt'] as int?) ?? 0;
    final ts = now();

    // PULL (tolera updateAt y diferentes formatos de tiempo)
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

    // PUSH
    await _pushDirtyCategories(uid);
    await _pushDirtyTransactions(uid);

    // Cursor
    await userRepo.setLastSync(uid, ts);
    debugPrint('[sync] done → lastSyncAt=$ts');

  }

  // ------------------------- HELPERS -------------------------

  // Normaliza a milisegundos: admite int en s/ms y Timestamp
  int _toMillis(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v < 100000000000 ? v * 1000 : v; // 10 dígitos => s → ms
    if (v is Timestamp) return v.millisecondsSinceEpoch;
    return 0;
  }

  // ------------------------- PULL ----------------------------

  Future<void> _pullCollection({
    required String uid,
    required String collection,
    required int lastSyncAt,
    required Future<void> Function(String remoteId, Map<String, dynamic> data)
    applyRemote,
  }) async {
    final base = fs.collection('users').doc(uid).collection(collection);

    // Si lastSyncAt <= 0 (FORCE PULL), no filtramos por updatedAt
    final q = (lastSyncAt > 0)
        ? base.where('updatedAt', isGreaterThan: lastSyncAt)
        : base;

    final snaps = await q.get();
    for (final d in snaps.docs) {
      await applyRemote(d.id, d.data());
    }
  }

  Future<void> _applyRemoteCategory(
      String remoteId, Map<String, dynamic> m) async {
    // Acepta updatedAt o el typo updateAt
    final remoteUpdated = _toMillis(m['updatedAt'] ?? m['updateAt']);
    final remoteDeleted = (m['isDeleted'] as bool?) ?? false;

    // Mapa normalizado que garantiza 'updatedAt' en ms
    final norm = Map<String, dynamic>.from(m);
    norm['updatedAt'] = remoteUpdated;

    final local = await db.findCategoryByRemoteId(remoteId);

    if (local == null) {
      if (!remoteDeleted) {
        await db.insertCategoryFromRemote(remoteId, norm);
      }
      return;
    }

    if (remoteUpdated > local.updatedAt) {
      if (remoteDeleted) {
        await db.markCategoryDeletedById(local.id, remoteUpdated);
      } else {
        await db.updateCategoryFromRemote(local.id, norm);
      }
    }
    // Si local es más nuevo, se subirá en PUSH (isDirty = true).
  }

  Future<void> _applyRemoteTransaction(
      String remoteId, Map<String, dynamic> m) async {
    final remoteUpdated = _toMillis(m['updatedAt']);
    final remoteDeleted = (m['isDeleted'] as bool?) ?? false;

    // Normaliza updatedAt y date a milisegundos
    final norm = Map<String, dynamic>.from(m);
    norm['updatedAt'] = remoteUpdated;
    norm['date'] = _toMillis(m['date']);

    final local = await db.findTxByRemoteId(remoteId);

    if (local == null) {
      if (!remoteDeleted) {
        await db.insertTxFromRemote(remoteId, norm);
      }
      return;
    }

    if (remoteUpdated > local.updatedAt) {
      if (remoteDeleted) {
        await db.markTxDeletedById(local.id, remoteUpdated);
      } else {
        await db.updateTxFromRemote(local.id, norm);
      }
    }
  }

  // ------------------------- PUSH ----------------------------

  Future<void> _pushDirtyCategories(String uid) async {
    final dirty = await db.findDirtyCategories();
    if (dirty.isEmpty) return;

    final batch = fs.batch();
    final col = fs.collection('users').doc(uid).collection('categories');

    for (final c in dirty) {
      final docRef = (c.remoteId != null && c.remoteId!.isNotEmpty)
          ? col.doc(c.remoteId!)
          : col.doc();

      // Enlaza remoteId local si es nuevo
      if (c.remoteId == null || c.remoteId!.isEmpty) {
        await db.attachCategoryRemoteId(c.id, docRef.id);
      }

      batch.set(
        docRef,
        {
          'name': c.name,
          'type': c.type,
          'updatedAt': c.updatedAt,
          'isDeleted': c.isDeleted,
        },
        SetOptions(merge: true), // upsert sin sobrescribir
      );
    }

    await batch.commit();
    await db.clearDirtyCategories(dirty.map((e) => e.id).toList());
  }

  Future<void> _pushDirtyTransactions(String uid) async {
    final dirty = await db.findDirtyTx();
    if (dirty.isEmpty) return;

    final batch = fs.batch();
    final col = fs.collection('users').doc(uid).collection('transactions');

    for (final t in dirty) {
      final docRef = (t.remoteId != null && t.remoteId!.isNotEmpty)
          ? col.doc(t.remoteId!)
          : col.doc();

      if (t.remoteId == null || t.remoteId!.isEmpty) {
        await db.attachTxRemoteId(t.id, docRef.id);
      }

      // Obtener remoteId de la categoría local (si existe)
      final cat = await (db.select(db.categories)
        ..where((c) => c.id.equals(t.categoryId)))
          .getSingleOrNull();
      final catRemoteId = cat?.remoteId;

      batch.set(
        docRef,
        {
          'amount': t.amount,
          'date': t.date.millisecondsSinceEpoch,
          'note': t.note,
          'categoryId': catRemoteId, // puede ser null si aún no está en cloud
          'updatedAt': t.updatedAt,
          'isDeleted': t.isDeleted,
        },
        SetOptions(merge: true), // upsert sin sobrescribir
      );
    }

    await batch.commit();
    await db.clearDirtyTx(dirty.map((e) => e.id).toList());
  }
}
