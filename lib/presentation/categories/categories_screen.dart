// lib/presentation/categories/categories_screen.dart
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/db_providers.dart';
import '../../data/db/app_database.dart';
import 'package:drift/drift.dart' as dr;
import '../../core/utils/icons.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  void _showCategoryDialog(
      BuildContext context, WidgetRef ref, Category? category) {
    showDialog(
      context: context,
      builder: (context) => _CategoryDialog(categoryToEdit: category),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCategoryDialog(context, ref, null),
        label: const Text('Nueva Categoria'),
        icon: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Category>>(
        stream: (db.select(db.categories)
          ..orderBy([(c) => dr.OrderingTerm.asc(c.name)]))
            .watch(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return const Center(
              child: Text('Sin categorías. Toca + para crear la primera.'),
            );
          }

          final incomes = items.where((c) => c.type == 'income').toList();
          final expenses = items.where((c) => c.type == 'expense').toList();

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            children: [
              if (incomes.isNotEmpty) ...[
                _buildSectionHeader(context, 'Ingresos'),
                ...incomes.map((c) =>
                    _buildCategoryTile(context, ref, db, c)),
              ],
              if (expenses.isNotEmpty) ...[
                _buildSectionHeader(context, 'Gastos'),
                ...expenses.map((c) =>
                    _buildCategoryTile(context, ref, db, c)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryTile(
      BuildContext context, WidgetRef ref, AppDatabase db, Category c) {
    final isExpense = c.type == 'expense';

    return Dismissible(
      key: ValueKey(c.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade700,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async => await _showConfirmDeleteDialog(context, c),
      onDismissed: (_) async {
        await (db.delete(db.categories)..where((t) => t.id.equals(c.id))).go();
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor:
            (isExpense ? Colors.red : Colors.green).withOpacity(0.15),
            child: Icon(
              categoryIcon(c.name, c.type, icon: c.icon),
              color: isExpense ? Colors.red.shade700 : Colors.green.shade700,
            ),
          ),
          title: Text(c.name, style: Theme.of(context).textTheme.bodyLarge),
          trailing: IconButton(
            icon: Icon(Icons.edit, color: Colors.grey.shade500),
            onPressed: () => _showCategoryDialog(context, ref, c),
          ),
          onTap: () => _showCategoryDialog(context, ref, c),
        ),
      ),
    );
  }

  Future<bool> _showConfirmDeleteDialog(BuildContext context, Category c) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Eliminar "${c.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    ) ??
        false;
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8, left: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _CategoryDialog extends ConsumerStatefulWidget {
  final Category? categoryToEdit;
  const _CategoryDialog({this.categoryToEdit});

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  String _type = 'expense';
  String? _iconKey;

  bool get _isEditing => widget.categoryToEdit != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.categoryToEdit?.name ?? '');
    _type = widget.categoryToEdit?.type ?? 'expense';
    _iconKey = widget.categoryToEdit?.icon;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    final db = ref.read(databaseProvider);
    final name = _nameCtrl.text.trim();

    if (_isEditing) {
      final updatedCategory = widget.categoryToEdit!.copyWith(
        name: name,
        type: _type,
        icon: dr.Value(_iconKey),
        isDirty: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await db.update(db.categories).replace(updatedCategory);
    } else {
      await db.into(db.categories).insert(
        CategoriesCompanion.insert(
          name: name,
          type: _type,
          icon: dr.Value(_iconKey),
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  void _pickIcon() async {
    final selected = await showDialog<String?>(
      context: context,
      builder: (context) => _IconPickerDialog(selectedIconKey: _iconKey),
    );
    if (selected != null) {
      setState(() => _iconKey = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar categoría' : 'Nueva categoría'),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Ícono:', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _pickIcon,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey.shade200,
                    child: Icon(
                      iconFromString(_iconKey),
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        ElevatedButton(onPressed: _onSave, child: const Text('Guardar')),
      ],
    );
  }
}

class _IconPickerDialog extends StatelessWidget {
  final String? selectedIconKey;
  const _IconPickerDialog({this.selectedIconKey});

  @override
  Widget build(BuildContext context) {
    final keys = categoryIconsMap.keys.toList();
    return AlertDialog(
      title: const Text('Seleccionar ícono'),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 4,
          children: keys.map((key) {
            final isSelected = key == selectedIconKey;
            return GestureDetector(
              onTap: () => Navigator.pop(context, key),
              child: Container(
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                      : null,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  categoryIconsMap[key],
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
