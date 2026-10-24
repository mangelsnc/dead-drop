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
///
/// Scoped to whichever vault environment is currently unlocked
/// ([VaultState.slot]) so Send always signs with — and the identity card
/// always displays — the fingerprint belonging to the open environment, not
/// the real one regardless of what the user unlocked. This is the fix for
/// the coercion hole: Task 6 made [IdentityStore] scopeable, but nothing
/// read [vaultControllerProvider] to pick a slot, so the real fingerprint
/// kept leaking out even with the decoy open.
///
/// `ref.watch` (not `ref.read`) on [vaultControllerProvider] is load-bearing:
/// it makes this provider — and therefore every provider that watches it,
/// including [sendProvider]/[receiveProvider] and the pages that watch this
/// one directly — rebuild on every lock/unlock, handing out a *new*
/// [IdentityStore] instance. A fresh instance matters because `IdentityStore`
/// caches the loaded identity in a `_cached` field per instance; reusing the
/// same instance across a slot change would keep serving the previous
/// environment's cached identity even though the storage key is correct.
/// When no vault is unlocked, `slot` is null, which reproduces today's
/// unscoped, unsuffixed-key behaviour exactly — existing installs that never
/// touch the vault see no change.
final identityStoreProvider = Provider<IdentityStore>((ref) {
  final sodium = ref.watch(sodiumProvider);
  final slot = ref.watch(vaultControllerProvider.select((s) => s.slot));
  return IdentityStore(sodium, environmentSlot: slot);
});

/// Global TOFU store provider (known sender fingerprints).
///
/// Scoped the same way and for the same reason as [identityStoreProvider]:
/// without this, opening the decoy would show the real environment's known
/// senders, which is as much a tell to an attacker as the identity leak. See
/// [identityStoreProvider] for why `ref.watch` and a fresh instance per slot
/// change both matter.
final tofuStoreProvider = Provider<TofuStore>((ref) {
  final slot = ref.watch(vaultControllerProvider.select((s) => s.slot));
  return TofuStore(environmentSlot: slot);
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
