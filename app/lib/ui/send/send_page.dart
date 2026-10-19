import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sodium_libs/sodium_libs.dart';

import '../../src/crypto.dart';
import '../../src/emitter.dart';
import '../../main.dart';

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
    );
  }
}

class SendNotifier extends StateNotifier<SendState> {
  SendNotifier(this._sodium) : super(SendState());

  final Sodium _sodium;
  Timer? _timer;

  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    state = state.copyWith(
      fileName: file.name,
      fileBytes: bytes,
      emitter: null,
      isEmitting: false,
      framesEmitted: 0,
    );
  }

  void setReceiverPk(Uint8List pk) {
    state = state.copyWith(receiverPk: pk);
  }

  void setChunkSize(int size) {
    state = state.copyWith(chunkSize: size, emitter: null);
  }

  void setEcLevel(String level) {
    state = state.copyWith(ecLevel: level);
  }

  void setFps(double fps) {
    state = state.copyWith(fps: fps);
    if (state.isEmitting) {
      _restartTimer();
    }
  }

  Future<void> startEmitting() async {
    if (state.fileBytes == null || state.receiverPk == null) return;
    final identity = await Identity.generate(_sodium);
    // Create a temporary ReceiverKeypair from the raw public key
    // so we can pass it to Emitter.create
    final receiverKp = _ReceiverKeypairFromPk(state.receiverPk!);
    final emitter = await Emitter.create(
      _sodium,
      state.fileBytes!,
      receiverKp,
      senderIdentity: identity,
      chunkSize: state.chunkSize,
    );
    state = state.copyWith(
      emitter: emitter,
      identity: identity,
      isEmitting: true,
      framesEmitted: 0,
    );
    _startTimer();
  }

  void stopEmitting() {
    _timer?.cancel();
    state = state.copyWith(isEmitting: false);
  }

  void _startTimer() {
    final interval = Duration(milliseconds: (1000 / state.fps).round());
    _timer = Timer.periodic(interval, (_) => _emitFrame());
  }

  void _restartTimer() {
    _timer?.cancel();
    _startTimer();
  }

  void _emitFrame() {
    if (state.emitter == null || !state.isEmitting) return;
    state.emitter!.nextFrame();
    state = state.copyWith(framesEmitted: state.framesEmitted + 1);
  }

  @override
  void dispose() {
    _timer?.cancel();
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
                    onPressed: notifier.pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(state.fileName == null
                        ? 'Choose file'
                        : 'Change file'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Step 2: Receiver key input
            _StepCard(
              step: 2,
              title: 'Receiver public key',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'The receiver shows their public key as a QR code. '
                    'Paste it here or scan it.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Public key (hex)',
                      hintText: 'e.g. a1b2c3...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      try {
                        final pk = _hexToBytes(value);
                        if (pk.length == 32) {
                          notifier.setReceiverPk(pk);
                        }
                      } catch (_) {}
                    },
                  ),
                  if (state.receiverPk != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Key loaded: ${_bytesToHex(state.receiverPk!).substring(0, 16)}...',
                      style: TextStyle(color: Colors.green[400]),
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
            if (state.fileBytes != null && state.receiverPk != null)
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

            // QR display
            if (state.isEmitting && state.emitter != null) ...[
              const SizedBox(height: 24),
              _QrDisplay(state: state),
            ],
          ],
        ),
      ),
    );
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (clean.length % 2 != 0) throw const FormatException('odd hex length');
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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

class _QrDisplay extends ConsumerStatefulWidget {
  const _QrDisplay({required this.state});

  final SendState state;

  @override
  ConsumerState<_QrDisplay> createState() => _QrDisplayState();
}

class _QrDisplayState extends ConsumerState<_QrDisplay> {
  Uint8List? _currentFrameBytes;
  bool _showBootstrap = true;

  @override
  void initState() {
    super.initState();
    _generateNext();
  }

  Future<void> _generateNext() async {
    if (!mounted || !widget.state.isEmitting) return;
    final emitter = widget.state.emitter!;
    if (_showBootstrap) {
      setState(() {
        _currentFrameBytes = emitter.bootstrapQrPayload();
      });
      // Show bootstrap for 3 seconds, then start data frames
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() => _showBootstrap = false);
      }
    } else {
      final frame = emitter.nextFrame();
      if (mounted) {
        setState(() {
          _currentFrameBytes = frame.pack();
        });
      }
    }
    // Schedule next frame
    if (mounted && widget.state.isEmitting) {
      final interval = Duration(milliseconds: (1000 / widget.state.fps).round());
      Future.delayed(interval, _generateNext);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFrameBytes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: String.fromCharCodes(_currentFrameBytes!),
            version: QrVersions.auto,
            errorCorrectionLevel: _ecLevelToQr(widget.state.ecLevel),
            size: 300,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _showBootstrap ? 'Session bootstrap' : 'Frame ${widget.state.framesEmitted}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          '${widget.state.fps.round()} fps · ${widget.state.chunkSize} B/chunk · EC-${widget.state.ecLevel}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[500],
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
