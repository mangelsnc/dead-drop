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

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/file_metadata.dart';
import '../../src/vault/vault_store.dart';
import '../theme.dart';
import '../passphrase_field.dart';
import '../technical_text.dart';
import '../send/send_page.dart';
import '../settings/settings_page.dart';
import 'delete_vault_dialog.dart';
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
          if (state.unlocked) ...[
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete vault',
              onPressed: () async {
                final erased = await showDeleteVaultDialog(context);
                if (erased && context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
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
            PassphraseField(
              controller: _controller,
              autofocus: true,
              textStyle: technicalTextStyle(ref),
              onSubmitted: () => _submitting ? null : _unlock(),
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
            const SizedBox(height: 8),
            // Reachable while locked on purpose. Someone who has forgotten
            // the passphrase still needs a way to clear the vault off their
            // device, and the button leaks nothing the screen behind it
            // does not already show: that a vault exists here. It still
            // asks for a passphrase, so being reachable is not the same as
            // being usable by whoever holds the phone.
            TextButton(
              onPressed: _submitting
                  ? null
                  : () async {
                      final erased = await showDeleteVaultDialog(context);
                      if (erased && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
              child: const Text(
                'Delete vault',
                style: TextStyle(color: DeadDropColors.textSecondary),
              ),
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

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry});

  final VaultEntry entry;

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Decides from the bytes, not the name.
  ///
  /// A file whose name was lost in transit arrives called
  /// `deaddrop_received_<timestamp>` with no extension, and deciding
  /// previewability from that would refuse to show a perfectly ordinary
  /// PNG. `guessMimeType` reads the magic bytes first and only falls back
  /// to the extension, which is the right order here.
  static bool _isImageMime(String? mime) =>
      mime != null && mime.startsWith('image/');

  static bool _isTextMime(String? mime) =>
      mime != null &&
      (mime.startsWith('text/') ||
          mime == 'application/json' ||
          mime == 'application/xml');

  Future<void> _preview(BuildContext context, WidgetRef ref) async {
    final bytes =
        await ref.read(vaultControllerProvider.notifier).readFile(entry.id);
    if (!context.mounted) return;
    if (bytes == null) {
      _say(context, 'The vault is locked.');
      return;
    }

    final dot = entry.name.lastIndexOf('.');
    final extension = dot > 0 ? entry.name.substring(dot + 1) : null;
    final mime = guessMimeType(bytes, extension);

    if (!_isImageMime(mime) && !_isTextMime(mime)) {
      _say(
        context,
        'This file cannot be shown here. Save it outside the vault to '
        'open it.',
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => _PreviewDialog(
        name: entry.name,
        bytes: bytes,
        isImage: _isImageMime(mime),
      ),
    );
  }

  /// Writes the file out of the vault, in the clear, where the user says.
  ///
  /// Confirmed first, and worded so the consequence is unmistakable: the
  /// whole point of the vault is that its contents are not sitting on the
  /// disk readable, and exporting undoes that for this one file.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save outside the vault?'),
        content: Text(
          '${entry.name} will be written to the place you choose, '
          'unencrypted. Anyone who can read that folder can read the file, '
          'and deleting it later does not undo that.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save outside'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    final bytes =
        await ref.read(vaultControllerProvider.notifier).readFile(entry.id);
    if (!context.mounted) return;
    if (bytes == null) {
      _say(context, 'The vault is locked.');
      return;
    }

    try {
      // file_picker, the same path the receive screen uses to save a file.
      // file_selector would be the obvious alternative but it pulls `http`
      // into the dependency graph of an app whose claim is that it has no
      // network code — see the note in pubspec.yaml.
      final chosen = await FilePicker.saveFile(
        dialogTitle: 'Save outside the vault',
        fileName: entry.name,
        bytes: bytes,
      );
      if (chosen == null || !context.mounted) return; // cancelled
      _say(context, 'Saved outside the vault.');
    } catch (e) {
      // A failed export must say so rather than look like a cancel: the
      // user would otherwise believe a file is on disk when it is not.
      if (context.mounted) _say(context, 'Could not save the file: $e');
    }
  }

  /// Stages this file on the send screen without it touching the disk.
  ///
  /// The alternative — export, pick, send, delete — would write the
  /// plaintext out just to read it straight back in, undoing the vault
  /// for as long as that copy existed.
  Future<void> _send(BuildContext context, WidgetRef ref) async {
    final bytes =
        await ref.read(vaultControllerProvider.notifier).readFile(entry.id);
    if (!context.mounted) return;
    if (bytes == null) {
      _say(context, 'The vault is locked.');
      return;
    }

    ref.read(sendProvider.notifier).loadBytes(entry.name, bytes);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SendPage()),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this file?'),
        content: Text(
          '${entry.name} will be removed from the vault. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: DeadDropColors.error)),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
    await ref.read(vaultControllerProvider.notifier).deleteFile(entry.id);
  }

  static void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.insert_drive_file_outlined),
        title: Text(entry.name),
        subtitle: Text(
          '${_formatSize(entry.sizeBytes)} · ${entry.addedAt.toLocal()}',
        ),
        // The same actions in both environments. A menu that offered more
        // in the real vault than in the decoy would be the tell the whole
        // feature exists to avoid.
        trailing: PopupMenuButton<String>(
          onSelected: (action) => switch (action) {
            'view' => _preview(context, ref),
            'send' => _send(context, ref),
            'export' => _export(context, ref),
            'delete' => _delete(context, ref),
            _ => null,
          },
          itemBuilder: (context) => [
            // Always offered. Whether a file can be drawn is decided from
            // its bytes when it is opened, not guessed from its name —
            // a name lost in transit must not hide a viewable file.
            const PopupMenuItem(value: 'view', child: Text('View')),
            const PopupMenuItem(
                value: 'send', child: Text('Send with DeadDrop')),
            const PopupMenuItem(
                value: 'export', child: Text('Save outside the vault')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}

/// Shows a vault file without it ever reaching the disk.
///
/// The bytes come straight from [VaultController.readFile] and are rendered
/// from memory. Handing the file to the system viewer instead would mean
/// writing plaintext somewhere outside the vault, which is what the design
/// forbids — so only types that can be drawn here are offered at all.
class _PreviewDialog extends StatelessWidget {
  const _PreviewDialog({
    required this.name,
    required this.bytes,
    required this.isImage,
  });

  final String name;
  final Uint8List bytes;
  final bool isImage;

  /// Text beyond this is truncated in the view. A preview is for checking
  /// what a file is, and rendering megabytes of text in a dialog janks the
  /// UI for no benefit.
  static const int _maxTextChars = 20000;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(name, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 480,
        child: isImage ? _image() : _text(context),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _image() => InteractiveViewer(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text('This file is not an image the app can show.'),
          ),
        ),
      );

  Widget _text(BuildContext context) {
    String body;
    try {
      body = utf8.decode(bytes);
    } on FormatException {
      // Named as binary rather than shown as mojibake: a wall of
      // replacement characters looks like corruption, which it is not.
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('This file is not text the app can show.'),
      );
    }
    final truncated = body.length > _maxTextChars;
    if (truncated) body = body.substring(0, _maxTextChars);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(body),
          if (truncated)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Shown: the first $_maxTextChars characters. '
                'Save it outside the vault to read all of it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
