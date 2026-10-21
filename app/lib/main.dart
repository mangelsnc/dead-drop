import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sodium_libs/sodium_libs.dart';

import 'src/identity_store.dart';
import 'src/tofu_store.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

/// Global sodium instance provider.
final sodiumProvider = Provider<Sodium>((ref) {
  throw UnimplementedError('sodiumProvider must be overridden in main()');
});

/// Global identity store provider (persistent Ed25519 signing identity).
final identityStoreProvider = Provider<IdentityStore>((ref) {
  final sodium = ref.watch(sodiumProvider);
  return IdentityStore(sodium);
});

/// Global TOFU store provider (known sender fingerprints).
final tofuStoreProvider = Provider<TofuStore>((ref) {
  return TofuStore();
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final sodium = await SodiumInit.init();
  runApp(
    ProviderScope(
      overrides: [
        sodiumProvider.overrideWithValue(sodium),
      ],
      child: const DeadDropApp(),
    ),
  );
}

class DeadDropApp extends StatelessWidget {
  const DeadDropApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeadDrop',
      theme: deadDropTheme(),
      home: const HomePage(),
    );
  }
}
