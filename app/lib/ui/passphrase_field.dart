/// passphrase_field.dart — a passphrase input you can read back.
///
/// The vault asks for six random words, not a password someone invented
/// and types daily. Nobody has that in muscle memory, and a typo in a
/// masked field of forty-odd characters is invisible: the only feedback
/// is "wrong passphrase", with no way to tell a mistyped word from a
/// misremembered one. Worse, each failed attempt counts towards
/// self-destruct when it is enabled.
///
/// So the field can be revealed. Masked by default, because the normal
/// case is unlocking with someone nearby; a tap shows it when the user
/// decides that is safe. That choice belongs to them — they can see the
/// room, the app cannot.
///
/// The choice is about the room they are in *now*, so it does not
/// outlive the attempt: [remask] lets the caller hide the text again
/// after a failure, which is the moment someone leans over to see what
/// went wrong.
library;

import 'package:flutter/material.dart';

class PassphraseField extends StatefulWidget {
  const PassphraseField({
    super.key,
    required this.controller,
    this.labelText = 'Passphrase',
    this.helperText,
    this.autofocus = false,
    this.startVisible = false,
    this.remask,
    this.onSubmitted,
    this.onChanged,
    this.textStyle,
  });

  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final bool autofocus;

  /// Whether the text starts readable. True where the user is choosing
  /// a phrase and has to read it; false where they are typing a known
  /// one back in, which is usually with someone nearby.
  final bool startVisible;

  /// Ticked by the caller to hide the text again.
  ///
  /// Revealing is a decision about the room the user is in at that
  /// moment. A wrong passphrase is the moment someone leans over to see
  /// what went wrong, and the phrase has to be retyped anyway, so
  /// re-masking costs nothing and stops a reveal outliving the
  /// circumstances it was granted under. The caller holds the counter
  /// because only it knows an attempt failed.
  final int? remask;

  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// Usually the shared technical-text style, so the size setting in
  /// Settings reaches this field too.
  final TextStyle? textStyle;

  @override
  State<PassphraseField> createState() => _PassphraseFieldState();
}

class _PassphraseFieldState extends State<PassphraseField> {
  late bool _visible = widget.startVisible;

  @override
  void didUpdateWidget(PassphraseField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.remask != oldWidget.remask) {
      setState(() => _visible = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      autofocus: widget.autofocus,
      style: widget.textStyle,
      // A passphrase is words, but the keyboard must not "correct" them:
      // the whole point is that they are random, and an autocorrect that
      // helpfully fixes "staple" to "stable" produces a passphrase the
      // user cannot reproduce and will never understand why.
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: widget.labelText,
        helperText: widget.helperText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          tooltip: _visible ? 'Hide passphrase' : 'Show passphrase',
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
      onChanged: widget.onChanged,
      onSubmitted:
          widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
    );
  }
}
