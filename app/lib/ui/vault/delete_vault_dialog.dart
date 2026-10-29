/// delete_vault_dialog.dart — confirming the erasure of a vault.
///
/// Two properties this dialog exists to hold, both of which a more
/// convenient design would quietly break.
///
/// **It never mentions the decoy.** Not "this will also delete your decoy",
/// not a second option for erasing one environment. A dialog whose wording
/// or options depend on whether a second environment was ever created is
/// a disclosure channel: an attacker reading over a coerced user's
/// shoulder learns from the screen what the passphrase was meant to hide.
/// The copy is identical for a vault with one environment and a vault with
/// two, so it says "everything in it", which is true in both cases.
///
/// **It asks for a typed confirmation, not a passphrase.** It used to ask
/// for the passphrase, which protected nothing: the vault is in the app's
/// data directory, so anyone with the unlocked phone can already erase it
/// from the system's settings or by uninstalling. What it did do was
/// strand the owner who had forgotten it — and, because a wrong guess
/// counted as a failed attempt, let them trip self-destruct while trying
/// to delete their own vault.
///
/// What is left to guard against is the accident, and a word typed on
/// purpose does that. Deleting discloses nothing: it does not unlock,
/// does not show an entry, and does not reveal whether a decoy exists.
/// The data was encrypted and stays encrypted — better deleted than read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import 'vault_controller.dart';

/// The word the user types to confirm.
///
/// Deliberately the plain English imperative rather than the vault's name
/// or a phrase: it has to be readable and typable by someone who is not
/// a native speaker and is already having a bad day.
const String kDeleteConfirmationWord = 'DELETE';

/// Whether [input] confirms the deletion.
///
/// Case and surrounding spaces are forgiven — a phone keyboard
/// capitalises and trails spaces on its own, and refusing "delete " would
/// be pedantry, not safety. What is not forgiven is a different word:
/// the point is that something was typed on purpose.
bool confirmsDeletion(String input) =>
    input.trim().toUpperCase() == kDeleteConfirmationWord;

/// Shows the delete-vault dialog. Returns true when the vault was erased.
Future<bool> showDeleteVaultDialog(BuildContext context) async {
  final erased = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DeleteVaultDialog(),
  );
  return erased ?? false;
}

class _DeleteVaultDialog extends ConsumerStatefulWidget {
  const _DeleteVaultDialog();

  @override
  ConsumerState<_DeleteVaultDialog> createState() => _DeleteVaultDialogState();
}

class _DeleteVaultDialogState extends ConsumerState<_DeleteVaultDialog> {
  final _controller = TextEditingController();
  bool _working = false;

  @override
  void initState() {
    super.initState();
    // The Delete button enables as soon as the word is right, so the
    // field has to be watched rather than read on submit.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!confirmsDeletion(_controller.text)) return;
    setState(() => _working = true);

    await ref.read(vaultControllerProvider.notifier).deleteVault();

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final confirmed = confirmsDeletion(_controller.text);

    return AlertDialog(
      title: const Text('Delete vault?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This erases the vault and everything in it. It cannot be '
            'undone, and there is no copy anywhere else.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Type $kDeleteConfirmationWord to confirm',
            ),
            onSubmitted: _working ? null : (_) => _delete(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: DeadDropColors.error,
          ),
          onPressed: (_working || !confirmed) ? null : _delete,
          child: _working
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Delete vault'),
        ),
      ],
    );
  }
}
