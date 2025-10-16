import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;

import '../../main.dart';
import '../../data/db/app_database.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();

  double? amount;
  int? categoryId;
  DateTime date = DateTime.now();
  String? note;

  @override
  void initState() {
    super.initState();
    // Semilla de categorías por si es la primera vez
    Future.microtask(() => ref.read(databaseProvider).seed());
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva transacción')),
      body: FutureBuilder<List<Category>>(
        future: db.select(db.categories).get(),
        builder: (context, snapshot) {
          final cats = snapshot.data ?? [];

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  // Monto
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Monto'),
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Ingresa un monto'
                        : null,
                    onSaved: (v) =>
                        amount = double.tryParse(v!.replaceAll(',', '.')),
                  ),
                  const SizedBox(height: 12),

                  // Categoría
                  DropdownButtonFormField<int>(
                    value: categoryId,
                    items: cats
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text('${c.name} (${c.type})'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => categoryId = v),
                    validator: (v) => v == null ? 'Selecciona categoría' : null,
                    decoration: const InputDecoration(labelText: 'Categoría'),
                  ),
                  const SizedBox(height: 12),

                  // Nota
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                    ),
                    onSaved: (v) => note = v?.trim().isEmpty == true ? null : v,
                  ),
                  const SizedBox(height: 12),

                  // Selector de fecha
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Fecha: ${date.toIso8601String().substring(0, 10)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('Cambiar'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
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

                  // Guardar
                  ElevatedButton(
                    onPressed: () async {
                      if (_formKey.currentState!.validate()) {
                        _formKey.currentState!.save();

                        await db
                            .into(db.transactions)
                            .insert(
                              TransactionsCompanion.insert(
                                amount: amount!,
                                categoryId: categoryId!,
                                date: date,
                                note: Value(note),
                              ),
                            );

                        if (context.mounted) Navigator.of(context).pop();
                      }
                    },
                    child: const Text('Guardar'),
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
