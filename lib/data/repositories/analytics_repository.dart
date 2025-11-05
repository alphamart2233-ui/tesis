import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Variable; // ← importante
import '../db/app_database.dart';
import '../models/monthly_total.dart';

class AnalyticsRepository {
  final AppDatabase db;
  AnalyticsRepository(this.db);

  Future<List<MonthlyTotal>> fetchMonthlyTotals({int monthsBack = 18}) async {
    final rows = await db.customSelect(
      '''
      SELECT 
        CAST(strftime('%Y', date) AS INT) AS y,
        CAST(strftime('%m', date) AS INT) AS m,
        SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS expenses,
        SUM(CASE WHEN amount >= 0 THEN amount ELSE 0 END) AS incomes
      FROM transactions
      GROUP BY y, m
      ORDER BY y DESC, m DESC
      LIMIT ?
      ''',
      variables: [Variable.withInt(monthsBack)],
      readsFrom: {db.transactions},
    ).get();

    final list = rows.map((r) {
      return MonthlyTotal(
        year: r.data['y'] as int,
        month: r.data['m'] as int,
        expenses: (r.data['expenses'] as num?)?.toDouble() ?? 0.0,
        incomes: (r.data['incomes'] as num?)?.toDouble() ?? 0.0,
      );
    }).toList();

    return list.sorted((a, b) => a.periodStart.compareTo(b.periodStart));
  }
}
