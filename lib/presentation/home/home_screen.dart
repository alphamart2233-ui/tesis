import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' as dr hide Column;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:tesis/debug/smoke_tests.dart';
import '../../core/state/db_providers.dart';
import '../../core/state/filters.dart';
import '../../core/utils/format.dart';
import '../../core/utils/csv_export.dart';
import '../../core/utils/icons.dart' as ic;

import '../../data/db/app_database.dart';
import '../widgets/next_month_prediction_card.dart';
import '../widgets/category_budget_risk.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final selectedMonth = ref.watch(selectedMonthProvider); // DateTime(year, month)

    final firstDay = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final nextMonth = (selectedMonth.month == 12)
        ? DateTime(selectedMonth.year + 1, 1, 1)
        : DateTime(selectedMonth.year, selectedMonth.month + 1, 1);

    return Scaffold(
      appBar: AppBar(
        title: Text('FinTrack EC — ${_monthLabel(selectedMonth)}'),
        actions: [
          // Exportar CSV (mes actual)
          IconButton(
            tooltip: 'Exportar CSV (mes)',
            icon: const Icon(Icons.download),
            onPressed: () async {
              final txs = await (db.select(db.transactions)
                ..where((t) => t.date.isBiggerOrEqualValue(firstDay))
                ..where((t) => t.date.isSmallerThanValue(nextMonth)))
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

              final file = await exportTransactionsToCsv(rows);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Exportado: ${file.path}')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) context.go('/login');
            },
          ),

          // Cambiar mes
          IconButton(
            tooltip: 'Cambiar mes',
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final picked = await showDialog<DateTime>(
                context: context,
                builder: (_) => _MonthPickerDialog(initial: selectedMonth),
              );
              if (picked != null && mounted) {
                ref.read(selectedMonthProvider.notifier).state =
                    DateTime(picked.year, picked.month);
              }
            },
          ),

          // Menú overflow: Corrección de signos de gastos (debug)
          PopupMenuButton<String>(
            onSelected: (key) async {
              if (key == 'fix_signs') {
                final fixed = await db.normalizeExpenseSignsOnce();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Corregidas $fixed transacciones de gasto en positivo')),
                );
                setState(() {}); // refresca lista
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'fix_signs',
                child: Text('Corregir signos (debug)'),
              ),
            ],
          ),
        ],
      ),

      // FAB: Agregar transacción
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agregar transacción',
        onPressed: () => context.pushNamed('add_transaction'),
        child: const Icon(Icons.add),
      ),

      // Contenido
      body: FutureBuilder(
        future: Future.wait<List<Object?>>([
          (db.select(db.transactions)
            ..where((t) => t.date.isBiggerOrEqualValue(firstDay))
            ..where((t) => t.date.isSmallerThanValue(nextMonth))
            ..orderBy([(t) => dr.OrderingTerm.desc(t.date)]))
              .get(),
          db.select(db.categories).get(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final txs = snapshot.data![0] as List<Transaction>;
          final cats = snapshot.data![1] as List<Category>;
          final catById = {for (final c in cats) c.id: c};

          // Totales del mes
          final double incomes = txs
              .where((t) => t.amount >= 0)
              .fold<double>(0.0, (a, b) => a + b.amount);
          final double expenses = txs
              .where((t) => t.amount < 0)
              .fold<double>(0.0, (a, b) => a + (-b.amount));
          final double balance = incomes - expenses;

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                // Resumen mensual
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _stat('Ingresos', Fx.money(incomes), Icons.trending_up),
                        const SizedBox(width: 16),
                        _stat('Gastos', Fx.money(expenses), Icons.trending_down),
                        const Spacer(),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Balance', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(
                              Fx.money(balance),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: balance >= 0 ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Predicción del próximo mes (baseline)
                const NextMonthPredictionCard(),

                const SizedBox(height: 8),

                // Riesgo de presupuesto por categoría (próximo mes)
                const CategoryBudgetRisk(),

                const SizedBox(height: 8),

                // Lista de transacciones del mes
                Card(
                  elevation: 2,
                  child: Column(
                    children: [
                      const ListTile(
                        title: Text('Transacciones del mes'),
                      ),
                      const Divider(height: 0),
                      if (txs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('Sin transacciones en este mes')),
                        )
                      else
                        ...txs.map((t) {
                          final cat = catById[t.categoryId];
                          final isExpense = t.amount < 0;
                          final iconData = ic.categoryIcon(
                            cat?.name ?? '',
                            cat?.type ?? (isExpense ? 'expense' : 'income'),
                          );
                          return Column(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  child: Icon(iconData),
                                ),
                                title: Text(cat?.name ?? '—'),
                                subtitle: Text(Fx.date(t.date)),
                                trailing: Text(
                                  Fx.money(isExpense ? -t.amount : t.amount),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isExpense ? Colors.red : Colors.green,
                                  ),
                                ),
                              ),
                              const Divider(height: 0),
                            ],
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }

  String _monthLabel(DateTime d) {
    // Muestra "YYYY-MM"
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  }
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, DateTime(_year, _month)),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
