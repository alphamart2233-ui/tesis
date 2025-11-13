//lib/core/state/filters.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

final selectedMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});
//filtro mensual
final selectedCategoryFilterProvider = StateProvider<int?>((ref) => null);
