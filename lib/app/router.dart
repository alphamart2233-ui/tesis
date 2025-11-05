import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/home/home_screen.dart';
import '../presentation/transactions/add_transaction_screen.dart';
import '../presentation/categories/categories_screen.dart';
import '../presentation/budgets/budgets_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'add',
            builder: (context, state) => const AddTransactionScreen(),
          ),
          GoRoute(
            path: 'categories',
            builder: (context, state) => const CategoriesScreen(),
          ),
          GoRoute(
            path: 'budgets',
            builder: (context, state) => const BudgetsScreen(), // ⬅️ nuevo
          ),
        ],
      ),
    ],
  );
});
