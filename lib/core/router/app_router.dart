// lib/core/router/app_router.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:tesis/presentation/home/home_screen.dart';
import 'package:tesis/presentation/transactions/add_transaction_screen.dart';
import 'package:tesis/presentation/auth/sign_in_screen.dart';
import 'package:tesis/presentation/debug/debug_screen.dart';
import 'package:tesis/presentation/auth/sign_up_screen.dart';
import 'package:tesis/presentation/categories/categories_screen.dart';
import 'package:tesis/presentation/budgets/budgets_screen.dart';
import 'package:tesis/presentation/analytics/analytics_screen.dart';

import '../../presentation/transactions/edit_transaction_screen.dart';
import '../../presentation/widgets/app_bottom_nav.dart';

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

GoRouter createRouter() {
  final auth = FirebaseAuth.instance;

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: GoRouterRefreshStream(auth.authStateChanges()),
    redirect: (context, state) {
      final user = auth.currentUser;
      final isAuthRoute = state.matchedLocation == '/login' || state.matchedLocation == '/signup';
      if (user == null) return isAuthRoute ? null : '/login';
      if (isAuthRoute) return '/';
      return null;
    },
    routes: [
      /// ✅ Rutas protegidas dentro de ShellRoute con BottomNavigation
      ShellRoute(
        builder: (context, state, child) {
          final location = state.fullPath ?? '';
          int index = 0;
          if (location.contains('categories')) index = 1;
          if (location.contains('budgets')) index = 2;
          if (location.contains('analytics')) index = 3;

          return Scaffold(
            body: child,
            bottomNavigationBar: buildBottomNav(context, index),
          );
        },
        routes: [
          GoRoute(
            path: '/',
            name: 'home',
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path: '/categories',
            name: 'categories',
            builder: (_, __) => const CategoriesScreen(),
          ),
          GoRoute(
            path: '/budgets',
            name: 'budgets',
            builder: (_, __) => const BudgetsScreen(),
          ),
          GoRoute(
            path: '/analytics',
            name: 'analytics',
            builder: (_, __) => const AnalyticsScreen(),
          ),
          GoRoute(
            name: 'edit_transaction',
            path: '/tx/:id/edit',
            builder: (context, state) {
              final idStr = state.pathParameters['id'];
              final id = int.tryParse(idStr ?? '');
              if (id == null) {
                return const Scaffold(
                  body: Center(child: Text('ID de transacción inválido')),
                );
              }
              return EditTransactionScreen(transactionId: id);
            },
          ),

        ],
      ),

      /// Pantallas independientes (sin bottom nav)
      GoRoute(
        path: '/add',
        name: 'add_transaction',
        builder: (_, __) => const AddTransactionScreen(),
      ),
      if (kDebugMode)
        GoRoute(
          path: '/debug',
          name: 'debug',
          builder: (_, __) => const DebugScreen(),
        ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (_, __) => const SignInScreen(),
      ),
      GoRoute(
        path: '/signup',
        name: 'sign_up',
        builder: (_, __) => const SignUpScreen(),
      ),
    ],
  );
}
