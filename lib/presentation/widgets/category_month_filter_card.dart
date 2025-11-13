// lib/presentation/widgets/category_month_filter_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/filters.dart';
import '../../core/state/analytics_providers.dart'; // latestByMonthProvider
import '../../core/utils/format.dart';

class CategoryMonthFilterCard extends ConsumerWidget {
  const CategoryMonthFilterCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selectedId = ref.watch(selectedCategoryFilterProvider);
    final txsAsync = ref.watch(latestByMonthProvider); // transacciones del mes seleccionado

    return Card.filled(
      elevation: 1,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: txsAsync.when(
          loading: () => const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text('Error: $e', style: TextStyle(color: scheme.error)),
          data: (txs) {
            // Totales de gasto por categoría (sólo montos negativos => positivos)
            final Map<int, ({String name, double total})> byCat = {};
            for (final (t, c) in txs) {
              if (t.amount >= 0) continue; // ignorar ingresos
              byCat.update(
                c.id,
                    (prev) => (name: prev.name, total: prev.total + (-t.amount)),
                ifAbsent: () => (name: c.name, total: -t.amount),
              );
            }

            // Ordenamos por total desc
            final entries = byCat.entries.toList()
              ..sort((a, b) => b.value.total.compareTo(a.value.total));

            // Total de la categoría seleccionada (o total global si null)
            double selectedTotal;
            String label;
            if (selectedId == null) {
              selectedTotal = entries.fold(0.0, (s, e) => s + e.value.total);
              label = 'Gasto total del mes';
            } else {
              final v = byCat[selectedId]?.total ?? 0.0;
              selectedTotal = v;
              label = 'Gasto en ${byCat[selectedId]?.name ?? '—'}';
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtrar por categoría',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),

                // Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        selected: selectedId == null,
                        label: const Text('Todas'),
                        onSelected: (_) =>
                        ref.read(selectedCategoryFilterProvider.notifier).state = null,
                      ),
                      const SizedBox(width: 8),
                      for (final e in entries) ...[
                        FilterChip(
                          selected: selectedId == e.key,
                          label: Text(e.value.name),
                          onSelected: (sel) {
                            ref.read(selectedCategoryFilterProvider.notifier).state =
                            sel ? e.key : null;
                          },
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Divider(height: 16, thickness: 0.5, color: scheme.outlineVariant),

                // Resumen
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodyMedium),
                    Text(
                      Fx.money(selectedTotal),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
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
}
