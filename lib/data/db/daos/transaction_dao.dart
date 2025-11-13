//lib/data/db/daos/transaction_dao.dart
import 'package:drift/drift.dart';
import '../app_database.dart';

part 'transaction_dao.g.dart';

@DriftAccessor(tables: [Transactions, Categories])
class TransactionDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionDaoMixin {
  TransactionDao(AppDatabase db) : super(db);

  Future<int> add(
    double amount,
    int categoryId,
    DateTime date, {
    String? note,
  }) {
    return into(transactions).insert(
      TransactionsCompanion.insert(
        amount: amount,
        categoryId: categoryId,
        date: date,
        note: Value(note),
      ),
    );
  }

  /// Últimos movimientos con su categoría (para listar en Home)
  Stream<List<(Transaction, Category)>> watchLatest({int limit = 20}) {
    final query =
        (select(transactions)
              ..orderBy([(t) => OrderingTerm.desc(t.date)])
              ..limit(limit))
            .join([
              leftOuterJoin(
                categories,
                categories.id.equalsExp(transactions.categoryId),
              ),
            ]);

    return query.watch().map(
      (rows) => rows
          .map((r) => (r.readTable(transactions), r.readTable(categories)))
          .toList(),
    );
  }
}
