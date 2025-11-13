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

  void _showCategoryDialog(BuildContext context, WidgetRef ref, Category? category) {
    showDialog(
      context: context,
      builder: (context) => _CategoryDialog(categoryToEdit: category),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorías'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        onPressed: () => _showCategoryDialog(context, ref, null),
        label: const Text('Nueva categoría'),
        icon: const Icon(Icons.add_rounded),
      ),
      body: StreamBuilder<List<Category>>(
        stream: (db.select(db.categories)..orderBy([(c) => dr.OrderingTerm.asc(c.name)])).watch(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Sin categorías aún.\nToca “Nueva categoría” para crear la primera.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final incomes = items.where((c) => c.type == 'income').toList();
          final expenses = items.where((c) => c.type == 'expense').toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
            children: [
              if (incomes.isNotEmpty) ...[
                _buildSectionHeader(context, 'Ingresos', Icons.trending_up_rounded, scheme.secondary),
                ...incomes.map((c) => _buildCategoryTile(context, ref, db, c)),
              ],
              if (expenses.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildSectionHeader(context, 'Gastos', Icons.trending_down_rounded, scheme.primary),
                ...expenses.map((c) => _buildCategoryTile(context, ref, db, c)),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryTile(
      BuildContext context,
      WidgetRef ref,
      AppDatabase db,
      Category c,
      ) {
    const expenseColor = Color(0xFFAB2D25); // 🎨 RGB(171,45,37)
    final scheme = Theme.of(context).colorScheme;
    final isExpense = c.type == 'expense';

    final iconColor = isExpense ? expenseColor : scheme.secondary;
    final bgColor = isExpense
        ? expenseColor.withOpacity(0.08)
        : scheme.secondary.withOpacity(0.12);

    return Dismissible(
      key: ValueKey(c.id),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      confirmDismiss: (_) async => await _showConfirmDeleteDialog(context, c),
      onDismissed: (_) async {
        await (db.delete(db.categories)..where((t) => t.id.equals(c.id))).go();
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: bgColor,
            child: Icon(
              categoryIcon(c.name, c.type, icon: c.icon),
              color: iconColor,
            ),
          ),
          title: Text(
            c.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          trailing: IconButton(
            icon: Icon(Icons.edit_rounded, color: scheme.outline),
            onPressed: () => _showCategoryDialog(context, ref, c),
          ),
          onTap: () => _showCategoryDialog(context, ref, c),
        ),
      ),
    );
  }

  Future<bool> _showConfirmDeleteDialog(BuildContext context, Category c) async {
    final scheme = Theme.of(context).colorScheme;
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Eliminar "${c.name}" permanentemente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Eliminar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ) ??
        false;
  }

  Widget _buildSectionHeader(
      BuildContext context,
      String title,
      IconData icon,
      Color? color,
      ) {
    const expenseColor = Color(0xFFAB2D25); // 🎨 rojo terroso de gastos
    final scheme = Theme.of(context).colorScheme;

    // Si el título es "Gastos", usamos el color fijo; si no, usamos el que se pasa o el secundario.
    final headerColor =
    title.toLowerCase().contains('gasto') ? expenseColor : (color ?? scheme.secondary);

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: headerColor),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: headerColor,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

}

// ===================== CATEGORY DIALOG =====================
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
      final updated = widget.categoryToEdit!.copyWith(
        name: name,
        type: _type,
        icon: dr.Value(_iconKey),
        isDirty: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await db.update(db.categories).replace(updated);
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
    if (selected != null) setState(() => _iconKey = selected);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa un nombre' : null,
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
                    radius: 22.0,
                    backgroundColor: scheme.surfaceContainerHighest,
                    child: Icon(
                      iconFromString(_iconKey),
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _onSave, child: const Text('Guardar')),
      ],
    );
  }
}

// ===================== ICON PICKER =====================
class _IconPickerDialog extends StatelessWidget {
  final String? selectedIconKey;
  const _IconPickerDialog({this.selectedIconKey});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                      ? scheme.primaryContainer.withOpacity(0.4)
                      : scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: scheme.primary, width: 2)
                      : null,
                ),
                child: Icon(
                  categoryIconsMap[key],
                  color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
