import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sodium/sodium.dart';

import '../../src/chunking.dart';
import '../../src/qrframe.dart';
import '../../src/crypto.dart';
import '../../src/screen_wake.dart';
import '../../src/emitter.dart';
import '../../src/file_metadata.dart';
import '../../src/handshake.dart';
import '../../src/identity_store.dart';
import '../../src/transport.dart';
import '../../main.dart';
import '../theme.dart';
import '../technical_text.dart';
import '../desktop_scanner_view.dart';
import '../../src/desktop_scanner.dart';
import '../responsive.dart';

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
    this.chunkSize = kDefaultChunkSize,
    this.ecLevel = 'M',
    this.fps = 12.0,
    this.isEmitting = false,
    this.framesEmitted = 0,
    this.totalFrames,
    this.currentQrData,
    this.showingBootstrap = false,
    this.sendError,
    this.appliedHint,
  });

  final String? fileName;
  final Uint8List? fileBytes;

  /// Lowercase file extension without the dot (e.g. "pdf", "png"), if known.
  final String? fileExtension;

  /// Absolute path of the picked file on the sender device, if the platform
  /// file picker exposed one (not available on web).
  final String? filePath;

  final Uint8List? receiverPk;

  /// The receiver's suggestion, when their QR carried one and it was
  /// applied. Held so the screen can say where these settings came from:
  /// numbers that changed by themselves are indistinguishable from a bug.
  final HandshakeHint? appliedHint;

  final Emitter? emitter;
  final Identity? identity;
  final int chunkSize;
  final String ecLevel;
  final double fps;
  final bool isEmitting;
  final int framesEmitted;

  /// Total number of source chunks (K) for the current transfer, when an
  /// emitter is active. Null before a transfer starts.
  final int? totalFrames;

  /// Current QR content (already enveloped, printable ASCII). Driven by the
  /// single frame generator in [SendNotifier] — the widget only renders it.
  final String? currentQrData;

  /// True while the static session-bootstrap QR is on screen.
  final bool showingBootstrap;

  /// A user-facing reason the current file cannot be sent, or null when the
  /// configuration is valid. Set when file-size validation fails.
  final String? sendError;

  bool get readyToSend =>
      fileBytes != null && receiverPk != null && sendError == null;

  /// Human-readable hint about what's missing before starting.
  String? get missingHint {
    // A validation error (e.g. file too large) takes priority — it is the
    // thing the user must fix before anything else can proceed.
    if (sendError != null) return sendError;
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
    int? totalFrames,
    String? currentQrData,
    bool? showingBootstrap,
    String? sendError,
    HandshakeHint? appliedHint,
    bool clearSendError = false,
    bool clearReceiverPk = false,
    bool clearHint = false,
  }) {
    return SendState(
      fileName: fileName ?? this.fileName,
      fileBytes: fileBytes ?? this.fileBytes,
      fileExtension: fileExtension ?? this.fileExtension,
      filePath: filePath ?? this.filePath,
      receiverPk: clearReceiverPk ? null : (receiverPk ?? this.receiverPk),
      emitter: emitter ?? this.emitter,
      identity: identity ?? this.identity,
      chunkSize: chunkSize ?? this.chunkSize,
      ecLevel: ecLevel ?? this.ecLevel,
      fps: fps ?? this.fps,
      isEmitting: isEmitting ?? this.isEmitting,
      framesEmitted: framesEmitted ?? this.framesEmitted,
      totalFrames: totalFrames ?? this.totalFrames,
      currentQrData: currentQrData ?? this.currentQrData,
      showingBootstrap: showingBootstrap ?? this.showingBootstrap,
      sendError: clearSendError ? null : (sendError ?? this.sendError),
      appliedHint: clearHint ? null : (appliedHint ?? this.appliedHint),
    );
  }
}

class SendNotifier extends StateNotifier<SendState> {
  SendNotifier(this._sodium, this._identityStore) : super(SendState());

  final Sodium _sodium;
  final IdentityStore _identityStore;
  Timer? _timer;

