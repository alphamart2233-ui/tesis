import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/state/analytics_providers.dart';
import '../../core/utils/format.dart';
import '../../core/state/db_providers.dart';

class NextMonthPredictionCard extends ConsumerWidget {
  const NextMonthPredictionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forecast = ref.watch(nextMonthForecastProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card.filled(
      elevation: 1,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: forecast.when(
          loading: () => const _LoadingRow(),
          error: (e, _) => Center(child: Text('Error en predicción: $e')),
          data: (f) {
            if (!f.hasData) {
              return Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8                  ),
                  Expanded(
                    child: Text(
                      'Sin datos suficientes para predecir el próximo mes.',
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              );
            }

            final bandLow =
            ((f.expenses - f.expensesStdDev).clamp(0, double.infinity))
                .toDouble();
            final bandHigh = (f.expenses + f.expensesStdDev).toDouble();
            final balance = f.balance.toDouble();
            final balanceColor =
            balance >= 0 ? const Color(0xFF2E8B57) : const Color(0xFFAB2D25);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Predicción del próximo mes',
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),

                // Balance proyectado central
                Center(
                  child: Column(
                    children: [
                      Text('Balance Proyectado', style: textTheme.bodySmall),
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
                const SizedBox(height: 6),

                // Texto + barra visual de la banda
                Column(
                  children: [
                    Text(
                      'Banda: ${Fx.money(bandLow)} – ${Fx.money(bandHigh)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _ConfidenceBar(
                      low: bandLow,
                      high: bandHigh,
                      value: balance.abs(),
                      color: balanceColor,
                    ),
                  ],
                ),
                const Divider(height: 24),

                // Gasto / Ingreso
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatColumn(
                      'Gasto',
                      f.expenses,
                      Icons.trending_down,
                      const Color(0xFFAB2D25),
                      textTheme,
                    ),
                    _buildStatColumn(
                      'Ingreso',
                      f.incomes,
                      Icons.trending_up,
                      const Color(0xFF2E8B57),
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

  Widget _buildStatColumn(
      String label,
      double value,
      IconData icon,
      Color color,
      TextTheme textTheme,
      ) {
    return Column(
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
          style: textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}

// Barra visual del rango de confianza con etiquetas mín/máx y marcador animado
class _ConfidenceBar extends StatefulWidget {
  final double low;
  final double high;
  final double value;
  final Color color;

  const _ConfidenceBar({
    required this.low,
    required this.high,
    required this.value,
    required this.color,
    super.key,
  });

  @override
  State<_ConfidenceBar> createState() => _ConfidenceBarState();
}

class _ConfidenceBarState extends State<_ConfidenceBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _ConfidenceBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio =
    ((widget.value - widget.low) / (widget.high - widget.low)).clamp(0.0, 1.0);

    return Column(
      children: [
        SizedBox(
          height: 24,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Banda base (gris claro)
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),

              // Porción coloreada
              FractionallySizedBox(
                widthFactor: ratio,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              // 🔵 Marcador animado
              AnimatedBuilder(
                animation: _animation,
                builder: (_, __) {
                  final width = MediaQuery.of(context).size.width - 64;
                  final pos = (ratio * width * _animation.value)
                      .clamp(0.0, width);
                  return Positioned(
                    left: pos,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.color,
                        border: Border.all(
                          color: scheme.surface,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withOpacity(0.35),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Mín', style: Theme.of(context).textTheme.labelSmall),
            Text('Máx', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}



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
