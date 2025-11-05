import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/user_profile_repository.dart';
import '../../core/providers/firebase_providers.dart';


final authStateChangesProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges();
});

final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authUser = ref.watch(authStateChangesProvider).value;
  if (authUser == null) return const Stream.empty();
  final repo = ref.watch(userProfileRepositoryProvider);
  return repo.watch(authUser.uid);
});

// Llama a ensureExists cuando haya login
final ensureUserProfileOnLoginProvider = Provider<void>((ref) {
  ref.listen<User?>(
    authStateChangesProvider as ProviderListenable<User?>,
        (prev, next) async {
      final user = next;
      if (user != null) {
        final repo = ref.read(userProfileRepositoryProvider);
        await repo.ensureExists(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName,
          locale: 'es-EC',
          currency: 'USD',
        );
      }
    },
  );
});
