// lib/presentation/analytics/analytics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/state/db_providers.dart';
import '../../core/state/filters.dart';
import '../../core/utils/format.dart';
import '../../core/state/analytics_providers.dart';
import '../../data/db/app_database.dart';


class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final summary = ref.watch(monthlySummaryProvider);
    final series = ref.watch(monthlyExpenseSeriesProvider);
    final predictions = ref.watch(nextMonthExpenseEstimatesProvider);
    final alerts = ref.watch(budgetAlertsProvider);
    final selectedCategory = ref.watch(selectedCategoryFilterProvider);
    final db = ref.watch(databaseProvider);


    return Scaffold(
      appBar: AppBar(title: const Text('Análisis financiero')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(monthlySummaryProvider);
          ref.invalidate(monthlyExpenseSeriesProvider);
          ref.invalidate(nextMonthExpenseEstimatesProvider);
          ref.invalidate(budgetAlertsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // 1️⃣ Resumen mensual
            summary.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (data) {
                return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0.3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Resumen del mes',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _summaryItem('Ingresos', data.income,
                                Icons.trending_up, scheme.primary),
                            _summaryItem('Gastos', data.expense,
                                Icons.trending_down, scheme.error),
                            _summaryItem('Balance', data.balance,
                                Icons.account_balance_wallet,
                                data.balance >= 0
                                    ? scheme.primary
                                    : scheme.error),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),
            // 2️⃣ Filtro por categoría
            _CategoryFilterRow(selectedCategory: selectedCategory),

            const SizedBox(height: 16),

            // 2️⃣ Alertas de presupuesto
            alerts.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (items) {
                if (items.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0.3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('⚠️ Categorías en riesgo de sobrepasar presupuesto',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ...items.map((a) {
                          final diff = a.estimate - a.limit;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(a.categoryName),
                                Text(
                                  '+${Fx.money(diff)}',
                                  style: TextStyle(
                                    color: scheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 16),


            // 3️⃣ Gráfico de tendencia mensual
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 0.3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Tendencia de gastos (últimos 6 meses)',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 220,
                      child: series.when(
                        loading: () =>
                        const Center(child: CircularProgressIndicator()),
                        error: (e, _) => Center(child: Text('Error: $e')),
                        data: (points) {
                          double? selectedX;
                          return StatefulBuilder(
                            builder: (context, setState) {
                              return LineChart(
                                LineChartData(
                                  lineTouchData: LineTouchData(
                                    handleBuiltInTouches: true,
                                    touchCallback: (event, response) {
                                      if (!event.isInterestedForInteractions ||
                                          response?.lineBarSpots == null) {
                                        setState(() => selectedX = null);
                                        return;
                                      }
                                      final spot =
                                          response!.lineBarSpots!.first;
                                      setState(() => selectedX = spot.x);
                                    },
                                    touchTooltipData: LineTouchTooltipData(
                                      tooltipBorderRadius: BorderRadius.circular(8),
                                    tooltipPadding: const EdgeInsets.all(8),
                                    tooltipMargin: 12,
                                    getTooltipItems: (touchedSpots) {
                                      return touchedSpots.map((spot) {
                                        final idx = spot.x.toInt();
                                        return LineTooltipItem(
                                          '${points[idx].label}\n${Fx.money(points[idx].total)}',
                                          const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        );
                                      }).toList();
                                    },
                                  ),

                                  ),
                                  gridData: FlGridData(show: false),
                                  borderData: FlBorderData(show: false),
                                  titlesData: FlTitlesData(
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 24,
                                        getTitlesWidget: (value, _) {
                                          final i = value.toInt();
                                          if (i < 0 || i >= points.length) {
                                            return const SizedBox();
                                          }
                                          return Padding(
                                            padding:
                                            const EdgeInsets.only(top: 6),
                                            child: Text(
                                              points[i]
                                                  .label
                                                  .substring(5), // mes
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: selectedX == i
                                                    ? scheme.primary
                                                    : scheme
                                                    .onSurfaceVariant,
                                                fontWeight: selectedX == i
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles:
                                      SideTitles(showTitles: false),
                                    ),
                                    topTitles: AxisTitles(),
                                    rightTitles: AxisTitles(),
                                  ),
                                  lineBarsData: [
                                    LineChartBarData(
                                      isCurved: true,
                                      color: scheme.primary,
                                      barWidth: 3,
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color:
                                        scheme.primary.withOpacity(0.1),
                                      ),
                                      dotData: FlDotData(
                                        show: true,
                                        getDotPainter:
                                            (spot, percent, bar, index) {
                                          final isSelected =
                                              selectedX == spot.x;
                                          return FlDotCirclePainter(
                                            radius: isSelected ? 6 : 4,
                                            color: isSelected
                                                ? scheme.primary
                                                : scheme.primary
                                                .withOpacity(0.4),
                                            strokeWidth:
                                            isSelected ? 2 : 1,
                                            strokeColor: isSelected
                                                ? scheme.primary
                                                : scheme.primary
                                                .withOpacity(0.3),
                                          );
                                        },
                                      ),
                                      spots: [
                                        for (int i = 0;
                                        i < points.length;
                                        i++)
                                          FlSpot(i.toDouble(),
                                              points[i].total),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 4️⃣ Predicción por categoría
            predictions.when(
              loading: () =>
              const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0.3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Estimación de gastos (próximo mes)',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        ...items.map((e) {
                          final category = e.$1;
                          final amount = e.$2;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    category,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ),
                                Text(
                                  Fx.money(amount),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: amount < 0
                                        ? const Color(0xFFAB2D25) // rojo FinTrack EC
                                        : theme.textTheme.bodyMedium?.color,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(
      String label, double value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(Fx.money(value),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
                fontSize: 16)),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}class _CategoryFilterRow extends ConsumerWidget {
  final int? selectedCategory;
  const _CategoryFilterRow({this.selectedCategory});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final db = ref.watch(databaseProvider);

    return FutureBuilder<List<Category>>(
      future: db.select(db.categories).get(),
      builder: (context, snapshot) {
        final cats = snapshot.data ?? [];
        return Card(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filtrar por categoría',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Todas'),
                      selected: selectedCategory == null,
                      onSelected: (_) => ref
                          .read(selectedCategoryFilterProvider.notifier)
                          .state = null,
                    ),
                    for (final cat in cats)
                      ChoiceChip(
                        label: Text(cat.name),
                        selected: selectedCategory == cat.id,
                        onSelected: (_) => ref
                            .read(selectedCategoryFilterProvider.notifier)
                            .state = cat.id,
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

