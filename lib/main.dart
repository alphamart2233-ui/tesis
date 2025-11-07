import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart'; // generado por `flutterfire configure`
import 'data/db/app_database.dart';
import 'core/state/db_providers.dart';
import 'core/router/app_router.dart';
import 'core/state/auth_listeners.dart'; // ensureUserProfileOnLoginProvider

// Instancia única de la base de datos (evitar múltiples en hot reload)
final _db = AppDatabase();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 🔧 Inicializa la localización en español (requerido por intl)
  await initializeDateFormatting('es_ES', null);

  runApp(
    ProviderScope(
      overrides: [
        // Inyección real del AppDatabase para databaseProvider
        databaseProvider.overrideWithValue(_db),
      ],
      child: const MyApp(),
    ),
  );
}


class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activa el listener que crea/asegura /users/{uid} al loguear
    ref.watch(ensureUserProfileOnLoginProvider);

    final router = createRouter();
    return MaterialApp.router(
      title: 'FinTrack EC',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
    );
  }
}
