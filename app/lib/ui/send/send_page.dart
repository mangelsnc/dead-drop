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
import '../../src/handshake.dart';
import '../../src/transport.dart';
import '../../main.dart';
import '../theme.dart';

/// State for the send flow.
class SendState {
  SendState({
    this.fileName,
    this.fileBytes,
    this.fileExtension,
    this.filePath,
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

  /// Lowercase file extension without the dot (e.g. "pdf", "png"), if known.
  final String? fileExtension;

  /// Absolute path of the picked file on the sender device, if the platform
  /// file picker exposed one (not available on web).
  final String? filePath;

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
    String? fileExtension,
    String? filePath,
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
      fileExtension: fileExtension ?? this.fileExtension,
      filePath: filePath ?? this.filePath,
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
      fileExtension: file.extension?.toLowerCase(),
      filePath: file.path,
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

// ---------------------------------------------------------------------------
// Send Page (step-by-step guided flow)
// ---------------------------------------------------------------------------

class SendPage extends ConsumerWidget {
  const SendPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sendProvider);
    final notifier = ref.read(sendProvider.notifier);

    // If actively emitting, show the full-screen QR transfer view.
    if (state.isEmitting && state.currentQrData != null) {
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
                      fileExtension: state.fileExtension,
                      filePath: state.filePath,
                      fileBytes: state.fileBytes,
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

/// Maps a lowercase file extension (no dot) to a type-specific icon.
IconData fileIconForExtension(String? extension) {
  switch (extension) {
    // Images
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'svg':
    case 'bmp':
    case 'heic':
      return Icons.image;
    // Video
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
    case 'webm':
      return Icons.videocam;
    // Audio
    case 'mp3':
    case 'wav':
    case 'ogg':
    case 'flac':
    case 'm4a':
      return Icons.audio_file;
    // PDF
    case 'pdf':
      return Icons.picture_as_pdf;
    // Text / code
    case 'txt':
    case 'md':
    case 'dart':
    case 'py':
    case 'js':
    case 'ts':
    case 'json':
    case 'yaml':
    case 'yml':
    case 'xml':
    case 'html':
    case 'css':
      return Icons.description;
    // Archives
    case 'zip':
    case 'tar':
    case 'gz':
    case '7z':
    case 'rar':
    case 'bz2':
      return Icons.folder_zip;
    default:
      return Icons.insert_drive_file;
  }
}

/// True for raster image extensions we can preview with [Image.memory].
bool isPreviewableImageExtension(String? extension) {
  switch (extension) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'heic':
      return true;
    default:
      return false;
  }
}

/// Shows the picked file: type icon (or image thumbnail), name and size by
/// default; tapping expands a metadata section with extension, size in
/// bytes, and full path. The file picker's `PlatformFile` does not expose a
/// last-modified date, so that field is omitted.
class _FileInfoTile extends StatefulWidget {
  const _FileInfoTile({
    required this.fileName,
    required this.fileSize,
    this.fileExtension,
    this.filePath,
    this.fileBytes,
  });

  final String fileName;
  final int fileSize;

  /// Lowercase extension without dot (e.g. "pdf"), if known.
  final String? fileExtension;

  /// Absolute path on the sender device, if the picker exposed one.
  final String? filePath;

  /// File bytes, used to render a thumbnail for image files.
  final Uint8List? fileBytes;

  @override
  State<_FileInfoTile> createState() => _FileInfoTileState();
}

class _FileInfoTileState extends State<_FileInfoTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasMetadata = widget.fileExtension != null || widget.filePath != null;

    return Container(
      decoration: BoxDecoration(
        color: DeadDropColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DeadDropColors.borderInput),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: hasMetadata
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _buildLeading(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.fileName,
                          style: Theme.of(context).textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _formatSize(widget.fileSize),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (hasMetadata)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: DeadDropColors.textSecondary,
                      size: 20,
                    ),
                  const SizedBox(width: 4),
                  const Icon(Icons.check_circle,
                      color: DeadDropColors.success, size: 20),
                ],
              ),
            ),
          ),
          if (_expanded && hasMetadata)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  if (widget.fileExtension != null)
                    _MetadataRow(
                      label: 'Type',
                      value: widget.fileExtension!.toUpperCase(),
                    ),
                  _MetadataRow(
                    label: 'Size',
                    value: '${widget.fileSize} bytes',
                  ),
                  if (widget.filePath != null)
                    _MetadataRow(
                      label: 'Path',
                      value: widget.filePath!,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLeading() {
    final bytes = widget.fileBytes;
    if (isPreviewableImageExtension(widget.fileExtension) &&
        bytes != null &&
        bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          bytes,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          // If decoding fails (corrupt/unsupported), fall back to the icon.
          errorBuilder: (context, error, stackTrace) => Icon(
            fileIconForExtension(widget.fileExtension),
            color: DeadDropColors.accent,
          ),
        ),
      );
    }
    return Icon(
      fileIconForExtension(widget.fileExtension),
      color: DeadDropColors.accent,
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// A single label/value line in the expanded metadata section.
class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DeadDropColors.textSecondary,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DeadDropColors.textPrimary,
                  ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Receiver key section (scan QR + manual fallback)
// ---------------------------------------------------------------------------

class _ReceiverKeySection extends StatelessWidget {
  const _ReceiverKeySection({
    required this.state,
    required this.notifier,
  });

  final SendState state;
  final SendNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.receiverPk != null) ...[
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
                const Icon(Icons.check_circle,
                    color: DeadDropColors.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Receiver key loaded',
                        style: TextStyle(
                          color: DeadDropColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${bytesToHex(state.receiverPk!).substring(0, 16)}…',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _scanReceiverKey(context),
                  child: const Text('Rescan'),
                ),
              ],
            ),
          ),
        ] else ...[
          // Scan button
          const Text(
            'Ask the receiver to show their QR code, then scan it.',
            style: TextStyle(color: DeadDropColors.textSecondary),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _scanReceiverKey(context),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan receiver\'s QR'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
          // Advanced: manual hex input
          const SizedBox(height: 8),
          _ManualKeyInput(onKeyLoaded: notifier.setReceiverPk),
        ],
      ],
    );
  }

  Future<void> _scanReceiverKey(BuildContext context) async {
    final pk = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const _KeyScanPage()),
    );
    if (pk != null) {
      notifier.setReceiverPk(pk);
    }
  }
}

