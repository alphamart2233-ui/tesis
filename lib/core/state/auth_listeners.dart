// lib/core/state/auth_listeners.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/firebase_providers.dart';
import '../../data/repositories/user_profile_repository.dart';

// Stream de auth (sigue igual)
final authStateChangesProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges();
});

// Provider intermedio que mapea AsyncValue<User?> → User?
final userProvider = Provider<User?>((ref) {
  return ref.watch(authStateChangesProvider).value;
});

// Listener que asegura el perfil en Firestore cuando hay user
final ensureUserProfileOnLoginProvider = Provider<void>((ref) {
  ref.listen<User?>(
    userProvider, // <- ahora sí es ProviderListenable<User?>
        (prevUser, nextUser) async {
      if (nextUser != null) {
        final repo = ref.read(userProfileRepositoryProvider);
        await repo.ensureExists(
          uid: nextUser.uid,
          email: nextUser.email ?? '',
          displayName: nextUser.displayName,
          locale: 'es-EC',
          currency: 'USD',
        );
      }
    },
  );
});
