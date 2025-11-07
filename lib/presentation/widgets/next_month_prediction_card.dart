// lib/presentation/widgets/next_month_prediction_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/analytics_providers.dart';
import '../../core/utils/format.dart';

class NextMonthPredictionCard extends ConsumerWidget {
  const NextMonthPredictionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(nextMonthForecastProvider);
    final textTheme = Theme.of(context).textTheme;

    // Usamos Card.filled para un look M3 más suave
    return Card.filled(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: forecast.when(
          loading: () => const _LoadingRow(),
          error: (e, _) => Center(child: Text('Error en predicción: $e')),
          data: (f) {
            // Si no hay datos, muestra un mensaje claro
            if (!f.hasData) {
              return Row(
                children: [
                  Icon(Icons.info_outline, color: textTheme.bodySmall?.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sin datos suficientes para predecir el próximo mes.',
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            }

            // Cálculos (igual que antes)
            final bandLow = (f.expenses - f.expensesStdDev).clamp(0, double.infinity);
            final bandHigh = f.expenses + f.expensesStdDev;
            final balance = f.balance;
            final balanceColor = balance >= 0 ? Colors.green.shade600 : Colors.red.shade600;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Título
                Text(
                  'Predicción del próximo mes',
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),

                // 1. HÉROE: Balance Proyectado
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Balance Proyectado',
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Fx.money(balance),
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: balanceColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // 2. CONTEXTO: Banda de Confianza
                Center(
                  child: Text(
                    'Banda: ${Fx.money(bandLow)} – ${Fx.money(bandHigh)}',
                    style: textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Divider(height: 24),

                // 3. DESGLOSE: Gasto e Ingreso
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn(
                      'Gasto',
                      f.expenses,
                      Icons.trending_down,
                      Colors.red.shade600,
                      textTheme,
                    ),
                    _buildStatColumn(
                      'Ingreso',
                      f.incomes,
                      Icons.trending_up,
                      Colors.green.shade600,
                      textTheme,
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

  // Helper para el desglose (Gasto/Ingreso)
  Widget _buildStatColumn(
      String label,
      double value,
      IconData icon,
      Color color,
      TextTheme textTheme,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(label, style: textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          Fx.money(value),
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// Helper de Carga
class _LoadingRow extends StatelessWidget {
  const _LoadingRow();
  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 10),
        Text('Calculando predicción...'),
      ],
    );
  }
}