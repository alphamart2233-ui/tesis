import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/prediction_providers.dart';
import '../../core/utils/format.dart';

class CategoryBudgetRisk extends ConsumerWidget {
  const CategoryBudgetRisk({super.key});

  Color _riskColor(double ratio) {
    if (ratio >= 1.0) return Colors.red;
    if (ratio >= 0.8) return Colors.orange;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = ref.watch(budgetRiskNextMonthProvider);

    return asyncItems.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 12),
            Text('Calculando riesgo de presupuesto...')
          ]),
        ),
      ),
      error: (e, st) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error al calcular riesgo: $e'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Sin categorías de gasto para evaluar.'),
            ),
          );
        }
        return Card(
          elevation: 2,
          child: Column(
            children: [
              const ListTile(
                title: Text('Riesgo de presupuesto (próximo mes)'),
                subtitle: Text('Predicción EWMA vs. límite asignado'),
              ),
              const Divider(height: 0),
              ...items.map((it) {
                final ratio = it.budget == null || it.budget == 0
                    ? 0.0
                    : (it.predicted / it.budget!).clamp(0.0, 1.0);
                return Column(
                  children: [
                    ListTile(
                      title: Text(it.category.name),
                      subtitle: it.budget == null
                          ? const Text('Sin presupuesto definido')
                          : Text(
                        '${Fx.money(it.predicted)} / ${Fx.money(it.budget!)}',
                      ),
                      trailing: it.budget == null
                          ? const Icon(Icons.info_outline)
                          : Text(
                        '${(100 * it.predicted / it.budget!).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _riskColor(it.predicted / it.budget!),
                        ),
                      ),
                    ),
                    if (it.budget != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ratio,
                            minHeight: 8,
                            backgroundColor: Colors.black12,
                            color: _riskColor(it.predicted / (it.budget == 0 ? 1 : it.budget!)),
                          ),
                        ),
                      ),
                    const Divider(height: 0),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
