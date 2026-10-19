import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sodium_libs/sodium_libs.dart';

import '../../src/crypto.dart';
import '../../src/emitter.dart';
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
    this.pinEnabled = true,
    this.selfDestructEnabled = false,
    this.isScanning = false,
    this.cameraError,
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
  final bool pinEnabled;
  final bool selfDestructEnabled;
  final bool isScanning;
  final String? cameraError;

  /// Whether the user can start the transfer.
  bool get canStart => fileBytes != null && receiverPk != null;

  /// Human-readable hint about what's missing before starting.
  String? get missingHint {
    if (fileBytes == null && receiverPk == null) {
      return 'Select a file and scan the receiver\'s QR code';
    }
    if (fileBytes == null) return 'Select a file first';
    if (receiverPk == null) return 'Scan the receiver\'s QR code';
    return null;
  }

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
    bool? pinEnabled,
    bool? selfDestructEnabled,
    bool? isScanning,
    String? cameraError,
    bool clearCameraError = false,
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
      pinEnabled: pinEnabled ?? this.pinEnabled,
      selfDestructEnabled: selfDestructEnabled ?? this.selfDestructEnabled,
      isScanning: isScanning ?? this.isScanning,
      cameraError: clearCameraError ? null : (cameraError ?? this.cameraError),
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

  void setPinEnabled(bool enabled) {
    state = state.copyWith(pinEnabled: enabled);
  }

  void setSelfDestructEnabled(bool enabled) {
    state = state.copyWith(selfDestructEnabled: enabled);
  }

  void startScanning() {
    state = state.copyWith(isScanning: true, clearCameraError: true);
  }

  void stopScanning() {
    state = state.copyWith(isScanning: false);
  }

  void setCameraError(String error) {
    state = state.copyWith(cameraError: error, isScanning: false);
  }

  Future<void> startEmitting() async {
    if (!state.canStart) return;
    final identity = await Identity.generate(_sodium);
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

// ---------------------------------------------------------------------------
// Send Page
// ---------------------------------------------------------------------------

class SendPage extends ConsumerStatefulWidget {
  const SendPage({super.key});

  @override
  ConsumerState<SendPage> createState() => _SendPageState();
}

class _SendPageState extends ConsumerState<SendPage> {
  MobileScannerController? _scannerController;

  @override
  void dispose() {
    _disposeScanner();
    super.dispose();
  }

  void _disposeScanner() {
    _scannerController?.dispose();
    _scannerController = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sendProvider);
    final notifier = ref.read(sendProvider.notifier);

    // If actively emitting, show the QR transfer screen.
    if (state.isEmitting && state.emitter != null) {
      return _SendingScreen(state: state, notifier: notifier);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Send a file')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Step 1: Select file ──────────────────────────────
            _StepCard(
              step: 1,
              title: 'Choose a file',
              isComplete: state.fileBytes != null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.fileName != null) ...[
                    _FileInfoTile(
                      fileName: state.fileName!,
                      fileSize: state.fileBytes!.length,
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.tonalIcon(
                    onPressed: notifier.pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(
                      state.fileName == null ? 'Choose file' : 'Change file',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 2: Scan receiver key ────────────────────────
            _StepCard(
              step: 2,
              title: 'Scan receiver\'s QR',
              isComplete: state.receiverPk != null,
              child: _ReceiverKeySection(
                state: state,
                notifier: notifier,
                scannerController: _scannerController,
                onStartScanner: _startScanner,
                onStopScanner: _stopScanner,
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 3: Configure (collapsible) ──────────────────
            _ConfigSection(state: state, notifier: notifier),
            const SizedBox(height: 24),

            // ── Step 4: Start ────────────────────────────────────
            _StartSection(state: state, notifier: notifier),
          ],
        ),
      ),
    );
  }

  void _startScanner() {
    // On desktop, use the default camera (no "back" facing concept).
    final isDesktop = Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: isDesktop ? CameraFacing.front : CameraFacing.back,
    );
  }

  void _stopScanner() {
    _disposeScanner();
  }
}

// ---------------------------------------------------------------------------
// Step card with completion indicator
// ---------------------------------------------------------------------------

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.isComplete,
    required this.child,
  });

  final int step;
  final String title;
  final bool isComplete;
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
                  backgroundColor: isComplete
                      ? DeadDropColors.success
                      : DeadDropColors.bgElevated,
                  child: isComplete
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text('$step'),
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

// ---------------------------------------------------------------------------
// File info tile
// ---------------------------------------------------------------------------

