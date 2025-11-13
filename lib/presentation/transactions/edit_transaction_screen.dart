// lib/presentation/transactions/edit_transaction_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import '../../core/state/db_providers.dart';
import '../../data/db/app_database.dart';

class EditTransactionScreen extends ConsumerStatefulWidget {
  final int transactionId;
  const EditTransactionScreen({super.key, required this.transactionId});

  @override
  ConsumerState<EditTransactionScreen> createState() =>
      _EditTransactionScreenState();
}

class _EditTransactionScreenState
    extends ConsumerState<EditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();

  double? amount;
  int? categoryId;
  DateTime? date;
  String? note;

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Editar transacción')),
      body: FutureBuilder(
        future: Future.wait([
          db.select(db.categories).get(),
          (db.select(db.transactions)
            ..where((t) => t.id.equals(widget.transactionId)))
              .getSingle(),
        ]),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final cats = snapshot.data![0] as List<Category>;
          final tx = snapshot.data![1] as Transaction;

          // Inicializar campos solo la primera vez
          amount ??= tx.amount.abs();
          categoryId ??= tx.categoryId;
          date ??= tx.date;
          note ??= tx.note ?? '';

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  // Monto
                  TextFormField(
                    initialValue: amount.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Monto',
                      hintText: 'Ej: 20.50',
                      prefixIcon: Icon(Icons.attach_money),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[-0-9.,]')),
                    ],
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Ingresa un monto' : null,
                    onSaved: (v) =>
                    amount = double.tryParse(v!.trim().replaceAll(',', '.')),
                  ),
                  const SizedBox(height: 12),

                  // Categoría
                  DropdownButtonFormField<int>(
                    value: categoryId,
                    items: cats
                        .map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text('${c.name} (${c.type})'),
                    ))
                        .toList(),
                    onChanged: (v) => setState(() => categoryId = v),
                    validator: (v) => v == null ? 'Selecciona categoría' : null,
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Nota
                  TextFormField(
                    initialValue: note,
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.notes),
                    ),
                    onSaved: (v) =>
                    note = (v?.trim().isEmpty ?? true) ? null : v!.trim(),
                  ),
                  const SizedBox(height: 12),

                  // Fecha
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Fecha: ${date!.toIso8601String().substring(0, 10)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('Cambiar'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date!,
                            firstDate: DateTime(2018),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => date = picked);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Guardar cambios
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Guardar cambios'),
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;
                        _formKey.currentState!.save();

                        final selectedCategory = await (db.select(db.categories)
                          ..where((c) => c.id.equals(categoryId!)))
                            .getSingle();

                        final double finalAmount =
                        selectedCategory.type == 'expense'
                            ? -amount!.abs()
                            : amount!.abs();

                        await (db.update(db.transactions)
                          ..where((t) => t.id.equals(widget.transactionId)))
                            .write(
                          TransactionsCompanion(
                            amount: Value(finalAmount),
                            categoryId: Value(categoryId!),
                            date: Value(date!),
                            note: Value(note),
                            updatedAt:
                            Value(DateTime.now().millisecondsSinceEpoch),
                            isDirty: const Value(true),
                          ),
                        );

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Transacción actualizada ✔️')),
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
