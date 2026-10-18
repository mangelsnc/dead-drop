import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../src/crypto.dart';
import '../../src/receiver.dart';
import '../../main.dart';

/// State for the receive flow.
class ReceiveState {
  ReceiveState({
    this.receiverKeypair,
    this.receiver,
    this.showHandshake = false,
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
  final bool showHandshake;
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

  ReceiveState copyWith({
    ReceiverKeypair? receiverKeypair,
    Receiver? receiver,
    bool? showHandshake,
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
      showHandshake: showHandshake ?? this.showHandshake,
      isScanning: isScanning ?? this.isScanning,
      framesReceived: framesReceived ?? this.framesReceived,
      chunksDecoded: chunksDecoded ?? this.chunksDecoded,
      totalChunks: totalChunks ?? this.totalChunks,
      fileBytes: fileBytes ?? this.fileBytes,
      fileName: fileName ?? this.fileName,
      savedPath: savedPath ?? this.savedPath,
      error: error ?? this.error,
    );
  }
}

class ReceiveNotifier extends StateNotifier<ReceiveState> {
  ReceiveNotifier(this._sodium) : super(ReceiveState());

  final Sodium _sodium;

  Future<void> initKeypair() async {
    final kp = await ReceiverKeypair.generate(_sodium);
    state = state.copyWith(receiverKeypair: kp);
  }

  void toggleHandshake() {
    state = state.copyWith(showHandshake: !state.showHandshake);
  }

  void startScanning() {
    state = state.copyWith(isScanning: true, error: null);
  }

  void stopScanning() {
    state = state.copyWith(isScanning: false);
  }

  Future<void> processQrData(Uint8List data) async {
    if (state.receiverKeypair == null) return;

    // Check if this is a session bootstrap (179 bytes, magic "DD")
    if (data.length == SessionHeader.packedSize &&
        data[0] == magic[0] &&
        data[1] == magic[1]) {
      await _processBootstrap(data);
      return;
    }

    // Otherwise it's a data frame
    if (state.receiver != null) {
      _processDataFrame(data);
    }
  }

  Future<void> _processBootstrap(Uint8List data) async {
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
    final advanced = receiver.feedFrame(data);
    if (!advanced) return; // duplicate or invalid frame

    state = state.copyWith(
      framesReceived: state.framesReceived + 1,
      chunksDecoded: receiver.decoder?.decoded.length ?? 0,
    );

    if (receiver.done) {
      try {
        final fileBytes = receiver.finish();
        state = state.copyWith(
          fileBytes: fileBytes,
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
      fileName: 'deaddrop_received_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (path == null) return;
    // Write file
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
    _scannerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiveProvider);
    final notifier = ref.read(receiveProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Receive a file')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handshake section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          child: Text('1'),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Your public key',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (state.receiverKeypair != null) ...[
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: QrImageView(
                            data: _bytesToHex(
                                state.receiverKeypair!.publicKey.bytes),
                            version: QrVersions.auto,
                            size: 200,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Show this QR to the sender. They will scan it to '
                        'get your public key.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ] else
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Scanner section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          child: Text('2'),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Scan sender QR codes',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!state.isScanning && state.fileBytes == null)
                      FilledButton.icon(
                        onPressed: () {
                          notifier.startScanning();
                          _startScanner();
                        },
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Start scanning'),
                      ),
                    if (state.isScanning) ...[
                      Container(
                        height: 300,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[700]!),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: MobileScanner(
                            controller: _scannerController,
                            onDetect: (capture) {
                              final barcodes = capture.barcodes;
                              if (barcodes.isEmpty) return;
                              final raw = barcodes.first.rawValue;
                              if (raw == null) return;
                              notifier.processQrData(
                                Uint8List.fromList(raw.codeUnits),
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
            ),
            const SizedBox(height: 16),

            // Progress section
            if (state.totalChunks > 0 || state.fileBytes != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            child: Text('3'),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Progress',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: state.progress,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${state.chunksDecoded} / ${state.totalChunks} chunks '
                        '(${state.framesReceived} frames)',
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
                                '${(state.fileBytes!.length / 1024).toStringAsFixed(1)} KB received',
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
                                    onPressed: notifier.saveFile,
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
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  void _stopScanner() {
    _scannerController?.dispose();
    _scannerController = null;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