class _FileInfoTile extends StatelessWidget {
  const _FileInfoTile({required this.fileName, required this.fileSize});

  final String fileName;
  final int fileSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DeadDropColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DeadDropColors.borderInput),
      ),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file, color: DeadDropColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatSize(fileSize),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle, color: DeadDropColors.success, size: 20),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ---------------------------------------------------------------------------
// Receiver key section (scan QR + advanced manual input)
// ---------------------------------------------------------------------------

class _ReceiverKeySection extends StatelessWidget {
  const _ReceiverKeySection({
    required this.state,
    required this.notifier,
    required this.scannerController,
    required this.onStartScanner,
    required this.onStopScanner,
  });

  final SendState state;
  final SendNotifier notifier;
  final MobileScannerController? scannerController;
  final VoidCallback onStartScanner;
  final VoidCallback onStopScanner;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.receiverPk != null && !state.isScanning) ...[
          // Key loaded — show confirmation
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DeadDropColors.success.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DeadDropColors.success),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: DeadDropColors.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receiver key loaded',
                        style: TextStyle(
                          color: DeadDropColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_bytesToHex(state.receiverPk!).substring(0, 16)}…',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    notifier.startScanning();
                    onStartScanner();
                  },
                  child: const Text('Rescan'),
                ),
              ],
            ),
          ),
        ] else if (state.isScanning) ...[
          // Camera view
          _ScannerView(
            scannerController: scannerController,
            onDetect: (data) {
              notifier.setReceiverPk(data);
              notifier.stopScanning();
              onStopScanner();
            },
            onError: (error) {
              notifier.setCameraError(error);
              onStopScanner();
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              notifier.stopScanning();
              onStopScanner();
            },
            icon: const Icon(Icons.close),
            label: const Text('Cancel'),
          ),
        ] else ...[
          // Scan button
          const Text(
            'Ask the receiver to show their QR code, then scan it.',
            style: TextStyle(color: DeadDropColors.textSecondary),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              notifier.startScanning();
              onStartScanner();
            },
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan receiver\'s QR'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ],

        // Camera error
        if (state.cameraError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DeadDropColors.error.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DeadDropColors.error),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: DeadDropColors.error),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.cameraError!,
                    style: TextStyle(color: DeadDropColors.error),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Advanced: manual hex input
        if (!state.isScanning && state.receiverPk == null) ...[
          const SizedBox(height: 8),
          _ManualKeyInput(onKeyLoaded: notifier.setReceiverPk),
        ],
      ],
    );
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

// ---------------------------------------------------------------------------
// Scanner view with error handling
// ---------------------------------------------------------------------------

class _ScannerView extends StatefulWidget {
  const _ScannerView({
    required this.scannerController,
    required this.onDetect,
    required this.onError,
  });

  final MobileScannerController? scannerController;
  final ValueChanged<Uint8List> onDetect;
  final ValueChanged<String> onError;

  @override
  State<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<_ScannerView> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: DeadDropColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DeadDropColors.error),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_off, color: DeadDropColors.error, size: 48),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DeadDropColors.error),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (widget.scannerController == null) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
          color: DeadDropColors.bgElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DeadDropColors.borderInput),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: MobileScanner(
          controller: widget.scannerController,
          onDetect: (capture) {
            final barcodes = capture.barcodes;
            if (barcodes.isEmpty) return;
            final raw = barcodes.first.rawValue;
            if (raw == null) return;
            // The receiver shows their public key as hex-encoded QR.
            try {
              final pk = _hexToBytes(raw);
              if (pk.length == 32) {
                widget.onDetect(pk);
              }
            } catch (_) {
              // Not a valid hex key — ignore this frame.
            }
          },
          errorBuilder: (context, error, child) {
            final message = _mapScannerError(error);
            // Schedule error callback after build.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onError(message);
            });
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_off,
                        color: DeadDropColors.error, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DeadDropColors.error),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _mapScannerError(MobileScannerException error) {
    return switch (error.errorCode) {
      MobileScannerErrorCode.controllerUninitialized =>
        'Camera is not ready yet. Please wait.',
      MobileScannerErrorCode.permissionDenied =>
        'Camera permission denied. Check your system settings and allow camera access for DeadDrop.',
      MobileScannerErrorCode.unsupported =>
        'No camera detected on this device.',
      MobileScannerErrorCode.controllerAlreadyInitialized =>
        'Camera is already in use.',
      _ => 'Camera error: ${error.errorDetails?.message ?? 'unknown error'}. '
          'Try closing other apps that use the camera.',
    };
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
}

