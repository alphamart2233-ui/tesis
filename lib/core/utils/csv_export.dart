import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/db/app_database.dart';

/// Exporta TODAS las transacciones (con nombre y tipo de categoría) a CSV.
/// Retorna la ruta absoluta del archivo creado.
Future<String> exportAllTransactionsToCsv(AppDatabase db) async {
  // Join para tener tx + categoría
  final query = (db.select(db.transactions)).join([
    leftOuterJoin(
      db.categories,
      db.categories.id.equalsExp(db.transactions.categoryId),
    ),
  ]);

  final joined = await query.get();

  // Construir CSV manual (sin paquetes), escapando comas y comillas
  final sb = StringBuffer();
  sb.writeln('id,amount,category_name,category_type,date,note');

  String esc(String? v) {
    if (v == null) return '';
    final s = v.replaceAll('"', '""'); // escapar comillas
    return '"$s"'; // envolver en comillas por si hay comas
  }

  for (final row in joined) {
    final tx = row.readTable(db.transactions);
    final cat = row.readTable(db.categories);

    final id = tx.id.toString();
    final amount = tx.amount.toString();
    final categoryName = esc(cat.name);
    final categoryType = esc(cat.type);
    final date = esc(tx.date.toIso8601String());
    final note = esc(tx.note);

    sb.writeln([id, amount, categoryName, categoryType, date, note].join(','));
  }

  // Guardar en Documents de la app con timestamp
  final dir = await getApplicationDocumentsDirectory();
  final ts = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final filePath = p.join(dir.path, 'fintrack_export_$ts.csv');
  final file = File(filePath);
  await file.writeAsString(sb.toString(), flush: true);
  return filePath;
}
