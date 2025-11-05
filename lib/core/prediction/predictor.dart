import 'dart:math';
import '../../data/models/monthly_total.dart';

class ExpenseForecast {
  final double estimate;
  final double? low;
  final double? high;
  final int horizonMonths; // 1 = próximo mes
  final int nPoints;       // cantidad de meses usados

  ExpenseForecast({
    required this.estimate,
    this.low,
    this.high,
    required this.horizonMonths,
    required this.nPoints,
  });
}

class Predictor {
  /// Promedio móvil simple de los últimos [window] meses.
  static double movingAverage(List<double> ys, {int window = 3}) {
    if (ys.isEmpty) return 0.0;
    final w = min(window, ys.length);
    final sub = ys.sublist(ys.length - w);
    final sum = sub.fold<double>(0.0, (a, b) => a + b);
    return sum / w;
  }

  /// Regresión lineal y = a + b*x sobre x = 0..n-1, pronostica en x = n+(h-1).
  static double linearTrendForecast(List<double> ys, {int horizon = 1}) {
    final n = ys.length;
    if (n == 0) return 0.0;
    if (n == 1) return ys.first;

    double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
    for (int i = 0; i < n; i++) {
      final x = i.toDouble();
      final y = ys[i];
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumXX += x * x;
    }
    final denom = n * sumXX - sumX * sumX;
    final b = denom == 0 ? 0.0 : (n * sumXY - sumX * sumY) / denom;
    final a = (sumY - b * sumX) / n;

    final xFuture = n.toDouble() + (horizon - 1);
    final pred = a + b * xFuture;
    return max(0.0, pred);
  }

  /// Ensamble: tendencia lineal + promedio móvil.
  static ExpenseForecast nextMonthExpense(List<MonthlyTotal> series) {
    final ys = series.map((e) => e.expenses.toDouble()).toList();
    if (ys.isEmpty) {
      return ExpenseForecast(estimate: 0.0, horizonMonths: 1, nPoints: 0);
    }

    final ma = movingAverage(ys, window: 3);
    final lr = linearTrendForecast(ys, horizon: 1);

    final hasHistory = ys.length >= 6;
    final wTrend = hasHistory ? 0.65 : 0.50;
    final wMA = 1 - wTrend;

    final est = max(0.0, wTrend * lr + wMA * ma);

    final spread = ys.length >= 12 ? 0.07 : 0.10;
    final low = max(0.0, est * (1 - spread));
    final high = est * (1 + spread);

    return ExpenseForecast(
      estimate: est,
      low: low,
      high: high,
      horizonMonths: 1,
      nPoints: ys.length,
    );
  }
}
