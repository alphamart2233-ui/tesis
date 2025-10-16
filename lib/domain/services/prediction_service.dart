import '../../data/db/app_database.dart';

class PredictionService {
  final AppDatabase db;
  PredictionService(this.db);

  /// Retorna {categoryId: montoEstimado} para el próximo mes
  Future<Map<int, double>> estimateNextMonthByCategory() async {
    final txs = await (db.select(db.transactions)).get();

    // Agrupar por mes y categoría
    final Map<int, Map<String, double>> monthlyByCat = {};
    for (final t in txs) {
      final key = '${t.date.year}-${t.date.month.toString().padLeft(2, '0')}';
      final catId = t.categoryId;
      monthlyByCat.putIfAbsent(catId, () => {});
      monthlyByCat[catId]![key] = (monthlyByCat[catId]![key] ?? 0) + t.amount;
    }

    final Map<int, double> estimates = {};
    for (final entry in monthlyByCat.entries) {
      final series = entry.value.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final values = series.map((e) => e.value).toList();
      if (values.isEmpty) continue;

      // Media móvil (3) o promedio si hay <3
      final mm3 = values.length >= 3
          ? (values.sublist(values.length - 3).reduce((a, b) => a + b)) / 3.0
          : (values.reduce((a, b) => a + b)) / values.length;

      // Suavizado exponencial simple α=0.3
      const alpha = 0.3;
      double? s;
      for (final v in values) {
        s = (s == null) ? v : alpha * v + (1 - alpha) * s;
      }
      final ses = s ?? values.last;

      estimates[entry.key] = (mm3 + ses) / 2.0;
    }

    return estimates;
  }
}
