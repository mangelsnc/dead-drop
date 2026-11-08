/// add_files.dart — getting files into the open environment.
///
/// Until now the only way in was to receive a transfer, which made the
/// decoy awkward to keep believable: an environment whose newest file
/// is months old, or which holds nothing but things that arrived over
/// QR codes, does not look like somewhere a person keeps documents.
///
/// Two ways in, because the platforms differ in what they can offer and
/// not in what they are allowed to do:
///
///   * A button, everywhere. It is the one gesture every platform has,
///     and on Android the system document picker already reaches
///     photos, audio and downloads, so "pick from the gallery" needs no
///     separate route and no extra dependency. (`image_picker` would
///     give a native gallery sheet and pulls `http` with it, which this
///     project does not accept — see pubspec.yaml.)
///   * A drop target, on desktop, where dragging a file is what a
///     person expects to be able to do.
///
/// **Both environments get both.** The real vault and the decoy are the
/// same screen with the same controls; an "add file" button present in
/// one and missing from the other would say which one you are looking
/// at, which is the disclosure the decoy exists to prevent. Nothing in
/// this file reads [VaultState.slot].
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/file_drop.dart';
import '../theme.dart';
import 'vault_controller.dart';

/// The largest file the vault will take in one go.
///
/// Reading happens into memory before sealing, so this is a guard
/// against an accidental drag of something enormous taking the app out
/// rather than a policy about what belongs in a vault. 256 MB is far
/// above any document and far below what would trouble a desktop.
const int kMaxVaultFileBytes = 256 * 1024 * 1024;

/// Seals [files] into whichever environment is open.
///
/// Returns a human-readable summary, or null if nothing was added.
/// Reports per-file failures rather than abandoning the batch: one
/// unreadable file in a dragged selection should not discard the rest.
Future<String?> addFilesToVault(
  WidgetRef ref,
  List<({String name, Future<Uint8List> Function() read})> files,
) async {
  if (files.isEmpty) return null;
  final controller = ref.read(vaultControllerProvider.notifier);

  var added = 0;
  final failed = <String>[];
  for (final file in files) {
    try {
      final bytes = await file.read();
      if (bytes.length > kMaxVaultFileBytes) {
        failed.add('${file.name} (too large)');
        continue;
      }
      final entry = await controller.saveFile(file.name, bytes);
      if (entry == null) {
        // saveFile returns null only when the vault is not open, so
        // every remaining file would fail the same way.
        return added == 0
            ? 'The vault is locked.'
            : 'Added $added, then the vault locked.';
      }
      added++;
    } catch (_) {
      // The path may have gone, or be unreadable. Naming the file is
      // the useful part; the exception's text is not.
      failed.add(file.name);
    }
  }

  if (added == 0 && failed.isEmpty) return null;
  final parts = <String>[];
  if (added > 0) parts.add('Added $added file${added == 1 ? '' : 's'}');
  if (failed.isNotEmpty) {
    parts.add('could not read ${failed.join(', ')}');
  }
  return '${parts.join(', ')}.';
}

/// Opens the system file picker and seals whatever is chosen.
///
/// On Android this is the document picker, which reaches photos, audio
/// and downloads as well as files.
Future<String?> pickAndAddFiles(WidgetRef ref) async {
  // No allowMultiple: file_picker 13 dropped the flag and always
  // returns a list, leaving multi-select to the platform's own picker.
  final picked = await FilePicker.pickFiles();
  if (picked.isEmpty) return null;
  return addFilesToVault(ref, [
    for (final file in picked)
      (name: file.name, read: () => file.readAsBytes()),
  ]);
}

/// The "Add files" button. Present on every platform, in both
/// environments.
class AddFilesButton extends ConsumerStatefulWidget {
  const AddFilesButton({super.key, required this.onResult});

  /// Called with the summary to show the user, after the work is done.
  final void Function(String message) onResult;

  @override
  ConsumerState<AddFilesButton> createState() => _AddFilesButtonState();
}

class _AddFilesButtonState extends ConsumerState<AddFilesButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final message = await pickAndAddFiles(ref);
      if (message != null) widget.onResult(message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _busy ? null : _run,
      icon: _busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add),
      label: const Text('Add files'),
    );
  }
}

/// Wraps [child] so a file dragged onto it is sealed into the vault.
///
/// A pass-through on a platform that cannot drag, so the caller does
/// not need to know which this is.
class VaultDropTarget extends ConsumerStatefulWidget {
  const VaultDropTarget({
    super.key,
    required this.child,
    required this.onResult,
  });

  final Widget child;
  final void Function(String message) onResult;

  @override
  ConsumerState<VaultDropTarget> createState() => _VaultDropTargetState();
}

class _VaultDropTargetState extends ConsumerState<VaultDropTarget> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!canDropFiles) return widget.child;

    return DropTarget(
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: (detail) async {
        setState(() => _hovering = false);
        final message = await addFilesToVault(ref, [
          for (final file in detail.files)
            (name: file.name, read: () => File(file.path).readAsBytes()),
        ]);
        if (message != null) widget.onResult(message);
      },
      child: Stack(
        children: [
          widget.child,
          if (_hovering)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: DeadDropColors.accent.withValues(alpha: 0.12),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: DeadDropColors.bgElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: DeadDropColors.accent),
                      ),
                      child: const Text('Drop to add to the vault'),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