  Future<void> pickFile() async {
    // file_picker 13 made these static and returns the files directly;
    // `withData` is gone because bytes always come back.
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final file = files.first;
    // PlatformFile.bytes is gone in file_picker 13: reading is explicit
    // now, so a picker no longer loads the whole file into memory before
    // anyone asks for it.
    final bytes = await file.readAsBytes();
    _stopTimer();

    // Auto-select the smallest chunk size that can carry this file without
    // overflowing the uint16 chunkCount field. The user can still lower it
    // afterwards; if even the largest option cannot fit the file, surface a
    // clear error instead of letting the transfer fail silently later.
    final chunkSize = recommendedChunkSize(bytes.length);
    final error = fileSizeError(bytes.length, chunkSize) ??
        (bytes.length > maxFileSizeForChunkSize(chunkSize)
            ? fileTooLargeError(bytes.length)
            : null);

    state = SendState(
      fileName: file.name,
      fileBytes: bytes,
      fileExtension: file.extension?.toLowerCase(),
      filePath: file.path,
      receiverPk: state.receiverPk,
      chunkSize: chunkSize,
      ecLevel: state.ecLevel,
      fps: state.fps,
      sendError: error,
    );
  }

  /// Stages bytes the user already has, rather than ones picked from
  /// disk.
  ///
  /// The vault uses this to send a file it holds: exporting it first,
  /// picking it back up and deleting it would mean writing the plaintext
  /// out just to read it in again, which is the one thing the vault is
  /// there to avoid.
  ///
  /// Shares pickFile's sizing and error handling so a vault file behaves
  /// exactly like any other once staged.
  void loadBytes(String name, Uint8List bytes) {
    _stopTimer();
    final chunkSize = recommendedChunkSize(bytes.length);
    final error = fileSizeError(bytes.length, chunkSize) ??
        (bytes.length > maxFileSizeForChunkSize(chunkSize)
            ? fileTooLargeError(bytes.length)
            : null);

    final dot = name.lastIndexOf('.');
    state = SendState(
      fileName: name,
      fileBytes: bytes,
      fileExtension:
          dot > 0 ? name.substring(dot + 1).toLowerCase() : null,
      receiverPk: state.receiverPk,
      chunkSize: chunkSize,
      ecLevel: state.ecLevel,
      fps: state.fps,
      sendError: error,
    );
  }

  /// Loads the receiver's public key, and applies the emission hint its
  /// QR carried, when it had one.
  ///
  /// Applied by default rather than merely offered: the receiver measured
  /// a real camera and the sender measured nothing, so the receiver's
  /// numbers are the better starting point. Every one of them stays
  /// adjustable, and the screen says where they came from — a suggestion
  /// the user cannot see the origin of is just an unexplained change to
  /// their settings.
  ///
  /// The chunk size is the exception. [pickFile] picks the smallest size
  /// that can carry the file at all, and a smaller suggestion would make
  /// the transfer impossible rather than slow, so a hint may only lower
  /// it within what the file allows.
  void setReceiverPk(Uint8List pk, {HandshakeHint? hint}) {
    if (hint == null) {
      state = state.copyWith(receiverPk: pk, clearHint: true);
      return;
    }

    final bytes = state.fileBytes;
    var chunkSize = hint.chunkSize;
    if (bytes != null && fileSizeError(bytes.length, chunkSize) != null) {
      // The suggestion cannot carry this file. Keep what pickFile chose:
      // a slower transfer beats one that cannot start.
      chunkSize = state.chunkSize;
    }

    // The pair has to be renderable. A hint arrives from another device
    // and knows nothing about the file being sent, so it can name a
    // combination that produces a QR larger than version 40 — which
    // displays nothing at all.
    final ec = chunkFitsQr(chunkSize, hint.ecLevel)
        ? hint.ecLevel
        : (ecLevelsFor(chunkSize).isEmpty
            ? state.ecLevel
            : ecLevelsFor(chunkSize).first);

    state = state.copyWith(
      receiverPk: pk,
      fps: hint.fps,
      chunkSize: chunkSize,
      ecLevel: ec,
      appliedHint: hint,
    );
  }

  /// Forgets the loaded receiver key, returning step 2 to its initial state.
  ///
  /// Needed because a wrong key is otherwise a dead end: the loaded-key card
  /// offered only "Rescan", and on a platform with no camera (Linux and
  /// Windows have no mobile_scanner implementation) rescanning cannot
  /// succeed, so the only way out was to restart the app.
  void clearReceiverPk() {
    state = state.copyWith(clearReceiverPk: true);
  }

