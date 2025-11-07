import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';


class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
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

  Future<void> _signIn() async {
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
  }

  Future<void> _signUp() async {
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
  }

  Future<void> _signInAnonymously() async {
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
              onPressed: _signIn,
              child: const Text('Entrar'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.push('/signup'),
              child: const Text('Crear cuenta'),
            ),
            const Divider(),
            TextButton(
              onPressed: _signInAnonymously,
              child: const Text('Entrar como invitado'),
            ),
          ],
        ),
      ),
    );
  }
}
