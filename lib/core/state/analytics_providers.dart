import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import '../../data/db/app_database.dart';
import '../state/db_providers.dart';

class NextMonthForecast {
  final double expenses;      // gasto positivo
  final double incomes;       // ingreso
  final double balance;       // incomes - expenses
  final double expensesStdDev;
  final bool hasData;         // <-- NUEVO: indica si hay muestras reales
  final int samples;          // <-- NUEVO: cuántos meses usados

  NextMonthForecast({
    required this.expenses,
    required this.incomes,
    required this.balance,
    required this.expensesStdDev,
    required this.hasData,
    required this.samples,
  });

  factory NextMonthForecast.empty() => NextMonthForecast(
    expenses: 0, incomes: 0, balance: 0, expensesStdDev: 0,
    hasData: false, samples: 0,
  );
}

Future<List<({int y, int m, double expenses, double incomes})>>
_historyMonthly(AppDatabase db, {int lookbackMonths = 6}) async {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month - (lookbackMonths - 1), 1);
  final nextOfNow = DateTime(now.year, now.month + 1, 1);

  final txs = await (db.select(db.transactions)
    ..where((t) => t.date.isBiggerOrEqualValue(first))
    ..where((t) => t.date.isSmallerThanValue(nextOfNow)))
      .get();

  final groups = groupBy(txs, (t) => (t.date.year, t.date.month));
  final list = <({int y, int m, double expenses, double incomes})>[];

  for (final entry in groups.entries) {
    final (y, m) = entry.key;
    final monthTxs = entry.value;
    double inc = 0, exp = 0;
    for (final t in monthTxs) {
      if (t.amount >= 0) inc += t.amount;
      else exp += -t.amount; // gasto positivo
    }
    list.add((y: y, m: m, expenses: exp, incomes: inc));
  }
  list.sort((a, b) => DateTime(a.y, a.m, 1).compareTo(DateTime(b.y, b.m, 1)));
  return list;
}

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
  return _sqrt(varSum / (xs.length - 1));
}

double _sqrt(double x) {
  if (x <= 0) return 0;
  double r = x, p = 0;
  for (int i=0; i<30 && (r-p).abs() > 1e-9; i++) { p = r; r = 0.5*(r + x/r); }
  return r;
}

final nextMonthForecastProvider = FutureProvider<NextMonthForecast>((ref) async {
  final db = ref.watch(databaseProvider);
  final hist = await _historyMonthly(db, lookbackMonths: 6);
  if (hist.isEmpty) return NextMonthForecast.empty();

  final expenses = hist.map((e) => e.expenses).toList();
  final incomes  = hist.map((e) => e.incomes).toList();
  final totalExp = expenses.fold<double>(0, (a,b)=>a+b);
  final totalInc = incomes.fold<double>(0, (a,b)=>a+b);

  // Si todo es 0, no hay datos útiles
  if (totalExp == 0 && totalInc == 0) {
    return NextMonthForecast.empty();
  }

  final expForecast = _ses(expenses, alpha: 0.6);
  final incForecast = _ses(incomes,  alpha: 0.6);
  final std         = _stdDev(expenses);

  return NextMonthForecast(
    expenses: expForecast,
    incomes: incForecast,
    balance: incForecast - expForecast,
    expensesStdDev: std,
    hasData: true,
    samples: hist.length,
  );
});