  void setChunkSize(int size) {
    // Changing the chunk size mid-transfer cannot be applied to a running
    // emission — the receiver's decoder is built around the chunk count in
    // the bootstrap header — so stop instead of silently ignoring the user.
    // They can then restart with the new value without re-pairing, which is
    // the whole point: finding the right parameters is trial and error.
    if (state.isEmitting) stopEmitting();
    // Re-validate the picked file against the new chunk size so the error
    // appears / clears immediately as the user moves the slider.
    final bytes = state.fileBytes;
    final error = bytes == null ? null : fileSizeError(bytes.length, size);

    // Weaken the correction if the new chunk will not fit a QR at the
    // current level. The alternative is a combination that renders
    // nothing, and the user asked for the chunk size — so that is the
    // choice to honour, with the level following it.
    final ec = chunkFitsQr(size, state.ecLevel)
        ? state.ecLevel
        : (ecLevelsFor(size).isEmpty ? state.ecLevel : ecLevelsFor(size).first);

    state = state.copyWith(
      chunkSize: size,
      ecLevel: ec,
      sendError: error,
      clearSendError: error == null,
    );
  }

  void setEcLevel(String level) {
    // Ignored when the current chunk could not be rendered at it. The UI
    // disables those, so this is the guard for anything reaching here
    // another way — the receiver's hint, most of all.
    if (!chunkFitsQr(state.chunkSize, level)) return;
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
    // Use the persistent device identity — NOT a fresh one per transfer.
    // This is what makes the Ed25519 signature meaningful: the receiver
    // can verify that the sender is the same installation across sessions.
    final identity = await _identityStore.loadOrGenerate();
    final receiverKp = _ReceiverKeypairFromPk(state.receiverPk!);

    // Session.open validates the file size against the chunk size and throws
    // a DeadDropCryptoError if the uint16 chunkCount would overflow. Surface
    // that as a friendly message instead of letting the transfer die silently.
    final Emitter emitter;
    try {
      emitter = await Emitter.create(
        _sodium,
        state.fileBytes!,
        receiverKp,
        senderIdentity: identity,
        chunkSize: state.chunkSize,
        fileName: state.fileName,
      );
    } on DeadDropCryptoError catch (e) {
      state = state.copyWith(
        sendError: fileSizeError(state.fileBytes!.length, state.chunkSize) ??
            e.message,
      );
      return;
    }
    state = state.copyWith(
      emitter: emitter,
      identity: identity,
      isEmitting: true,
      framesEmitted: 0,
      totalFrames: emitter.session.chunkCount,
      showingBootstrap: true,
      currentQrData: encodeQrPayload(emitter.bootstrapQrPayload()),
      clearSendError: true,
    );
    // The screen must not dim while it is the transmission medium.
    unawaited(keepScreenAwake());
    // Hold the static bootstrap QR long enough for the receiver to lock on,
    // then switch to the animated data stream.
    _timer = Timer(const Duration(seconds: 4), _startDataPhase);
  }

  /// Stops the emission, keeping the picked file and the receiver key so the
  /// user can adjust parameters and start again without re-scanning.
  void stopEmitting() {
    _stopTimer();
    unawaited(allowScreenSleep());
    state = state.copyWith(
      isEmitting: false,
      showingBootstrap: false,
      currentQrData: null,
      framesEmitted: 0,
    );
  }

  /// Clears everything about this transfer and returns to step 1.
  ///
  /// stopEmitting keeps the file and the key so the user can retune and
  /// start again; this is the other case — done with that file, on to the
  /// next. Without it the only way back to an empty form was to close the
  /// app, which is a poor answer to "send another one".
  ///
  /// Keeps the identity, which belongs to the device rather than to any
  /// transfer, and keeps the emission settings: having just tuned fps and
  /// chunk size for the receiver's camera, being handed the defaults back
  /// would be a step backwards.
  void resetTransfer() {
    _stopTimer();
    unawaited(allowScreenSleep());
    state = SendState(
      identity: state.identity,
      chunkSize: state.chunkSize,
      ecLevel: state.ecLevel,
      fps: state.fps,
    );
  }

