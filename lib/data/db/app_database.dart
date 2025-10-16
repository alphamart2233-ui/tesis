import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'income' | 'expense'
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
}

class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get year => integer()();
  IntColumn get month => integer()(); // 1..12
  RealColumn get limit => real()();
}

@DriftDatabase(tables: [Categories, Transactions, Budgets])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<void> seed() async {
    final current = await (select(categories)).get();
    if (current.isEmpty) {
      await into(categories).insert(
        CategoriesCompanion.insert(name: 'Alimentación', type: 'expense'),
      );
      await into(
        categories,
      ).insert(CategoriesCompanion.insert(name: 'Transporte', type: 'expense'));
      await into(
        categories,
      ).insert(CategoriesCompanion.insert(name: 'Salario', type: 'income'));
    }
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'finanzas.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
