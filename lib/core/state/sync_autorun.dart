import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../data/sync/sync_service.dart';
import '../providers/firebase_providers.dart';
import 'sync_prefs.dart';

final autoSyncProvider = Provider<void>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final enabled = ref.watch(autoSyncEnabledProvider); // bool garantizado
  if (auth.currentUser == null || enabled == false) return;

  final sync = ref.watch(syncServiceProvider);

  // Foreground
  final appListener = AppLifecycleListener(
    onResume: () async {
      debugPrint('[sync] onResume → syncOnce()');
      await sync.syncOnce();
    },
  );
  ref.onDispose(appListener.dispose);

  // Conectividad (v6/v7 pueden emitir List<ConnectivityResult> o un solo ConnectivityResult)
  final sub = Connectivity().onConnectivityChanged.listen((event) async {
    bool hasNet;
    if (event is List<ConnectivityResult>) {
      hasNet = event.any((r) => r != ConnectivityResult.none);
    } else if (event is ConnectivityResult) {
      hasNet = event != ConnectivityResult.none;
    } else {
      hasNet = false;
    }
    if (hasNet) {
      debugPrint('[sync] connectivity regained → syncOnce()');
      await sync.syncOnce();
    }
  });
  ref.onDispose(() => sub.cancel());
});
