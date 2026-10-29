/// Deleting the vault takes a typed word, not a passphrase.
///
/// The passphrase protected nothing — the vault sits in the app's data
/// directory, so anyone with the unlocked phone can erase it from system
/// settings or by uninstalling — while stranding the owner who had
/// forgotten it. What remains worth guarding against is the accident,
/// and that is what the typed word does.
library;

import 'package:dead_drop/ui/vault/delete_vault_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('confirmsDeletion', () {
    test('accepts the word', () {
      expect(confirmsDeletion('DELETE'), isTrue);
    });

    test('forgives what a phone keyboard does on its own', () {
      // Autocapitalisation and a trailing space are the keyboard's
      // doing, not the user's: refusing them is pedantry, not safety.
      expect(confirmsDeletion('delete'), isTrue);
      expect(confirmsDeletion('Delete'), isTrue);
      expect(confirmsDeletion('DELETE '), isTrue);
      expect(confirmsDeletion('  delete  '), isTrue);
    });

    test('rejects anything that is not the word', () {
      // The point is that something was typed deliberately, so a near
      // miss is still a miss.
      for (final input in const [
        '',
        ' ',
        'DELET',
        'DELETED',
        'DELETE VAULT',
        'yes',
        'y',
        'borrar',
        'D',
      ]) {
        expect(confirmsDeletion(input), isFalse, reason: 'input: "$input"');
      }
    });

    test('an empty field never confirms', () {
      // The specific accident this guards: a dialog dismissed by a
      // stray tap on the destructive button.
      expect(confirmsDeletion(''), isFalse);
    });

    test('the word is the one the dialog tells the user to type', () {
      // A label and a check that disagree would make the dialog
      // impossible to satisfy.
      expect(confirmsDeletion(kDeleteConfirmationWord), isTrue);
    });
  });
}
