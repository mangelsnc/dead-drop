import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sodium_libs/sodium_libs.dart' show SodiumInit;
import 'package:sodium_libs/sodium_libs_sumo.dart';

import 'src/identity_store.dart';
import 'src/tofu_store.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';
import 'ui/vault/vault_controller.dart';

/// Global sodium instance provider, used by every non-vault consumer
/// (`IdentityStore`, Send, Receive).
///
/// Stays typed as the plain [Sodium] those consumers have always used.
/// `main()` now obtains the instance via [SodiumSumoInit] when sumo is
/// available (since `SodiumSumo implements Sodium`, the same instance
/// satisfies both this provider and [sodiumSumoProvider]), falling back to
/// the plain [SodiumInit] only if sumo itself is unavailable on this
/// platform — see main() for why that fallback exists: this provider must
/// never be left unoverridden, because unlike the vault, Send and Receive
/// are not allowed to degrade.
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

  // Sumo can be unavailable on a given platform build (SodiumSumoUnavailable).
  // The vault is the only feature that needs it — Send and Receive do not —
  // so a sumo failure must degrade to "no vault", never block startup. When
  // sumo is unavailable we still need *some* Sodium instance for
  // sodiumProvider (Identity, Send, Receive all depend on it), so we fall
  // back to the plain, non-sumo init in that case.
  SodiumSumo? sumo;
  Sodium sodium;
  try {
    sumo = await SodiumSumoInit.init();
    sodium = sumo;
  } on SodiumSumoUnavailable {
    sumo = null;
    sodium = await SodiumInit.init();
  }

  final overrides = <Override>[
    sodiumProvider.overrideWithValue(sodium),
    if (sumo != null) ...[
      sodiumSumoProvider.overrideWithValue(sumo),
      vaultDirectoryProvider.overrideWithValue(await resolveVaultDirectory()),
    ],
  ];

  runApp(
    ProviderScope(
      overrides: overrides,
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
