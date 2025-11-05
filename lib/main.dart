import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart'; // generado por `flutterfire configure`
import 'data/db/app_database.dart';
import 'core/state/db_providers.dart';

import 'presentation/home/home_screen.dart';
import 'presentation/transactions/add_transaction_screen.dart';

// Instancia única de la base de datos (evitar múltiples en hot reload)
final _db = AppDatabase();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    ProviderScope(
      overrides: [
        // ⬅️ Inyección real del AppDatabase para databaseProvider
        databaseProvider.overrideWithValue(_db),
      ],
      child: const MyApp(),
    ),
  );
}

/// Notificador para refrescar GoRouter cuando cambia el estado de Auth.
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

GoRouter _createRouter() {
  return GoRouter(
    initialLocation: '/login',
    refreshListenable:
    GoRouterRefreshStream(FirebaseAuth.instance.authStateChanges()),
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final loggingIn = state.matchedLocation == '/login';
      if (user == null) return loggingIn ? null : '/login';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: '/add',
        name: 'add_transaction', // coincide con context.pushNamed('add_transaction')
        builder: (_, __) => const AddTransactionScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (_, __) => const _SignInScreen(),
      ),
    ],
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final router = _createRouter();
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

/// Pantalla simple de inicio de sesión (email/clave + opción invitado)
class _SignInScreen extends StatefulWidget {
  const _SignInScreen({super.key});
  @override
  State<_SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<_SignInScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar sesión')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              decoration: const InputDecoration(labelText: 'Contraseña'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                try {
                  await FirebaseAuth.instance.signInWithEmailAndPassword(
                    email: _email.text.trim(),
                    password: _pass.text.trim(),
                  );
                } on FirebaseAuthException catch (e) {
                  final msg = switch (e.code) {
                    'invalid-email' => 'Email inválido',
                    'user-not-found' => 'Usuario no encontrado',
                    'wrong-password' => 'Contraseña incorrecta',
                    'user-disabled' => 'Usuario deshabilitado',
                    'operation-not-allowed' =>
                    'Proveedor deshabilitado en Firebase Console',
                    _ => 'Error: ${e.code}',
                  };
                  _showMsg(msg);
                } catch (e) {
                  _showMsg('Error inesperado: $e');
                }
              },
              child: const Text('Entrar'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                try {
                  await FirebaseAuth.instance.createUserWithEmailAndPassword(
                    email: _email.text.trim(),
                    password: _pass.text.trim(),
                  );
                } on FirebaseAuthException catch (e) {
                  final msg = switch (e.code) {
                    'email-already-in-use' => 'El email ya está en uso',
                    'invalid-email' => 'Email inválido',
                    'weak-password' => 'Contraseña débil',
                    'operation-not-allowed' =>
                    'Proveedor deshabilitado en Firebase Console',
                    _ => 'Error: ${e.code}',
                  };
                  _showMsg(msg);
                } catch (e) {
                  _showMsg('Error inesperado: $e');
                }
              },
              child: const Text('Crear cuenta'),
            ),
            const Divider(),
            TextButton(
              onPressed: () async {
                try {
                  await FirebaseAuth.instance.signInAnonymously();
                } on FirebaseAuthException catch (e) {
                  _showMsg(
                    e.code == 'operation-not-allowed'
                        ? 'Habilita "Anonymous" en Firebase Console → Authentication'
                        : 'Error: ${e.code}',
                  );
                } catch (e) {
                  _showMsg('Error inesperado: $e');
                }
              },
              child: const Text('Entrar como invitado'),
            ),
          ],
        ),
      ),
    );
  }
}