  /// Stops and immediately starts again, rebuilding the emitter so the
  /// current fps, chunk size and EC level apply. The session gets a new
  /// file_id, so the receiver — which filters frames by that id — treats it
  /// as a fresh transfer and ignores whatever it had collected.
  Future<void> restartEmitting() async {
    stopEmitting();
    await startEmitting();
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
    // A wakelock outliving the notifier would keep the screen on for the
    // rest of the app's life, draining a device whose owner may have no way
    // to charge it.
    unawaited(allowScreenSleep());
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
  final identityStore = ref.watch(identityStoreProvider);
  return SendNotifier(sodium, identityStore);
});

// ---------------------------------------------------------------------------
// Send Page (step-by-step guided flow)
// ---------------------------------------------------------------------------

class SendPage extends ConsumerStatefulWidget {
  const SendPage({super.key});

  @override
  ConsumerState<SendPage> createState() => _SendPageState();
}

class _SendPageState extends ConsumerState<SendPage> {
  /// Captured here so dispose can use it: `ref` throws once the element
  /// is finalizing, and the provider is global so the notifier outlives
  /// this widget anyway.
  late final SendNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = ref.read(sendProvider.notifier);
  }

  @override
  void dispose() {
    // Leaving the page ends the transfer. sendProvider is global, so
    // without this a file picked and then abandoned was still selected
    // the next time Send was opened — the user had moved on, the app
    // had not.
    //
    // Deferred past this frame because dispose runs during a build, and
    // changing provider state there throws.
    // Guarded for the same reason as the receive side: a ProviderScope
    // torn down with the page leaves a disposed notifier behind, and
    // state about to be discarded needs no reset.
    Future.microtask(() {
      if (_notifier.mounted) _notifier.resetTransfer();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        child: ContentWidthLimit(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Steps 1 and 2 are the actions; configuration and identity are
              // supporting material. On a desktop window they sit side by
              // side rather than stacking into a column that scrolls while
              // two thirds of the window stays empty. On a phone the same
              // widgets stack in this order.
              TwoColumnLayout(
                start: [
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
                            state.fileName == null
                                ? 'Choose file'
                                : 'Change file',
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
                ],
                end: [
                  // ── Step 3: Configure (collapsible) ──────────────
                  _ConfigSection(state: state, notifier: notifier),
                  const SizedBox(height: 16),

                  // ── Identity fingerprint ─────────────────────────
                  const _IdentityFingerprintCard(),
                  const SizedBox(height: 16),
                ],
              ),
              const SizedBox(height: 8),

              // Full width in both layouts: this is the one action that acts
              // on everything above it, and it should not look like it
              // belongs to either column.
              _StartSection(state: state, notifier: notifier),
            ],
          ),
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
                // Expanded, not a bare Text: in the two-column desktop
                // layout a card gets roughly half the window, and a title
                // at its natural size overflows the row.
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
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
/// default. An info button toggles a metadata section with type, dimensions
/// (images), page count (PDFs), size, magic bytes, and full path.
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

  /// File bytes, used to render a thumbnail and extract metadata.
  final Uint8List? fileBytes;

  @override
  State<_FileInfoTile> createState() => _FileInfoTileState();
}

class _FileInfoTileState extends State<_FileInfoTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasMetadata = widget.fileExtension != null ||
        widget.filePath != null ||
        widget.fileBytes != null;

    return Container(
      decoration: BoxDecoration(
        color: DeadDropColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DeadDropColors.borderInput),
      ),
      child: Column(
        children: [
          Padding(
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
                        formatFileSize(widget.fileSize),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (hasMetadata) ...[
                  _InfoButton(
                    expanded: _expanded,
                    onTap: () => setState(() => _expanded = !_expanded),
                  ),
                  const SizedBox(width: 4),
                ],
                const Icon(Icons.check_circle,
                    color: DeadDropColors.success, size: 20),
              ],
            ),
          ),
          if (_expanded && hasMetadata) _buildMetadataSection(),
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

  Widget _buildMetadataSection() {
    final bytes = widget.fileBytes;
    final ext = widget.fileExtension;
    final rows = <Widget>[];

    // Type: extension + MIME
    final mime = guessMimeType(bytes, ext);
    if (ext != null || mime != null) {
      final typeLabel = ext != null ? ext.toUpperCase() : '';
      final mimeLabel = mime ?? '';
      final value = mimeLabel.isNotEmpty && typeLabel.isNotEmpty
          ? '$typeLabel ($mimeLabel)'
          : typeLabel.isNotEmpty
              ? typeLabel
              : mimeLabel;
      if (value.isNotEmpty) {
        rows.add(_MetadataRow(label: 'Type', value: value));
      }
    }

    // Dimensions (images only)
    if (bytes != null && isPreviewableImageExtension(ext)) {
      final dims = parseImageDimensions(bytes);
      if (dims != null) {
        rows.add(_MetadataRow(
          label: 'Dimensions',
          value: '${dims.width} \u00d7 ${dims.height}',
        ));
      }
    }

    // Page count (PDFs only)
    if (bytes != null && ext == 'pdf') {
      final pages = countPdfPages(bytes);
      if (pages != null) {
        rows.add(_MetadataRow(
          label: 'Pages',
          value: '~$pages',
        ));
      }
    }

    // Size: human-readable + exact bytes
    rows.add(_MetadataRow(
      label: 'Size',
      value: formatSizeWithBytes(widget.fileSize),
    ));

    // Magic bytes / signature
    if (bytes != null && bytes.isNotEmpty) {
      rows.add(_MetadataRow(
        label: 'Signature',
        value: fileSignature(bytes),
      ));
    }

    // Path
    if (widget.filePath != null) {
      rows.add(_MetadataRow(
        label: 'Path',
        value: widget.filePath!,
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }
}

/// A circular bordered info button that toggles the metadata section.
class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: expanded ? 'Hide metadata' : 'View metadata',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: expanded
                  ? DeadDropColors.accent
                  : DeadDropColors.borderButton,
              width: 1.5,
            ),
            color: expanded
                ? DeadDropColors.accent.withValues(alpha: 0.15)
                : Colors.transparent,
          ),
          child: Icon(
            Icons.info_outline,
            size: 18,
            color:
                expanded ? DeadDropColors.accent : DeadDropColors.textSecondary,
          ),
        ),
      ),
    );
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
            width: 72,
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

