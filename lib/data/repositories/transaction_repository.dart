import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart'; // equals(), &, etc.

import '../db/app_database.dart';
import '../db/daos/transaction_dao.dart';
import '../../main.dart';
import '../../domain/services/prediction_service.dart';
import '../../core/state/filters.dart';

/// ------------------------------
/// DAO Provider
/// ------------------------------
final transactionDaoProvider = Provider<TransactionDao>((ref) {
  final db = ref.watch(databaseProvider);
  return TransactionDao(db);
});

/// ------------------------------
/// Últimos movimientos (stream general)
/// ------------------------------
final latestTransactionsProvider =
    StreamProvider<List<(Transaction, Category)>>((ref) {
      final dao = ref.watch(transactionDaoProvider);
      return dao.watchLatest(limit: 50);
    });

/// ------------------------------
/// Serie mensual para gráfico de gastos (6 meses terminando en el mes seleccionado)
/// ------------------------------
class MonthlyPoint {
  final String label; // 'YYYY-MM'
  final double total; // total de gastos del mes
  MonthlyPoint(this.label, this.total);
}

final monthlyExpenseSeriesProvider = StreamProvider<List<MonthlyPoint>>((
  ref,
) async* {
  final dao = ref.watch(transactionDaoProvider);
  final sel = ref.watch(selectedMonthProvider); // mes elegido (día 1)

  // Ventana fija de 6 meses: sel -5 ... sel
  final end = DateTime(sel.year, sel.month, 1);
  final months = List.generate(6, (i) {
    final d = DateTime(end.year, end.month - (5 - i), 1); // antiguo -> reciente
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
  });

  // Mapa con ceros por defecto para incluir meses sin datos
  final Map<String, double> byMonth = {for (final k in months) k: 0.0};

  await for (final rows in dao.watchLatest(limit: 2000)) {
    // Reinicia conteos dentro de la ventana
    for (final k in byMonth.keys) {
      byMonth[k] = 0.0;
    }
    for (final (tx, cat) in rows) {
      if (cat.type != 'expense') continue;
      final key = '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
      if (byMonth.containsKey(key)) {
        byMonth[key] = (byMonth[key] ?? 0) + tx.amount;
      }
    }
    yield months
        .map((k) => MonthlyPoint(k, byMonth[k]!))
        .toList(); // 6 puntos exactos
  }
});

/// ------------------------------
/// Servicio de predicción + estimados por categoría (solo gasto)
/// ------------------------------
final predictionServiceProvider = Provider<PredictionService>((ref) {
  final db = ref.watch(databaseProvider);
  return PredictionService(db);
});

/// Devuelve [(nombreCategoria, estimado)] para el próximo mes (solo categorías de GASTO)
final nextMonthExpenseEstimatesProvider =
    FutureProvider<List<(String, double)>>((ref) async {
      final db = ref.watch(databaseProvider);
      final svc = ref.watch(predictionServiceProvider);
      final estimates = await svc.estimateNextMonthByCategory();

      // Catálogo de categorías
      final allCats = await db.select(db.categories).get();
      final byId = {for (final c in allCats) c.id: c};

      final result = <(String, double)>[];
      estimates.forEach((catId, value) {
        final cat = byId[catId];
        if (cat == null) return;
        if (cat.type != 'expense') return;
        result.add((cat.name, value));
      });

      // Orden descendente por estimado
      result.sort((a, b) => b.$2.compareTo(a.$2));
      return result;
    });

/// ------------------------------
/// Alertas: estimado (próximo mes) > presupuesto (próximo mes)
/// ------------------------------
class BudgetAlert {
  final String categoryName;
  final double estimate;
  final double limit;
  double get overBy => estimate - limit;
  BudgetAlert({
    required this.categoryName,
    required this.estimate,
    required this.limit,
  });
}

final budgetAlertsProvider = FutureProvider<List<BudgetAlert>>((ref) async {
  final db = ref.watch(databaseProvider);
  final svc = ref.watch(predictionServiceProvider);

  // Estimados por categoría (próximo mes)
  final estimates = await svc.estimateNextMonthByCategory();

  // Próximo mes (año/mes)
  final now = DateTime.now();
  final next = DateTime(now.year, now.month + 1, 1);
  final year = next.year;
  final month = next.month;

  // Presupuestos de ese mes
  final budgets = await (db.select(
    db.budgets,
  )..where((b) => b.year.equals(year) & b.month.equals(month))).get();

  if (budgets.isEmpty) return [];

  // Catálogo de categorías
  final cats = await db.select(db.categories).get();
  final byId = {for (final c in cats) c.id: c};

  final alerts = <BudgetAlert>[];
  for (final b in budgets) {
    final cat = byId[b.categoryId];
    if (cat == null) continue;
    if (cat.type != 'expense') continue; // solo gastos
    final est = estimates[b.categoryId] ?? 0.0;
    if (est > b.limit) {
      alerts.add(
        BudgetAlert(categoryName: cat.name, estimate: est, limit: b.limit),
      );
    }
  }
  alerts.sort((a, b) => b.overBy.compareTo(a.overBy));
  return alerts;
});

/// ------------------------------
/// Resumen mensual (ingresos, gastos, balance) usando el mes seleccionado
/// ------------------------------
final monthlySummaryProvider = StreamProvider<_MonthlySummary>((ref) async* {
  final dao = ref.watch(transactionDaoProvider);
  final sel = ref.watch(selectedMonthProvider); // mes elegido
  final ymKey = '${sel.year}-${sel.month.toString().padLeft(2, '0')}';

  await for (final rows in dao.watchLatest(limit: 1000)) {
    double income = 0, expense = 0;
    for (final (tx, cat) in rows) {
      final k = '${tx.date.year}-${tx.date.month.toString().padLeft(2, '0')}';
      if (k != ymKey) continue;
      if (cat.type == 'income') {
        income += tx.amount;
      } else if (cat.type == 'expense') {
        expense += tx.amount;
      }
    }
    yield _MonthlySummary(
      year: sel.year,
      month: sel.month,
      income: income,
      expense: expense,
    );
  }
});

class _MonthlySummary {
  final int year;
  final int month;
  final double income;
  final double expense;
  double get balance => income - expense;
  _MonthlySummary({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
  });
}

/// ------------------------------
/// Últimos movimientos filtrados por el mes seleccionado
/// ------------------------------
final latestByMonthProvider = StreamProvider<List<(Transaction, Category)>>((
  ref,
) async* {
  final baseStream = ref.watch(latestTransactionsProvider.stream);
  final sel = ref.watch(selectedMonthProvider);
  final y = sel.year, m = sel.month;

  await for (final rows in baseStream) {
    final filtered = rows
        .where((e) => e.$1.date.year == y && e.$1.date.month == m)
        .toList();
    yield filtered;
  }
});
