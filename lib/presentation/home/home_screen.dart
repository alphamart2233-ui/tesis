// lib/presentation/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../core/state/filters.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart' as ic;

import '../../data/sync/sync_service.dart';
import '../../core/state/sync_autorun.dart';
import '../../core/state/last_sync_provider.dart';

import '../../data/repositories/transaction_repository.dart';
import '../../data/db/app_database.dart';

import '../widgets/last_sync_chip.dart';
import '../widgets/next_month_prediction_card.dart';
import '../widgets/category_budget_risk.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(autoSyncProvider);
    final selectedMonth = ref.watch(selectedMonthProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('FinTrack EC — ${_monthLabel(selectedMonth)}'),
        actions: [
          IconButton(
            tooltip: 'Cambiar mes',
            icon: const Icon(Icons.calendar_month),
            onPressed: () => _showMonthPicker(context, ref, selectedMonth),
          ),
          _buildOverflowMenu(context, ref),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        tooltip: 'Agregar transacción',
        onPressed: () => context.pushNamed('add_transaction'),
        child: const Icon(Icons.add),
      ),

      body: RefreshIndicator(
        onRefresh: () => _syncData(context, ref),
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
            _MonthlySummaryCard(),
            const SizedBox(height: 8),
            const NextMonthPredictionCard(),
            const SizedBox(height: 8),
            const CategoryBudgetRisk(),
            const SizedBox(height: 8),
            _TransactionListCard(),
          ],
        ),
      ),
    );
  }

  Future<void> _syncData(BuildContext context, WidgetRef ref) async {
    await ref.read(syncServiceProvider).syncOnce();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sincronizado ✔️')),
      );
    }
  }

  Future<void> _showMonthPicker(BuildContext context, WidgetRef ref, DateTime selectedMonth) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthPickerDialog(initial: selectedMonth),
    );
    if (picked != null && context.mounted) {
      ref.read(selectedMonthProvider.notifier).state = DateTime(picked.year, picked.month);
    }
  }

  PopupMenuButton<String> _buildOverflowMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (key) async {
        if (key == 'sync_now') {
          await _syncData(context, ref);
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

  String _monthLabel(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
}

class _MonthlySummaryCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(monthlySummaryProvider);

    return Card.filled(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: summaryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (summary) {
            final balance = summary.balance;
            return Column(
              children: [
                Text(
                  Fx.money(balance),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: balance >= 0 ? Colors.green.shade600 : Colors.red.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Balance del mes', style: Theme.of(context).textTheme.bodySmall),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Ingresos', Fx.money(summary.income), Icons.trending_up, Colors.green),
                    _stat('Gastos', Fx.money(summary.expense), Icons.trending_down, Colors.red),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
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
}

class _TransactionListCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txsAsync = ref.watch(latestByMonthProvider);

    return Card.outlined(
      elevation: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: txsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (txs) {
            return Column(
              children: [
                ListTile(
                  title: Text(
                    'Transacciones del mes',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  trailing: Text('${txs.length} mov.'),
                ),
                const Divider(height: 0, thickness: 0.5),
                if (txs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Sin transacciones en este mes')),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: txs.length,
                    separatorBuilder: (_, __) =>
                    const Divider(height: 0, thickness: 0.5, indent: 16, endIndent: 16),
                    itemBuilder: (context, index) {
                      final (t, cat) = txs[index];
                      final isExpense = t.amount < 0;
                      final iconData = ic.categoryIcon(cat.name, cat.type);
                      return ListTile(
                        leading: CircleAvatar(child: Icon(iconData, size: 20)),
                        title: Text(cat.name),
                        subtitle: Text(Fx.date(t.date)),
                        trailing: Text(
                          Fx.money(isExpense ? -t.amount : t.amount),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isExpense ? Colors.red : Colors.green,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.pop(context, DateTime(_year, _month)), child: const Text('Aceptar')),
      ],
    );
  }
}