// ---------------------------------------------------------------------------
// Full-screen key scanner page with desktop camera support + error handling
// ---------------------------------------------------------------------------

class _KeyScanPage extends StatefulWidget {
  const _KeyScanPage();

  @override
  State<_KeyScanPage> createState() => _KeyScanPageState();
}

class _KeyScanPageState extends State<_KeyScanPage> {
  late final MobileScannerController _controller;
  bool _found = false;

  @override
  void initState() {
    super.initState();
    // On desktop, use the default camera (no "back" facing concept).
    final isDesktop =
        Platform.isLinux || Platform.isMacOS || Platform.isWindows;
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: isDesktop ? CameraFacing.front : CameraFacing.back,
    );
  }

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
            errorBuilder: (context, error, child) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off,
                          color: DeadDropColors.error, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        _mapScannerError(error),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: DeadDropColors.error),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Go back'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          ),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          maxLength: 64,
          onChanged: _validate,
        ),
      ],
    );
  }

  void _validate(String value) {
    setState(() {
      if (value.isEmpty) {
        _error = null;
        return;
      }
      try {
        final pk = hexToBytes(value);
        if (pk.length != 32) {
          _error =
              'Expected 64 hex characters (32 bytes), got ${pk.length * 2}';
        } else {
          _error = null;
          widget.onKeyLoaded(pk);
        }
      } catch (_) {
        _error = 'Invalid hex format';
      }
    });
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
          leading: const CircleAvatar(
            radius: 14,
            child: Text('3'),
          ),
          title: Text(
            'Options',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            'Transfer parameters',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          initiallyExpanded: false,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
          onPressed: state.readyToSend ? notifier.startEmitting : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start transfer'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
          ),
        ),
        if (!state.readyToSend) ...[
          const SizedBox(height: 8),
          Text(
            state.missingHint!,
            textAlign: TextAlign.center,
            style: const TextStyle(
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
                state.showingBootstrap
                    ? 'Session bootstrap'
                    : 'Frame ${state.framesEmitted}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${state.fps.round()} fps · ${state.chunkSize} B/chunk · '
                'EC-${state.ecLevel}',
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
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
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

/// Dumb QR renderer: displays exactly what the notifier produced. All frame
/// generation logic lives in [SendNotifier], so there is a single source of
/// truth for the emitted sequence.
class _QrDisplay extends StatelessWidget {
  const _QrDisplay({required this.state});

  final SendState state;

  @override
  Widget build(BuildContext context) {
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
