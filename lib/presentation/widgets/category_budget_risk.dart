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

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: risksAsync.when(
          loading: () => const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => Text('Error riesgo por categoría: $e'),
          data: (items) {
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child:
                Text('Sin categorías de gasto o sin datos para estimar.'),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(
                    'Riesgo de presupuesto por categoría (próx. mes)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Divider(height: 8),
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
    final name = r.category.name;
    final icon = ic.categoryIcon(name, 'expense');
    final color = switch (r.level) {
      RiskLevel.high => Colors.red,
      RiskLevel.medium => Colors.orange,
      RiskLevel.low => Colors.green,
      RiskLevel.noBudget => Colors.grey,
    };
    final budgetTxt = r.budget == null ? '—' : Fx.money(r.budget!);
    final ratioPct = (r.budget == null || r.budget == 0)
        ? '—'
        : '${(r.ratio * 100).toStringAsFixed(0)}%';

    return LayoutBuilder(
      builder: (context, constraints) {
        // Trailing ocupa ~24% del ancho, con límites para evitar overflow
        final maxTrailing =
        (constraints.maxWidth * 0.24).clamp(84.0, 120.0).toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Leading
              CircleAvatar(
                backgroundColor: color.withOpacity(0.1),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),

              // Centro: título + subtítulo (se expande y envuelve)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    // Subtítulo: puede saltar a 2 líneas sin romper
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        Text('Proyección: ${Fx.money(r.forecast)}'),
                        Text(
                          'Presupuesto: $budgetTxt',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Trailing: ancho acotado
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTrailing),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      switch (r.level) {
                        RiskLevel.high => 'ALTO',
                        RiskLevel.medium => 'MEDIO',
                        RiskLevel.low => 'BAJO',
                        RiskLevel.noBudget => 'SIN PRES.',
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ratioPct,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                      const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
