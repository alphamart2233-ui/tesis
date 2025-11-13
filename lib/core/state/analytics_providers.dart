// lib/core/state/analytics_providers.dart
import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/db/app_database.dart';
import '../state/db_providers.dart';
import '../state/filters.dart';

/// =======================================================
/// CLASES DE DATOS
/// =======================================================

class BudgetRiskItem {
  final String categoryName;
  final double estimate;      // gasto estimado (próx mes relativo al mes seleccionado)
  final double? budgetLimit;  // null => “SIN PRES.”
  double get overBy => (budgetLimit ?? double.infinity) == double.infinity
      ? 0
      : estimate - (budgetLimit ?? 0);

  BudgetRiskItem({
    required this.categoryName,
    required this.estimate,
    required this.budgetLimit,
  });
}

class MonthlySummary {
  final double income;
  final double expense;
  double get balance => income - expense;
  const MonthlySummary({required this.income, required this.expense});
}

class MonthlyPoint {
  final String label; // 'YYYY-MM'
  final double total; // gastos del mes (positivo)
  const MonthlyPoint(this.label, this.total);
}

class BudgetAlert {
  final String categoryName;
  final double estimate; // forecast de gasto (positivo)
  final double limit;    // presupuesto del próximo mes
  const BudgetAlert({required this.categoryName, required this.estimate, required this.limit});
}

class NextMonthForecast {
  final double expenses;      // gastos pronosticados (>0)
  final double incomes;       // ingresos pronosticados (>0)
  double get balance => incomes - expenses;
  final double expensesStdDev;
  final bool hasData;
  final int samples;

  const NextMonthForecast({
    required this.expenses,
    required this.incomes,
    required this.expensesStdDev,
    required this.hasData,
    required this.samples,
  });

  factory NextMonthForecast.empty() => const NextMonthForecast(
    expenses: 0, incomes: 0, expensesStdDev: 0, hasData: false, samples: 0,
  );
}

/// =======================================================
/// FUNCIONES AUXILIARES
/// =======================================================

double _ses(List<double> xs, {double alpha = 0.6}) {
  if (xs.isEmpty) return 0;
  double f = xs.first;
  for (int i = 1; i < xs.length; i++) {
    f = alpha * xs[i] + (1 - alpha) * f;
  }
  return f;
}

double _stdDev(List<double> xs) {
  if (xs.length < 2) return 0;
  final mean = xs.reduce((a,b)=>a+b) / xs.length;
  final varSum = xs.map((v) => (v-mean)*(v-mean)).reduce((a,b)=>a+b);
  final variance = varSum / (xs.length - 1);
  // sqrt newton
  if (variance <= 0) return 0;
  double r = variance, p = 0;
  for (int i=0; i<30 && (r-p).abs()>1e-9; i++) { p = r; r = 0.5*(r + variance/r); }
  return r;
}

DateTime _firstDay(int y, int m) => DateTime(y, m, 1);
DateTime _firstDayNext(int y, int m) => DateTime(y, m + 1, 1);

/// =======================================================
/// PROVIDERS PRINCIPALES
/// =======================================================

/// 1️⃣ Resumen mensual (ingresos, gastos, balance)
final monthlySummaryProvider = FutureProvider<MonthlySummary>((ref) async {
  final db = ref.watch(databaseProvider);
  final sel = ref.watch(selectedMonthProvider);
  final from = _firstDay(sel.year, sel.month);
  final to   = _firstDayNext(sel.year, sel.month);

  final txs = await (db.select(db.transactions)
    ..where((t) => t.date.isBiggerOrEqualValue(from))
    ..where((t) => t.date.isSmallerThanValue(to)))
      .get();

  double inc = 0, exp = 0;
  for (final t in txs) {
    if (t.amount >= 0) inc += t.amount; else exp += -t.amount;
  }
  return MonthlySummary(income: inc, expense: exp);
});