/// Whether this platform can scan a QR code at all.
///
/// `mobile_scanner` 5.2.3 ships implementations for android, ios, macos and
/// web only — there is no Linux or Windows scanner. Where this is false the
/// scan button is not offered (it could only fail) and manual entry is the
/// primary path rather than a disclosed fallback.
// Which platforms can scan is decided in src/desktop_scanner.dart, where
// both implementations live: mobile_scanner on android/ios/macos, and the
// camera_desktop + zxing2 pair on linux/windows.
bool get _canScanQr => canScanQr;

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
              color: DeadDropColors.success.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DeadDropColors.success),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: DeadDropColors.success),
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
                // "Change", not only "Rescan": a key that loaded but is the
                // wrong one must not be a dead end. Rescanning is impossible
                // where there is no camera, so this returns step 2 to its
                // initial state, where scanning and manual entry are both
                // available again.
                TextButton(
                  onPressed: notifier.clearReceiverPk,
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
        ] else ...[
          // Scanning is only offered where a scanner exists. mobile_scanner
          // 5.2.3 ships android, ios, macos and web implementations only, so
          // on Linux and Windows the button could never do anything —
          // offering it sends the user to a camera screen that cannot work
          // and tells them nothing about why.
          if (_canScanQr) ...[
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
          ] else
            const Text(
              'Ask the receiver for their public key and paste it below. '
              'Scanning is not available on this platform yet.',
              style: TextStyle(color: DeadDropColors.textSecondary),
            ),
          // Advanced: manual hex input
          const SizedBox(height: 8),
          _ManualKeyInput(onKeyLoaded: notifier.setReceiverPk),
        ],
      ],
    );
  }

  Future<void> _scanReceiverKey(BuildContext context) async {
    final payload = await Navigator.of(context).push<HandshakePayload>(
      MaterialPageRoute(builder: (_) => const _KeyScanPage()),
    );
    if (payload != null) {
      notifier.setReceiverPk(payload.publicKey, hint: payload.hint);
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
  bool _found = false;

  /// Handles one decoded QR string, from either camera implementation.
  ///
  /// Ignores anything that is not a handshake QR — the user may well be
  /// pointing at some other code on the way — and returns the first key
  /// it recognises.
  void _onRaw(String raw) {
    if (_found) return;
    final payload = decodeHandshakePayload(raw);
    if (payload == null) return;
    _found = true;
    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receiver key')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          DesktopScannerView(onDetect: _onRaw),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
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

// ---------------------------------------------------------------------------
// Manual key input (advanced fallback)
// ---------------------------------------------------------------------------

class _ManualKeyInput extends ConsumerStatefulWidget {
  const _ManualKeyInput({required this.onKeyLoaded});

  final ValueChanged<Uint8List> onKeyLoaded;

  @override
  ConsumerState<_ManualKeyInput> createState() => _ManualKeyInputState();
}

class _ManualKeyInputState extends ConsumerState<_ManualKeyInput> {
  /// Starts expanded where there is no camera to scan with. On Linux and
  /// Windows `mobile_scanner` has no implementation at all, so typing or
  /// pasting the key is not an "advanced fallback" there — it is the only
  /// way to load one, and hiding it behind a disclosure is a trap.
  late bool _expanded = !_canScanQr;
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
          _canScanQr ? 'Manual entry (advanced)' : 'Enter the key',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Public key (hex)',
            hintText: '64 hex characters',
            border: const OutlineInputBorder(),
            errorText: _error,
            // Pasting matters more than typing: the key reaches the sender
            // through some other channel, so it is almost always already on
            // the clipboard. Sixty-four hex characters is not something to
            // retype by hand.
            suffixIcon: IconButton(
              icon: const Icon(Icons.content_paste, size: 20),
              tooltip: 'Paste',
              onPressed: _pasteFromClipboard,
            ),
          ),
          style: technicalTextStyle(ref),
          maxLength: 64,
          onChanged: _validate,
        ),
      ],
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      setState(() => _error = 'Clipboard is empty');
      return;
    }
    _controller.text = text;
    _validate(text);
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
            // Said on the collapsed tile on purpose. The panel starts
            // closed, so a note about changed settings placed inside it
            // would only be read by someone who already went looking —
            // and settings that changed by themselves, unexplained, read
            // as a bug.
            state.appliedHint == null
                ? 'Transfer parameters'
                : 'Set from the receiver\'s camera — tap to adjust',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: state.appliedHint == null
                      ? null
                      : DeadDropColors.success,
                ),
          ),
          initiallyExpanded: false,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (state.appliedHint != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'The receiver\'s QR carried these settings, measured from '
                  'their camera. They are a suggestion — change anything '
                  'here if the transfer is not reading well.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DeadDropColors.textSecondary,
                      ),
                ),
              ),
            ],
            _ChunkSizeSelector(state: state, notifier: notifier),
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
              // A level is disabled when the current chunk would not fit
              // in a QR with that much correction. Stronger correction
              // leaves less room for data, so at 2048 bytes only L has
              // the capacity — offering the others rendered nothing.
              segments: [
                for (final ec in const [
                  ('L', 'L (7%)'),
                  ('M', 'M (15%)'),
                  ('Q', 'Q (25%)'),
                  ('H', 'H (30%)'),
                ])
                  ButtonSegment(
                    value: ec.$1,
                    label: Text(ec.$2),
                    enabled: chunkFitsQr(state.chunkSize, ec.$1),
                  ),
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
            style: TextStyle(
              // A validation error is a hard stop — show it in the error
              // colour; a "what's missing" hint stays a softer warning.
              color: state.sendError != null
                  ? DeadDropColors.error
                  : DeadDropColors.warning,
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
                formatFileSize(state.fileBytes?.length ?? 0),
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
                    : state.totalFrames != null
                        ? 'Frame ${state.framesEmitted}/${state.totalFrames}'
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

              // Restart and Stop. Restart exists because finding workable
              // fps and chunk-size values is trial and error, and without
              // it the only way to apply a new value was to close the app
              // and re-pair with the receiver.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: notifier.restartEmitting,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Restart'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: notifier.stopEmitting,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                        backgroundColor: DeadDropColors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Done with this file, on to the next. Stop keeps the file
              // and the key so the user can retune and start again; this
              // clears both. Without it the only way back to an empty
              // form was to close the app.
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    notifier.resetTransfer();
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New transfer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

/// Discrete chunk-size picker.
///
/// Chunk size is a trade-off a non-technical user should not have to reason
/// about, so the file picker pre-selects the smallest size that fits the file
/// (see [recommendedChunkSize]). This control exists for the rare case where
/// the user wants to override that choice. Options that cannot fit the
/// current file are disabled, and the chosen size shows the largest file it
/// can carry — so the limit is visible *before* it bites, never as a silent
/// failure mid-transfer.
class _ChunkSizeSelector extends StatelessWidget {
  const _ChunkSizeSelector({required this.state, required this.notifier});

  final SendState state;
  final SendNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final fileSize = state.fileBytes?.length;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Chunk size'),
            Text('${state.chunkSize} bytes'),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final size in kChunkSizeOptions)
              ChoiceChip(
                label: Text('$size'),
                selected: state.chunkSize == size,
                // Disabled when it cannot carry the picked file, and
                // when the frame would not fit in a QR at the chosen
                // error correction. The second case used to be
                // selectable and simply broke the display: 2048 bytes
                // encodes to about 2,860 characters, which only level L
                // can hold.
                onSelected: state.isEmitting ||
                        (fileSize != null &&
                            fileSize > maxFileSizeForChunkSize(size)) ||
                        !chunkFitsQr(size, state.ecLevel)
                    ? null
                    : (_) => notifier.setChunkSize(size),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          fileSize == null
              ? 'Larger chunks fit larger files but are harder to scan.'
              : 'Up to ${formatSizeForMessage(maxFileSizeForChunkSize(state.chunkSize))} '
                  'per transfer at this size.',
          style: textTheme.bodySmall
              ?.copyWith(color: DeadDropColors.textSecondary),
        ),
      ],
    );
  }
}