// ---------------------------------------------------------------------------
// Manual key input (advanced fallback)
// ---------------------------------------------------------------------------

class _ManualKeyInput extends StatefulWidget {
  const _ManualKeyInput({required this.onKeyLoaded});

  final ValueChanged<Uint8List> onKeyLoaded;

  @override
  State<_ManualKeyInput> createState() => _ManualKeyInputState();
}

class _ManualKeyInputState extends State<_ManualKeyInput> {
  bool _expanded = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    if (!_expanded) {
      return TextButton.icon(
        onPressed: () => setState(() => _expanded = true),
        icon: const Icon(Icons.keyboard, size: 18),
        label: const Text('Enter key manually'),
        style: TextButton.styleFrom(
          foregroundColor: DeadDropColors.textSecondary,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Manual entry (advanced)',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            labelText: 'Public key (hex)',
            hintText: '64 hex characters',
            border: const OutlineInputBorder(),
            errorText: _error,
            suffixIcon: _error == null && _lastValidKey != null
                ? Icon(Icons.check_circle, color: DeadDropColors.success)
                : null,
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          maxLength: 64,
          onChanged: _validate,
        ),
      ],
    );
  }

  Uint8List? _lastValidKey;

  void _validate(String value) {
    setState(() {
      if (value.isEmpty) {
        _error = null;
        _lastValidKey = null;
        return;
      }
      try {
        final pk = _hexToBytes(value);
        if (pk.length != 32) {
          _error = 'Expected 64 hex characters (32 bytes), got ${pk.length * 2}';
          _lastValidKey = null;
        } else {
          _error = null;
          _lastValidKey = pk;
          widget.onKeyLoaded(pk);
        }
      } catch (_) {
        _error = 'Invalid hex format';
        _lastValidKey = null;
      }
    });
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
}

// ---------------------------------------------------------------------------
// Configuration section (collapsible)
// ---------------------------------------------------------------------------

class _ConfigSection extends StatelessWidget {
  const _ConfigSection({required this.state, required this.notifier});

  final SendState state;
  final SendNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: CircleAvatar(
            radius: 14,
            child: const Text('3'),
          ),
          title: Text(
            'Options',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            'PIN protection, self-destruct, advanced',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          initiallyExpanded: false,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            // PIN toggle
            SwitchListTile(
              title: const Text('Protect with PIN'),
              subtitle: const Text('The receiver needs a PIN to decrypt'),
              value: state.pinEnabled,
              onChanged: notifier.setPinEnabled,
              contentPadding: EdgeInsets.zero,
            ),
            // Self-destruct toggle
            SwitchListTile(
              title: const Text('Self-destruct after read'),
              subtitle: const Text('File is deleted after first decryption'),
              value: state.selfDestructEnabled,
              onChanged: notifier.setSelfDestructEnabled,
              contentPadding: EdgeInsets.zero,
            ),
            const Divider(),
            const SizedBox(height: 8),
            // Advanced parameters
            Text(
              'Advanced',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Start section (always visible, with hints)
// ---------------------------------------------------------------------------

class _StartSection extends StatelessWidget {
  const _StartSection({required this.state, required this.notifier});

  final SendState state;
  final SendNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: state.canStart ? notifier.startEmitting : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start transfer'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
          ),
        ),
        if (!state.canStart) ...[
          const SizedBox(height: 8),
          Text(
            state.missingHint!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DeadDropColors.warning,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Active sending screen (full-screen QR)
// ---------------------------------------------------------------------------

class _SendingScreen extends StatelessWidget {
  const _SendingScreen({required this.state, required this.notifier});

  final SendState state;
  final SendNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sending'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // File info
              Text(
                state.fileName ?? 'file',
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _formatSize(state.fileBytes?.length ?? 0),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),

              // QR display — takes remaining space
              Expanded(
                child: Center(
                  child: _QrDisplay(state: state),
                ),
              ),
              const SizedBox(height: 24),

              // Progress info
              Text(
                'Frame ${state.framesEmitted}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${state.fps.round()} fps · ${state.chunkSize} B/chunk · EC-${state.ecLevel}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DeadDropColors.textSecondary,
                    ),
              ),
              const SizedBox(height: 24),

              // Stop button
              FilledButton.icon(
                onPressed: notifier.stopEmitting,
                icon: const Icon(Icons.stop),
                label: const Text('Stop transfer'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: DeadDropColors.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ---------------------------------------------------------------------------
// Parameter slider
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// QR display (animated frames)
// ---------------------------------------------------------------------------

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
      mainAxisSize: MainAxisSize.min,
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
