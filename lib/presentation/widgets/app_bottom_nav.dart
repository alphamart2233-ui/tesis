// lib/presentation/widgets/app_bottom_nav.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// currentIndex:
/// 0 = Home, 1 = Categorías, 2 = Presupuestos, 3 = Análisis
BottomNavigationBar buildBottomNav(BuildContext context, int currentIndex) {
  return BottomNavigationBar(
    currentIndex: currentIndex,
    onTap: (i) {
      if (i == currentIndex) return; // evita recargar
      switch (i) {
        case 0:
          context.goNamed('home');
          break;
        case 1:
          context.goNamed('categories');
          break;
        case 2:
          context.goNamed('budgets');
          break;
        case 3:
          context.goNamed('analytics');
          break;
      }
    },
    items: const [
      BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      BottomNavigationBarItem(icon: Icon(Icons.category), label: 'Categorías'),
      BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Presupuestos'),
      BottomNavigationBarItem(icon: Icon(Icons.insights), label: 'Análisis'),
    ],
    type: BottomNavigationBarType.fixed,
  );
}