/// How wide to draw the emitted QR, given the space the layout offers.
///
/// A dense code has to survive two reductions before it is read: the
/// sender's own rasterisation, and the receiver's camera. A 1024-byte
/// chunk is a 157x157 module code, so at the 300 logical pixels this
/// used to be fixed at, a module was under two pixels on the sender's
/// screen -- destroyed before any camera saw it. Filling the available
/// width gives those modules room on a phone and on a desktop window
/// alike.
///
/// [kQrMinDisplaySize] keeps a narrow window from shrinking the code
/// below what the old fixed size gave, and [kQrMaxDisplaySize] stops a
/// maximised desktop window from drawing a QR nobody can fit in frame.
double qrDisplaySize(double available) {
  if (!available.isFinite) return kQrMinDisplaySize;
  final usable = available - _qrPadding * 2;
  return usable.clamp(kQrMinDisplaySize, kQrMaxDisplaySize);
}

/// The floor for [qrDisplaySize]: the size the renderer used to be fixed at.
const double kQrMinDisplaySize = 300;

/// The ceiling for [qrDisplaySize].
///
/// Past this a code stops being easier to scan and starts being hard to
/// hold entirely within the camera's view.
const double kQrMaxDisplaySize = 720;

const double _qrPadding = 16;

/// Dumb QR renderer: displays exactly what the notifier produced. All frame
/// generation logic lives in [SendNotifier], so there is a single source of
/// truth for the emitted sequence.
class _QrDisplay extends StatelessWidget {
  const _QrDisplay({required this.state});

  final SendState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Column(
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
              size: qrDisplaySize(constraints.maxWidth),
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          if (state.showingBootstrap)
            Text(
              'Session bootstrap — point the receiver camera here',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
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

// ---------------------------------------------------------------------------
// Identity fingerprint card (shown on the send page)
// ---------------------------------------------------------------------------

/// Displays the device's persistent Ed25519 identity fingerprint.
///
/// This is the "who am I" of the sender: the receiver can compare this
/// fingerprint out-of-band (in person, over a call) to confirm the file
/// is coming from the expected device.
class _IdentityFingerprintCard extends ConsumerWidget {
  const _IdentityFingerprintCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityStore = ref.watch(identityStoreProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.fingerprint, color: DeadDropColors.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your identity fingerprint',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FutureBuilder<String>(
              future: identityStore.fingerprint(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  children: [
                    Center(
                      child: SelectableText(
                        snapshot.data!,
                        style: technicalTextStyle(ref, relativeTo: 1.4,
                            letterSpacing: 2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Share this fingerprint with the receiver through '
                      'another channel (in person, phone call) so they can '
                      'verify the file comes from your device.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
