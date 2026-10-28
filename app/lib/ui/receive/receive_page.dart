import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sodium/sodium.dart';

import '../../src/crypto.dart';
import '../../src/handshake.dart';
import '../../src/receiver.dart';
import '../../src/screen_wake.dart';
import '../../src/tofu_store.dart';
import '../../src/transport.dart';
import '../../src/utils.dart';
import '../../main.dart';
import '../theme.dart';
import '../technical_text.dart';
import '../passphrase_field.dart';
import '../desktop_scanner_view.dart';
import '../../src/camera_measurement_store.dart';
import '../../src/capability_hint.dart';
import '../vault/vault_controller.dart';

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
    this.savedToVault = false,
    this.error,
    this.senderFingerprint,
    this.senderName,
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

  /// Set once the received bytes have been sealed into the vault via
  /// [ReceiveNotifier.saveToVault]. Kept separate from [savedPath] — the two
  /// destinations are mutually exclusive in the UI (see receive_page.dart's
  /// result card) but are tracked independently so neither save path has to
  /// know about the other's bookkeeping.
  final bool savedToVault;

  /// The sender's identity fingerprint (first 16 hex chars of their
  /// Ed25519 public key), extracted from the verified session header.
  final String? senderFingerprint;

  /// True when this sender fingerprint had never been seen before (TOFU)
  /// and the user accepted it during this session. Kept so the UI can keep
  /// showing the "verify out of band" hint for the rest of the transfer.
  final bool isNewSender;

  /// The name the user gave this sender, or null if they are unnamed or
  /// this is a first contact. A local label, not an authenticated claim —
  /// see TofuStore.
  final String? senderName;

  /// A verified session from an unrecognised sender, held until the user
  /// accepts or rejects the fingerprint.
  ///
  /// TOFU only means anything if a human looks at the fingerprint the first
  /// time: trust established automatically is not trust. While this is set
  /// the session is NOT armed — [receiver] stays null, incoming data frames
  /// are ignored, and nothing has been written to the TOFU store.
  final PendingSender? pendingSender;

  double get progress => totalChunks > 0 ? chunksDecoded / totalChunks : 0.0;

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
    bool? savedToVault,
    String? error,
    String? senderFingerprint,
    String? senderName,
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
      savedToVault: savedToVault ?? this.savedToVault,
      error: error,
      senderFingerprint: senderFingerprint ?? this.senderFingerprint,
      senderName: senderName ?? this.senderName,
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

  // The wakelock is not taken or released here. The receive screen holds
  // it for as long as it is open, because the screen matters before the
  // camera starts too: the handshake QR is on display while the sender
  // lines their camera up. Releasing it when scanning stops would let the
  // phone dim during exactly that wait.
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
        senderName: await _tofuStore.nameFor(fingerprint),
        isNewSender: false,
      );
    } on DeadDropCryptoError catch (e) {
      state = state.copyWith(error: 'Session rejected: ${e.message}');
    }
  }

  /// The user confirmed the fingerprint out of band: remember the sender and
  /// arm the held session so data frames start decoding.
  /// [name] is the label the user chose for this sender, or null if they
  /// accepted without naming them. Naming is offered because a device's
  /// identity is persistent: the same sender shows the same fingerprint on
  /// every transfer, so the name stays meaningful.
  Future<void> acceptPendingSender({String? name}) async {
    final pending = state.pendingSender;
    if (pending == null) return;

    await _tofuStore.markKnown(pending.fingerprint, name: name);
    state = state.copyWith(
      receiver: pending.receiver,
      totalChunks: pending.receiver.session!.header.chunkCount,
      isNewSender: true,
      clearPendingSender: true,
      senderName: name,
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
    final bytes = state.fileBytes;
    if (bytes == null) return;

    final name = state.fileName ??
        'deaddrop_received_${DateTime.now().millisecondsSinceEpoch}';

    try {
      // The user picks the destination on every platform, including mobile.
      //
      // On Android and iOS `saveFile` requires `bytes` and throws an
      // ArgumentError without them; it then hands the bytes to the platform
      // and writes the file itself. An earlier fix read that failure as
      // "saveFile is desktop-only" and fell back to the app's private
      // documents directory, which made the button work but chose the
      // destination for the user — the file landed somewhere they could not
      // reach from a file manager. Passing the bytes gets the system
      // document picker, so any folder they can write to is available.
      //
      // file_picker 13 takes the bytes on every platform and writes the
      // file itself, so the desktop branch that used to write them by
      // hand is gone. It returns a Uri rather than a path.
      final chosen = await FilePicker.saveFile(
        dialogTitle: 'Save received file',
        fileName: name,
        bytes: bytes,
      );
      if (chosen == null) return; // cancelled

      state = state.copyWith(savedPath: chosen.toFilePath());
    } catch (e) {
      // A failed save must say so. Swallowing it leaves the user believing
      // a file they may have crossed a border for is on disk when it is not.
      state = state.copyWith(error: 'Could not save the file: $e');
    }
  }

  /// Seals the received bytes directly into the open vault environment via
  /// [vaultController].
  ///
  /// Unlike [saveFile], this never touches [FilePicker] and never writes
  /// plaintext to disk at any point: the bytes go straight from
  /// [ReceiveState.fileBytes] (already in memory from the transfer) into
  /// [VaultController.saveFile] / [VaultStore.put], which seal them before
  /// the first byte is written. There is no intermediate temp file for the
  /// caller to clean up — the store's own atomic-write path
  /// (temp-then-rename) only ever sees ciphertext.
  ///
  /// Requires an unlocked vault — [VaultController.saveFile] returns null
  /// otherwise, in which case this leaves [ReceiveState.savedToVault]
  /// unset. The UI (`_ReceivePageState`) is responsible for getting the
  /// vault unlocked before calling this.
  /// Returns whether the file actually reached the vault, so the caller
  /// can tell the user. A silent failure here is the worst outcome
  /// available: the file is gone from the screen and was never stored,
  /// and the user has no way to know.
  Future<bool> saveToVault(VaultController vaultController) async {
    if (state.fileBytes == null) return false;
    final name = state.fileName ??
        'deaddrop_received_${DateTime.now().millisecondsSinceEpoch}';
    final entry = await vaultController.saveFile(name, state.fileBytes!);
    if (entry == null) {
      state = state.copyWith(
        error: 'Could not save to the vault — it is locked.',
      );
      return false;
    }
    state = state.copyWith(savedToVault: true, error: null);
    return true;
  }

  /// Clears everything about the current transfer, keeping this device's
  /// receiver keypair so the sender does not have to re-scan the handshake
  /// QR. Use when a transfer is going badly and the sender is going to
  /// restart with different parameters.
  void reset() {
    state = ReceiveState(receiverKeypair: state.receiverKeypair);
  }

  /// Abandons a transfer that is partway through.
  ///
  /// Separate from [reset] only so the UI can offer it with honest wording:
  /// the partially-decoded chunks are discarded, and because the sender
  /// mints a new file_id when it restarts, nothing collected so far could
  /// have been reused anyway.
  void cancelTransfer() {
    reset();
  }
}

