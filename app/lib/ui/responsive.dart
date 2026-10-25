/// responsive.dart — shared layout rules for phone and desktop windows.
///
/// This app is built phone-first, which is right: the coercion scenario the
/// vault defends against is a phone-in-hand scenario, and a camera pointed
/// at another screen is a phone gesture. But the desktop builds are first-
/// class deliverables too (the contest requires Windows, macOS and Linux),
/// and a phone layout in a 1280x720 window is a single tall column that
/// scrolls while most of the window sits empty.
///
/// These are the two decisions that stops that, in one place so the send and
/// receive pages cannot drift apart: where "wide" begins, and how wide a
/// column is allowed to get.
library;

import 'package:flutter/widgets.dart';

/// Width at or above which a window is laid out as a desktop window.
///
/// 900 logical pixels: comfortably above a large phone in landscape (a
/// Pixel 8 Pro is 892) and below the 1280 default of the Linux and Windows
/// runners, so a desktop window gets the desktop layout at its default size
/// without the user resizing anything. A tablet in portrait stays in the
/// single-column layout, which is the right call — it is still a
/// hold-in-two-hands device.
const double kWideLayoutBreakpoint = 900;

/// The widest a single column of content is allowed to be.
///
/// Without this a maximised window stretches every button and text field
/// across the full screen, which is harder to read and to aim at than a
/// column of a comfortable width — the line length stops being scannable
/// well before the window runs out of room.
const double kMaxContentWidth = 1100;

/// Whether [context]'s window should use the desktop layout.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

/// Centres [child] and stops it growing past [kMaxContentWidth].
class ContentWidthLimit extends StatelessWidget {
  const ContentWidthLimit({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
        child: child,
      ),
    );
  }
}

/// Lays [children] out in one column on a phone and two on a desktop window.
///
/// [start] is the column that gets the primary actions; [end] takes the
/// supporting material. In the narrow layout they are concatenated, [start]
/// first, so reading order is preserved and nothing is hidden — the narrow
/// layout is never a reduced version of the wide one.
///
/// Both columns are top-aligned rather than stretched: the two sides hold
/// different amounts of content, and stretching makes the shorter one grow
/// mysterious vertical gaps.
class TwoColumnLayout extends StatelessWidget {
  const TwoColumnLayout({
    super.key,
    required this.start,
    required this.end,
    this.spacing = 24,
  });

  final List<Widget> start;
  final List<Widget> end;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [...start, ...end],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: start,
          ),
        ),
        SizedBox(width: spacing),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: end,
          ),
        ),
      ],
    );
  }
}
