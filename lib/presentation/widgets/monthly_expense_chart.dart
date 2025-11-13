//lib/presentation/widgets/monthly_expense_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tesis/core/state/analytics_providers.dart';

class MonthlyExpenseChart extends ConsumerWidget {
  const MonthlyExpenseChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(monthlyExpenseSeriesProvider);

    return series.when(
      loading: () => const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => SizedBox(
        height: 180,
        child: Center(child: Text('Error: $e')),
      ),
      data: (points) {
        if (points.isEmpty) {
          return const SizedBox(
            height: 180,
            child: Center(child: Text('Sin datos para el gráfico')),
          );
        }

        final spots = <FlSpot>[
          for (var i = 0; i < points.length; i++)
            FlSpot(i.toDouble(), -points[i].total.toDouble()) // 👈 signo negativo aquí

        ];

        return SizedBox(
          height: 220,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: LineChart(
              LineChartData(
                minY: null, // deja fl_chart decidir
                gridData: const FlGridData(show: true),
                borderData: FlBorderData(show: true),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (touchedSpot) => Theme.of(context).colorScheme.primary.withOpacity(0.9),
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      tooltipMargin: 12,
                      getTooltipItems: (spots) => spots.map((spot) {
                        final i = spot.x.toInt();
                        final month = points[i].label;
                        final value = points[i].total.toStringAsFixed(2);
                        return LineTooltipItem(
                          '$month\n\$ $value',
                          const TextStyle(color: Colors.white),
                        );
                      }).toList(),
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                    ),
                  ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 38),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= points.length) {
                          return const SizedBox.shrink();
                        }
                        final mm = points[i].label.substring(5); // MM
                        return Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(mm, style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Theme.of(context).colorScheme.primary,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(show: false),
                    isStrokeCapRound: true,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
