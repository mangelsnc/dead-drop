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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/file_drop.dart';
import '../../src/file_metadata.dart';
import '../../src/vault/attempt_guard.dart';
import '../../src/vault/vault_store.dart';
import '../responsive.dart';
import '../theme.dart';
import '../passphrase_field.dart';
import '../technical_text.dart';
import '../send/send_page.dart';
import '../settings/settings_page.dart';
import 'add_files.dart';
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
        // Settings only. Deleting the vault used to sit beside it here,
        // one icon away from the control people reach for without
        // looking — an irreversible action in the position reserved for
        // adjusting things. It lives in Settings → Security now, with
        // the other destructive controls, and on the locked screen for
        // someone who has forgotten the passphrase.
        actions: [
          if (state.unlocked)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
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

  /// Seconds left of a rate-limiting wait, or null when not waiting.
  ///
  /// Counted down in the UI rather than taken from the controller,
  /// which serves the whole delay in one go. The number is cosmetic:
  /// the wait itself is the controller's, and this only shows it.
  int? _waitSeconds;
  Timer? _waitTicker;

  /// Bumped on each failed attempt, which re-masks the passphrase field.
  int _failures = 0;

  @override
  void dispose() {
    _waitTicker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Shows the wait the controller is about to serve, ticking down.
  void _startWaitCountdown(Duration wait) {
    _waitTicker?.cancel();
    if (!mounted) return;
    setState(() => _waitSeconds = (wait.inMilliseconds / 1000).ceil());
    _waitTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final left = (_waitSeconds ?? 1) - 1;
      if (left <= 0) {
        timer.cancel();
        setState(() => _waitSeconds = null);
        return;
      }
      setState(() => _waitSeconds = left);
    });
  }

  Future<void> _unlock() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await ref
        .read(vaultControllerProvider.notifier)
        .unlock(_controller.text, onWaiting: _startWaitCountdown);
    _waitTicker?.cancel();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _submitting = false;
        _waitSeconds = null;
        _failures++;
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
              Icon(
                Icons.lock_outline,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text('No vault yet', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Create a vault to store files behind a passphrase.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: DeadDropColors.textSecondary,
                ),
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
        child: FormWidthLimit(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Enter your passphrase',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              // A build that erases on the third wrong passphrase must say
              // so where the passphrase is typed. Compile-time constant, so
              // an ordinary build drops this branch entirely.
              if (selfDestructRehearsal) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DeadDropColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DeadDropColors.error),
                  ),
                  child: Text(
                    'Rehearsal build: $selfDestructThreshold wrong '
                    'passphrases erase every environment, with no delays '
                    'in between. Do not keep anything here you want.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: DeadDropColors.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              PassphraseField(
                controller: _controller,
                remask: _failures,
                autofocus: true,
                textStyle: technicalTextStyle(ref),
                onSubmitted: () => _submitting ? null : _unlock(),
              ),
              // The wait comes first: while one is running there is no
              // error to show, and an empty pause under a spinner is what
              // reads as a hung app.
              if (_waitSeconds != null) ...[
                const SizedBox(height: 12),
                Text(
                  unlockWaitMessage(Duration(seconds: _waitSeconds!))!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: DeadDropColors.textSecondary,
                  ),
                ),
              ] else if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: DeadDropColors.error,
                  ),
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
              // Reachable while locked on purpose, and the one place it
              // has to be: someone who has forgotten the passphrase has no
              // other way out, and this screen is where they are standing
              // when they find that out.
              //
              // It used to ask for the passphrase here, which made the
              // button a promise it could not keep — the one person who
              // needs it is the one person who cannot use it. It no longer
              // does; see delete_vault_dialog.dart for why that costs
              // nothing, and why typing a word is the right guard instead.
              //
              // It leaks nothing the screen behind it does not already
              // show: that a vault exists here.
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
      ),
    );
  }
}

