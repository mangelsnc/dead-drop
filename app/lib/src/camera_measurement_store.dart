/// camera_measurement_store.dart — remembering what this device's camera
/// managed last time, so the next handshake QR can say so.
///
/// The hint in the handshake QR has an ordering problem. The receiver shows
/// its QR *before* it starts reading anything, so at the moment the code is
/// drawn there is nothing measured yet: the camera has not run. Starting it
/// early, just to measure, would turn on a camera nobody asked to turn on.
///
/// So the measurement is kept from the previous reception and used for the
/// next one. This is honest for the case it serves — the same laptop, the
/// same webcam, often the same room — and it degrades the right way: a
/// first-ever reception simply carries no hint, exactly as before, and the
/// sender uses its own defaults.
///
/// A stale measurement is the known weakness. A reading taken in good light
/// and reused in a dark room suggests a stream the camera can no longer
/// follow. Two things bound the damage: the sender can override every
/// value, and the receiver's own screen shows what it is announcing, so a
/// wrong figure is visible rather than silent. Measurements older than
/// [kMeasurementMaxAge] are discarded rather than trusted.
///
/// Not secret, and deliberately not in the vault: a camera's frame rate
/// says nothing about what was transferred, and writing it per environment
/// would make the file's presence depend on which environment was open.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'capability_hint.dart';

/// How long a measurement is trusted.
///
/// A fortnight covers "the same laptop later in the week" without carrying
/// a reading from a camera, a room or a phone the user has since changed.
const Duration kMeasurementMaxAge = Duration(days: 14);

/// A camera measurement and when it was taken.
class StoredMeasurement {
  const StoredMeasurement({required this.capability, required this.takenAt});

  final CameraCapability capability;
  final DateTime takenAt;
}

/// Reads and writes the last camera measurement.
///
/// [directory] is injectable so tests do not touch the real app support
/// directory; production resolves it through `path_provider`.
class CameraMeasurementStore {
  CameraMeasurementStore({this.directory, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final Directory? directory;
  final DateTime Function() _now;

  static const _fileName = 'camera_measurement.json';

  Future<File> _file() async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// The last measurement, or null when there is none worth using.
  ///
  /// Null covers every failure: no file, unreadable file, malformed
  /// contents, nonsensical numbers, or a reading older than
  /// [kMeasurementMaxAge]. Null is a safe answer — the QR carries no hint
  /// and the sender uses its defaults, which is what happened before this
  /// existed.
  Future<StoredMeasurement?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;

      final doc = jsonDecode(await file.readAsString());
      if (doc is! Map) return null;

      final fps = doc['fps'];
      final width = doc['w'];
      final height = doc['h'];
      final rate = doc['rate'];
      final at = doc['at'];
      if (fps is! num || width is! int || height is! int || at is! int) {
        return null;
      }
      // A camera cannot run at zero or a thousand frames a second, and a
      // zero-pixel frame is not a frame. Values outside the plausible
      // range mean a corrupt file, not a strange camera.
      if (fps <= 0 || fps > 240 || width <= 0 || height <= 0) return null;

      final takenAt = DateTime.fromMillisecondsSinceEpoch(at);
      if (_now().difference(takenAt) > kMeasurementMaxAge) return null;

      return StoredMeasurement(
        capability: CameraCapability(
          framesPerSecond: fps.toDouble(),
          width: width,
          height: height,
          decodeRate: rate is num && rate >= 0 && rate <= 1
              ? rate.toDouble()
              : null,
        ),
        takenAt: takenAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// Stores [capability] as this device's latest measurement.
  ///
  /// A failed write is swallowed. The next handshake simply carries no
  /// hint, which is the behaviour this feature improves on rather than
  /// depends on.
  Future<void> write(CameraCapability capability) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({
        'fps': capability.framesPerSecond,
        'w': capability.width,
        'h': capability.height,
        if (capability.decodeRate != null) 'rate': capability.decodeRate,
        'at': _now().millisecondsSinceEpoch,
      }));
    } catch (_) {
      // See above.
    }
  }

  /// Removes any stored measurement. Used when the user asks the app to
  /// stop announcing one.
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Nothing to report: the next read fails closed to null anyway.
    }
  }

  @visibleForTesting
  Future<File> debugFile() => _file();
}
