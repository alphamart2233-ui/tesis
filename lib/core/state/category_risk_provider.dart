// lib/core/state/category_risk_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as dr;
import 'package:rxdart/rxdart.dart';

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

/// SES simple para series mensuales
double _ses(List<double> xs, {double alpha = 0.6}) {
  if (xs.isEmpty) return 0;
  double f = xs.first;
  for (int i = 1; i < xs.length; i++) {
    f = alpha * xs[i] + (1 - alpha) * f;
  }
  return f;
}

RiskLevel _level(double forecast, double? budget) {
  if (budget == null || budget <= 0) return RiskLevel.noBudget;
  final r = forecast / budget;
  if (r >= 1.10) return RiskLevel.high;     // >110%
  if (r >= 0.80) return RiskLevel.medium;   // 80–110%
  return RiskLevel.low;                     // <80%
}

/// ------------------------------
/// PROVEEDOR REACTIVO PRINCIPAL
/// ------------------------------
/// Emite una lista de CategoryRisk ordenada. Se actualiza cuando cambian:
/// - transacciones (gastos)
/// - categorías
/// - presupuestos del (year, month)
final categoryRiskProvider =
StreamProvider.family<List<CategoryRisk>, DateTime>((ref, selectedMonth) {
  final db = ref.watch(databaseProvider);
  final year = selectedMonth.year;
  final month = selectedMonth.month;

  // 1) Streams base (reactivos con .watch)
  final categories$ = db.select(db.categories).watch(); // todas las categorías
  final budgets$ = (db.select(db.budgets)
    ..where((b) => b.year.equals(year))
    ..where((b) => b.month.equals(month)))
      .watch(); // presupuestos del mes

  // Transacciones de lookback (gastos) + join categorías para filtrar type='expense'
  const lookbackMonths = 6;
  final firstOfTarget = DateTime(year, month, 1);
  final firstLookback = DateTime(year, month - lookbackMonths, 1);
  final firstOfNext = DateTime(year, month + 1, 1);

  final t = db.transactions;
  final c = db.categories;

  final txJoin$ = (db.select(t).join([
    dr.innerJoin(c, c.id.equalsExp(t.categoryId)),
  ])
    ..where(t.date.isBiggerOrEqualValue(firstLookback))
    ..where(t.date.isSmallerThanValue(firstOfNext))
    ..where(c.type.equals('expense')))
      .watch(); // <-- REACTIVO

  // 2) Combinamos 3 streams y computamos riesgos
  return Rx.combineLatest3<List<Category>, List<Budget>, List<dr.TypedResult>,
      List<CategoryRisk>>(categories$, budgets$, txJoin$, (cats, budgets, rows) {
    final expenseCats = cats.where((cc) => cc.type == 'expense').toList();
    final catsById = {for (final c0 in cats) c0.id: c0};
    final budgetsByCat = {for (final b in budgets) b.categoryId: b.limit};

    // Serie mensual por categoría
    final Map<int, Map<(int, int), double>> perCat = {};
    for (final row in rows) {
      final tx = row.readTable(t);
      final cat = row.readTable(c);
      if (tx.amount >= 0) continue;
      final key = (tx.date.year, tx.date.month);
      perCat.putIfAbsent(cat.id, () => {});
      perCat[cat.id]!
          .update(key, (v) => v + (-tx.amount), ifAbsent: () => -tx.amount);
    }

    // Pronóstico SES (lookbackMonths)
    final Map<int, double> forecastByCat = {};
    for (final catId in perCat.keys) {
      final monthMap = perCat[catId]!;
      final series = <double>[];
      for (int i = lookbackMonths; i >= 1; i--) {
        final dt = DateTime(firstOfTarget.year, firstOfTarget.month - i, 1);
        series.add(monthMap[(dt.year, dt.month)] ?? 0.0);
      }
      forecastByCat[catId] = _ses(series, alpha: 0.6);
    }

    // Construimos riesgos
    final List<CategoryRisk> items = [];
    for (final cat in expenseCats) {
      final f = forecastByCat[cat.id] ?? 0.0;
      final b = budgetsByCat[cat.id];
      final lvl = _level(f, b);
      final ratio = (b == null || b == 0) ? 0.0 : (f / b);
      items.add(CategoryRisk(
        category: catsById[cat.id] ?? cat,
        forecast: f,
        budget: b,
        ratio: ratio,
        level: lvl,
      ));
    }

    // Orden: high → medium → low → noBudget; dentro, ratio desc.
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
});