/// The last camera measurement this device took, shared so the handshake
/// QR and the scanner agree on one store.
final cameraMeasurementStoreProvider = Provider<CameraMeasurementStore>(
  (ref) => CameraMeasurementStore(),
);

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

/// Renders a save destination in a form a person can act on.
///
/// Desktop returns a real filesystem path, which is already readable and is
/// shown unchanged. Android's Storage Access Framework instead returns a
/// content URI such as
/// `content://com.android.providers.downloads.documents/document/raw%3A%2Fstorage%2Femulated%2F0%2FDownload%2Freport.pdf`,
/// which tells the user nothing. Where such a URI embeds a readable path,
/// that path is shown; otherwise the decoded document identifier is, which
/// at least names the folder and file.
@visibleForTesting
String displayPath(String raw) {
  if (!raw.startsWith('content://')) return raw;

  final decoded = Uri.decodeComponent(raw);
  // SAF document ids look like "raw:/storage/emulated/0/Download/x.pdf" or
  // "primary:Download/x.pdf"; both carry the part worth showing after the
  // last colon.
  final marker = decoded.lastIndexOf(':');
  if (marker != -1 && marker + 1 < decoded.length) {
    final tail = decoded.substring(marker + 1);
    if (tail.contains('/')) return tail;
  }
  return decoded;
}

