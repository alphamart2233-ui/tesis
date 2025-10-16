import 'package:intl/intl.dart';

class Fx {
  static final _usd = NumberFormat.simpleCurrency(locale: 'es_EC', name: 'USD');
  static String money(num v) => _usd.format(v);
  static String ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
}
