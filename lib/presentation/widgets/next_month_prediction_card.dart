import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as dr; // evita conflicto con Column
import '../../core/state/db_providers.dart';
import '../../data/db/app_database.dart';
import '../../core/utils/format.dart';

class NextMonthPredictionCard extends ConsumerWidget {
  const NextMonthPredictionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return FutureBuilder<_PredData>(
      future: _computePrediction(db),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 12),
                  Text('Calculando predicción...'),
                ],
              ),
            ),
          );
        }
        final data = snap.data!;

        if (data.samples.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Aún no hay datos suficientes para predecir el próximo mes.'),
            ),
          );
        }

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Predicción de gasto (próximo mes)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  Fx.money(data.prediction),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: data.samples
                      .map((e) => Chip(
                    label: Text('${e.label}: ${Fx.money(e.value)}'),
                  ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Método: promedio móvil de los últimos 3 meses de gastos.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<_PredData> _computePrediction(AppDatabase db) async {
    final now = DateTime.now();
    final month0 = DateTime(now.year, now.month, 1);        // inicio mes actual
    final start = DateTime(month0.year, month0.month - 3, 1); // 3 meses atrás (excluye mes actual)

    final txs = await (db.select(db.transactions)
      ..where((t) => t.date.isBiggerOrEqualValue(start))
      ..where((t) => t.date.isSmallerThanValue(month0)))
        .get();

    // Agrupa gastos (amount < 0) por YYYY-MM y suma en positivo
    final Map<String, double> perMonth = {};
    for (final t in txs) {
      if (t.amount >= 0) continue; // sólo gastos
      final d = t.date;
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
      perMonth.update(key, (v) => v + (-t.amount), ifAbsent: () => -t.amount);
    }

    // Orden cronológico de los últimos 3 meses previos
    final labels = List.generate(3, (i) {
      final dt = DateTime(month0.year, month0.month - (3 - i), 1);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    });

    final samples = <_Sample>[];
    double sum = 0;
    int n = 0;
    for (final k in labels) {
      final v = perMonth[k] ?? 0.0;
      samples.add(_Sample(k, v));
      sum += v;
      n++;
    }

    final prediction = n == 0 ? 0.0 : (sum / n); // SMA(3)
    return _PredData(prediction: prediction, samples: samples);
  }
}

class _Sample {
  final String label;
  final double value;
  _Sample(this.label, this.value);
}

class _PredData {
  final double prediction;
  final List<_Sample> samples;
  _PredData({required this.prediction, required this.samples});
}
