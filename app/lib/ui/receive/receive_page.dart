import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sodium_libs/sodium_libs.dart';

import '../../src/crypto.dart';
import '../../src/handshake.dart';
import '../../src/receiver.dart';
import '../../src/transport.dart';
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

  double get progress =>
      totalChunks > 0 ? chunksDecoded / totalChunks : 0.0;

  bool get sessionActive => receiver != null;

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
    );
  }
}

class ReceiveNotifier extends StateNotifier<ReceiveState> {
  ReceiveNotifier(this._sodium) : super(ReceiveState());

  final Sodium _sodium;

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
      await receiver.startSession(data);
      state = state.copyWith(
        receiver: receiver,
        totalChunks: receiver.session!.header.chunkCount,
        error: null,
      );
    } on DeadDropCryptoError catch (e) {
      state = state.copyWith(error: 'Session rejected: ${e.message}');
    }
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
  return ReceiveNotifier(sodium);
});

class ReceivePage extends ConsumerStatefulWidget {
  const ReceivePage({super.key});

  @override
  ConsumerState<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends ConsumerState<ReceivePage> {
  MobileScannerController? _scannerController;

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
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
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
                      'Show this QR to the sender. It contains only your '
                      'public key — the file itself is encrypted end-to-end.',
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
