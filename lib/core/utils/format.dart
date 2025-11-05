import 'package:intl/intl.dart';

class Fx {
  static String money(num v) =>
      NumberFormat.currency(locale: 'es_EC', symbol: r'$').format(v);
  static String date(DateTime d) => DateFormat('dd/MM/yyyy').format(d);
}