/// 2) Serie de gastos de los últimos 6 meses terminando en el mes seleccionado,
/// opcionalmente filtrada por categoría seleccionada
final monthlyExpenseSeriesProvider = FutureProvider<List<MonthlyPoint>>((ref) async {
  final db = ref.watch(databaseProvider);
  final sel = ref.watch(selectedMonthProvider);
  final selectedCatId = ref.watch(selectedCategoryFilterProvider);

  final first = DateTime(sel.year, sel.month - 5, 1);
  final lastExclusive = DateTime(sel.year, sel.month + 1, 1);

  final txQuery = db.select(db.transactions)
    ..where((t) => t.date.isBiggerOrEqualValue(first))
    ..where((t) => t.date.isSmallerThanValue(lastExclusive));

  // ✅ aplica el filtro por categoría (si se eligió)
  if (selectedCatId != null) {
    txQuery.where((t) => t.categoryId.equals(selectedCatId));
  }

  final txs = await txQuery.get();

  // sumamos sólo gastos por (año, mes)
  final Map<(int, int), double> byYm = {};
  for (final t in txs) {
    if (t.amount >= 0) continue;
    final key = (t.date.year, t.date.month);
    byYm.update(key, (v) => v + (-t.amount), ifAbsent: () => -t.amount);
  }

  // generamos los puntos (6 meses)
  final points = <MonthlyPoint>[];
  for (int i = 5; i >= 0; i--) {
    final d = DateTime(sel.year, sel.month - i, 1);
    final key = (d.year, d.month);
    points.add(MonthlyPoint(
      '${d.year}-${d.month.toString().padLeft(2, '0')}',
      byYm[key] ?? 0.0,
    ));
  }

  return points;
});

/// 📊 Serie de gastos por categoría seleccionada (últimos 6 meses)
final monthlyExpenseSeriesByCategoryProvider =
FutureProvider<List<MonthlyPoint>>((ref) async {
  final db = ref.watch(databaseProvider);
  final sel = ref.watch(selectedMonthProvider);
  final selectedCategoryId = ref.watch(selectedCategoryFilterProvider); // 👈 es int?

  final first = DateTime(sel.year, sel.month - 5, 1);
  final lastExclusive = DateTime(sel.year, sel.month + 1, 1);

  final txsQuery = db.select(db.transactions)
    ..where((t) => t.date.isBiggerOrEqualValue(first))
    ..where((t) => t.date.isSmallerThanValue(lastExclusive));

  if (selectedCategoryId != null) {
    txsQuery.where((t) => t.categoryId.equals(selectedCategoryId)); // ✅ usa el int directamente
  }

  final txs = await txsQuery.get();

  final Map<(int, int), double> byYm = {};
  for (final t in txs) {
    if (t.amount >= 0) continue;
    final key = (t.date.year, t.date.month);
    byYm.update(key, (v) => v + (-t.amount), ifAbsent: () => -t.amount);
  }

  final points = <MonthlyPoint>[];
  for (int i = 5; i >= 0; i--) {
    final d = DateTime(sel.year, sel.month - i, 1);
    final key = (d.year, d.month);
    points.add(
      MonthlyPoint('${d.year}-${d.month.toString().padLeft(2, '0')}',
          byYm[key] ?? 0),
    );
  }
  return points;
});

/// 3️⃣ Últimas transacciones del mes seleccionado (con filtro por categoría)
final latestByMonthProvider = FutureProvider<List<(Transaction, Category)>>((ref) async {
  final db = ref.watch(databaseProvider);
  final sel = ref.watch(selectedMonthProvider);
  final selectedCatId = ref.watch(selectedCategoryFilterProvider);

  final from = _firstDay(sel.year, sel.month);
  final to   = _firstDayNext(sel.year, sel.month);

  final t = db.transactions;
  final q = db.select(t)
    ..where((tt) => tt.date.isBiggerOrEqualValue(from))
    ..where((tt) => tt.date.isSmallerThanValue(to))
    ..orderBy([(tt) => OrderingTerm(expression: tt.date, mode: OrderingMode.desc)]);

  if (selectedCatId != null) {
    q.where((tt) => tt.categoryId.equals(selectedCatId));
  }

  final txs = await q.get();

  final cats = await db.select(db.categories).get();
  final byId = {for (final c in cats) c.id: c};

  return [
    for (final t in txs)
      if (byId[t.categoryId] != null) (t, byId[t.categoryId]!)
  ];
});

