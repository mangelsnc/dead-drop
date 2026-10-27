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
/// **It asks for a passphrase.** Erasing is destructive and irreversible,
/// and an unlocked phone in someone else's hands must not be enough to
/// destroy the owner's files. Any environment's passphrase works, and any
/// of them erases the whole vault — see [VaultController.deleteVault].
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../passphrase_field.dart';
import '../theme.dart';
import 'vault_controller.dart';

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
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    setState(() {
      _working = true;
      _error = null;
    });

    final ok = await ref
        .read(vaultControllerProvider.notifier)
        .deleteVault(_controller.text);

    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _working = false;
      _error = 'Incorrect passphrase';
    });
  }

  @override
  Widget build(BuildContext context) {
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
          PassphraseField(
            controller: _controller,
            autofocus: true,
            labelText: 'Passphrase',
            helperText: 'Required, so a phone left unlocked cannot be '
                'wiped by someone else.',
            onSubmitted: _working ? null : _delete,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DeadDropColors.error,
                  ),
            ),
          ],
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
          onPressed: _working ? null : _delete,
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
