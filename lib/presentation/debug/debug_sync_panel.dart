// lib/presentation/debug/debug_sync_panel.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as dr;

import '../../core/state/db_providers.dart';
import '../../core/state/filters.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/format.dart';
import '../../data/db/app_database.dart';
import '../../data/sync/sync_service.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/providers/firebase_providers.dart';

class DebugSyncPanel extends ConsumerWidget {
  const DebugSyncPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final selected = ref.watch(selectedMonthProvider);
    final y = selected.year;
    final m = selected.month;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          // ================== SYNC ==================
          FilledButton.icon(
            icon: const Icon(Icons.cloud_upload),
            label: const Text('PUSH (local → Firestore)'),
            onPressed: () async {
              // Fallback a bidireccional mientras no existan métodos unidireccionales
              final sync = ref.read(syncServiceProvider);
              await sync.syncOnce();
              _snack(context, 'Sync ejecutado (fallback a PUSH)');
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.cloud_download),
            label: const Text('FORCE PULL (Firestore → local)'),
            onPressed: () async {
              final sync = ref.read(syncServiceProvider);
              await sync.syncOnce();
              _snack(context, 'Sync ejecutado (fallback a PULL)');
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.sync),
            label: const Text('SYNC NOW'),
            onPressed: () async {
              final sync = ref.read(syncServiceProvider);
              await sync.syncOnce();
              _snack(context, 'Sincronizado ✔️');
            },
          ),

          // ============= SEEDS / DEMO DATA ============
          ElevatedButton(
            child: const Text('Sembrar 6 meses (demo) para el mes seleccionado'),
            onPressed: () async {
              await _seed6MonthsForSelected(db, y, m);
              _snack(context, 'Histórico DEMO (6 meses) sembrado ✔️');
            },
          ),
          ElevatedButton(
            child: const Text('Sembrar gastos del mes seleccionado (demo)'),
            onPressed: () async {
              await _seedSelectedMonthExpenses(db, y, m);
              _snack(context, 'Gastos DEMO añadidos al mes seleccionado ✔️');
            },
          ),
          ElevatedButton(
            child: const Text('Borrar datos DEMO (note="DEMO")'),
            onPressed: () async {
              final n = await (db.delete(db.transactions)
                ..where((t) => t.note.equals('DEMO')))
                  .go();
              _snack(context, 'Eliminadas $n transacciones DEMO');
            },
          ),

          // ========== CSV + FIX SIGNS (solo debug) ==========
          ElevatedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Exportar CSV (mes actual)'),
            onPressed: () async {
              final file = await _exportCsvForMonth(db, DateTime(y, m, 1));
              _snack(context, 'Exportado: ${file.path}');
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.rule_folder),
            label: const Text('Corregir signos (gastos en negativo)'),
            onPressed: () async {
              final fixed = await db.normalizeExpenseSignsOnce();
              _snack(context, 'Corregidas $fixed transacciones');
            },
          ),

          // ========== CATEGORIES + BUDGETS ==========
          OutlinedButton(
            child: const Text('Crear categoría'),
            onPressed: () => _showAddCategoryDialog(context, ref),
          ),
          OutlinedButton(
            child: const Text('Agregar/editar presupuesto (mes seleccionado)'),
            onPressed: () => _showAddBudgetDialog(context, ref),
          ),
          ElevatedButton(
            child: const Text('Crear presupuestos demo (Comida 300, Transp 200, Salud 100)'),
            onPressed: () async {
              await _createDemoBudgets(db, y, m);
              _snack(
                context,
                'Presupuestos demo creados para $y-${m.toString().padLeft(2, '0')}',
              );
            },
          ),
          ElevatedButton(
            child: const Text('Borrar presupuestos del mes seleccionado'),
            onPressed: () async {
              final deleted = await (db.delete(db.budgets)
                ..where((b) => b.year.equals(y) & b.month.equals(m)))
                  .go();
              _snack(context,
                  'Eliminados $deleted presupuestos de $y-${m.toString().padLeft(2, '0')}');
            },
          ),

          // ========== DATA REPAIR ==========
          ElevatedButton(
            child: const Text('Reparar categorías huérfanas → "Otros"'),
            onPressed: () async {
              final fix = await _repairOrphansToOthers(db);
              _snack(context, 'Reasignadas $fix transacciones a "Otros"');
            },
          ),

          // ========== WIPES ==========
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50),
            child: const Text('Borrar TODO (solo local)', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              final ok = await _confirm(context, '¿Borrar TODO local?',
                  'Se eliminarán transacciones, presupuestos y categorías en la base local.');
              if (ok != true) return;
              await db.transaction(() async {
                await db.delete(db.transactions).go();
                await db.delete(db.budgets).go();
                await db.delete(db.categories).go();
              });
              await db.seed(); // opcional
              _snack(context, 'Base local vaciada ✔️');
            },
          ),

          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade100),
            child:
            const Text('Borrar TODO (local + Firestore)', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              final ok = await _confirm(context, '¿Borrar TODO en local + Firestore?',
                  'Esto eliminará TODOS tus datos de prueba en la nube y en la base local. Acción irreversible.');
              if (ok != true) return;

              final fs = ref.read(firestoreProvider);
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) {
                _snack(context, 'No hay usuario autenticado');
                return;
              }

              // Local
              await db.transaction(() async {
                await db.delete(db.transactions).go();
                await db.delete(db.budgets).go();
                await db.delete(db.categories).go();
              });

              // Cloud (batch paginado)
              Future<int> _deleteCollection(CollectionReference col, {int batchSize = 200}) async {
                int total = 0;
                while (true) {
                  final snap = await col.limit(batchSize).get();
                  if (snap.docs.isEmpty) break;
                  final batch = fs.batch();
                  for (final d in snap.docs) {
                    batch.delete(d.reference);
                  }
                  await batch.commit();
                  total += snap.docs.length;
                }
                return total;
              }

              final catCol = fs.collection('users').doc(uid).collection('categories');
              final txCol = fs.collection('users').doc(uid).collection('transactions');
              final deletedCats = await _deleteCollection(catCol);
              final deletedTxs = await _deleteCollection(txCol);

              await fs.collection('users').doc(uid).set({'lastSyncAt': 0}, SetOptions(merge: true));

              await db.seed(); // opcional
              _snack(context,
                  'Borrado total ✔️ (cloud: $deletedCats categorías, $deletedTxs transacciones)');
            },
          ),

          // ========== RECALC ==========
          OutlinedButton(
            child: const Text('Recalcular predicción'),
            onPressed: () async {
              await ref.read(syncServiceProvider).syncOnce();
              _snack(context, 'Recalculo listo ✔️ (refresca Home)');
            },
          ),

          const Divider(),
          _InfoSelectedMonth(y: y, m: m),
        ],
      ),
    );
  }

  // -------- Helpers UI ----------
  void _snack(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool?> _confirm(BuildContext ctx, String title, String body) {
    return showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
  }
}

