/// file_drop.dart — whether this platform can accept a dragged file.
///
/// Dragging a file onto a window is a desktop gesture. There is nothing
/// to drag from on a phone, so the vault offers the button there and
/// both here: the button is the thing every platform has, and the drop
/// target is an extra on the platforms where it means something.
///
/// Kept behind a named getter rather than a `Platform.isX` at the call
/// site for the reason screen_wake.dart gives: `dart:io` is not
/// something a widget test can fake, and a layout that only one
/// platform renders is a layout no test ever sees.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Overrides the platform check in tests.
@visibleForTesting
bool? debugCanDropFilesOverride;

/// Whether a file can be dragged onto this app's window.
///
/// macOS, Linux and Windows. A phone has no desktop to drag from.
bool get canDropFiles =>
    debugCanDropFilesOverride ??
    (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
