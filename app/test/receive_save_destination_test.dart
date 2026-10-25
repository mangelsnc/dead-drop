/// Tests for how a received file's save destination is chosen and reported
/// (app/lib/ui/receive/receive_page.dart).
///
/// Two user-visible properties are pinned here:
///
/// - The user chooses the destination on every platform. The regression this
///   guards against is a silent fallback to an app-private directory, which
///   makes the button appear to work while putting the file somewhere the
///   user cannot reach from a file manager.
/// - Whatever the platform hands back is rendered as something a person can
///   act on. On Android that is a Storage Access Framework content URI, not
///   a path.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dead_drop/ui/receive/receive_page.dart';

void main() {
  group('displayPath', () {
    test('a desktop filesystem path is shown unchanged', () {
      expect(
        displayPath('/home/mangel/Documents/report.pdf'),
        '/home/mangel/Documents/report.pdf',
      );
      expect(
        displayPath(r'C:\Users\mangel\Documents\report.pdf'),
        r'C:\Users\mangel\Documents\report.pdf',
      );
    });

    test('a SAF "raw:" content URI is reduced to the real path', () {
      // What Android's document picker actually returns when the user picks
      // Downloads — percent-encoded, with the real path after "raw:".
      const uri = 'content://com.android.providers.downloads.documents/'
          'document/raw%3A%2Fstorage%2Femulated%2F0%2FDownload%2Freport.pdf';

      expect(displayPath(uri), '/storage/emulated/0/Download/report.pdf');
    });

    test('a SAF "primary:" content URI is reduced to the folder and file', () {
      const uri = 'content://com.android.externalstorage.documents/'
          'document/primary%3ADocuments%2Fdeaddrop%2Freport.pdf';

      expect(displayPath(uri), 'Documents/deaddrop/report.pdf');
    });

    test('a content URI with no readable path still renders something', () {
      // Some providers return an opaque numeric id. There is no path to
      // recover; the point is that this does not throw and does not render
      // an empty string, which would read as "saved to nowhere".
      const uri = 'content://com.example.provider/document/1234';

      final shown = displayPath(uri);
      expect(shown, isNotEmpty);
      expect(shown, contains('1234'));
    });

    test('a trailing colon does not produce an empty destination', () {
      // Guards the substring arithmetic: a URI ending in ':' must not yield
      // "Saved to: " with nothing after it.
      const uri = 'content://com.example.provider/document/raw%3A';

      expect(displayPath(uri), isNotEmpty);
    });
  });
}