/// Shown once an environment is unlocked: its entry list, whichever
/// environment that happens to be.
/// How the file list is ordered.
enum _VaultSort {
  nameAsc('Name A-Z'),
  nameDesc('Name Z-A'),
  newestFirst('Newest first'),
  oldestFirst('Oldest first');

  const _VaultSort(this.label);
  final String label;
}

class _UnlockedView extends ConsumerStatefulWidget {
  const _UnlockedView();

  @override
  ConsumerState<_UnlockedView> createState() => _UnlockedViewState();
}

class _UnlockedViewState extends ConsumerState<_UnlockedView> {
  final TextEditingController _search = TextEditingController();
  _VaultSort _sort = _VaultSort.newestFirst;

  /// Which page of entries is showing, from zero.
  int _page = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Filters and orders the entries for display.
  ///
  /// Done in memory, over the entries the controller already decrypted.
  /// Nothing here touches the disk or the store, so searching cannot
  /// reveal anything about the environment that is open — and the decoy
  /// gets exactly the same controls, because a search box present in one
  /// and absent in the other would be a tell.
  List<VaultEntry> _visible(List<VaultEntry> entries) {
    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? [...entries]
        : entries.where((e) => e.name.toLowerCase().contains(query)).toList();

    filtered.sort(switch (_sort) {
      _VaultSort.nameAsc => (a, b) => a.name.toLowerCase().compareTo(
        b.name.toLowerCase(),
      ),
      _VaultSort.nameDesc => (a, b) => b.name.toLowerCase().compareTo(
        a.name.toLowerCase(),
      ),
      _VaultSort.newestFirst => (a, b) => b.addedAt.compareTo(a.addedAt),
      _VaultSort.oldestFirst => (a, b) => a.addedAt.compareTo(b.addedAt),
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultControllerProvider);
    final theme = Theme.of(context);
    final visible = _visible(state.entries);
    final pageCount = visible.isEmpty
        ? 1
        : ((visible.length - 1) ~/ kVaultPageSize) + 1;
    // Deleting the last file on the final page, or typing into the
    // search box, can leave _page past the end. Clamped on read rather
    // than reset from every callback that could cause it.
    final page = _page.clamp(0, pageCount - 1);
    final start = page * kVaultPageSize;
    final pageEntries = visible
        .skip(start)
        .take(kVaultPageSize)
        .toList(growable: false);

    // The drop target is inside the unlocked view on purpose: a file
    // dropped on a locked vault has nowhere to go, and a window that
    // accepts the drag and then refuses it is worse than one that
    // never offered.
    return VaultDropTarget(
      onResult: (message) => _EntryTile._say(context, message, ok: true),
      child: Column(
        children: [
          // Search and sort. Shown whenever there is more than one file —
          // below that they are clutter — and identical in both
          // environments.
          if (state.entries.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() => _page = 0),
                      decoration: InputDecoration(
                        hintText: 'Search files',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                tooltip: 'Clear',
                                onPressed: () => setState(_search.clear),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<_VaultSort>(
                    initialValue: _sort,
                    tooltip: 'Sort',
                    icon: const Icon(Icons.sort),
                    onSelected: (value) => setState(() {
                      _sort = value;
                      _page = 0;
                    }),
                    itemBuilder: (context) => [
                      for (final option in _VaultSort.values)
                        PopupMenuItem(value: option, child: Text(option.label)),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: state.entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.folder_open,
                            size: 56,
                            color: DeadDropColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No files yet',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            canDropFiles
                                ? 'Drag files here, or use Add files below.'
                                : 'Use Add files below to put something here.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: DeadDropColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : visible.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Nothing matches "${_search.text.trim()}".',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: DeadDropColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: pageEntries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _EntryTile(entry: pageEntries[index]),
                  ),
          ),
          // How many files there are, and which page of them this is.
          //
          // Both environments get this, like every other control here: a
          // count shown in one and hidden in the other would say which
          // one is open. It counts only what this environment holds,
          // which is all it can see.
          if (state.entries.isNotEmpty)
            _VaultListFooter(
              total: state.entries.length,
              filtered: visible.length,
              searching: _search.text.trim().isNotEmpty,
              page: page,
              pageCount: pageCount,
              onPage: (next) => setState(() => _page = next),
            ),
          // Add and lock, in that order: adding is the frequent action
          // and lock is the way out. Both environments get both, like
          // every other control on this screen.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AddFilesButton(
              onResult: (message) =>
                  _EntryTile._say(context, message, ok: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: OutlinedButton.icon(
              onPressed: () =>
                  ref.read(vaultControllerProvider.notifier).lock(),
              icon: const Icon(Icons.lock_outline),
              label: const Text('Lock vault'),
            ),
          ),
        ],
      ),
    );
  }
}

/// How many entries one page of the vault list shows.
///
/// A vault is not a filesystem browser: the common case is a handful of
/// files, and the search box handles the rest. 25 is enough that most
/// vaults never see a second page, and small enough that the one that
/// does stays scrollable by thumb.
const int kVaultPageSize = 25;

/// The count, and the pager when there is more than one page.
///
/// Identical in both environments. A footer that appeared only in the
/// real vault would answer the question the decoy exists to leave open.
class _VaultListFooter extends StatelessWidget {
  const _VaultListFooter({
    required this.total,
    required this.filtered,
    required this.searching,
    required this.page,
    required this.pageCount,
    required this.onPage,
  });

  final int total;
  final int filtered;
  final bool searching;
  final int page;
  final int pageCount;
  final ValueChanged<int> onPage;

  String get _countLabel {
    final files = '$total file${total == 1 ? '' : 's'}';
    // While searching, say what the search found as well as the whole,
    // so the number never silently contradicts the list on screen.
    if (searching) return '$filtered of $files';
    return files;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _countLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: DeadDropColors.textSecondary,
            ),
          ),
          if (pageCount > 1)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous page',
                  onPressed: page == 0 ? null : () => onPage(page - 1),
                ),
                Text(
                  '${page + 1} / $pageCount',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: DeadDropColors.textSecondary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next page',
                  onPressed: page >= pageCount - 1
                      ? null
                      : () => onPage(page + 1),
                ),
              ],
            ),
        ],
      ),
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
    final bytes = await ref
        .read(vaultControllerProvider.notifier)
        .readFile(entry.id);
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

    final bytes = await ref
        .read(vaultControllerProvider.notifier)
        .readFile(entry.id);
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
      _say(context, 'Saved outside the vault.', ok: true);
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
    final bytes = await ref
        .read(vaultControllerProvider.notifier)
        .readFile(entry.id);
    if (!context.mounted) return;
    if (bytes == null) {
      _say(context, 'The vault is locked.');
      return;
    }

    ref.read(sendProvider.notifier).loadBytes(entry.name, bytes);
    if (!context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SendPage()));
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
            child: const Text(
              'Delete',
              style: TextStyle(color: DeadDropColors.error),
            ),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;
    await ref.read(vaultControllerProvider.notifier).deleteFile(entry.id);
  }

  /// Shows a message that is actually visible.
  ///
  /// The default snack bar is close enough to this app's background on
  /// macOS to be missed entirely, so these carry a colour: green when
  /// something worked, red when it did not.
  static void _say(BuildContext context, String message, {bool ok = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: ok ? DeadDropColors.success : DeadDropColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: ok ? 3 : 6),
      ),
    );
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
        // Tapping the row previews it, which is what a file list implies
        // it will do. Everything else stays in the menu: exporting and
        // deleting are deliberate acts and should take a deliberate tap.
        onTap: () => _preview(context, ref),
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
              value: 'send',
              child: Text('Send with DeadDrop'),
            ),
            const PopupMenuItem(
              value: 'export',
              child: Text('Save outside the vault'),
            ),
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
      content: SizedBox(width: 480, child: isImage ? _image() : _text(context)),
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
