/// info_point.dart — a tappable (i) that explains a transfer setting.
///
/// The three settings on the send screen — chunk size, frame rate and
/// error correction — are the knobs that decide whether a transfer reads
/// at all, and all three are meaningless to someone who has not thought
/// about how a QR code carries data. The app picks sensible values and
/// the receiver's camera refines them, so nobody *has* to touch these;
/// but when a transfer is not reading, these are what the user is told
/// to change, and changing a control you do not understand is guesswork.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// A small (i) that opens a dialog explaining one setting.
///
/// A dialog rather than a tooltip: a tooltip needs a hover, which a
/// phone does not have, and long-press is not discoverable. The text is
/// several sentences, which is more than a tooltip should hold anyway.
class InfoPoint extends StatelessWidget {
  const InfoPoint({
    super.key,
    required this.title,
    required this.body,
  });

  /// The setting's name, as the heading of the dialog.
  final String title;

  /// What the setting does, what raising it costs, and what to do when a
  /// transfer is not reading.
  final String body;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.info_outline, size: 18),
      color: DeadDropColors.textSecondary,
      // The icon is small, so the tap target is padded out to something
      // a finger can hit rather than something a cursor can.
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      tooltip: 'What is $title?',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the (i) next to each transfer setting says.
///
/// Kept together so the three read as one explanation rather than three
/// unrelated ones: each says what the setting does, which way to move it
/// when a transfer is not reading, and what that costs. They are written
/// for someone who has never thought about how a QR carries data.
abstract final class SettingHelp {
  static const chunkSize = 'How much of the file travels in each QR '
      'code.\n\n'
      'Bigger chunks mean fewer codes to show, so the transfer finishes '
      'sooner. But a bigger chunk makes a denser code — more, smaller '
      'squares — and a camera needs enough pixels on each square to '
      'read it.\n\n'
      'If the receiver is not reading anything, try a smaller chunk. It '
      'will take longer, but a slow transfer beats one that never '
      'starts.\n\n'
      'The app picks a size that fits your file, and the receiver\'s '
      'camera suggests one that suits it. You only need this if that is '
      'not working.';

  static const frameRate = 'How many QR codes are shown per second.\n\n'
      'Faster means the transfer finishes sooner, but the receiving '
      'camera has to catch each code while it is on screen. A camera '
      'that cannot keep up simply misses codes, and they have to come '
      'round again.\n\n'
      'If the receiver is reading slowly or stalling, lower this. '
      'Nothing is lost when a code is missed — the transfer just takes '
      'longer.';

  static const errorCorrection =
      'How much of each QR code is spare, so it can still be read when '
      'part of it is unclear.\n\n'
      'A higher level survives glare, a smudged screen, an awkward '
      'angle or a shaky hand. The spare part takes room that would '
      'otherwise carry your file, so a higher level means either a '
      'denser code or more codes to show.\n\n'
      'L is enough between two steady screens in good light. Move up if '
      'the receiver is struggling, especially hand-held or under a '
      'bright lamp.';

  static const brightness =
      'How bright this screen is while it is showing the codes.\n\n'
      'Full brightness is usually right: the camera needs to tell the '
      'dark squares from the light ones, and a dim screen makes that '
      'harder.\n\n'
      'Lower it if the receiving camera adjusts to the brightness and '
      'washes the code out. Webcams do this more than phones — they '
      'measure the whole bright screen, close down, and the dark '
      'squares come out grey. If the other device sees the code but '
      'cannot read it, try lowering this before anything else.';
}
