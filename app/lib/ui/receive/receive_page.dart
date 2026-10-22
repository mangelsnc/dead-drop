import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sodium_libs/sodium_libs.dart';

import '../../src/crypto.dart';
import '../../src/handshake.dart';
import '../../src/receiver.dart';
import '../../src/tofu_store.dart';
import '../../src/transport.dart';
import '../../src/utils.dart';
import '../../main.dart';
import '../theme.dart';

/// State for the receive flow.
class ReceiveState {
  ReceiveState({
    this.receiverKeypair,
    this.receiver,
    this.isScanning = false,
    this.framesReceived = 0,
    this.chunksDecoded = 0,
    this.totalChunks = 0,
    this.fileBytes,
    this.fileName,
    this.savedPath,
    this.error,
    this.senderFingerprint,
    this.isNewSender = false,
    this.pendingSender,
  });

  final ReceiverKeypair? receiverKeypair;
  final Receiver? receiver;
  final bool isScanning;
  final int framesReceived;
  final int chunksDecoded;
  final int totalChunks;
  final Uint8List? fileBytes;
  final String? fileName;
  final String? savedPath;
  final String? error;

  /// The sender's identity fingerprint (first 16 hex chars of their
  /// Ed25519 public key), extracted from the verified session header.
  final String? senderFingerprint;

  /// True when this sender fingerprint had never been seen before (TOFU)
  /// and the user accepted it during this session. Kept so the UI can keep
  /// showing the "verify out of band" hint for the rest of the transfer.
  final bool isNewSender;

  /// A verified session from an unrecognised sender, held until the user
  /// accepts or rejects the fingerprint.
  ///
  /// TOFU only means anything if a human looks at the fingerprint the first
  /// time: trust established automatically is not trust. While this is set
  /// the session is NOT armed — [receiver] stays null, incoming data frames
  /// are ignored, and nothing has been written to the TOFU store.
  final PendingSender? pendingSender;

  double get progress =>
      totalChunks > 0 ? chunksDecoded / totalChunks : 0.0;

  bool get sessionActive => receiver != null;

  /// True while an unrecognised sender is waiting for the user's decision.
  bool get awaitingSenderApproval => pendingSender != null;

  ReceiveState copyWith({
    ReceiverKeypair? receiverKeypair,
    Receiver? receiver,
    bool? isScanning,
    int? framesReceived,
    int? chunksDecoded,
    int? totalChunks,
    Uint8List? fileBytes,
    String? fileName,
    String? savedPath,
    String? error,
    String? senderFingerprint,
    bool? isNewSender,
    PendingSender? pendingSender,
    // copyWith's `??` idiom cannot express "set this back to null", and
    // clearing the pending sender is exactly what accept/reject must do.
    bool clearPendingSender = false,
  }) {
    return ReceiveState(
      receiverKeypair: receiverKeypair ?? this.receiverKeypair,
      receiver: receiver ?? this.receiver,
      isScanning: isScanning ?? this.isScanning,
      framesReceived: framesReceived ?? this.framesReceived,
      chunksDecoded: chunksDecoded ?? this.chunksDecoded,
      totalChunks: totalChunks ?? this.totalChunks,
      fileBytes: fileBytes ?? this.fileBytes,
      fileName: fileName ?? this.fileName,
      savedPath: savedPath ?? this.savedPath,
      error: error,
      senderFingerprint: senderFingerprint ?? this.senderFingerprint,
      isNewSender: isNewSender ?? this.isNewSender,
      pendingSender:
          clearPendingSender ? null : (pendingSender ?? this.pendingSender),
    );
  }
}

/// A session whose signature verified but whose sender is unknown to this
/// device, waiting on the user's accept/reject decision.
class PendingSender {
  const PendingSender({required this.receiver, required this.fingerprint});

  final Receiver receiver;
  final String fingerprint;
}

class ReceiveNotifier extends StateNotifier<ReceiveState> {
  ReceiveNotifier(this._sodium, this._tofuStore) : super(ReceiveState());

  final Sodium _sodium;
  final TofuStore _tofuStore;

  Future<void> initKeypair() async {
    if (state.receiverKeypair != null) return;
    final kp = await ReceiverKeypair.generate(_sodium);
    state = state.copyWith(receiverKeypair: kp);
  }

  void startScanning() {
    state = state.copyWith(isScanning: true, error: null);
  }

  void stopScanning() {
    state = state.copyWith(isScanning: false);
  }

