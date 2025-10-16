import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mes seleccionado (normalizado al día 1)
final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});
