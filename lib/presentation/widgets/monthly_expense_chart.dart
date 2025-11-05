import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tesis/data/repositories/transaction_repository.dart';




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
      error: (e, _) =>
          SizedBox(height: 180, child: Center(child: Text('Error: $e'))),
      data: (points) {
        if (points.isEmpty) {
          return const SizedBox(
            height: 180,
            child: Center(child: Text('Sin datos para el gráfico')),
          );
        }
        final spots = <FlSpot>[];
        for (var i = 0; i < points.length; i++) {
          spots.add(FlSpot(i.toDouble(), points[i].total));
        }
        return SizedBox(
          height: 220,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            child: LineChart(
              LineChartData(
                minY: 0,
                gridData: const FlGridData(show: true),
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
                        if (i < 0 || i >= points.length)
                          return const SizedBox.shrink();
                        final mm = points[i].label.substring(5); // MM
                        return Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text(mm, style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    dotData: const FlDotData(show: true),
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
