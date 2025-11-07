import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:drift/drift.dart' show Value;

import '../../core/state/filters.dart';
import '../../core/state/last_sync_provider.dart';
import '../../core/state/sync_autorun.dart';
import '../../core/state/db_providers.dart';
import '../../data/db/app_database.dart';
import '../../data/sync/sync_service.dart';
import '../../core/utils/format.dart';

// Widgets
import '../widgets/last_sync_chip.dart';
import '../widgets/next_month_prediction_card.dart';
import '../widgets/monthly_expense_chart.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mantén el autosync activo también aquí
    ref.watch(autoSyncProvider);

    final selectedMonth = ref.watch(selectedMonthProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Análisis'),
        actions: [
          IconButton(
            tooltip: 'Cambiar mes',
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _showMonthPicker(context, ref, selectedMonth),
          ),
          _buildOverflowMenu(context, ref),
        ],
      ),

      // ⛔️ No incluir bottomNavigationBar aquí. Ya lo provee ShellRoute

      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(syncServiceProvider).syncOnce();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ref.watch(lastSyncAtProvider).when(
                data: (lastSync) {
                  final time = (lastSync == null || lastSync <= 0)
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(lastSync);
                  return LastSyncChip(time: time);
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 8),
            const NextMonthPredictionCard(),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 8, right: 8, top: 12, bottom: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gasto mensual (últimos 6)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    const MonthlyExpenseChart(),
                    const SizedBox(height: 4),
                    Text(
                      'Mes base: ${_monthLabel(selectedMonth)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // 👇 Botón para insertar dummy tx
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _insertDummyTransaction(ref),
        icon: const Icon(Icons.bug_report),
        label: const Text('Dummy TX'),
      ),
    );
  }

  /// 🔁 Inserta una transacción dummy
  Future<void> _insertDummyTransaction(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final cat = await (db.select(db.categories)..limit(1)).getSingleOrNull();

    if (cat == null) {
      debugPrint('[DummyTx] ❌ No hay categorías disponibles');
      return;
    }

    final tx = TransactionsCompanion(
      categoryId: Value(cat.id),
      amount: Value(10.0),
      date: Value(DateTime.now()),
      // Si la columna “description” no existe, omítela:
      // description: Value('Dummy Transaction'),
    );


    await db.into(db.transactions).insert(tx);
    debugPrint('[DummyTx] ✅ Transacción insertada');
  }

  PopupMenuButton<String> _buildOverflowMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (key) async {
        if (key == 'sync_now') {
          await ref.read(syncServiceProvider).syncOnce();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sincronizado ✔️')),
            );
          }
        } else if (key == 'debug') {
          context.pushNamed('debug');
        } else if (key == 'logout') {
          await FirebaseAuth.instance.signOut();
          if (context.mounted) context.go('/login');
        }
      },
      itemBuilder: (ctx) => <PopupMenuEntry<String>>[
        const PopupMenuItem(value: 'sync_now', child: Text('Sincronizar ahora')),
        if (kDebugMode) const PopupMenuItem(value: 'debug', child: Text('Debug Tools')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: Text('Cerrar sesión')),
      ],
    );
  }

  Future<void> _showMonthPicker(
      BuildContext context, WidgetRef ref, DateTime selectedMonth) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthPickerDialog(initial: selectedMonth),
    );
    if (picked != null && context.mounted) {
      ref.read(selectedMonthProvider.notifier).state =
          DateTime(picked.year, picked.month);
    }
  }

  String _monthLabel(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

class _MonthPickerDialog extends StatefulWidget {
  final DateTime initial;
  const _MonthPickerDialog({required this.initial});

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year;
    _month = widget.initial.month;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Seleccionar mes'),
      content: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                if (_month == 1) {
                  _month = 12;
                  _year--;
                } else {
                  _month--;
                }
              });
            },
          ),
          Expanded(
            child: Center(
              child: Text(
                '$_year-${_month.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                if (_month == 12) {
                  _month = 1;
                  _year++;
                } else {
                  _month++;
                }
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.pop(context, DateTime(_year, _month)), child: const Text('Aceptar')),
      ],
    );
  }
}
