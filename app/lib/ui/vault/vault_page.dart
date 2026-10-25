/// vault_page.dart — unlock prompt and file list for the vault.
///
/// This single widget renders both the real environment and the decoy: the
/// controller never tells this screen which slot is open except via
/// [VaultState.slot]'s raw index, and this screen itself never branches
/// layout, typography, or which actions are available on that index. The
/// only thing that ever differs between opening the real passphrase and the
/// decoy passphrase is the content in [VaultState.entries] — exactly what
/// the coercion-resistance property requires: a user who hands over the
/// decoy passphrase under duress must not hand the attacker any visual tell
/// that what they're looking at isn't the whole story.
///
/// No biometric unlock: the passphrase is typed every time. Biometrics
/// would authenticate exactly one identity (whichever fingerprint/face was
/// enrolled), which defeats the decoy outright — and can be used against an
/// unwilling person without their choice the way a typed secret cannot.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/vault/vault_store.dart';
import '../theme.dart';
import '../settings/settings_page.dart';
import 'vault_controller.dart';
import 'vault_setup_page.dart';

/// The vault screen: shows the unlock prompt when locked, the file list
/// when unlocked. Reached only as a section from the home screen — never a
/// launch gate, per the plan's explicit requirement that nothing may prompt
/// for a passphrase at app start.
class VaultPage extends ConsumerWidget {
  const VaultPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vaultControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        actions: [
          if (state.unlocked)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: state.unlocked
            ? const _UnlockedView()
            : _LockedView(exists: state.exists),
      ),
    );
  }
}

/// Shown when no environment is open: either a passphrase prompt (a vault
/// already exists) or a first-run "create a vault" invitation.
class _LockedView extends ConsumerStatefulWidget {
  const _LockedView({required this.exists});

  final bool exists;

  @override
  ConsumerState<_LockedView> createState() => _LockedViewState();
}

class _LockedViewState extends ConsumerState<_LockedView> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await ref
        .read(vaultControllerProvider.notifier)
        .unlock(_controller.text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _submitting = false;
        _error = ref.read(vaultControllerProvider).error ?? 'Could not unlock';
      });
    }
    // On success the widget rebuilds via vaultControllerProvider into the
    // unlocked view; nothing further to do here.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // First run: no vault has been created yet in this session. Offer setup
    // rather than a passphrase box with nothing behind it.
    if (!widget.exists) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text('No vault yet', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Create a vault to store files behind a passphrase.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: DeadDropColors.textSecondary),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VaultSetupPage()),
                ),
                child: const Text('Set up vault'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.lock_outline,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'Enter your passphrase',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Passphrase'),
              onSubmitted: (_) => _submitting ? null : _unlock(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: DeadDropColors.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _unlock,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown once an environment is unlocked: its entry list, whichever
/// environment that happens to be.
class _UnlockedView extends ConsumerWidget {
  const _UnlockedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vaultControllerProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Expanded(
          child: state.entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.folder_open,
                            size: 56, color: DeadDropColors.textSecondary),
                        const SizedBox(height: 16),
                        Text(
                          'No files yet',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Files you save to the vault will appear here.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: DeadDropColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _EntryTile(entry: state.entries[index]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => ref.read(vaultControllerProvider.notifier).lock(),
            icon: const Icon(Icons.lock_outline),
            label: const Text('Lock vault'),
          ),
        ),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final VaultEntry entry;

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: Text(entry.name),
        subtitle: Text(
          '${_formatSize(entry.sizeBytes)} · ${entry.addedAt.toLocal()}',
        ),
      ),
    );
  }
}