  /// Entry point for every QR string the camera picks up. Foreign QRs are
  /// silently ignored; DeadDrop payloads are routed by type.
  Future<void> processRawQr(String raw) async {
    if (state.receiverKeypair == null) return;
    final data = decodeQrPayload(raw);
    if (data == null) return; // not a DeadDrop QR — keep scanning

    // Session bootstrap: fixed-size binary header with "DD" magic.
    if (data.length == SessionHeader.packedSize &&
        data[0] == magic[0] &&
        data[1] == magic[1]) {
      await _processBootstrap(data);
      return;
    }

    // Anything else is treated as a data frame once a session is active.
    if (state.receiver != null && !state.receiver!.done) {
      _processDataFrame(data);
    }
  }

  Future<void> _processBootstrap(Uint8List data) async {
    // Ignore a second identical bootstrap once the session is armed.
    if (state.receiver != null) return;
    try {
      final receiver = Receiver(
        sodium: _sodium,
        keypair: state.receiverKeypair!,
      );
      // startSession() now verifies the Ed25519 signature inside
      // ReceiverSession.accept() — a bad signature throws here.
      await receiver.startSession(data);

      // Extract the sender's identity fingerprint from the verified header.
      // Same derivation the sender shows in its own identity card — both
      // sides must render an identical string or the comparison the user is
      // asked to make is meaningless.
      final fingerprint =
          fingerprintOf(receiver.session!.header.senderVerifyKey);

      // TOFU check: have we seen this sender before?
      final known = await _tofuStore.isKnown(fingerprint);
      if (!known) {
        // An unrecognised sender is held here, NOT armed. The fingerprint is
        // only written to the TOFU store once the user accepts it in
        // acceptPendingSender() — otherwise the first contact would be
        // trusted automatically and every later transfer from an impostor
        // would show up as an already-known sender.
        state = state.copyWith(
          pendingSender:
              PendingSender(receiver: receiver, fingerprint: fingerprint),
          senderFingerprint: fingerprint,
          error: null,
        );
        return;
      }

      state = state.copyWith(
        receiver: receiver,
        totalChunks: receiver.session!.header.chunkCount,
        error: null,
        senderFingerprint: fingerprint,
        isNewSender: false,
      );
    } on DeadDropCryptoError catch (e) {
      state = state.copyWith(error: 'Session rejected: ${e.message}');
    }
  }

  /// The user confirmed the fingerprint out of band: remember the sender and
  /// arm the held session so data frames start decoding.
  Future<void> acceptPendingSender() async {
    final pending = state.pendingSender;
    if (pending == null) return;

    await _tofuStore.markKnown(pending.fingerprint);
    state = state.copyWith(
      receiver: pending.receiver,
      totalChunks: pending.receiver.session!.header.chunkCount,
      isNewSender: true,
      clearPendingSender: true,
      error: null,
    );
  }

  /// The user rejected the sender: drop the session without recording any
  /// trust, and keep scanning.
  void rejectPendingSender() {
    if (state.pendingSender == null) return;
    state = state.copyWith(
      clearPendingSender: true,
      error: 'Sender rejected — the transfer was not accepted.',
    );
  }

  void _processDataFrame(Uint8List data) {
    final receiver = state.receiver!;
    final decodedBefore = receiver.decoder?.decoded.length ?? 0;
    receiver.feedFrame(data);
    final decodedAfter = receiver.decoder?.decoded.length ?? 0;

    state = state.copyWith(
      framesReceived: state.framesReceived + 1,
      chunksDecoded: decodedAfter,
      fileName: receiver.fileName ?? state.fileName,
    );

    if (decodedAfter == decodedBefore && !receiver.done) {
      // Duplicate / redundant / metadata frame — nothing else to do.
      return;
    }

    if (receiver.done) {
      try {
        final fileBytes = receiver.finish();
        state = state.copyWith(
          fileBytes: fileBytes,
          fileName: receiver.fileName ?? state.fileName,
          isScanning: false,
        );
      } catch (e) {
        state = state.copyWith(error: 'Integrity check failed: $e');
      }
    }
  }

  Future<void> saveFile() async {
    if (state.fileBytes == null) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save received file',
      fileName: state.fileName ??
          'deaddrop_received_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (path == null) return;
    final file = File(path);
    await file.writeAsBytes(state.fileBytes!);
    state = state.copyWith(savedPath: path);
  }

  void reset() {
    state = ReceiveState(receiverKeypair: state.receiverKeypair);
  }
}

final receiveProvider =
    StateNotifierProvider<ReceiveNotifier, ReceiveState>((ref) {
  final sodium = ref.watch(sodiumProvider);
  final tofuStore = ref.watch(tofuStoreProvider);
  return ReceiveNotifier(sodium, tofuStore);
});

class ReceivePage extends ConsumerStatefulWidget {
  const ReceivePage({super.key});

