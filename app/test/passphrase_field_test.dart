/// Tests for the passphrase input (app/lib/ui/passphrase_field.dart).
///
/// A vault passphrase is six random words. Nobody types that from muscle
/// memory, and in a masked field a typo is invisible: the only feedback is
/// "wrong passphrase", which does not distinguish a mistyped word from a
/// misremembered one. Each failed attempt also counts towards self-destruct.
///
/// So the field can be revealed. What the tests pin is that it starts
/// masked where the user is typing a phrase back in — the case where
/// someone is plausibly nearby — and that the keyboard never "corrects"
/// a word, which would silently produce a passphrase they cannot
/// reproduce.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/ui/passphrase_field.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void main() {
  testWidgets('starts masked by default', (tester) async {
    await tester.pumpWidget(_wrap(
      PassphraseField(controller: TextEditingController()),
    ));

    expect(_field(tester).obscureText, isTrue);
  });

  testWidgets('tapping the eye reveals the text, and again hides it',
      (tester) async {
    final controller = TextEditingController(text: 'correct horse battery');
    await tester.pumpWidget(_wrap(PassphraseField(controller: controller)));

    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();
    expect(_field(tester).obscureText, isFalse);

    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pumpAndSettle();
    expect(_field(tester).obscureText, isTrue,
        reason: 'the user must be able to hide it again when someone walks in');
  });

  testWidgets('starts readable where the user is choosing a phrase',
      (tester) async {
    await tester.pumpWidget(_wrap(
      PassphraseField(
        controller: TextEditingController(),
        startVisible: true,
      ),
    ));

    expect(_field(tester).obscureText, isFalse);
  });

  testWidgets('never autocorrects or suggests', (tester) async {
    // The property that silently destroys a passphrase: a keyboard
    // "fixing" staple to stable produces something the user cannot
    // reproduce, and nothing on screen says it happened.
    await tester.pumpWidget(_wrap(
      PassphraseField(controller: TextEditingController()),
    ));

    final field = _field(tester);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets('revealing does not disturb what was typed', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_wrap(PassphraseField(controller: controller)));

    await tester.enterText(find.byType(TextField), 'six random words here ok');
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();

    expect(controller.text, 'six random words here ok');
  });

  testWidgets('reports changes while hidden and while shown',
      (tester) async {
    // vault_setup_page drives a live strength meter off this field.
    final seen = <String>[];
    await tester.pumpWidget(_wrap(
      PassphraseField(
        controller: TextEditingController(),
        onChanged: seen.add,
      ),
    ));

    await tester.enterText(find.byType(TextField), 'one');
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'two');

    expect(seen, ['one', 'two']);
  });
}