/// 4️⃣ Estimación de gasto por categoría (para próximo mes)
final nextMonthExpenseEstimatesProvider = FutureProvider<List<(String,double)>>((ref) async {
  final db = ref.watch(databaseProvider);
  final sel = ref.watch(selectedMonthProvider);

  final first = DateTime(sel.year, sel.month - 5, 1);
  final end   = _firstDayNext(sel.year, sel.month);

  final txs = await (db.select(db.transactions)
    ..where((t) => t.date.isBiggerOrEqualValue(first))
    ..where((t) => t.date.isSmallerThanValue(end)))
      .get();

  final cats = await db.select(db.categories).get();
  final expenseIds = {for (final c in cats.where((c) => c.type == 'expense')) c.id: c.name};

  // Serie mensual ordenada por categoría
  final Map<int, Map<(int,int), double>> acc = {};
  for (final t in txs) {
    if (t.amount >= 0) continue;
    if (!expenseIds.containsKey(t.categoryId)) continue;
    final key = (t.date.year, t.date.month);
    acc.putIfAbsent(t.categoryId, () => {});
    acc[t.categoryId]!.update(key, (v) => v + (-t.amount), ifAbsent: () => -t.amount);
  }

  final estimates = <(String,double)>[];
  for (final catId in acc.keys) {
    final series = <double>[];
    for (int i = 6; i >= 1; i--) {
      final d = DateTime(sel.year, sel.month - i + 1, 1);
      series.add(acc[catId]![(d.year, d.month)] ?? 0.0);
    }
    final forecast = _ses(series, alpha: 0.6);
    estimates.add((expenseIds[catId] ?? '—', forecast));
  }

  // Agregar categorías sin historial
  for (final entry in expenseIds.entries) {
    if (!acc.containsKey(entry.key)) {
      estimates.add((entry.value, 0.0));
    }
  }

  estimates.sort((a, b) => b.$2.compareTo(a.$2));
  return estimates;
});

/// 5️⃣ Categorías en riesgo de sobrepasar presupuesto (alertas)
final budgetAlertsProvider = FutureProvider<List<BudgetAlert>>((ref) async {
  final db = ref.watch(databaseProvider);
  final sel = ref.watch(selectedMonthProvider);
  final next = DateTime(sel.year, sel.month + 1, 1);

  final forecasts = await ref.watch(nextMonthExpenseEstimatesProvider.future);

  final budgets = await (db.select(db.budgets)
    ..where((b) => b.year.equals(next.year))
    ..where((b) => b.month.equals(next.month)))
      .get();

  final cats = await db.select(db.categories).get();
  final idByName = {for (final c in cats) c.name: c.id};
  final limitById = {for (final b in budgets) b.categoryId: b.limit};

  final out = <BudgetAlert>[];
  for (final (name, est) in forecasts) {
    final id = idByName[name];
    if (id == null) continue;
    final lim = limitById[id];
    if (lim == null) continue;
    if (est > lim) out.add(BudgetAlert(categoryName: name, estimate: est, limit: lim));
  }

  out.sort((a, b) => (b.estimate - b.limit).compareTo(a.estimate - a.limit));
  return out;
});

/// 6️⃣ Pronóstico global de ingresos y gastos (SES)
Future<List<({int y,int m,double expenses,double incomes})>> _historyMonthly(
    AppDatabase db, {
      required DateTime endExclusive,
      int lookbackMonths = 6,
    }) async {
  final first = DateTime(endExclusive.year, endExclusive.month - lookbackMonths, 1);
  final txs = await (db.select(db.transactions)
    ..where((t) => t.date.isBiggerOrEqualValue(first))
    ..where((t) => t.date.isSmallerThanValue(endExclusive)))
      .get();

  final Map<(int,int), ({double inc,double exp})> acc = {};
  for (final t in txs) {
    final key = (t.date.year, t.date.month);
    final cur = acc[key] ?? (inc:0.0, exp:0.0);
    if (t.amount >= 0) {
      acc[key] = (inc: cur.inc + t.amount, exp: cur.exp);
    } else {
      acc[key] = (inc: cur.inc, exp: cur.exp + (-t.amount));
    }
  }

  final out = <({int y,int m,double expenses,double incomes})>[];
  for (int i = lookbackMonths; i >= 1; i--) {
    final d = DateTime(endExclusive.year, endExclusive.month - i, 1);
    final v = acc[(d.year, d.month)] ?? (inc:0.0, exp:0.0);
    out.add((y:d.year, m:d.month, expenses:v.exp, incomes:v.inc));
  }
  return out;
}

final nextMonthForecastProvider = FutureProvider<NextMonthForecast>((ref) async {
  final db  = ref.watch(databaseProvider);
  final sel = ref.watch(selectedMonthProvider);
  final end = DateTime(sel.year, sel.month + 1, 1);

  final hist = await _historyMonthly(db, endExclusive: end, lookbackMonths: 6);
  if (hist.isEmpty) return NextMonthForecast.empty();

  final expenses = hist.map((e) => e.expenses).toList();
  final incomes  = hist.map((e) => e.incomes).toList();

  if (expenses.every((e) => e == 0) && incomes.every((e) => e == 0)) {
    return NextMonthForecast.empty();
  }

  final expForecast = _ses(expenses, alpha: 0.6);
  final incForecast = _ses(incomes,  alpha: 0.6);
  final std = _stdDev(expenses);

  return NextMonthForecast(
    expenses: expForecast,
    incomes:  incForecast,
    expensesStdDev: std,
    hasData: true,
    samples: hist.length,
  );
});
