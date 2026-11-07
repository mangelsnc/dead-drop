/// settings_page.dart — app settings, with a Security section gated to the
/// real environment.
///
/// Settings itself is always reachable, whichever environment (or none) is
/// open. The **Security** section inside it renders for whichever
/// environment is open, and renders identically in both.
///
/// It used to render only for slot 0, on the reasoning that a greyed-out
/// control would tell an attacker the decoy feature exists. That
/// reasoning held, and missed that the asymmetry runs both ways: a decoy
/// with no Security section is a decoy an attacker can recognise, because
/// the real environment has one. Someone made to unlock under duress who
/// opens Settings and finds nothing there learns they are not where the
/// owner keeps things.
///
/// Both environments now exist from the moment the vault is created
/// (ADR 0002), so there is nothing for the real one to offer that the
/// decoy cannot: no "set up decoy", because there is one. What remains
/// applies to whichever environment is open.
///
/// vault_ui_test.dart captures every string this page renders in each
/// environment and fails if they differ — anything that differs is a
/// tell, whether or not anyone thought about it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../src/secure_storage.dart';
import '../theme.dart';
import '../technical_text.dart';
import '../senders/known_senders_page.dart';
import '../../src/app_version.dart';
import '../../src/vault/attempt_guard.dart';
import '../vault/vault_controller.dart';
import '../vault/delete_vault_dialog.dart';
import '../vault/vault_setup_page.dart';

const _secureStorage = kSecureStorage;

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vaultControllerProvider);
    // Deliberately not "is this slot 0": see this file's doc comment and
    // ADR 0002. What Settings shows must not depend on which environment
    // is open, because a section the real one has and the decoy does not
    // tells an attacker which they are looking at.
    final isVaultOpen = state.unlocked;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            const _SectionHeader('General'),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About DeadDrop'),
              // The version is here, not behind a tap: someone reporting
              // a problem has to be able to read it off the screen, and
              // a build they cannot identify is a report we cannot act
              // on.
              subtitle: Text('Air-gapped file transfer\n$appVersionLabel'),
              isThreeLine: true,
            ),
            // In General rather than Security for the same reason as the
            // text-size control: the Security section is absent in the
            // decoy, and the list itself is already environment-scoped,
            // so the decoy shows the decoy's contacts and nothing else.
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Known senders'),
              subtitle: const Text(
                'People you have received from, and the names you gave '
                'them.',
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const KnownSendersPage()),
              ),
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
            // Security renders for whichever environment is open, and
            // renders the same — see this file's doc comment. It used to
            // render only for slot 0, which made its absence a tell.
            if (isVaultOpen) ...[
              const _SectionHeader('Security'),
              const _SelfDestructTile(),
              // Moved here from the vault's app bar, where it sat one
              // icon away from Settings: an irreversible action in the
              // position people press without looking.
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: DeadDropColors.error,
                ),
                title: const Text('Delete vault'),
                subtitle: const Text(
                  'Erases every environment and everything stored in '
                  'them. Asks for your passphrase first.',
                ),
                onTap: () async {
                  final erased = await showDeleteVaultDialog(context);
                  // Settings sits on top of the vault, which no longer
                  // has anything to show.
                  if (erased && context.mounted) Navigator.of(context).pop();
                },
              ),
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
