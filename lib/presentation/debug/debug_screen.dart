import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'debug_sync_panel.dart';

class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug tools')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(12),
        child: DebugSyncPanel(),
      ),
    );
  }
}
