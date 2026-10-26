/// settings_page.dart — app settings, with a Security section gated to the
/// real environment.
///
/// Settings itself is always reachable, whichever environment (or none) is
/// open. The **Security** section inside it — add a decoy, self-destruct —
/// renders only when the open environment is slot 0 (the real one). Inside
/// the decoy it is absent, not disabled or greyed out: a greyed-out control
/// still tells an attacker the feature exists and is merely locked away,
/// which is exactly the tell this feature exists to deny them. This is the
/// single behavioural property the whole coercion-resistance design rests
/// on, so this file renders the section by building a different widget
/// subtree per state — not by wrapping the same subtree in an `IgnorePointer`
/// or disabling its controls — there must be nothing in the widget tree at
/// all for a decoy session to accidentally expose (e.g. via an inspector,
/// an accessibility tree walk, or a future bug in a disabled-state check).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../theme.dart';
import '../technical_text.dart';
import '../../src/vault/attempt_guard.dart';
import '../vault/vault_controller.dart';
import '../vault/vault_setup_page.dart';

const _secureStorage = FlutterSecureStorage(
  lOptions: LinuxOptions(),
  mOptions: MacOsOptions(),
);

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vaultControllerProvider);
    final isRealEnvironment = state.unlocked && state.slot == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            const _SectionHeader('General'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('About DeadDrop'),
              subtitle: Text('Air-gapped file transfer'),
            ),
            // Deliberately in General, not under Security: that section is
            // absent in the decoy environment, and someone who needs
            // larger text needs it there too. It also reveals nothing —
            // a font size says nothing about whether a vault exists.
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: TechnicalTextSizeControl(),
            ),
            // The vault is opt-in and enabled from here — not from the home
            // screen, which only ever shows a Vault entry after one exists
            // (see home_page.dart). Offering setup from Settings keeps a
            // never-enabled vault completely out of the home screen's
            // interface, exactly as the spec requires: "until then ... the
            // vault UI does not exist anywhere in the interface" beyond
            // this one entry point to turn it on.
            if (!state.exists)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Set up vault'),
                subtitle: const Text(
                  'Store files behind a passphrase, separate from Send and '
                  'Receive.',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VaultSetupPage()),
                ),
              ),
            // Security renders only for the real, unlocked environment. No
            // placeholder, no disabled tile, nothing — see this file's doc
            // comment for why that absence is load-bearing.
            if (isRealEnvironment) ...[
              const _SectionHeader('Security'),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Set up decoy'),
                subtitle: const Text(
                  'A second passphrase that opens a separate, convincing '
                  'environment instead of this one.',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const VaultSetupPage(isDecoy: true),
                  ),
                ),
              ),
              const _SelfDestructTile(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: DeadDropColors.accent,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

/// Toggle for self-destruct: wiping every environment after too many wrong
/// passphrase attempts (the attempt counting itself is Task 8b — this tile
/// only needs to exist and be honest about what it does).
///
/// Off by default. The copy states plainly that an attacker — not just an
/// accident — can trigger it deliberately: someone who turns this on is
/// choosing "I would rather lose this than have it seen", and that choice
/// deserves to be made with the actual threat model in view, not a vague
/// "extra security" promise.
class _SelfDestructTile extends StatefulWidget {
  const _SelfDestructTile();

  @override
  State<_SelfDestructTile> createState() => _SelfDestructTileState();
}

class _SelfDestructTileState extends State<_SelfDestructTile> {
  bool _enabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final stored = await _secureStorage.read(key: kSelfDestructStorageKey);
    if (!mounted) return;
    setState(() {
      _enabled = stored == 'true';
      _loaded = true;
    });
  }

  Future<void> _set(bool value) async {
    setState(() => _enabled = value);
    // Always write, on or off — see kSelfDestructStorageKey's doc comment.
    await _secureStorage.write(
      key: kSelfDestructStorageKey,
      value: value ? 'true' : 'false',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return SwitchListTile(
      value: _enabled,
      onChanged: _set,
      title: const Text('Self-destruct'),
      subtitle: const Text(
        'After too many wrong passphrase attempts, every environment is '
        'wiped — including this one. An attacker who suspects this is on '
        'can trigger it deliberately by entering wrong passphrases on '
        'purpose. Only enable this if losing everything is preferable to '
        'it being seen.',
      ),
    );
  }
}