// ====== Dialogs ======
Future<void> _showAddCategoryDialog(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final nameCtrl = TextEditingController();
  String type = 'expense';

  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Nueva categoría'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: type,
            items: const [
              DropdownMenuItem(value: 'expense', child: Text('Gasto')),
              DropdownMenuItem(value: 'income', child: Text('Ingreso')),
            ],
            onChanged: (v) => type = v ?? 'expense',
            decoration: const InputDecoration(labelText: 'Tipo'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            await db.insertCategory(CategoriesCompanion.insert(name: name, type: type));
            if (context.mounted) Navigator.pop(context);
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('Categoría "$name" creada')));
            }
          },
          child: const Text('Crear'),
        ),
      ],
    ),
  );
}

Future<void> _showAddBudgetDialog(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final selected = ref.read(selectedMonthProvider);
  final y = selected.year;
  final m = selected.month;

  final cats =
  await (db.select(db.categories)..where((c) => c.type.equals('expense'))).get();
  if (cats.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Crea primero una categoría de gasto')));
    }
    return;
  }

  int catId = cats.first.id;
  final amountCtrl = TextEditingController();

  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Presupuesto $y-${m.toString().padLeft(2, '0')}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            value: catId,
            items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => catId = v ?? cats.first.id,
            decoration: const InputDecoration(labelText: 'Categoría (gasto)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Monto límite (ej. 300.00)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            final txt = amountCtrl.text.replaceAll(',', '.').trim();
            final limit = double.tryParse(txt);
            if (limit == null || limit < 0) return;
            await db.upsertBudget(categoryId: catId, year: y, month: m, limit: limit);
            if (context.mounted) Navigator.pop(context);
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Presupuesto guardado')));
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

// ====== Seed helpers ======
Future<void> _seed6MonthsForSelected(AppDatabase db, int ySel, int mSel) async {
  final comidaId = await _ensureExpenseCat(db, 'Comida');
  final transporteId = await _ensureExpenseCat(db, 'Transporte');
  final saludId = await _ensureExpenseCat(db, 'Salud');

  await (db.delete(db.transactions)..where((t) => t.note.equals('DEMO'))).go();

  for (int i = 6; i >= 1; i--) {
    final month = DateTime(ySel, mSel - i, 15);
    final comida = 220 + (i % 3) * 30;
    final transp = 120 + (i % 2) * 20;
    final salud = 80 + (i % 4) * 15;

    await db.insertTransaction(TransactionsCompanion.insert(
      amount: -comida * 0.55,
      date: month.subtract(const Duration(days: 8)),
      categoryId: comidaId,
      note: const dr.Value('DEMO'),
    ));
    await db.insertTransaction(TransactionsCompanion.insert(
      amount: -comida * 0.45,
      date: month.subtract(const Duration(days: 2)),
      categoryId: comidaId,
      note: const dr.Value('DEMO'),
    ));

    await db.insertTransaction(TransactionsCompanion.insert(
      amount: -transp * 0.6,
      date: month.add(const Duration(days: 3)),
      categoryId: transporteId,
      note: const dr.Value('DEMO'),
    ));
    await db.insertTransaction(TransactionsCompanion.insert(
      amount: -transp * 0.4,
      date: month.add(const Duration(days: 11)),
      categoryId: transporteId,
      note: const dr.Value('DEMO'),
    ));

    await db.insertTransaction(TransactionsCompanion.insert(
      amount: -salud * 0.7,
      date: month.add(const Duration(days: 6)),
      categoryId: saludId,
      note: const dr.Value('DEMO'),
    ));
    await db.insertTransaction(TransactionsCompanion.insert(
      amount: -salud * 0.3,
      date: month.add(const Duration(days: 19)),
      categoryId: saludId,
      note: const dr.Value('DEMO'),
    ));
  }
}

Future<void> _seedSelectedMonthExpenses(AppDatabase db, int y, int m) async {
  final comidaId = await _ensureExpenseCat(db, 'Comida');
  final transporteId = await _ensureExpenseCat(db, 'Transporte');
  final saludId = await _ensureExpenseCat(db, 'Salud');

  DateTime d(int day) => DateTime(y, m, day.clamp(1, 28));

  await db.insertTransaction(TransactionsCompanion.insert(
    amount: -120,
    date: d(3),
    categoryId: comidaId,
    note: const dr.Value('DEMO'),
  ));
  await db.insertTransaction(TransactionsCompanion.insert(
    amount: -80,
    date: d(10),
    categoryId: transporteId,
    note: const dr.Value('DEMO'),
  ));
  await db.insertTransaction(TransactionsCompanion.insert(
    amount: -60,
    date: d(17),
    categoryId: saludId,
    note: const dr.Value('DEMO'),
  ));
  await db.insertTransaction(TransactionsCompanion.insert(
    amount: -95,
    date: d(24),
    categoryId: comidaId,
    note: const dr.Value('DEMO'),
  ));
}

Future<int> _ensureExpenseCat(AppDatabase db, String name) async {
  final c = await (db.select(db.categories)
    ..where((t) => t.name.equals(name) & t.type.equals('expense')))
      .getSingleOrNull();
  if (c != null) return c.id;
  return await db.insertCategory(CategoriesCompanion.insert(name: name, type: 'expense'));
}

Future<void> _createDemoBudgets(AppDatabase db, int y, int m) async {
  final comidaId = await _ensureExpenseCat(db, 'Comida');
  final transporteId = await _ensureExpenseCat(db, 'Transporte');
  final saludId = await _ensureExpenseCat(db, 'Salud');

  await db.upsertBudget(categoryId: comidaId, year: y, month: m, limit: 300);
  await db.upsertBudget(categoryId: transporteId, year: y, month: m, limit: 200);
  await db.upsertBudget(categoryId: saludId, year: y, month: m, limit: 100);
}

Future<int> _repairOrphansToOthers(AppDatabase db) async {
  // Asegurar "Otros" (expense)
  final otros = await (db.select(db.categories)
    ..where((c) => c.name.equals('Otros') & c.type.equals('expense')))
      .getSingleOrNull();
  final otrosId =
      otros?.id ?? await db.insertCategory(CategoriesCompanion.insert(name: 'Otros', type: 'expense'));

  // IDs válidos
  final cats = await db.select(db.categories).get();
  final validIds = {for (final c in cats) c.id};

  // Reasignar
  final allTx = await db.select(db.transactions).get();
  int fix = 0;
  for (final t in allTx) {
    if (!validIds.contains(t.categoryId)) {
      await (db.update(db.transactions)..where((row) => row.id.equals(t.id)))
          .write(TransactionsCompanion(categoryId: dr.Value(otrosId)));
      fix++;
    }
  }
  return fix;
}

// ====== CSV helper ======
Future<File> _exportCsvForMonth(AppDatabase db, DateTime month) async {
  final first = DateTime(month.year, month.month, 1);
  final next = DateTime(month.year, month.month + 1, 1);

  final txs = await (db.select(db.transactions)
    ..where((t) => t.date.isBiggerOrEqualValue(first))
    ..where((t) => t.date.isSmallerThanValue(next)))
      .get();

  final cats = await db.select(db.categories).get();
  final catById = {for (final c in cats) c.id: c};

  final rows = txs.map((t) {
    final cat = catById[t.categoryId];
    return {
      'date': t.date,
      'category': cat?.name ?? '—',
      'amount': t.amount,
      'note': t.note ?? '',
    };
  }).toList();

  return exportTransactionsToCsv(rows);
}

// ====== Visual small info ======
class _InfoSelectedMonth extends StatelessWidget {
  const _InfoSelectedMonth({required this.y, required this.m});
  final int y;
  final int m;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 16),
        const SizedBox(width: 6),
        Text(
          'Mes seleccionado: $y-${m.toString().padLeft(2, '0')}',
          style: const TextStyle(color: Colors.black54),
        ),
      ],
    );
  }
}
