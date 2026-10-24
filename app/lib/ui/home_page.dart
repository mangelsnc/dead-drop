import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'send/send_page.dart';
import 'receive/receive_page.dart';
import 'settings/settings_page.dart';
import 'theme.dart';
import 'vault/vault_controller.dart';
import 'vault/vault_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The Vault entry is shown only once a vault exists (VaultState.exists),
    // never merely disabled beforehand — an absent entry says nothing; a
    // disabled one says "there is a vault feature, just not for you yet",
    // which is itself a tell a launch-time prompt or a greyed button would
    // also give away. See vault_controller.dart's VaultState.exists doc
    // comment for why this is session-local rather than read off disk: the
    // on-disk layout must never reveal whether a vault has ever been set
    // up, so there is deliberately no way to know this before the user
    // creates or unlocks one in this session.
    final vaultExists = ref.watch(
      vaultControllerProvider.select((s) => s.exists),
    );

    return Scaffold(
      appBar: AppBar(
        // Settings is always reachable, whichever environment (or none) is
        // open — unlike the Vault entry below, its visibility never depends
        // on vault state. Vault setup lives inside it; see
        // settings_page.dart for why that, not a home-screen button, is the
        // vault's one opt-in entry point.
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.qr_code_2,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'DeadDrop',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Air-gapped file transfer',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: DeadDropColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 48),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SendPage()),
              ),
              icon: const Icon(Icons.upload),
              label: const Text('Send a file'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(240, 56),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReceivePage()),
              ),
              icon: const Icon(Icons.download),
              label: const Text('Receive a file'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(240, 56),
              ),
            ),
            if (vaultExists) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VaultPage()),
                ),
                icon: const Icon(Icons.lock_outline),
                label: const Text('Vault'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(240, 56),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
