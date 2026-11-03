/// qr_raster.dart — turn a QR payload into an image, once, ahead of time.
///
/// ## Why this exists
///
/// `QrPainter` walks the code's modules and issues one `canvas.drawRect`
/// per module. A 512-byte chunk encodes to a version 18 code: 89×89, so
/// **7,921 rectangles per frame**, redrawn from scratch every time the
/// code changes — which on the sending screen is every frame.
///
/// Measured in the dev container on 2026-11-03, 578 px, version pinned:
///
/// | | per frame |
/// |---|---|
/// | build the draw list (7,921 rects) | 14.4 ms |
/// | build it and rasterise to an image | 17.9 ms |
/// | draw an image already rasterised | **0.196 ms** |
///
/// Drawing a finished image is 73× cheaper than drawing the modules. The
/// container renders in software on an emulated CPU, so the absolute
/// figures are not the ones a real machine sees — the ratio is the point.
///
/// On real hardware the sending screen's whole frame was measured at
/// 132 ms on a MacBook Pro M3 and 547 ms on a Slimbook running Kali,
/// against a 66 ms budget at 15 fps. The Slimbook emitted 1.8 of the
/// 15 fps it was asked for.
///
/// ## How it is used
///
/// The sender knows the next code before it has to show it, so the
/// rasterisation happens while the previous code is still on screen —
/// in time that is otherwise spent waiting for a timer. What lands in
/// the frame is the 0.196 ms draw.
///
/// ## Pinning the version
///
/// `QrVersions.auto` searches for a version by trying sizes: 2.38 ms,
/// against 0.007 ms when the version is given. It is a small part of the
/// total, but the search is pure waste here — every frame of a transfer
/// carries the same payload size, so the version found for the first is
/// the version for all of them. [QrRasteriser] therefore finds it once
/// and reuses it, falling back to a fresh search if a payload turns out
/// not to fit.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A QR code rendered to an image, with the payload it came from.
///
/// [image] must be disposed when it is no longer displayed; [QrRasteriser]
/// does that for the images it replaces.
class RasterisedQr {
  const RasterisedQr({
    required this.payload,
    required this.image,
    required this.sizePx,
  });

  /// The exact string this image encodes. The display compares it against
  /// what it was asked to show, so a stale image is never presented as a
  /// current one.
  final String payload;

  final ui.Image image;

  /// The square edge the image was rendered at, in physical pixels.
  final int sizePx;

  void dispose() => image.dispose();
}

/// Renders QR payloads to images, reusing the version it discovers.
///
/// Not a widget and not tied to one: the send page owns an instance for
/// the length of a transfer and disposes it at the end.
class QrRasteriser {
  QrRasteriser({required this.errorCorrectionLevel});

  /// The level the transfer is configured with. A change makes any cached
  /// version wrong, so the owner builds a new rasteriser rather than
  /// mutating this.
  final int errorCorrectionLevel;

  /// The version found for the first payload, reused for the rest.
  ///
  /// Null until the first call, and reset to null whenever a payload does
  /// not fit it — see [rasterise].
  int? _version;

  /// Which version this rasteriser is reusing, for tests and diagnostics.
  int? get pinnedVersion => _version;

  /// How many times a payload did not fit the pinned version.
  ///
  /// Expected to stay at zero during a transfer: every frame carries the
  /// same chunk size. A non-zero count means the assumption behind pinning
  /// is wrong for some payload, which is worth knowing rather than
  /// silently absorbing.
  int get versionMisses => _versionMisses;
  int _versionMisses = 0;

  /// Renders [payload] at [sizePx] square.
  ///
  /// Returns null when the payload cannot be encoded at all — too long for
  /// any version at this error-correction level. The caller shows nothing
  /// rather than a wrong code.
  Future<RasterisedQr?> rasterise(String payload, int sizePx) async {
    if (sizePx <= 0) return null;

    var qr = _encode(payload, _version);
    if (qr == null && _version != null) {
      // The payload outgrew the version found for an earlier one. Search
      // again rather than fail: a bootstrap code and a data code need not
      // be the same size.
      _versionMisses++;
      _version = null;
      qr = _encode(payload, null);
    }
    if (qr == null) return null;
    _version ??= qr.typeNumber;

    final painter = QrPainter.withQr(
      qr: qr,
      gapless: true,
      // Black on nothing: the widget draws the white panel behind this,
      // so the image carries only the modules and keeps its alpha.
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF000000),
      ),
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF000000),
      ),
    );

    final recorder = ui.PictureRecorder();
    painter.paint(
      Canvas(recorder),
      Size(sizePx.toDouble(), sizePx.toDouble()),
    );
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(sizePx, sizePx);
      return RasterisedQr(payload: payload, image: image, sizePx: sizePx);
    } finally {
      picture.dispose();
    }
  }

  /// Encodes [payload], or returns null if it does not fit [version].
  ///
  /// `QrValidator.validate` is not enough on its own: it reports a code
  /// as valid and `QrPainter` then throws `QrInputTooLongException` while
  /// building the matrix, because the length check happens later. A throw
  /// here would reach the emission timer, so the data is built inside the
  /// try as well.
  QrCode? _encode(String payload, int? version) {
    try {
      final result = QrValidator.validate(
        data: payload,
        version: version ?? QrVersions.auto,
        errorCorrectionLevel: errorCorrectionLevel,
      );
      if (!result.isValid || result.qrCode == null) return null;
      // Forces the matrix to be built now, where the throw can be caught,
      // rather than inside QrPainter's constructor.
      QrImage(result.qrCode!);
      return result.qrCode;
    } on Exception {
      return null;
    }
  }
}
