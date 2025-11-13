// lib/presentation/home/home_screen.dart
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../core/state/db_providers.dart';
import '../../core/state/filters.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart' as ic;

import '../../data/sync/sync_service.dart';
import '../../core/state/sync_autorun.dart';
import '../../core/state/last_sync_provider.dart';

import '../../data/db/app_database.dart';
import '../../core/state/analytics_providers.dart';
import '../widgets/category_month_filter_card.dart';
import '../../core/state/filters.dart';

import '../widgets/last_sync_chip.dart';
import '../widgets/next_month_prediction_card.dart';
import '../widgets/category_budget_risk.dart' show CategoryBudgetRisk;


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
      floatingActionButton: const _ExpandableFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

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
            const _MonthlySummaryCard(),
            const SizedBox(height: 8),
            const NextMonthPredictionCard(),
            const SizedBox(height: 8),
            const CategoryBudgetRisk(),
            const SizedBox(height: 8),
            const CategoryMonthFilterCard(),
            const SizedBox(height: 8),
            const _TransactionListCard(),
          ],
        ),
      ),
    );
  }

  Future<void> _syncData(BuildContext context, WidgetRef ref) async {
    await ref.read(syncServiceProvider).syncOnce();

    // 🔁 Invalida providers para forzar recálculo tras sincronizar
    ref.invalidate(monthlySummaryProvider);
    ref.invalidate(monthlyExpenseSeriesProvider);
    ref.invalidate(budgetAlertsProvider);
    ref.invalidate(latestByMonthProvider);
    ref.invalidate(nextMonthForecastProvider);             // ← predicción global
    ref.invalidate(nextMonthExpenseEstimatesProvider);     // ← detalle por categoría

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sincronizado ✔️')),
      );
    }
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


      ref.read(selectedCategoryFilterProvider.notifier).state = null;

      // 🔁 Fuerza recálculo de pronósticos si quieres
      ref.invalidate(nextMonthForecastProvider);
      ref.invalidate(nextMonthExpenseEstimatesProvider);
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
  const _MonthlySummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    const expenseColor = Color(0xFFAB2D25); // 🎨 rojo FinTrack EC
    final summaryAsync = ref.watch(monthlySummaryProvider);

    return Card.filled(
      elevation: 1,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: summaryAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (summary) {
            final balance = summary.balance;
            final isPositive = balance >= 0;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  Fx.money(balance),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: isPositive ? scheme.primary : expenseColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Balance del mes',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const Divider(height: 28, thickness: 0.6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat(
                      context,
                      label: 'Ingresos',
                      value: Fx.money(summary.income),
                      icon: Icons.trending_up_rounded,
                      color: scheme.primary,
                    ),
                    _stat(
                      context,
                      label: 'Gastos',
                      value: Fx.money(summary.expense),
                      icon: Icons.trending_down_rounded,
                      color: expenseColor,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stat(
      BuildContext context, {
        required String label,
        required String value,
        required IconData icon,
        required Color color,
      }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _TransactionListCard extends ConsumerWidget {
  const _TransactionListCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    const expenseColor = Color(0xFFAB2D25);
    final txsAsync = ref.watch(latestByMonthProvider);
    final selectedCatId = ref.watch(selectedCategoryFilterProvider);

    return Card.filled(
      elevation: 1,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: txsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error: $e', style: TextStyle(color: scheme.error)),
        ),
        data: (txs) {
          final filtered = (selectedCatId == null)
              ? txs
              : txs.where((e) => e.$2.id == selectedCatId).toList();
          return Column(
            children: [
              ListTile(
                title: Text(
                  'Transacciones del mes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                trailing: Text(
                  '${txs.length} mov.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              const Divider(height: 0, thickness: 0.6),

              if (txs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'Sin transacciones este mes',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: txs.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 0, thickness: 0.5, color: scheme.outlineVariant),
                  itemBuilder: (context, index) {
                    final (t, cat) = txs[index];
                    final isExpense = t.amount < 0;
                    final color = isExpense ? expenseColor : scheme.primary;
                    final icon = ic.categoryIcon(cat.name, cat.type);

                    return ListTile(
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: color.withOpacity(0.12),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: cat.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  if (t.note?.isNotEmpty == true) ...[
                                    const TextSpan(text: ' — '),
                                    TextSpan(
                                      text: t.note!,
                                      style: const TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        Fx.date(t.date),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Text(
                        Fx.money(isExpense ? -t.amount : t.amount),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      onTap: () => context.pushNamed('edit_transaction', extra: t.id),
                    );
                  },
                ),
            ],
          );
        },
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

// --- FAB Expandible ---
class _ExpandableFab extends StatefulWidget {
  const _ExpandableFab({super.key});
  @override
  State<_ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<_ExpandableFab>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _controller;
  late final Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInBack,
    );
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.bottomRight,
        clipBehavior: Clip.none,
        children: [
          if (_expanded)
            GestureDetector(
              onTap: _toggle,
              child: Container(color: scheme.surface.withOpacity(0.55)),
            ),
          ..._buildExpandingButtons(context),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.identity()..translate(0.0, _expanded ? 5.0 : 0.0),
            child: FloatingActionButton(
              heroTag: 'main_fab',
              backgroundColor: scheme.primary,
              elevation: _expanded ? 6 : 4,
              onPressed: _toggle,
              child: AnimatedRotation(
                turns: _expanded ? 0.125 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.add, size: 28, color: scheme.onPrimary),
              ),
            ),
          )
        ],
      ),
    );
  }

  List<Widget> _buildExpandingButtons(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final buttons = <_ActionButton>[
      _ActionButton(
        label: 'Crear transacción',
        icon: Icons.add_rounded,
        color: scheme.surfaceContainerHigh,
        iconColor: scheme.primary,
        onTap: () {
          context.pushNamed('add_transaction');
          _toggle();
        },
      ),
      _ActionButton(
        label: 'Editar transacción',
        icon: Icons.edit_rounded,
        color: scheme.surfaceContainerHigh,
        iconColor: scheme.secondary,
        onTap: () async {
          _toggle();
          await showDialog(
            context: context,
            builder: (_) => const _TransactionPickerDialog(isDeleteMode: false),
          );
        },
      ),
      _ActionButton(
        label: 'Eliminar transacción',
        icon: Icons.delete_rounded,
        color: scheme.errorContainer,
        iconColor: scheme.onErrorContainer,
        onTap: () async {
          _toggle();
          await showDialog(
            context: context,
            builder: (_) => const _TransactionPickerDialog(isDeleteMode: true),
          );
        },
      ),
    ];

    return List.generate(buttons.length, (i) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        right: 16,
        bottom: _expanded ? (80.0 + (i * 64.0)) : 16,
        child: ScaleTransition(scale: _expandAnimation, child: buttons[i]),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color? iconColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        FloatingActionButton.small(
          heroTag: label,
          backgroundColor: color,
          elevation: 2,
          onPressed: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: color == scheme.errorContainer
                  ? Colors.transparent
                  : scheme.outlineVariant,
            ),
          ),
          child: Icon(icon, color: iconColor ?? scheme.onSurface),
        ),
      ],
    );
  }
}

