class MonthlyTotal {
  final int year;
  final int month;
  final double expenses; // valores positivos (gasto absoluto)
  final double incomes;  // valores positivos

  const MonthlyTotal({
    required this.year,
    required this.month,
    required this.expenses,
    required this.incomes,
  });

  DateTime get periodStart => DateTime(year, month, 1);
}
