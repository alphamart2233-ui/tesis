// lib/core/state/category_risk_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as dr;

import '../../data/db/app_database.dart';
import '../state/db_providers.dart';

enum RiskLevel { low, medium, high, noBudget }

class CategoryRisk {
  final Category category;
  final double forecast;   // gasto proyectado (positivo)
  final double? budget;    // límite mensual (null si no hay)
  final double ratio;      // forecast / budget (0 si no hay budget)
  final RiskLevel level;

  CategoryRisk({
    required this.category,
    required this.forecast,
    required this.budget,
    required this.ratio,
    required this.level,
  });
}

/// Suavizado exponencial simple (SES) para series mensuales
double _ses(List<double> xs, {double alpha = 0.6}) {
  if (xs.isEmpty) return 0;
  double f = xs.first;
  for (int i = 1; i < xs.length; i++) {
    f = alpha * xs[i] + (1 - alpha) * f;
  }
  return f;
}

/// Construye series de gasto mensual por categoría (sólo categorías de tipo 'expense').
/// Usa JOIN con categories para evitar transacciones huérfanas y filtra por rango.
Future<Map<int, double>> _categoryMonthlyExpenseSeries(
    AppDatabase db, {
      required int year,
      required int month,
      int lookbackMonths = 6,
    }) async {
  final firstOfTarget = DateTime(year, month, 1);
  final firstLookback = DateTime(year, month - lookbackMonths, 1);
  final firstOfNext   = DateTime(year, month + 1, 1);

  final t = db.transactions;
  final c = db.categories;

  // JOIN categories → asegura existencia de categoría y type == 'expense'
  final rows = await (db.select(t).join([
    dr.innerJoin(c, c.id.equalsExp(t.categoryId)),
  ])
    ..where(t.date.isBiggerOrEqualValue(firstLookback))
    ..where(t.date.isSmallerThanValue(firstOfNext))
    ..where(c.type.equals('expense')))
      .get();

  // Map<catId, Map<(y,m), sumaGastoPositivo>>
  final Map<int, Map<(int,int), double>> perCat = {};
  for (final row in rows) {
    final tx  = row.readTable(t);
    final cat = row.readTable(c);

    if (tx.amount >= 0) continue; // sólo gastos
    final key = (tx.date.year, tx.date.month);

    perCat.putIfAbsent(cat.id, () => {});
    perCat[cat.id]!.update(key, (v) => v + (-tx.amount), ifAbsent: () => -tx.amount);
  }

  // Serie cronológica de lookbackMonths por categoría y pronóstico SES
  final Map<int, double> forecastByCat = {};
  for (final entry in perCat.entries) {
    final catId = entry.key;
    final monthMap = entry.value;

    final series = <double>[];
    for (int i = lookbackMonths; i >= 1; i--) {
      final dt  = DateTime(firstOfTarget.year, firstOfTarget.month - i, 1);
      final key = (dt.year, dt.month);
      series.add(monthMap[key] ?? 0.0);
    }
    forecastByCat[catId] = _ses(series, alpha: 0.6);
  }

  return forecastByCat;
}

/// Carga presupuestos definidos para (year, month).
Future<Map<int, double>> _budgetsForMonth(
    AppDatabase db, {
      required int year,
      required int month,
    }) async {
  final bs = await db.budgetsOf(year, month);
  return { for (final b in bs) b.categoryId: b.limit };
}

RiskLevel _level(double forecast, double? budget) {
  if (budget == null || budget <= 0) return RiskLevel.noBudget;
  final r = forecast / budget;
  if (r >= 1.10) return RiskLevel.high;     // >110% del límite
  if (r >= 0.80) return RiskLevel.medium;   // 80–110%
  return RiskLevel.low;                      // <80%
}

/// Proveedor principal: devuelve la lista ordenada de riesgos por categoría
final categoryRiskProvider = FutureProvider.family<List<CategoryRisk>, DateTime>((ref, selectedMonth) async {
  final db = ref.watch(databaseProvider);

  final year  = selectedMonth.year;
  final month = selectedMonth.month;

  // Carga todas las categorías (para poder devolver el objeto Category completo)
  final allCats = await db.select(db.categories).get();
  final catsById = { for (final c in allCats) c.id: c };

  final forecastByCat = await _categoryMonthlyExpenseSeries(
    db, year: year, month: month, lookbackMonths: 6,
  );
  final budgetsByCat  = await _budgetsForMonth(
    db, year: year, month: month,
  );

  // Solo categorías de gasto
  final expenseCats = allCats.where((c) => c.type == 'expense');

  final List<CategoryRisk> items = [];
  for (final c in expenseCats) {
    final f = forecastByCat[c.id] ?? 0.0;
    final b = budgetsByCat[c.id];
    final lvl = _level(f, b);
    final ratio = (b == null || b == 0) ? 0.0 : (f / b);
    items.add(CategoryRisk(
      category: c,
      forecast: f,
      budget: b,
      ratio: ratio,
      level: lvl,
    ));
  }

  // Orden: high → medium → low → noBudget, y dentro por ratio descendente
  const prio = {
    RiskLevel.high: 0,
    RiskLevel.medium: 1,
    RiskLevel.low: 2,
    RiskLevel.noBudget: 3,
  };
  items.sort((a, b) {
    final byLvl = prio[a.level]!.compareTo(prio[b.level]!);
    if (byLvl != 0) return byLvl;
    return b.ratio.compareTo(a.ratio);
  });

  return items;
});