class _TransactionPickerDialog extends ConsumerStatefulWidget {
  final bool isDeleteMode;
  const _TransactionPickerDialog({this.isDeleteMode = false, super.key});

  @override
  ConsumerState<_TransactionPickerDialog> createState() =>
      _TransactionPickerDialogState();
}

class _TransactionPickerDialogState
    extends ConsumerState<_TransactionPickerDialog> {
  String _query = '';
  bool _busy = false;
  Map<String, dynamic>? _lastDeleted;

  void _snack(String msg, {String? actionLabel, VoidCallback? onAction}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: (onAction != null && actionLabel != null)
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txsAsync = ref.watch(latestByMonthProvider);
    final db = ref.watch(databaseProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560, minWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: txsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (txs) {
              final filtered = txs.where((tup) {
                final (t, cat) = tup;
                final q = _query.toLowerCase();
                return cat.name.toLowerCase().contains(q) ||
                    (t.note ?? '').toLowerCase().contains(q) ||
                    Fx.money(t.amount.abs()).toLowerCase().contains(q);
              }).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(widget.isDeleteMode
                          ? Icons.delete_outline
                          : Icons.edit_outlined),
                      const SizedBox(width: 8),
                      Text(
                        widget.isDeleteMode
                            ? 'Eliminar transacción'
                            : 'Editar transacción',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Buscar por categoría, nota o monto...',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => setState(() => _query = val),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                      child: Text('Sin resultados',
                          style: TextStyle(
                              fontSize: 14, color: Colors.black54)),
                    )
                        : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 0, color: Colors.grey.shade200),
                      itemBuilder: (context, i) {
                        final (t, cat) = filtered[i];
                        final isExpense = t.amount < 0;
                        final color = isExpense ? Colors.red : Colors.green;
                        final icon = ic.categoryIcon(cat.name, cat.type);

                        final tile = ListTile(
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: color.withOpacity(0.15),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          title: Text(
                            cat.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${Fx.date(t.date)} • ${t.note?.isNotEmpty == true ? t.note : 'Sin nota'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                          trailing: Text(
                            Fx.money(isExpense ? -t.amount : t.amount),
                            style: TextStyle(color: color, fontWeight: FontWeight.bold),
                          ),
                          onTap: () async {
                            if (widget.isDeleteMode) {
                              final ok = await _confirmDelete(t, cat.name);
                              if (ok == true) await _deleteTx(db, t);
                            } else {
                              if (mounted) Navigator.pop(context);
                              context.pushNamed('edit_transaction', extra: t.id);
                            }
                          },
                        );

                        final dismissibleTile = widget.isDeleteMode
                            ? Dismissible(
                          key: ValueKey('tx_${t.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            color: Colors.redAccent.withOpacity(0.15),
                            child: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          ),
                          confirmDismiss: (_) => _confirmDelete(t, cat.name),
                          onDismissed: (_) => _deleteTx(db, t),
                          child: tile,
                        )
                            : tile;

                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                            child: FadeTransition(opacity: anim, child: child),
                          ),
                          child: dismissibleTile,
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text('Cerrar'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(Transaction t, String catName) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
          '¿Eliminar "$catName" del ${Fx.date(t.date)} por ${Fx.money(t.amount.abs())}?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTx(AppDatabase db, Transaction t) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      _lastDeleted = {
        'id': t.id,
        'amount': t.amount,
        'categoryId': t.categoryId,
        'date': t.date,
        'note': t.note,
      };
      await (db.delete(db.transactions)..where((tr) => tr.id.equals(t.id))).go();
      _snack(
        'Transacción eliminada',
        actionLabel: 'Deshacer',
        onAction: () async {
          final d = _lastDeleted;
          if (d == null) return;
          await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              amount: d['amount'] as double,
              categoryId: d['categoryId'] as int,
              date: d['date'] as DateTime,
              note: Value(d['note'] as String?),
            ),
          );
          _snack('Transacción restaurada ✔️');
        },
      );
    } catch (e) {
      _snack('Error al eliminar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
