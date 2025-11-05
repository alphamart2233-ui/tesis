import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as dr;
import '../state/db_providers.dart';
import '../../data/db/app_database.dart';

/// α de la suavización exponencial (0<α<1). 0.4 es un buen punto de partida.
/// En SES, el pronóstico a futuro es el último nivel suavizado.
final forecastAlphaProvider = StateProvider<double>((ref) => 0.4);

/// Cuántos meses hacia atrás usamos como historial (excluye el mes actual)
final forecastHistoryMonthsProvider = StateProvider<int>((ref) => 6);

DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
DateTime _addMonths(DateTime d, int m) => DateTime(d.year, d.month + m, 1);

/// SES / EWMA simple
double _ewma(Iterable<double> values, double alpha) {
  double? s;
  for (final x in values) {
    if (s == null) {
      s = x; // init con el primer valor (también podrías usar media)
    } else {
      s = alpha * x + (1 - alpha) * s;
    }
  }
  return s ?? 0.0;
}

/// Pronóstico por categoría (solo gastos) para el PRÓXIMO mes usando EWMA.
/// Devuelve: { categoryId: predictedAmount }
final categoryForecastProvider =
FutureProvider<Map<int, double>>((ref) async {
  final db = ref.watch(databaseProvider);
  final alpha = ref.watch(forecastAlphaProvider);
  final k = ref.watch(forecastHistoryMonthsProvider);

  final now = DateTime.now();
  final m0 = _monthStart(now);            // inicio del mes actual
  final start = _addMonths(m0, -k);       // k meses atrás (excluye actual)

  // Traer transacciones históricas (k meses) - sin el mes actual
  final txs = await (db.select(db.transactions)
    ..where((t) => t.date.isBiggerOrEqualValue(start))
    ..where((t) => t.date.isSmallerThanValue(m0)))
      .get();

  // Traer categorías para identificar tipo==expense
  final cats = await db.select(db.categories).get();
  final expenseCatIds = {
    for (final c in cats.where((c) => c.type.toLowerCase() == 'expense')) c.id
  };

  // Línea de tiempo de meses (en orden cronológico)
  final months = List.generate(k, (i) => _addMonths(m0, -(k - i)));

  // Agregar gastos por categoría y mes (acumula en positivo)
  final Map<int, List<double>> series = {
    for (final id in expenseCatIds) id: List.filled(k, 0.0)
  };

  for (final t in txs) {
    if (!expenseCatIds.contains(t.categoryId)) continue;
    final d = _monthStart(t.date);
    final idx = months.indexWhere((m) => m.year == d.year && m.month == d.month);
    if (idx == -1) continue;
    final amt = t.amount < 0 ? -t.amount : 0.0; // gasto = negativo => suma en positivo
    series[t.categoryId]![idx] += amt;
  }

  // EWMA por categoría
  final Map<int, double> forecast = {};
  series.forEach((catId, values) {
    forecast[catId] = _ewma(values, alpha);
  });
  return forecast;
});

/// Riesgo vs presupuesto del PRÓXIMO mes (year/month siguiente)
class BudgetRiskItem {
  final Category category;
  final double predicted; // gasto pronosticado
  final double? budget;   // límite (puede ser null si no hay)
  double get ratio => (budget == null || budget == 0) ? 0 : (predicted / budget!);
  BudgetRiskItem({required this.category, required this.predicted, required this.budget});
}

final budgetRiskNextMonthProvider =
FutureProvider<List<BudgetRiskItem>>((ref) async {
  final db = ref.watch(databaseProvider);
  final perCat = await ref.watch(categoryForecastProvider.future);

  final now = DateTime.now();
  final next = now.month == 12 ? DateTime(now.year + 1, 1, 1) : DateTime(now.year, now.month + 1, 1);

  final cats = await db.select(db.categories).get();
  final budgets = await (db.select(db.budgets)
    ..where((b) => b.year.equals(next.year))
    ..where((b) => b.month.equals(next.month)))
      .get();
  final budgetByCat = {for (final b in budgets) b.categoryId: b.limit};

  final items = <BudgetRiskItem>[];
  for (final c in cats.where((c) => c.type.toLowerCase() == 'expense')) {
    final pred = perCat[c.id] ?? 0.0;
    final bud = budgetByCat[c.id];
    items.add(BudgetRiskItem(category: c, predicted: pred, budget: bud));
  }

  // Ordena: mayor riesgo primero (ratio alto), y si no hay budget, al final
  items.sort((a, b) {
    final ar = a.budget == null ? -1.0 : a.ratio;
    final br = b.budget == null ? -1.0 : b.ratio;
    return br.compareTo(ar);
  });

  return items;
});

/// (Opcional) Métrica de error para backtest interno (MAPE).
/// Ignora meses con valor real=0 para evitar división por cero.
/// Útil para evaluar si tu α actual es razonable.
double mape(List<double> actual, List<double> forecast) {
  final pairs = <(double, double)>[];
  for (var i = 0; i < actual.length && i < forecast.length; i++) {
    if (actual[i] == 0) continue;
    pairs.add((actual[i], forecast[i]));
  }
  if (pairs.isEmpty) return 0;
  final err = pairs
      .map((p) => ((p.$1 - p.$2).abs() / p.$1).abs())
      .reduce((a, b) => a + b);
  return 100 * err / pairs.length;
}
