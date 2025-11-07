import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});
  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _email = TextEditingController();
  final _name  = TextEditingController();
  final _pass  = TextEditingController();
  final _pass2 = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _signUp() async {
    final email = _email.text.trim();
    final pass  = _pass.text.trim();
    final pass2 = _pass2.text.trim();

    if (email.isEmpty) { _msg('Ingresa un email'); return; }
    if (pass.isEmpty || pass2.isEmpty) { _msg('Completa ambas contraseñas'); return; }
    if (pass != pass2) { _msg('Las contraseñas no coinciden'); return; }
    if (pass.length < 6) { _msg('Mínimo 6 caracteres'); return; }

    setState(() => _busy = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      if (_name.text.trim().isNotEmpty) {
        await cred.user?.updateDisplayName(_name.text.trim());
      }
      await cred.user?.sendEmailVerification(); // opcional
      _msg('Cuenta creada. Revisa tu correo para verificar.');
    } on FirebaseAuthException catch (e) {
      _msg('Error: ${e.code}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
              enabled: !_busy,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre (opcional)'),
              enabled: !_busy,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pass,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              obscureText: _obscure,
              enabled: !_busy,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pass2,
              decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
              obscureText: _obscure,
              enabled: !_busy,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _signUp,
              child: _busy ? const CircularProgressIndicator() : const Text('Crear cuenta'),
            ),
          ],
        ),
      ),
    );
  }
}
