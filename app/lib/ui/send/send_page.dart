import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sodium_libs/sodium_libs.dart';

import '../../src/crypto.dart';
import '../../src/emitter.dart';
import '../../src/handshake.dart';
import '../../src/transport.dart';
import '../../main.dart';
import '../theme.dart';

/// State for the send flow.
class SendState {
  SendState({
    this.fileName,
    this.fileBytes,
    this.receiverPk,
    this.emitter,
    this.identity,
    this.chunkSize = 512,
    this.ecLevel = 'M',
    this.fps = 12.0,
    this.isEmitting = false,
    this.framesEmitted = 0,
    this.currentQrData,
    this.showingBootstrap = false,
  });

  final String? fileName;
  final Uint8List? fileBytes;
  final Uint8List? receiverPk;
  final Emitter? emitter;
  final Identity? identity;
  final int chunkSize;
  final String ecLevel;
  final double fps;
  final bool isEmitting;
  final int framesEmitted;

  /// Current QR content (already enveloped, printable ASCII). Driven by the
  /// single frame generator in [SendNotifier] — the widget only renders it.
  final String? currentQrData;

  /// True while the static session-bootstrap QR is on screen.
  final bool showingBootstrap;

  bool get readyToSend => fileBytes != null && receiverPk != null;

  SendState copyWith({
    String? fileName,
    Uint8List? fileBytes,
    Uint8List? receiverPk,
    Emitter? emitter,
    Identity? identity,
    int? chunkSize,
    String? ecLevel,
    double? fps,
    bool? isEmitting,
    int? framesEmitted,
    String? currentQrData,
    bool? showingBootstrap,
  }) {
    return SendState(
      fileName: fileName ?? this.fileName,
      fileBytes: fileBytes ?? this.fileBytes,
      receiverPk: receiverPk ?? this.receiverPk,
      emitter: emitter ?? this.emitter,
      identity: identity ?? this.identity,
      chunkSize: chunkSize ?? this.chunkSize,
      ecLevel: ecLevel ?? this.ecLevel,
      fps: fps ?? this.fps,
      isEmitting: isEmitting ?? this.isEmitting,
      framesEmitted: framesEmitted ?? this.framesEmitted,
      currentQrData: currentQrData ?? this.currentQrData,
      showingBootstrap: showingBootstrap ?? this.showingBootstrap,
    );
  }
}

class SendNotifier extends StateNotifier<SendState> {
  SendNotifier(this._sodium) : super(SendState());

  final Sodium _sodium;
  Timer? _timer;

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    _stopTimer();
    state = SendState(
      fileName: file.name,
      fileBytes: bytes,
      receiverPk: state.receiverPk,
      chunkSize: state.chunkSize,
      ecLevel: state.ecLevel,
      fps: state.fps,
    );
  }

  void setReceiverPk(Uint8List pk) {
    state = state.copyWith(receiverPk: pk);
  }

  void setChunkSize(int size) {
    if (state.isEmitting) return; // locked during a transfer
    state = state.copyWith(chunkSize: size);
  }

  void setEcLevel(String level) {
    state = state.copyWith(ecLevel: level);
  }

  void setFps(double fps) {
    state = state.copyWith(fps: fps);
    // The periodic timer picks the new interval up on the next restart;
    // if we are emitting, restart immediately so the change is live.
    if (state.isEmitting && !state.showingBootstrap) {
      _startDataTimer();
    }
  }

  Future<void> startEmitting() async {
    if (!state.readyToSend || state.isEmitting) return;
    final identity = await Identity.generate(_sodium);
    final receiverKp = _ReceiverKeypairFromPk(state.receiverPk!);
    final emitter = await Emitter.create(
      _sodium,
      state.fileBytes!,
      receiverKp,
      senderIdentity: identity,
      chunkSize: state.chunkSize,
      fileName: state.fileName,
    );
    state = state.copyWith(
      emitter: emitter,
      identity: identity,
      isEmitting: true,
      framesEmitted: 0,
      showingBootstrap: true,
      currentQrData: encodeQrPayload(emitter.bootstrapQrPayload()),
    );
    // Hold the static bootstrap QR long enough for the receiver to lock on,
    // then switch to the animated data stream.
    _timer = Timer(const Duration(seconds: 4), _startDataPhase);
  }

  void stopEmitting() {
    _stopTimer();
    state = state.copyWith(
      isEmitting: false,
      showingBootstrap: false,
      currentQrData: null,
    );
  }

  void _startDataPhase() {
    if (!state.isEmitting || state.emitter == null) return;
    state = state.copyWith(showingBootstrap: false);
    _emitNextFrame(); // render the first data frame immediately
    _startDataTimer();
  }

  void _startDataTimer() {
    _stopTimer();
    final interval = Duration(milliseconds: (1000 / state.fps).round());
    _timer = Timer.periodic(interval, (_) => _emitNextFrame());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _emitNextFrame() {
    final emitter = state.emitter;
    if (emitter == null || !state.isEmitting) return;
    final frame = emitter.nextFrame();
    state = state.copyWith(
      framesEmitted: state.framesEmitted + 1,
      currentQrData: encodeQrPayload(frame.pack()),
    );
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }
}

/// Adapter: wraps a raw public key into the ReceiverKeypair interface
/// that Emitter.create expects. We only need the public key for sending.
class _ReceiverKeypairFromPk implements ReceiverKeypair {
  _ReceiverKeypairFromPk(this._pkBytes);
  final Uint8List _pkBytes;