class _ReceivePageState extends ConsumerState<ReceivePage> {

  /// Whether the receiver public key is shown as text instead of a QR code.
  /// The text view helps when the sender cannot scan (no camera, small or
  /// cracked screen, focus issues) and needs to type or paste the key.
  bool _showKeyAsText = false;

  /// Captured in initState so dispose can use it.
  ///
  /// `ref` is unusable from dispose: by then the element is finalizing and
  /// reading it throws "Cannot use ref after the widget was disposed". The
  /// notifier itself outlives this widget — the provider is global — so
  /// holding it is safe, and it is the only way to reset state on the way
  /// out.
  late final ReceiveNotifier _notifier;

  /// The hint this device will put in its handshake QR, from the last
  /// reception. Null on a first run, which simply means no hint.
  EmissionHint? _hint;


  @override
  void initState() {
    super.initState();
    _notifier = ref.read(receiveProvider.notifier);
    // Held for the whole screen, not just while the camera runs. The
    // receiver shows its handshake QR first and then waits, sometimes for
    // a while, for the other person to scan it — and a phone that dims
    // mid-wait hides the very thing the sender is pointing a camera at.
    // Reported from a real Android device: the screen kept dimming.
    unawaited(keepScreenAwake());
    _loadHint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifier.initKeypair();
    });
  }

  Future<void> _loadHint() async {
    final stored = await ref.read(cameraMeasurementStoreProvider).read();
    if (!mounted || stored == null) return;
    setState(() => _hint = suggestEmission(stored.capability));
  }


  /// Remembers what the camera managed, for the next handshake.
  ///
  /// Written as it improves rather than once at the end: the scanner can
  /// be closed at any moment, and a measurement that only lands on a
  /// clean exit would mostly never land.
  void _rememberMeasurement(CameraCapability capability) {
    unawaited(ref.read(cameraMeasurementStoreProvider).write(capability));
  }

  @override
  void dispose() {
    _stopScanner();
    // Released here rather than when scanning stops, to match where it is
    // acquired. A wakelock left held drains the battery of a device whose
    // owner may have no way to charge it.
    unawaited(allowScreenSleep());
    // Leaving the page ends the reception, for the same reason as the
    // send side: receiveProvider is global, so a half-finished transfer
    // was still on screen when the user came back having moved on.
    //
    // reset() keeps the receiver keypair, so the sender does not have to
    // re-scan the handshake QR — that pairing is not what the user
    // walked away from.
    // Guarded: when the whole ProviderScope is being torn down — the app
    // closing, or a test ending — the notifier may already be disposed by
    // the time this microtask runs, and touching its state then throws.
    // Nothing is lost in that case: state that is about to be discarded
    // does not need resetting.
    Future.microtask(() {
      if (_notifier.mounted) _notifier.reset();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(receiveProvider);
    final notifier = ref.read(receiveProvider.notifier);

    // Mirrors home_page.dart: the vault destination is offered only once a
    // vault exists in this session, never merely disabled — see that file's
    // doc comment on vaultExists for why an absent option, not a greyed-out
    // one, is the property the vault's coercion-resistance depends on.
    final vaultExists = ref.watch(
      vaultControllerProvider.select((s) => s.exists),
    );

    // Stop the camera as soon as the transfer completes.
    ref.listen(receiveProvider, (prev, next) {
      if (next.fileBytes != null && (prev?.fileBytes == null)) {
        _stopScanner();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Receive a file')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Two columns once there is room for them. The breakpoint is
          // about where a laptop window stops being phone-shaped; below
          // it the single column is unchanged, because a phone has no
          // width to give away.
          final wide = constraints.maxWidth >= 900;

          // While the camera is running it is the thing the user is
          // looking at, so the handshake QR folds away: its job ended
          // when the sender scanned it, and on a phone it was pushing
          // the progress bar off the bottom of the screen.
          final showKeyStep = !state.isScanning || wide;

          final keyStep = <Widget>[
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
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            child: QrImageView(
                              data: encodeHandshakeQr(
                                state.receiverKeypair!.publicKey,
                                hint: _hint == null
                                    ? null
                                    : HandshakeHint(
                                        fps: _hint!.fps,
                                        chunkSize: _hint!.chunkSize,
                                        ecLevel: _hint!.ecLevel,
                                      ),
                              ),
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
                            : _hint == null
                                ? 'Show this QR to the sender. It contains only '
                                    'your public key — the file itself is '
                                    'encrypted end-to-end.'
                                : 'Show this QR to the sender. It contains your '
                                    'public key and a suggestion for how fast to '
                                    'send, based on what this camera managed last '
                                    'time — the file itself is encrypted '
                                    'end-to-end.',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ] else
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),
          ];

          final scanStep = <Widget>[
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
                          child: DesktopScannerView(
                            onDetect: notifier.processRawQr,
                            onMeasured: _rememberMeasurement,
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
          ];

          final senderBlock = <Widget>[
              // ── Unknown sender: decision required before decoding ────
              if (state.awaitingSenderApproval) ...[
                _UnknownSenderPrompt(
                  fingerprint: state.pendingSender!.fingerprint,
                  onAccept: (name) =>
                      notifier.acceptPendingSender(name: name),
                  onReject: notifier.rejectPendingSender,
                ),
                const SizedBox(height: 16),
              ]
              // ── Sender identity (shown after bootstrap) ──────────
              else if (state.senderFingerprint != null) ...[
                _SenderIdentityCard(
                  fingerprint: state.senderFingerprint!,
                  isNewSender: state.isNewSender,
                  name: state.senderName,
                ),
                const SizedBox(height: 16),
              ],
          ];

          final progressBlock = <Widget>[
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
                      // Cancel is offered only while a transfer is still
                      // running: a slow one usually means the sender needs to
                      // change fps or chunk size, and without this the only
                      // way out was to close the app and re-pair.
                      if (state.fileBytes == null) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            notifier.cancelTransfer();
                            _stopScanner();
                          },
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel transfer'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            foregroundColor: DeadDropColors.error,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Cancelling keeps your key, so the sender does not '
                            'have to scan it again.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: DeadDropColors.textSecondary,
                                ),
                          ),
                        ),
                      ],
                      if (state.fileBytes != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[900]!.withValues(alpha: 0.3),
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
                                  Expanded(
                                    child: Text(
                                      'Transfer complete!',
                                      style: TextStyle(
                                        color: Colors.green[400],
                                        fontWeight: FontWeight.bold,
                                      ),
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
                                // Selectable and wrapping rather than
                                // truncated: this is the only record of where
                                // a file the user may have taken real risks
                                // for actually went, and they may need to
                                // copy it.
                                SelectableText(
                                  'Saved to: ${displayPath(state.savedPath!)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              if (state.savedToVault) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Saved to vault',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                              const SizedBox(height: 12),
                              // Stacked, not side by side. Three labelled
                              // buttons sharing a phone's width left each one
                              // too narrow to read, and the labels had been
                              // cut to single words ("Device", "New") to make
                              // them fit at all. Full width each costs a
                              // little vertical space on a screen that has it
                              // — the file has arrived, nothing else is
                              // competing for room — and buys labels that say
                              // what they do.
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: state.savedPath == null
                                      ? notifier.saveFile
                                      : null,
                                  icon: const Icon(Icons.save),
                                  label: const Text('Save to this device'),
                                ),
                              ),
                              // The vault destination is offered only once a
                              // vault exists in this session — never shown
                              // disabled. A greyed-out option would itself
                              // tell an attacker the feature exists and the
                              // user set it up, which is exactly the kind of
                              // tell the vault's coercion-resistance is built
                              // to avoid (see home_page.dart's identical
                              // treatment of its Vault entry).
                              if (vaultExists) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: state.savedToVault
                                        ? null
                                        : () => _saveToVault(context, ref),
                                    icon: const Icon(Icons.lock_outline),
                                    label: const Text('Save to the vault'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    notifier.reset();
                                    _stopScanner();
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('New transfer'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
          ];

          final errorBlock = <Widget>[
            if (state.error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[900]!.withValues(alpha: 0.3),
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
          ];

          List<Widget> spaced(List<Widget> items) => [
                for (final w in items) ...[w, const SizedBox(height: 16)],
              ];

          if (wide) {
            // Camera on the left, everything that reports on the right.
            // The sender block no longer displaces the progress bar,
            // because the two are not in the same column any more.
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: spaced([...keyStep, ...scanStep]),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: spaced([
                        ...senderBlock,
                        ...progressBlock,
                        ...errorBlock,
                      ]),
                    ),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: spaced([
                if (showKeyStep) ...keyStep,
                ...scanStep,
                ...senderBlock,
                ...progressBlock,
                ...errorBlock,
              ]),
            ),
          );
        },
      ),
    );
  }

  /// Saves the received file into the vault, prompting for the vault's
  /// passphrase first if it is locked.
  ///
  /// The vault must be unlocked to receive a write: [VaultController] only
  /// ever holds a data key for whichever environment the user explicitly
  /// unlocked, and there is no way to derive one from nothing (unlocking is
  /// the whole point of the passphrase — see vault_controller.dart). Three
  /// options exist when a vault exists but is locked: offer the button and
  /// let the save fail (confusing — the button looked actionable), silently
  /// unlock with no passphrase (impossible, and if it were possible it would
  /// defeat the vault's purpose), or ask for the passphrase right here. This
  /// picks the third: a small inline prompt that unlocks via the same
  /// [VaultController.unlock] the Vault screen uses, then proceeds with the
  /// save on success. A wrong passphrase here behaves exactly like a wrong
  /// passphrase on the Vault screen (attempt-guard penalties, self-destruct)
  /// — this prompt does not bypass any of that, it just reaches the same
  /// entry point from a second place in the UI.
  Future<void> _saveToVault(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(receiveProvider.notifier);
    final vaultController = ref.read(vaultControllerProvider.notifier);

    if (!ref.read(vaultControllerProvider).unlocked) {
      final unlocked = await _promptVaultUnlock(context);
      if (!unlocked) return;
    }

    final saved = await notifier.saveToVault(vaultController);
    if (!context.mounted) return;
    // Say so. The button disabling itself is too quiet a signal for an
    // action whose whole point is that the file is now somewhere the user
    // cannot see, and a failure showed nothing at all.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'Saved to the vault.' : 'Could not save to the vault.',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Coloured, not the default surface. On macOS the default snack
        // bar is nearly the same shade as this app's background and the
        // confirmation went unnoticed — which for an action whose whole
        // point is that the file is now somewhere invisible is the one
        // message that must land.
        backgroundColor:
            saved ? DeadDropColors.success : DeadDropColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: saved ? 3 : 6),
      ),
    );
  }

  /// Shows a small modal asking for the vault passphrase, used when
  /// [_saveToVault] is invoked while the vault is locked. Returns whether
  /// the vault ended up unlocked.
  Future<bool> _promptVaultUnlock(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _VaultUnlockDialog(),
    );
    return result ?? false;
  }

  /// Scanning lifecycle hooks.
  ///
  /// [DesktopScannerView] owns the camera: it opens one on mount and
  /// releases it on dispose, and measures it while it reads. These remain
  /// as the page's own start/stop points so the call sites stay readable
  /// and a future need for per-scan state has somewhere to live.
  void _startScanner() {}

  void _stopScanner() {}

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
                // Expanded, not a bare Text: a title at its natural size
                // overflows the row on a narrow phone.
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

