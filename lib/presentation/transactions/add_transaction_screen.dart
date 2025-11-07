import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:go_router/go_router.dart';

import '../../core/state/db_providers.dart';
import '../../data/db/app_database.dart';
import '../../core/utils/icons.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  Category? _selectedCategory;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selectedCategory == null) return;
    final db = ref.read(databaseProvider);
    final amount = double.parse(_amountCtrl.text.replaceAll(',', '.'));
    final note = _noteCtrl.text.trim();
    final categoryId = _selectedCategory!.id;

    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        amount: amount * (_selectedCategory!.type == 'expense' ? -1 : 1),
        note: Value(note.isEmpty ? null : note),
        date: _selectedDate,
        categoryId: _selectedCategory!.id,
      ),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transacción guardada')),
    );
    context.goNamed('home'); // o la ruta que uses para volver
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nueva transacción'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: FutureBuilder<List<Category>>(
          future: db.getAllCategories(),
          builder: (context, snap) {
            final cats = snap.data ?? [];
            final expenseCats = cats.where((c) => c.type == 'expense').toList();
            final incomeCats = cats.where((c) => c.type == 'income').toList();
            final allCats = [...incomeCats, ...expenseCats];

            return Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _amountCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.attach_money),
                        labelText: 'Monto',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Ingresa un monto';
                        final d = double.tryParse(v.replaceAll(',', '.'));
                        if (d == null || d == 0) return 'Monto inválido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<Category>(
                      value: _selectedCategory,
                      decoration: InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                      ),
                      items: allCats.map((c) {
                        return DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: (c.type == 'expense' ? Colors.red : Colors.green).withOpacity(0.15),
                                child: Icon(categoryIcon(c.name, c.type, icon: c.icon), size: 20, color: (c.type == 'expense' ? Colors.red : Colors.green)),
                              ),
                              const SizedBox(width: 8),
                              Text(c.name),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedCategory = v),
                      validator: (v) => v == null ? 'Selecciona una categoría' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _noteCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.note),
                        labelText: 'Nota (opcional)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Fecha: ${_selectedDate.toLocal().toString().split(' ')[0]}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Cambiar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.check),
                        label: const Text('Guardar'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
