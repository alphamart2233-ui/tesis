// lib/presentation/budgets/budgets_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:rxdart/rxdart.dart';

import '../../core/state/db_providers.dart';
import '../../data/db/app_database.dart';
import '../../core/utils/icons.dart';

class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key});

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final scheme = Theme.of(context).colorScheme;

    final cats$ = db.select(db.categories).watch();
    final budgets$ = (db.select(db.budgets)
      ..where((b) => b.year.equals(_year))
      ..where((b) => b.month.equals(_month)))
        .watch();

    final combined$ = Rx.combineLatest2<List<Category>, List<Budget>,
        (List<Category>, List<Budget>)>(
      cats$,
      budgets$,
          (cats, budgets) => (cats, budgets),
    );

    final monthLabel =
    DateFormat.yMMMM('es_ES').format(DateTime(_year, _month));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Presupuestos'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Cambiar mes',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () async {
              final picked = await showDialog<(int, int)>(
                context: context,
                builder: (_) =>
                    _MonthPickerDialog(year: _year, month: _month),
              );
              if (picked != null && mounted) {
                setState(() {
                  _year = picked.$1;
                  _month = picked.$2;
                });
              }
            },
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        label: const Text('Nuevo'),
        icon: const Icon(Icons.add_rounded),
        onPressed: () async {
          final cats = await db.select(db.categories).get();
          if (!mounted) return;
          final expenseCats = cats.where((c) => c.type == 'expense').toList();
          if (expenseCats.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Primero crea categorías de gasto.')),
            );
            return;
          }
          final result = await showDialog<_BudgetFormResult>(
            context: context,
            builder: (_) => _BudgetDialog(
              year: _year,
              month: _month,
              categories: expenseCats,
            ),
          );
          if (!mounted || result == null) return;

          final existing = await (db.select(db.budgets)
            ..where((b) => b.categoryId.equals(result.categoryId))
            ..where((b) => b.year.equals(_year))
            ..where((b) => b.month.equals(_month)))
              .getSingleOrNull();

          if (existing == null) {
            await db.into(db.budgets).insert(
              BudgetsCompanion.insert(
                categoryId: result.categoryId,
                year: _year,
                month: _month,
                limit: result.limit,
              ),
            );
          } else {
            await (db.update(db.budgets)..where((b) => b.id.equals(existing.id)))
                .write(BudgetsCompanion(limit: Value(result.limit)));
          }
        },
      ),

      body: StreamBuilder<(List<Category>, List<Budget>)>(
        stream: combined$,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final cats = snap.data!.$1;
          final budgets = snap.data!.$2;
          final expenseCats = cats.where((c) => c.type == 'expense').toList()
            ..sort((a, b) => a.name.compareTo(b.name));

          final budgetsByCat = {for (final b in budgets) b.categoryId: b};
          final chartData = <String, double>{};
          double total = 0;

          for (final c in expenseCats) {
            final b = budgetsByCat[c.id];
            if (b != null && b.limit > 0) {
              chartData[c.name] = b.limit;
              total += b.limit;
            }
          }

          return CustomScrollView(
            slivers: [
              if (chartData.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Card(
                      elevation: 0,
                      color: scheme.surfaceContainerHighest,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _BudgetDonut(
                          data: chartData,
                          total: total,
                          colors: [
                            scheme.primary,
                            scheme.secondary,
                            scheme.tertiary,
                            scheme.primaryContainer,
                            scheme.secondaryContainer,
                            scheme.tertiaryContainer,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              SliverToBoxAdapter(
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.wallet_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Presupuestos de $monthLabel',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ),

              SliverList.separated(
                itemCount: expenseCats.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final cat = expenseCats[i];
                  final b = budgetsByCat[cat.id];
                  final icon =
                  categoryIcon(cat.name, cat.type, icon: cat.icon);

                  return Card(
                    color: scheme.surfaceContainerLow,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: scheme.primary.withOpacity(0.1),
                        child: Icon(icon, color: scheme.primary, size: 20),
                      ),
                      title: Text(
                        cat.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        b == null
                            ? 'Sin presupuesto'
                            : 'Presupuesto: $monthLabel',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: Text(
                        b == null
                            ? '—'
                            : NumberFormat.currency(symbol: '\$')
                            .format(b.limit),
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () async {
                        final result = await showDialog<_BudgetFormResult>(
                          context: context,
                          builder: (_) => _BudgetDialog(
                            year: _year,
                            month: _month,
                            categories: [cat],
                            initial: b?.limit,
                            initialCategoryId: cat.id,
                          ),
                        );
                        if (result == null) return;

                        final existing = await (db.select(db.budgets)
                          ..where((bb) =>
                              bb.categoryId.equals(result.categoryId))
                          ..where((bb) => bb.year.equals(_year))
                          ..where((bb) => bb.month.equals(_month)))
                            .getSingleOrNull();

                        if (existing == null) {
                          await db.into(db.budgets).insert(
                            BudgetsCompanion.insert(
                              categoryId: result.categoryId,
                              year: _year,
                              month: _month,
                              limit: result.limit,
                            ),
                          );
                        } else {
                          await (db.update(db.budgets)
                            ..where((bb) => bb.id.equals(existing.id)))
                              .write(BudgetsCompanion(
                              limit: Value(result.limit)));
                        }
                      },
                      onLongPress: b == null
                          ? null
                          : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Eliminar presupuesto'),
                            content: Text(
                                '¿Quitar presupuesto de "${cat.name}" para $monthLabel?'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancelar')),
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Eliminar')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await (db.delete(db.budgets)
                          ..where((bb) => bb.id.equals(b.id)))
                            .go();
                      },
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          );
        },
      ),
    );
  }
}

class _BudgetDonut extends StatelessWidget {
  const _BudgetDonut({
    required this.data,
    required this.colors,
    required this.total,
  });

  final Map<String, double> data;
  final List<Color> colors;
  final double total;

  Color _tint(Color base, double amount) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness * (1 - amount)).clamp(0.25, 0.75))
        .toColor();
  }

  // ---------- Grafico tipo dona ----------
  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList();
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    // 🎨 Paleta armónica (sin rojo)
    final baseColors = [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primaryContainer,
      scheme.secondaryContainer,
      scheme.tertiaryContainer,
    ];

    // Ajustar brillo según tema
    final palette = baseColors
        .map((c) =>
    brightness == Brightness.light ? _tint(c, 0.05) : _tint(c, -0.1))
        .toList();

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1.4,
          child: PieChart(
            PieChartData(
              sectionsSpace: 3,
              centerSpaceRadius: 42,
              startDegreeOffset: -90,
              sections: List.generate(entries.length, (i) {
                final e = entries[i];
                final pct = total == 0 ? 0 : (e.value / total) * 100;
                final color = palette[i % palette.length];

                return PieChartSectionData(
                  value: e.value,
                  radius: 54,
                  color: color,
                  title: '${pct.toStringAsFixed(0)}%',
                  titleStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          children: List.generate(entries.length, (i) {
            final e = entries[i];
            final color = palette[i % palette.length];
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${e.key}: ${NumberFormat.simpleCurrency(decimalDigits: 0).format(e.value)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

// ---------- Dialog & Model ----------
class _BudgetFormResult {
  final int categoryId;
  final double limit;
  _BudgetFormResult(this.categoryId, this.limit);
}

class _BudgetDialog extends StatefulWidget {
  final int year;
  final int month;
  final List<Category> categories;
  final double? initial;
  final int? initialCategoryId;

  const _BudgetDialog({
    required this.year,
    required this.month,
    required this.categories,
    this.initial,
    this.initialCategoryId,
  });

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  final _formKey = GlobalKey<FormState>();
  final _limitCtrl = TextEditingController();
  int? _catId;

  @override
  void initState() {
    super.initState();
    _catId = widget.initialCategoryId ?? widget.categories.first.id;
    if (widget.initial != null) {
      _limitCtrl.text = widget.initial!.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Presupuesto ${widget.year}-${widget.month.toString().padLeft(2, '0')}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: _catId,
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _catId = v),
              decoration: const InputDecoration(labelText: 'Categoría (gasto)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _limitCtrl,
              decoration: const InputDecoration(labelText: 'Límite mensual'),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Ingresa un monto';
                final d = double.tryParse(v.replaceAll(',', '.'));
                if (d == null || d < 0) return 'Monto inválido';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate() && _catId != null) {
              final d = double.parse(_limitCtrl.text.replaceAll(',', '.'));
              Navigator.pop(context, _BudgetFormResult(_catId!, d));
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

// ---------- Month Picker ----------
class _MonthPickerDialog extends StatefulWidget {
  final int year;
  final int month;
  const _MonthPickerDialog({required this.year, required this.month});

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = widget.year;
    _month = widget.month;
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
              child: Text('$_year-${_month.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 18)),
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
        ElevatedButton(onPressed: () => Navigator.pop(context, (_year, _month)), child: const Text('Aceptar')),
      ],
    );
  }
}
