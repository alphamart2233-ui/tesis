// lib/presentation/widgets/category_budget_risk.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/category_risk_provider.dart';
import '../../core/state/filters.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart' as ic;

class CategoryBudgetRisk extends ConsumerWidget {
  const CategoryBudgetRisk({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedMonth = ref.watch(selectedMonthProvider);
    final risksAsync = ref.watch(categoryRiskProvider(selectedMonth));
    final scheme = Theme.of(context).colorScheme;

    return Card.filled(
      elevation: 1,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: risksAsync.when(
          loading: () => const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text(
            'Error riesgo por categoría: $e',
            style: TextStyle(color: scheme.error),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Sin categorías de gasto o sin datos para estimar.',
                  style: TextStyle(color: Colors.black54),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Riesgo de presupuesto por categoría (próx. mes)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Divider(height: 16, thickness: 0.5, color: scheme.outlineVariant),
                ...items.map((r) => _RiskRow(r: r)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.r});
  final CategoryRisk r;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const expenseColor = Color(0xFFAB2D25); // alto
    const mediumColor = Color(0xFFDD8F00);  // medio
    const lowColor = Color(0xFF2E8B57);     // bajo

    final name = r.category.name;
    final icon = ic.categoryIcon(name, 'expense');
    final color = switch (r.level) {
      RiskLevel.high => expenseColor,
      RiskLevel.medium => mediumColor,
      RiskLevel.low => lowColor,
      RiskLevel.noBudget => scheme.outlineVariant,
    };

    final budgetTxt = r.budget == null ? '—' : Fx.money(r.budget!);
    final ratioPct = (r.budget == null || r.budget == 0)
        ? '—'
        : '${(r.ratio * 100).toStringAsFixed(0)}%';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Proyección: ${Fx.money(r.forecast)}   •   Presupuesto: $budgetTxt',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                switch (r.level) {
                  RiskLevel.high => 'ALTO',
                  RiskLevel.medium => 'MEDIO',
                  RiskLevel.low => 'BAJO',
                  RiskLevel.noBudget => 'SIN PRES.',
                },
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                ratioPct,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
