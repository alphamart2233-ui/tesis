// lib/presentation/budgets/budgets_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';

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

  final _colors = [
    Colors.redAccent,
    Colors.blueAccent,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.amber,
  ];

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Presupuestos'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Cambiar mes',
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final picked = await showDialog<(int, int)>(
                context: context,
                builder: (_) => _MonthPickerDialog(year: _year, month: _month),
              );
              if (!mounted) return;
              if (picked != null) {
                setState(() {
                  _year = picked.$1;
                  _month = picked.$2;
                });
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agregar/Editar presupuesto',
        onPressed: () async {
          final cats = await db.select(db.categories).get();
          if (!mounted) return;
          if (cats.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Primero crea categorías.')),
            );
            return;
          }
          final result = await showDialog<_BudgetFormResult>(
            context: context,
            builder: (_) => _BudgetDialog(
              year: _year,
              month: _month,
              categories: cats.where((c) => c.type == 'expense').toList(),
            ),
          );
          if (!mounted) return;
          if (result != null) {
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
              await (db.update(db.budgets)
                ..where((b) => b.id.equals(existing.id)))
                  .write(BudgetsCompanion(limit: Value(result.limit)));
            }
            if (!mounted) return;
            setState(() {});
          }
        },
        child: const Icon(Icons.add),
      ),
      // ⛔ bottomNavigationBar eliminado — ShellRoute lo maneja

      body: FutureBuilder<List<Object?>>(
        future: Future.wait([
          db.select(db.categories).get(),
          (db.select(db.budgets)
            ..where((b) => b.year.equals(_year))
            ..where((b) => b.month.equals(_month)))
              .get(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final cats = snapshot.data![0] as List<Category>;
          final budgets = snapshot.data![1] as List<Budget>;

          final expenseCats = cats.where((c) => c.type == 'expense').toList();
          final budgetsByCat = {for (var b in budgets) b.categoryId: b};

          final dataMap = <String, double>{};
          for (var c in expenseCats) {
            final b = budgetsByCat[c.id];
            if (b != null && b.limit > 0) {
              dataMap[c.name] = b.limit;
            }
          }

          final items = expenseCats..sort((a, b) => a.name.compareTo(b.name));

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: items.length + (dataMap.isNotEmpty ? 1 : 0),
            itemBuilder: (context, i) {
              if (dataMap.isNotEmpty && i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AspectRatio(
                    aspectRatio: 1.3,
                    child: PieChart(
                      PieChartData(
                        sections: dataMap.entries.toList().asMap().entries.map((entry) {
                          final index = entry.key;
                          final e = entry.value;
                          return PieChartSectionData(
                            value: e.value,
                            title: e.value.toStringAsFixed(0),
                            color: _colors[index % _colors.length],
                            radius: 50,
                          );
                        }).toList(),
                        sectionsSpace: 4,
                        centerSpaceRadius: 30,
                      ),
                    ),
                  ),
                );
              }

              final offset = dataMap.isNotEmpty ? 1 : 0;
              final cat = items[i - offset];
              final b = budgetsByCat[cat.id];

              final isExpense = cat.type == 'expense';
              final icon = categoryIcon(cat.name, cat.type, icon: cat.icon);
              final formattedDate = DateFormat.yMMMM('es_ES').format(DateTime(_year, _month));

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: CircleAvatar(
                    backgroundColor: (isExpense ? Colors.red : Colors.green).withOpacity(0.15),
                    child: Icon(icon, color: isExpense ? Colors.red : Colors.green),
                  ),
                  title: Text(cat.name, style: Theme.of(context).textTheme.titleMedium),
                  subtitle: Text('Presupuesto: $formattedDate'),
                  trailing: Text(
                    b == null ? '—' : '\$${b.limit.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
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
                    if (!mounted) return;
                    if (result != null) {
                      final existing = await (db.select(db.budgets)
                        ..where((bb) => bb.categoryId.equals(result.categoryId))
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
                            .write(BudgetsCompanion(limit: Value(result.limit)));
                      }
                      if (!mounted) return;
                      setState(() {});
                    }
                  },
                  onLongPress: b == null
                      ? null
                      : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Eliminar presupuesto'),
                        content: Text('¿Quitar presupuesto de "${cat.name}" para $formattedDate?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
                        ],
                      ),
                    ) ??
                        false;
                    if (ok) {
                      await (db.delete(db.budgets)..where((bb) => bb.id.equals(b.id))).go();
                      if (!mounted) return;
                      setState(() {});
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
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
    _catId = widget.initialCategoryId ?? widget.categories.firstOrNull?.id;
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
              child: Text('$_year-${_month.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 18)),
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