/// Text view of the receiver public key: selectable hex grouped in blocks
/// of four characters (easy to read out loud or type by hand), plus a
/// copy-to-clipboard button. Used when the sender cannot scan the QR.
class _PublicKeyTextView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
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
            style: technicalTextStyle(ref, relativeTo: 1.08,
                    letterSpacing: 0.5)
                .copyWith(height: 1.6),
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
class _UnknownSenderPrompt extends ConsumerStatefulWidget {
  const _UnknownSenderPrompt({
    required this.fingerprint,
    required this.onAccept,
    required this.onReject,
  });

  final String fingerprint;

  /// Called with the name the user typed, or null if they left it blank.
  final void Function(String? name) onAccept;
  final VoidCallback onReject;

  @override
  ConsumerState<_UnknownSenderPrompt> createState() =>
      _UnknownSenderPromptState();
}

class _UnknownSenderPromptState extends ConsumerState<_UnknownSenderPrompt> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

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
                widget.fingerprint,
                style: technicalTextStyle(ref, relativeTo: 1.4,
                    letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 16),
            // Naming is offered here, and only here, because this is the
            // one moment the user is already looking at the person the
            // code belongs to. A device's identity is persistent, so the
            // name stays correct for every later transfer — and "From:
            // Ana" is something they can check against their own memory,
            // which sixteen hex characters is not.
            //
            // Optional on purpose: someone receiving under pressure should
            // not have to fill in a form to accept a file.
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name this sender (optional)',
                hintText: 'e.g. Ana',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _accept(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onReject,
                    icon: const Icon(Icons.close),
                    label: const Text("Codes don't match"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _accept,
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

  void _accept() => widget.onAccept(_nameController.text);
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
class _SenderIdentityCard extends ConsumerWidget {
  const _SenderIdentityCard({
    required this.fingerprint,
    required this.isNewSender,
    this.name,
  });

  final String fingerprint;
  final bool isNewSender;

  /// The name the user gave this sender, if any.
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A known sender collapses to one line.
    //
    // This card used to sit between the camera preview and the progress
    // bar at full height, so on a phone the user had to choose between
    // aiming the camera and watching progress — scrolling between the two
    // during a transfer, which is the one moment attention is scarce.
    //
    // For a sender they have already checked and named there is nothing to
    // act on, so it says who it is and gets out of the way; the full
    // fingerprint is still one tap away. A NEW sender keeps the full
    // warning, because there the user is being asked to do something.
    if (!isNewSender) {
      return _KnownSenderLine(fingerprint: fingerprint, name: name);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber,
                    color: DeadDropColors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name == null ? 'Sender identity' : 'From $name',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: SelectableText(
                fingerprint,
                style: technicalTextStyle(ref, relativeTo: 1.4,
                    letterSpacing: 2),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DeadDropColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: DeadDropColors.warning.withValues(alpha: 0.4),
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
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: DeadDropColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line for a sender the user has already checked: who it is, and a tap
/// to see the fingerprint again.
class _KnownSenderLine extends ConsumerWidget {
  const _KnownSenderLine({required this.fingerprint, this.name});

  final String fingerprint;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = name ?? 'Known sender';

    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(name == null ? 'Sender identity' : 'From $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                fingerprint,
                style: technicalTextStyle(ref, relativeTo: 1.4,
                    letterSpacing: 2),
              ),
              const SizedBox(height: 12),
              Text(
                'This device has received files from this identity before. '
                'The name is a label you gave it on this device — it is not '
                'proof of who they are.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            const Icon(Icons.verified_user,
                color: DeadDropColors.success, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'From $label',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: DeadDropColors.success,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.info_outline,
                size: 16, color: Theme.of(context).hintColor),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Vault unlock prompt (shown from the receive result when saving to a
// locked vault)
// ---------------------------------------------------------------------------

/// A small modal passphrase prompt, used only to unlock the vault from the
/// receive flow's "Save to vault" button when no environment is currently
/// open.
///
/// Deliberately a thin reuse of [VaultController.unlock] rather than a
/// separate unlock code path — attempt-guard penalties and self-destruct
/// must apply identically here and on the main Vault screen (vault_page.dart
/// `_LockedView`), since a passphrase typed here is indistinguishable from
/// one typed there as far as a coercion scenario is concerned. Reads
/// [VaultState.error] via `ref.watch` (the same public surface the Vault
/// screen itself uses) rather than touching [VaultController.state]
/// directly, which is `@visibleForTesting`/protected outside this library.
class _VaultUnlockDialog extends ConsumerStatefulWidget {
  const _VaultUnlockDialog();

  @override
  ConsumerState<_VaultUnlockDialog> createState() => _VaultUnlockDialogState();
}

class _VaultUnlockDialogState extends ConsumerState<_VaultUnlockDialog> {
  final _passphraseController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final ok = await ref
        .read(vaultControllerProvider.notifier)
        .unlock(_passphraseController.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _error = ref.read(vaultControllerProvider).error ?? 'Could not unlock';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unlock vault'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PassphraseField(
            controller: _passphraseController,
            autofocus: true,
            onSubmitted: () => _submitting ? null : _unlock(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: DeadDropColors.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _unlock,
          child: _submitting
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Unlock'),
        ),
      ],
    );
  }
}
