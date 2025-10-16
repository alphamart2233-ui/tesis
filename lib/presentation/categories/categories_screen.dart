import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../main.dart';
import '../../data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
import '../../core/utils/icons.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await showDialog<_CategoryFormResult>(
            context: context,
            builder: (context) => const _CategoryDialog(),
          );
          if (result != null) {
            await db
                .into(db.categories)
                .insert(
                  CategoriesCompanion.insert(
                    name: result.name,
                    type: result.type,
                  ),
                );
          }
        },
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Category>>(
        stream: db.select(db.categories).watch(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text('Sin categorías. Toca + para crear la primera.'),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final c = items[i];
              return Dismissible(
                key: ValueKey(c.id),
                background: Container(color: Colors.red.withOpacity(0.8)),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Eliminar categoría'),
                          content: Text(
                            '¿Eliminar "${c.name}"? (También afectará nuevas transacciones que la usen)',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Eliminar'),
                            ),
                          ],
                        ),
                      ) ??
                      false;
                },
                onDismissed: (_) async {
                  await (db.delete(
                    db.categories,
                  )..where((t) => t.id.equals(c.id))).go();
                },
                child: ListTile(
                  leading: Icon(
                    categoryIcon(c.name, c.type),
                    color: c.type == 'expense' ? Colors.red : Colors.green,
                  ),
                  title: Text(c.name),
                  subtitle: Text(c.type == 'expense' ? 'Gasto' : 'Ingreso'),
                  // ...
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryFormResult {
  final String name;
  final String type; // 'income' | 'expense'
  _CategoryFormResult(this.name, this.type);
}

class _CategoryDialog extends StatefulWidget {
  final String? initialName;
  final String? initialType;
  const _CategoryDialog({this.initialName, this.initialType});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  String _type = 'expense';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _type = widget.initialType ?? 'expense';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.initialName == null ? 'Nueva categoría' : 'Editar categoría',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ingresa un nombre' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'expense', child: Text('Gasto')),
                DropdownMenuItem(value: 'income', child: Text('Ingreso')),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'expense'),
              decoration: const InputDecoration(labelText: 'Tipo'),
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
            if (_formKey.currentState!.validate()) {
              Navigator.pop(
                context,
                _CategoryFormResult(_nameCtrl.text.trim(), _type),
              );
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
