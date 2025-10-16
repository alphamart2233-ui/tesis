import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../widgets/monthly_expense_chart.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../core/utils/format.dart';
import '../../core/utils/csv_export.dart';
import '../../core/state/filters.dart';
import '../../core/utils/icons.dart'; // opcional si creaste categoryIcon()
import '../../main.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Streams/base
    final latestAll = ref.watch(
      latestTransactionsProvider,
    ); // ← stream base (no filtrado)
    final estimatesAsync = ref.watch(nextMonthExpenseEstimatesProvider);
    final alertsAsync = ref.watch(budgetAlertsProvider);
    final monthly = ref.watch(monthlySummaryProvider);
    final selMonth = ref.watch(selectedMonthProvider);

    // DB para exportar CSV
    final db = ref.read(databaseProvider);

    final ymLabel =
        '${selMonth.year}-${selMonth.month.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Finanzas Predict — $ymLabel'),
        actions: [
          // Selector de mes (bottom sheet estable)
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Elegir mes',
            onPressed: () async {
              final current = ref.read(selectedMonthProvider);
              final picked = await _pickMonth(context, current);
              if (picked != null) {
                ref.read(selectedMonthProvider.notifier).state = DateTime(
                  picked.year,
                  picked.month,
                  1,
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.category),
            tooltip: 'Categorías',
            onPressed: () => context.push('/categories'),
          ),
          IconButton(
            icon: const Icon(Icons.wallet),
            tooltip: 'Presupuestos',
            onPressed: () => context.push('/budgets'),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exportar CSV',
            onPressed: () async {
              try {
                final path = await exportAllTransactionsToCsv(db);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('CSV exportado en:\n$path')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al exportar: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/add'),
        child: const Icon(Icons.add),
      ),
      body: latestAll.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) {
          // Filtrado síncrono por el mes seleccionado (no re-suscribe el stream)
          final filtered = rows
              .where(
                (e) =>
                    e.$1.date.year == selMonth.year &&
                    e.$1.date.month == selMonth.month,
              )
              .toList();

          return ListView(
            children: [
              const SizedBox(height: 8),

              // ====== Resumen mensual (ingresos, gastos, balance)
              monthly.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('No se pudo calcular el resumen: $e'),
                ),
                data: (m) {
                  final ym = '${m.year}-${m.month.toString().padLeft(2, '0')}';
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 4.0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            title: 'Ingresos $ym',
                            value: Fx.money(m.income),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            title: 'Gastos $ym',
                            value: Fx.money(m.expense),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            title: 'Balance $ym',
                            value: Fx.money(m.balance),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),

              // ====== Gráfico mensual (gastos últimos 6 meses, sincronizado con el mes seleccionado)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Gasto mensual (últimos 6 meses)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const MonthlyExpenseChart(),

              // ====== Predicción próximo mes
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'Gasto estimado próximo mes (por categoría)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              estimatesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('No se pudo calcular estimaciones: $e'),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Aún no hay suficientes datos para estimar.'),
                    );
                  }
                  final top = items.length > 3 ? items.sublist(0, 3) : items;
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 4.0,
                    ),
                    child: Column(
                      children: [
                        for (final it in top)
                          ListTile(
                            leading: const Icon(Icons.trending_up, size: 20),
                            title: Text(it.$1),
                            trailing: Text(Fx.money(it.$2)),
                          ),
                        if (items.length > 3)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8.0),
                            child: Text('… (hay más categorías)'),
                          ),
                      ],
                    ),
                  );
                },
              ),

              // ====== Alertas presupuesto (próximo mes)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'Alertas de presupuesto (próximo mes)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              alertsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: LinearProgressIndicator(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('No se pudieron calcular alertas: $e'),
                ),
                data: (alerts) {
                  if (alerts.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 4.0,
                      ),
                      child: Text(
                        'Sin alertas: define presupuestos del próximo mes o ajusta los existentes.',
                      ),
                    );
                  }
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 4.0,
                    ),
                    child: Column(
                      children: [
                        for (final a in alerts)
                          ListTile(
                            leading: const Icon(
                              Icons.warning_amber,
                              color: Colors.red,
                              size: 20,
                            ),
                            title: Text(a.categoryName),
                            subtitle: Text('Presupuesto: ${Fx.money(a.limit)}'),
                            trailing: Text(
                              '+${Fx.money(a.overBy)}',
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),

              const Divider(height: 0),

              // ====== Últimos movimientos (filtrados por mes en la UI)
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Sin movimientos este mes.'),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Text('Últimos movimientos'),
                ),
                ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (context, i) {
                    final (tx, cat) = filtered[i];
                    final isExpense = cat.type == 'expense';
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: isExpense
                            ? Colors.red.withOpacity(0.12)
                            : Colors.green.withOpacity(0.12),
                        child: Icon(
                          categoryIcon(cat.name, cat.type),
                          size: 18,
                          color: isExpense ? Colors.red : Colors.green,
                        ),
                      ),
                      title: Text(cat.name),
                      subtitle: Text(Fx.ymd(tx.date)),
                      trailing: Text(
                        (isExpense ? '-' : '+') + Fx.money(tx.amount),
                        style: TextStyle(
                          color: isExpense ? Colors.red : Colors.green,
                        ),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selector de mes estable (bottom sheet + StatefulBuilder)
Future<DateTime?> _pickMonth(BuildContext context, DateTime initial) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: false,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      int year = initial.year;
      int month = initial.month;

      return StatefulBuilder(
        builder: (context, setState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header año
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() => year--),
                      ),
                      Text(
                        '$year',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(() => year++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Grid de meses
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 12,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 2.6,
                        ),
                    itemBuilder: (_, i) {
                      final m = i + 1;
                      final isSel = m == month;
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSel
                              ? Colors.indigo
                              : Colors.grey[300],
                          foregroundColor: isSel
                              ? Colors.white
                              : Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          Navigator.pop(context, DateTime(year, m, 1));
                        },
                        child: Text(m.toString().padLeft(2, '0')),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
