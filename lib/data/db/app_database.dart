// lib/data/db/app_database.dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// DAO(s)
import 'daos/transaction_dao.dart';

part 'app_database.g.dart';

// ---------------------------------------------------------------------------
// TABLAS (incluye columnas de sincronización usadas por SyncService)
// ---------------------------------------------------------------------------

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'income' | 'expense'
  TextColumn get icon => text().nullable()();

  // Sync
  TextColumn get remoteId => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();
}

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get date => dateTime()();
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();

  // Sync
  TextColumn get remoteId => text().nullable()();
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();
}

class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().references(Categories, #id, onDelete: KeyAction.cascade)();
  RealColumn get limit => real()();
  IntColumn get month => integer()();
  IntColumn get year => integer()();

  @override
  List<String> get customConstraints => [
    'UNIQUE(category_id, month, year)',
  ];
}

// ---------------------------------------------------------------------------
// BASE DE DATOS
// ---------------------------------------------------------------------------

@DriftDatabase(
  tables: [Categories, Transactions, Budgets],
  daos: [TransactionDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Si migras desde esquema sin columnas de sync, usa 2.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(categories, categories.remoteId);
        await m.addColumn(categories, categories.updatedAt);
        await m.addColumn(categories, categories.isDeleted);
        await m.addColumn(categories, categories.isDirty);

        await m.addColumn(transactions, transactions.remoteId);
        await m.addColumn(transactions, transactions.updatedAt);
        await m.addColumn(transactions, transactions.isDeleted);
        await m.addColumn(transactions, transactions.isDirty);
      }
    },
  );

  // -------------------------------------------------------------------------
  // CRUD / UTILIDADES GENERALES
  // -------------------------------------------------------------------------

  // Categorías
  Future<List<Category>> getAllCategories() => select(categories).get();
  Stream<List<Category>> watchAllCategories() => select(categories).watch();
  Future<int> insertCategory(CategoriesCompanion entry) =>
      into(categories).insert(entry);
  Future<bool> updateCategory(Category c) => update(categories).replace(c);
  Future<int> deleteCategory(int id) =>
      (delete(categories)..where((t) => t.id.equals(id))).go();

  // Transacciones
  Future<List<Transaction>> getAllTransactions() => select(transactions).get();
  Stream<List<Transaction>> watchAllTransactions() =>
      select(transactions).watch();
  Future<int> insertTransaction(TransactionsCompanion entry) =>
      into(transactions).insert(entry);
  Future<bool> updateTransaction(Transaction t) =>
      update(transactions).replace(t);
  Future<int> deleteTransaction(int id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  // Presupuestos
  Future<List<Budget>> getAllBudgets() => select(budgets).get();
  Stream<List<Budget>> watchAllBudgets() => select(budgets).watch();

  Future<List<Budget>> budgetsOf(int year, int month) =>
      (select(budgets)
        ..where((b) => b.year.equals(year))
        ..where((b) => b.month.equals(month)))
          .get();

  Future<void> upsertBudget({
    required int categoryId,
    required int year,
    required int month,
    required double limit,
  }) async {
    final existing = await (select(budgets)
      ..where((b) => b.categoryId.equals(categoryId))
      ..where((b) => b.year.equals(year))
      ..where((b) => b.month.equals(month)))
        .getSingleOrNull();

    if (existing == null) {
      await into(budgets).insert(
        BudgetsCompanion.insert(
          categoryId: categoryId,
          year: year,
          month: month,
          limit: limit,
        ),
      );
    } else {
      await (update(budgets)..where((b) => b.id.equals(existing.id))).write(
        BudgetsCompanion(limit: Value(limit)),
      );
    }
  }

  // Normalizador (convierte gastos en negativos una sola vez)
  Future<int> normalizeExpenseSignsOnce() async {
    final t = transactions;
    final c = categories;

    final rows = await (select(t).join([
      innerJoin(c, c.id.equalsExp(t.categoryId)),
    ])
      ..where(c.type.equals('expense'))
      ..where(t.amount.isBiggerThanValue(0)))
        .get();

    var count = 0;
    for (final row in rows) {
      final tx = row.readTable(t);
      await (update(t)..where((tbl) => tbl.id.equals(tx.id))).write(
        TransactionsCompanion(amount: Value(-tx.amount)),
      );
      count++;
    }
    return count;
  }

  // Seed inicial
  Future<void> seed() async {
    final existing = await select(categories).get();
    if (existing.isNotEmpty) return;

    await batch((b) {
      b.insertAll(categories, [
        CategoriesCompanion.insert(
            name: 'Comida', type: 'expense', icon: const Value('restaurant')),
        CategoriesCompanion.insert(
            name: 'Transporte', type: 'expense', icon: const Value('bus')),
        CategoriesCompanion.insert(
            name: 'Salud', type: 'expense', icon: const Value('health')),
        CategoriesCompanion.insert(
            name: 'Otros', type: 'expense', icon: const Value('money')),
        CategoriesCompanion.insert(
            name: 'Salario', type: 'income', icon: const Value('income')),
      ]);
    });
  }

  // -------------------------------------------------------------------------
  // HELPERS USADOS POR SyncService (Pull/Push) — CATEGORÍAS
  // -------------------------------------------------------------------------

  Future<Category?> findCategoryByRemoteId(String remoteId) =>
      (select(categories)..where((c) => c.remoteId.equals(remoteId)))
          .getSingleOrNull();

  Future<void> insertCategoryFromRemote(
      String remoteId, Map<String, dynamic> m) async {
    await into(categories).insert(
      CategoriesCompanion.insert(
        name: m['name'] as String,
        type: m['type'] as String,
        remoteId: Value(remoteId),
        updatedAt: Value((m['updatedAt'] as int?) ?? 0),
        isDeleted: Value((m['isDeleted'] as bool?) ?? false),
        isDirty: const Value(false),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> updateCategoryFromRemote(
      int localId, Map<String, dynamic> m) async {
    await (update(categories)..where((c) => c.id.equals(localId))).write(
      CategoriesCompanion(
        name: Value(m['name'] as String),
        type: Value(m['type'] as String),
        updatedAt: Value((m['updatedAt'] as int?) ?? 0),
        isDeleted: Value((m['isDeleted'] as bool?) ?? false),
        isDirty: const Value(false),
      ),
    );
  }

  Future<void> markCategoryDeletedById(int localId, int remoteUpdated) async {
    await (update(categories)..where((c) => c.id.equals(localId))).write(
      const CategoriesCompanion(
        isDeleted: Value(true),
      ).copyWith(updatedAt: Value(remoteUpdated), isDirty: const Value(false)),
    );
  }

  Future<List<Category>> findDirtyCategories() =>
      (select(categories)..where((c) => c.isDirty.equals(true))).get();

  Future<void> attachCategoryRemoteId(int localId, String newRemoteId) async {
    await (update(categories)..where((c) => c.id.equals(localId))).write(
      CategoriesCompanion(remoteId: Value(newRemoteId)),
    );
  }

  Future<void> clearDirtyCategories(List<int> ids) async {
    await (update(categories)..where((c) => c.id.isIn(ids))).write(
      const CategoriesCompanion(isDirty: Value(false)),
    );
  }

  // -------------------------------------------------------------------------
  // HELPERS USADOS POR SyncService (Pull/Push) — TRANSACCIONES
  // -------------------------------------------------------------------------

  Future<Transaction?> findTxByRemoteId(String remoteId) =>
      (select(transactions)..where((t) => t.remoteId.equals(remoteId)))
          .getSingleOrNull();

  Future<void> insertTxFromRemote(
      String remoteId, Map<String, dynamic> m) async {
    await into(transactions).insert(
      TransactionsCompanion.insert(
        amount: (m['amount'] as num).toDouble(),
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        categoryId: await _localCategoryIdFromRemote(m['categoryId'] as String?),
        note: Value(m['note'] as String?),
        remoteId: Value(remoteId),
        updatedAt: Value((m['updatedAt'] as int?) ?? 0),
        isDeleted: Value((m['isDeleted'] as bool?) ?? false),
        isDirty: const Value(false),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> updateTxFromRemote(int localId, Map<String, dynamic> m) async {
    await (update(transactions)..where((t) => t.id.equals(localId))).write(
      TransactionsCompanion(
        amount: Value((m['amount'] as num).toDouble()),
        date: Value(DateTime.fromMillisecondsSinceEpoch(m['date'] as int)),
        note: Value(m['note'] as String?),
        categoryId: Value(
          await _localCategoryIdFromRemote(m['categoryId'] as String?),
        ),
        updatedAt: Value((m['updatedAt'] as int?) ?? 0),
        isDeleted: Value((m['isDeleted'] as bool?) ?? false),
        isDirty: const Value(false),
      ),
    );
  }

  Future<void> markTxDeletedById(int localId, int remoteUpdated) async {
    await (update(transactions)..where((t) => t.id.equals(localId))).write(
      const TransactionsCompanion(
        isDeleted: Value(true),
      ).copyWith(updatedAt: Value(remoteUpdated), isDirty: const Value(false)),
    );
  }

  Future<List<Transaction>> findDirtyTx() =>
      (select(transactions)..where((t) => t.isDirty.equals(true))).get();

  Future<void> attachTxRemoteId(int localId, String newRemoteId) async {
    await (update(transactions)..where((t) => t.id.equals(localId))).write(
      TransactionsCompanion(remoteId: Value(newRemoteId)),
    );
  }

  Future<void> clearDirtyTx(List<int> ids) async {
    await (update(transactions)..where((t) => t.id.isIn(ids))).write(
      const TransactionsCompanion(isDirty: Value(false)),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers internos: mapear category.remoteId → category.id (local)
  // -------------------------------------------------------------------------

  Future<int> _localCategoryIdFromRemote(String? remote) async {
    if (remote == null) return await _fallbackOtherCategoryId();
    final cat = await (select(categories)..where((c) => c.remoteId.equals(remote)))
        .getSingleOrNull();
    return cat?.id ?? await _fallbackOtherCategoryId();
  }

  Future<int> _fallbackOtherCategoryId() async {
    final other = await (select(categories)..where((c) => c.name.equals('Otros')))
        .getSingleOrNull();
    if (other != null) return other.id;
    return await into(categories).insert(
      CategoriesCompanion.insert(
        name: 'Otros',
        type: 'expense',
        isDirty: Value(true),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CONEXIÓN LOCAL
// ---------------------------------------------------------------------------

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'fintrack.db'));
    return NativeDatabase(file);
  });
}