  @override
  Uint8List get publicKey => _pkBytes;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Only publicKey is available');
}

final sendProvider = StateNotifierProvider<SendNotifier, SendState>((ref) {
  final sodium = ref.watch(sodiumProvider);
  return SendNotifier(sodium);
});

class SendPage extends ConsumerWidget {
  const SendPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sendProvider);
    final notifier = ref.read(sendProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Send a file')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step 1: File selection
            _StepCard(
              step: 1,
              title: 'Select file',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.fileName != null) ...[
                    Text(
                      state.fileName!,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${(state.fileBytes!.length / 1024).toStringAsFixed(1)} KB',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.tonalIcon(
                    onPressed:
                        state.isEmitting ? null : notifier.pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(state.fileName == null
                        ? 'Choose file'
                        : 'Change file'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Step 2: Receiver key via QR handshake
            _StepCard(
              step: 2,
              title: 'Receiver key',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'On the receiving device, tap "Receive a file" — it shows '
                    'a QR with its public key. Scan it here.',
                  ),
                  const SizedBox(height: 12),
                  if (state.receiverPk == null)
                    FilledButton.tonalIcon(
                      onPressed: state.isEmitting
                          ? null
                          : () => _scanReceiverKey(context, notifier),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan receiver key QR'),
                    )
                  else ...[
                    Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: DeadDropColors.success, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Key loaded: '
                            '${bytesToHex(state.receiverPk!).substring(0, 16)}…',
                            style: const TextStyle(
                                color: DeadDropColors.success),
                          ),
                        ),
                        if (!state.isEmitting)
                          IconButton(
                            tooltip: 'Scan a different key',
                            icon: const Icon(Icons.refresh),
                            onPressed: () =>
                                _scanReceiverKey(context, notifier),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Step 3: Parameters
            _StepCard(
              step: 3,
              title: 'Transfer parameters',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ParamSlider(
                    label: 'Chunk size',
                    value: state.chunkSize.toDouble(),
                    min: 256,
                    max: 1024,
                    divisions: 3,
                    unit: ' bytes',
                    onChanged: (v) => notifier.setChunkSize(v.round()),
                  ),
                  _ParamSlider(
                    label: 'Frame rate',
                    value: state.fps,
                    min: 4,
                    max: 24,
                    divisions: 20,
                    unit: ' fps',
                    onChanged: notifier.setFps,
                  ),
                  const SizedBox(height: 12),
                  const Text('Error correction'),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'L', label: Text('L (7%)')),
                      ButtonSegment(value: 'M', label: Text('M (15%)')),
                      ButtonSegment(value: 'Q', label: Text('Q (25%)')),
                      ButtonSegment(value: 'H', label: Text('H (30%)')),
                    ],
                    selected: {state.ecLevel},
                    onSelectionChanged: (s) => notifier.setEcLevel(s.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Start/Stop button
            if (state.readyToSend)
              FilledButton.icon(
                onPressed: state.isEmitting
                    ? notifier.stopEmitting
                    : notifier.startEmitting,
                icon: Icon(state.isEmitting ? Icons.stop : Icons.play_arrow),
                label: Text(state.isEmitting ? 'Stop' : 'Start transfer'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor:
                      state.isEmitting ? Colors.red[700] : null,
                ),
              ),

            // QR display — renders whatever the notifier is emitting.
            if (state.isEmitting && state.currentQrData != null) ...[
              const SizedBox(height: 24),
              _QrDisplay(state: state),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _scanReceiverKey(
      BuildContext context, SendNotifier notifier) async {
    final pk = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const _KeyScanPage()),
    );
    if (pk != null) {
      notifier.setReceiverPk(pk);
    }
  }
}

/// Full-screen camera page that scans the receiver's public-key QR and
/// pops with the decoded key.
class _KeyScanPage extends StatefulWidget {
  const _KeyScanPage();

  @override
  State<_KeyScanPage> createState() => _KeyScanPageState();
}

class _KeyScanPageState extends State<_KeyScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _found = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receiver key')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_found) return;
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw == null) continue;
                final pk = decodeHandshakeQr(raw);
                if (pk != null) {
                  _found = true;
                  Navigator.of(context).pop(pk);
                  return;
                }
              }
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Point at the QR shown on the receiving device',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
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

class _ParamSlider extends StatelessWidget {
  const _ParamSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('${value.round()}$unit'),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Dumb QR renderer: displays exactly what the notifier produced. All frame
/// generation logic lives in [SendNotifier], so there is a single source of
/// truth for the emitted sequence.
class _QrDisplay extends StatelessWidget {
  const _QrDisplay({required this.state});

  final SendState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: state.currentQrData!,
            version: QrVersions.auto,
            errorCorrectionLevel: _ecLevelToQr(state.ecLevel),
            size: 300,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          state.showingBootstrap
              ? 'Session bootstrap — point the receiver camera here'
              : 'Frame ${state.framesEmitted}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          '${state.fps.round()} fps · ${state.chunkSize} B/chunk · EC-${state.ecLevel}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: DeadDropColors.textSecondary,
              ),
        ),
      ],
    );
  }

  int _ecLevelToQr(String level) {
    return switch (level) {
      'L' => QrErrorCorrectLevel.L,
      'M' => QrErrorCorrectLevel.M,
      'Q' => QrErrorCorrectLevel.Q,
      'H' => QrErrorCorrectLevel.H,
      _ => QrErrorCorrectLevel.M,
    };
  }
}