  @override
  ConsumerState<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends ConsumerState<ReceivePage> {
  MobileScannerController? _scannerController;

  /// Whether the receiver public key is shown as text instead of a QR code.
  /// The text view helps when the sender cannot scan (no camera, small or
  /// cracked screen, focus issues) and needs to type or paste the key.
  bool _showKeyAsText = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(receiveProvider.notifier).initKeypair();
    });
  }

  @override
  void dispose() {
    _stopScanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiveProvider);
    final notifier = ref.read(receiveProvider.notifier);

    // Stop the camera as soon as the transfer completes.
    ref.listen(receiveProvider, (prev, next) {
      if (next.fileBytes != null && (prev?.fileBytes == null)) {
        _stopScanner();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Receive a file')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step 1: show our public key so the sender can address the file
            // to us (handshake).
            _StepCard(
              step: 1,
              title: 'Your public key',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.receiverKeypair != null) ...[
                    Center(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.qr_code_2),
                            label: Text('QR'),
                          ),
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.text_fields),
                            label: Text('Text'),
                          ),
                        ],
                        selected: {_showKeyAsText},
                        onSelectionChanged: (selection) {
                          setState(() => _showKeyAsText = selection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_showKeyAsText)
                      _PublicKeyTextView(
                        publicKey: state.receiverKeypair!.publicKey,
                      )
                    else
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius:
                                BorderRadius.all(Radius.circular(12)),
                          ),
                          child: QrImageView(
                            data: encodeHandshakeQr(
                                state.receiverKeypair!.publicKey),
                            version: QrVersions.auto,
                            size: 200,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _showKeyAsText
                          ? 'Share this public key with the sender — they can '
                              'copy it or type it in manually. It contains only '
                              'your public key — the file itself is encrypted '
                              'end-to-end.'
                          : 'Show this QR to the sender. It contains only your '
                              'public key — the file itself is encrypted '
                              'end-to-end.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ] else
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Step 2: scan the sender's bootstrap + data frames.
            _StepCard(
              step: 2,
              title: 'Scan sender QR codes',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!state.isScanning && state.fileBytes == null)
                    FilledButton.icon(
                      onPressed: () {
                        notifier.startScanning();
                        _startScanner();
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: Text(state.sessionActive
                          ? 'Resume scanning'
                          : 'Start scanning'),
                    ),
                  if (state.isScanning) ...[
                    Container(
                      height: 300,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: DeadDropColors.borderInput,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: MobileScanner(
                          controller: _scannerController,
                          onDetect: (capture) {
                            for (final barcode in capture.barcodes) {
                              final raw = barcode.rawValue;
                              if (raw != null) {
                                notifier.processRawQr(raw);
                              }
                            }
                          },
                          errorBuilder: (context, error, child) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.videocam_off,
                                        color: DeadDropColors.error,
                                        size: 48),
                                    const SizedBox(height: 12),
                                    Text(
                                      _mapScannerError(error),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: DeadDropColors.error),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        notifier.stopScanning();
                        _stopScanner();
                      },
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop scanning'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Unknown sender: decision required before decoding ────
            if (state.awaitingSenderApproval) ...[
              _UnknownSenderPrompt(
                fingerprint: state.pendingSender!.fingerprint,
                onAccept: notifier.acceptPendingSender,
                onReject: notifier.rejectPendingSender,
              ),
              const SizedBox(height: 16),
            ]
            // ── Sender identity (shown after bootstrap) ──────────
            else if (state.senderFingerprint != null) ...[
              _SenderIdentityCard(
                fingerprint: state.senderFingerprint!,
                isNewSender: state.isNewSender,
              ),
              const SizedBox(height: 16),
            ],

            // Step 3: live progress / result.
            if (state.sessionActive) ...[
              _StepCard(
                step: 3,
                title: 'Progress',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.fileName != null) ...[
                      Text(
                        state.fileName!,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                    ],
                    LinearProgressIndicator(
                      value: state.progress,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${state.chunksDecoded} / ${state.totalChunks} chunks '
                      '(${state.framesReceived} frames scanned)',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (state.fileBytes != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green[900]!.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[700]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.check_circle,
                                    color: Colors.green[400]),
                                const SizedBox(width: 8),
                                Text(
                                  'Transfer complete!',
                                  style: TextStyle(
                                    color: Colors.green[400],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${(state.fileBytes!.length / 1024).toStringAsFixed(1)} KB received'
                              '${state.fileName != null ? ' · ${state.fileName}' : ''}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (state.savedPath != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Saved to: ${state.savedPath}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: state.savedPath == null
                                      ? notifier.saveFile
                                      : null,
                                  icon: const Icon(Icons.save),
                                  label: const Text('Save file'),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    notifier.reset();
                                    _stopScanner();
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('New transfer'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            // Error display
            if (state.error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[900]!.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[700]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red[400]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: TextStyle(color: Colors.red[400]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _startScanner() {
    // On desktop, use the default camera (no "back" facing concept).
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: isDesktop ? CameraFacing.front : CameraFacing.back,
    );
  }

  void _stopScanner() {
    _scannerController?.dispose();
    _scannerController = null;
  }

  static String _mapScannerError(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.controllerUninitialized =>
        'Camera is not ready yet. Please wait.',
      MobileScannerErrorCode.permissionDenied =>
        'Camera permission denied. Check your system settings and allow '
            'camera access for DeadDrop.',
      MobileScannerErrorCode.unsupported =>
        'No camera detected on this device.',
      MobileScannerErrorCode.controllerAlreadyInitialized =>
        'Camera is already in use by another application. '
            'Close it and try again.',
      _ => 'Camera error: ${error.errorDetails?.message ?? 'unknown error'}. '
          'Try closing other apps that use the camera.',
    };
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.child,
  });

  final int step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  child: Text('$step'),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Text view of the receiver public key: selectable hex grouped in blocks
/// of four characters (easy to read out loud or type by hand), plus a
/// copy-to-clipboard button. Used when the sender cannot scan the QR.
class _PublicKeyTextView extends StatelessWidget {
  const _PublicKeyTextView({required this.publicKey});

  final Uint8List publicKey;

  /// Formats a hex string in space-separated groups of four characters:
  /// `a1b2 c3d4 e5f6 …`. Grouping makes the key easier to read, dictate
  /// over the phone, and compare visually.
  static String _groupHex(String hex) {
    final buffer = StringBuffer();
    for (var i = 0; i < hex.length; i += 4) {
      if (i > 0) buffer.write(' ');
      final end = (i + 4 > hex.length) ? hex.length : i + 4;
      buffer.write(hex.substring(i, end));
    }
    return buffer.toString();
  }

  void _copyToClipboard(String hexKey) {
    unawaited(Clipboard.setData(ClipboardData(text: hexKey)));
  }

  @override
  Widget build(BuildContext context) {
    final hexKey = bytesToHex(publicKey);
    final grouped = _groupHex(hexKey);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeadDropColors.bgSurface,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border.all(color: DeadDropColors.borderInput),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            grouped,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.6,
              letterSpacing: 0.5,
              color: DeadDropColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${hexKey.length} hex characters · X25519 public key',
            style: Theme.of(context).textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: () => _copyToClipboard(hexKey),
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy to clipboard'),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unknown sender prompt (blocks the transfer until the user decides)
// ---------------------------------------------------------------------------

/// Asks the user to confirm an unrecognised sender before any data is
/// decoded.
///
/// This is the moment TOFU depends on: the fingerprint is only remembered
/// once a human has compared it with the sender out of band. Deciding
/// automatically here would make every later transfer from an impostor look
/// like a familiar sender.
///
/// The copy deliberately avoids "public key", "fingerprint of the Ed25519
/// identity" and similar: the user is asked to compare a code with the
/// person in front of them, which is the whole action.
class _UnknownSenderPrompt extends StatelessWidget {
  const _UnknownSenderPrompt({
    required this.fingerprint,
    required this.onAccept,
    required this.onReject,
  });

  final String fingerprint;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline, color: DeadDropColors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Is this who you expect?',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'You have not received from this device before. Ask the person '
              'sending the file to read out the code shown on their screen '
              'and check that it matches:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Center(
              child: SelectableText(
                fingerprint,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  letterSpacing: 2,
                  color: DeadDropColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close),
                    label: const Text("Codes don't match"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAccept,
                    icon: const Icon(Icons.check),
                    label: const Text('Codes match'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sender identity card (shown on the receive page after bootstrap)
// ---------------------------------------------------------------------------

/// Displays the sender's identity fingerprint and a TOFU warning when the
/// sender has never been seen before.
///
/// The fingerprint is extracted from the verified session header — the
/// Ed25519 signature has already been validated by the time this widget
/// appears. The TOFU warning prompts the user to verify the fingerprint
/// through a separate channel (in person, phone call, etc.).
class _SenderIdentityCard extends StatelessWidget {
  const _SenderIdentityCard({
    required this.fingerprint,
    required this.isNewSender,
  });

  final String fingerprint;
  final bool isNewSender;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isNewSender ? Icons.warning_amber : Icons.verified_user,
                  color: isNewSender
                      ? DeadDropColors.warning
                      : DeadDropColors.success,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sender identity',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: SelectableText(
                fingerprint,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  letterSpacing: 2,
                  color: DeadDropColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (isNewSender) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DeadDropColors.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: DeadDropColors.warning.withOpacity(0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        color: DeadDropColors.warning, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'New sender — verify this fingerprint through '
                        'another channel (in person, phone call) to '
                        'confirm the sender\'s identity.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: DeadDropColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                'Known sender — this device has received files from '
                'this identity before.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DeadDropColors.success,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
