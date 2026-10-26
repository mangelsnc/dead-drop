/// vault_setup_page.dart — first-run vault creation and decoy provisioning.
///
/// Generation is the default path here, not an afterthought. A review of
/// [estimateStrength] found it scores a famous line of Shakespeare
/// ('tobeornottobethatisthequestion') at ~88 bits, when a phrase-list
/// attacker who simply tries well-known quotes would find it in the first
/// ~20-27 bits of search space — the estimator cannot recognise "famous",
/// only "structurally predictable". An entropy estimate is advisory; a
/// passphrase drawn uniformly at random by [generatePassphrase] is a
/// guarantee regardless of what a human might have picked instead. So this
/// screen leads with a generated six-word passphrase, displayed and
/// copyable, and only offers "type my own" as the secondary choice — and
/// when a user does take that path, the copy says plainly that a
/// self-chosen phrase can be weaker than it looks.
///
/// This same page, with [isDecoy] set, provisions the decoy (slot 1). An
/// empty decoy is worse than no decoy at all — it reads as a space
/// something was removed from — so the decoy flow does not let the user
/// walk away thinking "done" without being told to add something to it
/// first.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../src/vault/passphrase_strength.dart';
import '../theme.dart';
import '../technical_text.dart';
import 'vault_controller.dart';
import 'vault_page.dart';

/// Setup screen for creating the real vault (slot 0) or provisioning the
/// decoy (slot 1), depending on [isDecoy].
class VaultSetupPage extends ConsumerStatefulWidget {
  const VaultSetupPage({super.key, this.isDecoy = false});

  /// When true, this screen provisions the decoy environment via
  /// [VaultController.addDecoy] instead of creating the real vault via
  /// [VaultController.createVault]. The real vault (slot 0) must already
  /// exist — callers only reach this screen with [isDecoy] true from
  /// Settings, which itself only renders once slot 0 is open.
  final bool isDecoy;

  @override
  ConsumerState<VaultSetupPage> createState() => _VaultSetupPageState();
}

class _VaultSetupPageState extends ConsumerState<VaultSetupPage> {
  /// Whether the user is on the generated-passphrase path (the default) or
  /// has switched to typing their own.
  bool _typingOwn = false;

  List<String>? _generatedWords;
  final _ownController = TextEditingController();
  bool _savedAcknowledged = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateNew();
    _ownController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ownController.dispose();
    super.dispose();
  }

  void _generateNew() {
    final sodium = ref.read(sodiumSumoProvider);
    if (sodium == null) return;
    setState(() {
      _generatedWords = generatePassphrase(sodium);
      _savedAcknowledged = false;
    });
  }

  String get _generatedPassphrase => (_generatedWords ?? const []).join(' ');

  StrengthResult? get _ownStrength {
    if (_ownController.text.isEmpty) return null;
    return estimateStrength(_ownController.text);
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (_typingOwn) {
      final strength = _ownStrength;
      return strength != null && strength.meetsMinimum;
    }
    return _savedAcknowledged && _generatedWords != null;
  }

  Future<void> _submit() async {
    final passphrase = _typingOwn ? _ownController.text : _generatedPassphrase;
    setState(() {
      _submitting = true;
      _error = null;
    });

    final controller = ref.read(vaultControllerProvider.notifier);
    if (widget.isDecoy) {
      await controller.addDecoy(passphrase);
    } else {
      await controller.createVault(passphrase);
    }

    if (!mounted) return;
    final state = ref.read(vaultControllerProvider);
    if (state.error != null) {
      setState(() {
        _submitting = false;
        _error = state.error;
      });
      return;
    }

    if (widget.isDecoy) {
      // An empty decoy is worse than none — send the user straight into it
      // so the next thing they see is "this has nothing in it", not a
      // "setup complete" screen that invites them to consider it finished.
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const VaultPage()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const VaultPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDecoy ? 'Set up decoy' : 'Set up your vault'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isDecoy) ...[
                const _DecoyWarningBanner(),
                const SizedBox(height: 24),
              ],
              Text(
                widget.isDecoy
                    ? 'Choose a decoy passphrase'
                    : 'Choose your passphrase',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'A generated passphrase is the safest choice: every word is '
                'drawn at random, so it carries no pattern an attacker could '
                'guess from knowing you.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: DeadDropColors.textSecondary),
              ),
              const SizedBox(height: 24),
              if (!_typingOwn) _buildGeneratedSection(theme),
              if (_typingOwn) _buildOwnSection(theme),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _typingOwn = !_typingOwn),
                  child: Text(
                    _typingOwn
                        ? 'Use a generated passphrase instead'
                        : 'Type my own instead',
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: DeadDropColors.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _canSubmit ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.isDecoy ? 'Create decoy' : 'Create vault'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGeneratedSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: DeadDropColors.bgElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DeadDropColors.borderInput),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                key: const Key('generatedPassphrase'),
                _generatedPassphrase,
                textAlign: TextAlign.center,
                style: technicalTextStyle(ref, relativeTo: 1.23)
                    .copyWith(height: 1.6),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      unawaited(Clipboard.setData(
                        ClipboardData(text: _generatedPassphrase),
                      ));
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _submitting ? null : _generateNew,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('New phrase'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _savedAcknowledged,
          onChanged: _submitting
              ? null
              : (v) => setState(() => _savedAcknowledged = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'I have written down or copied this passphrase somewhere safe',
          ),
        ),
      ],
    );
  }

  Widget _buildOwnSection(ThemeData theme) {
    final strength = _ownStrength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: DeadDropColors.bgElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DeadDropColors.warning),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  color: DeadDropColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A phrase you choose yourself can be weaker than it '
                  'looks. Our strength check cannot recognise famous '
                  'quotes, song lyrics, or phrases specific to you — it only '
                  'spots common patterns. The estimate below is advice, not '
                  'a guarantee.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        TextField(
          controller: _ownController,
          obscureText: false,
          decoration: const InputDecoration(
            labelText: 'Passphrase',
          ),
        ),
        const SizedBox(height: 12),
        if (strength != null)
          Text(
            strength.advice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: strength.meetsMinimum
                  ? DeadDropColors.success
                  : DeadDropColors.error,
            ),
          ),
      ],
    );
  }
}

class _DecoyWarningBanner extends StatelessWidget {
  const _DecoyWarningBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DeadDropColors.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DeadDropColors.borderButton),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined,
              color: DeadDropColors.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'An empty decoy is worse than no decoy at all — it reads as '
              'a space something was removed from. Add at least one file '
              'to it once it is set up.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
