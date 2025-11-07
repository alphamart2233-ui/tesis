import 'package:flutter_riverpod/flutter_riverpod.dart';

/// true = auto-sync activo (default)
final autoSyncEnabledProvider = StateProvider<bool>((ref) => true);
