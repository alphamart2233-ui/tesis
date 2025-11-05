import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value; // para Value(...)
import '../../core/state/db_providers.dart';
import '../../data/db/app_database.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Presupuestos'),
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
            // upsert por (cat, año, mes)
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
            if (!mounted) return;
            setState(() {}); // refrescar
          }
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder(
        future: Future.wait<List<Object?>>([
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

          final expenseCats = {
            for (final c in cats.where((c) => c.type == 'expense')) c.id: c,
          };
          final byCat = {for (final b in budgets) b.categoryId: b};

          if (expenseCats.isEmpty) {
            return const Center(
              child: Text('No hay categorías de gasto. Crea una en Categorías.'),
            );
          }

          final items = expenseCats.entries.toList()
            ..sort((a, b) => a.value.name.compareTo(b.value.name));

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final cat = items[i].value;
              final b = byCat[cat.id];

              return ListTile(
                title: Text(cat.name),
                subtitle: Text('$_year-${_month.toString().padLeft(2, '0')}'),
                trailing: Text(b == null ? '—' : b.limit.toStringAsFixed(2)),
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
                      await (db.update(db.budgets)..where((bb) => bb.id.equals(existing.id)))
                          .write(BudgetsCompanion(limit: Value(result.limit)));
                    }
                    if (!mounted) return;
                    setState(() {}); // refrescar
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
                        '¿Quitar presupuesto de "${cat.name}" para '
                            '$_year-${_month.toString().padLeft(2, '0')}?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Eliminar'),
                        ),
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
    _catId = widget.initialCategoryId ??
        (widget.categories.isNotEmpty ? widget.categories.first.id : null);
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
      title: Text(
        'Presupuesto ${widget.year}-${widget.month.toString().padLeft(2, '0')}',
      ),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
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
          onPressed: () => Navigator.pop(context, (_year, _month)),
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
