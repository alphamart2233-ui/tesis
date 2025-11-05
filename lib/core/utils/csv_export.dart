import 'dart:io';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

Future<File> exportTransactionsToCsv(List<Map<String, dynamic>> rows) async {
  // Crear formato
  final formatter = DateFormat('yyyy-MM-dd HH:mm');
  final headers = ['Fecha', 'Categoría', 'Monto', 'Nota'];

  final data = [
    headers,
    ...rows.map((r) => [
      formatter.format(r['date'] as DateTime),
      r['category'] ?? '',
      (r['amount'] as num).toStringAsFixed(2),
      r['note'] ?? '',
    ]),
  ];

  final csv = const ListToCsvConverter().convert(data);

  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/fintrack_export.csv');
  await file.writeAsString(csv);

  return file;
}
