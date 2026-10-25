/// vault_store.dart — the vault's on-disk shape: sealed file contents,
/// sealed metadata, and the environment key slots.
///
/// This is where the key hierarchy (vault_keys.dart) and the constant-cost
/// unlock (vault_session.dart) meet actual bytes on disk, and therefore
/// where the coercion-resistance property either holds or quietly breaks.
/// Encryption alone is not enough: if the filesystem shape reveals that a
/// second environment exists, or that one slot is empty and the other is
/// not, a coerced user handing over the decoy passphrase gains nothing —
/// the attacker already knows to keep asking. So this file is built around
/// one rule: nothing observable on disk — file names, directory structure,
/// file count, or file sizes — may depend on whether a decoy has ever been
/// created, or on which slot a given stored file belongs to.
///
/// Content and metadata (including the original filename) are both sealed
/// under the per-environment data key with `crypto_secretbox`, the same
/// primitive vault_keys.dart uses to wrap that data key. Entry ids are
/// random, not derived from the filename or slot, so two files named
/// identically can coexist and the id itself leaks nothing. Writes go to a
/// temp file and are renamed into place, so a crash mid-write can never
/// leave a half-written entry live in the index.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'pwhash.dart' show kVaultSaltBytes;
import 'vault_keys.dart';

/// One stored file's metadata, as returned by [VaultStore.list] and
/// [VaultStore.put].
///
/// Deliberately excludes the slot: callers already know which slot they
/// asked about, and a [VaultEntry] should not be a vehicle for carrying
/// that information anywhere it doesn't already need to be.
class VaultEntry {
  VaultEntry({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.addedAt,
  });

  /// Random identifier for this entry. Not derived from [name] or content:
  /// two entries with the same [name] get different, unrelated ids, and the
  /// id itself carries no information about what it names.
  final String id;

  /// The original filename, as sealed in the entry's metadata.
  final String name;

  /// Size of the plaintext content, in bytes.
  final int sizeBytes;

  /// When this entry was added to the vault.
  final DateTime addedAt;
}

/// Thrown when sealed bytes read from disk fail to authenticate.
///
/// Covers both a wrong data key (asking for a slot's content with another
/// slot's key, or a key derived from the wrong passphrase further up the
/// stack) and genuine corruption of the sealed bytes. Those two cases are
/// deliberately not distinguished here, mirroring [unwrapDataKey]'s refusal
/// to distinguish "wrong passphrase" from "no such environment": telling
/// them apart would let an attacker use decryption failures to probe
/// whether a given id belongs to a different, perhaps-nonexistent,
/// environment.
class VaultStoreException implements Exception {
  VaultStoreException(this.message);

  final String message;

  @override
  String toString() => 'VaultStoreException: $message';
}

/// Thrown when an entry id is not found in the store at all (no file on
/// disk for it), as opposed to [VaultStoreException] (a file exists but did
/// not decrypt). Kept separate because "no such entry" is routine —
/// deleting twice, or listing after a concurrent delete — while a
/// decryption failure is either a bug or an attack and deserves a type
/// callers can tell apart deliberately.
class VaultEntryNotFoundException implements Exception {
  VaultEntryNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'VaultEntryNotFoundException: no entry $id';
}

/// Number of random bytes in an entry id, hex-encoded for the filename.
///
/// 16 bytes (128 bits) is comfortably collision-free for a personal vault's
/// file count and matches the id's only job: being an unguessable,
/// content-free handle. It is not derived from the filename, slot, or
/// content hash — any of those would leak information through the id
/// itself (e.g. two files with identical bytes producing the same id).
const int _kEntryIdBytes = 16;

/// Size, in bytes, of the data key a [WrappedKey] wraps.
///
/// Matches `_kDataKeyBytes` in vault_keys.dart; duplicated here (rather than
/// imported) because that constant is private to that library. Used only to
/// size the padding for an empty slot file — see [VaultStore._slotFileBytes].
const int _kWrappedDataKeyBytes = 32;

/// A sealed on-disk store for a vault's environment slots and the files
/// held in each environment.
///
/// All paths under [root] are fixed by [init] regardless of how many
/// environments are ever provisioned: `slots/slot0.bin` and
/// `slots/slot1.bin` always exist, always at [_slotFileBytes], and entries
/// for every slot share one `entries/` directory with randomly-named
/// files. Nothing in the directory listing distinguishes a one-environment
/// vault from a two-environment one, or reveals which slot an entry
/// belongs to — that's only recoverable by successfully decrypting it with
/// a given slot's data key.
class VaultStore {
  VaultStore(this.root, this.sodium);

  /// Root directory for this vault's on-disk store.
  final Directory root;

  /// Sodium instance used for all sealing/unsealing and randomness.
  final SodiumSumo sodium;

  Directory get _slotsDir => Directory('${root.path}/slots');
  Directory get _entriesDir => Directory('${root.path}/entries');

  File _slotFile(int slot) => File('${_slotsDir.path}/slot$slot.bin');
  File _entryFile(String id) => File('${_entriesDir.path}/$id.bin');

  /// Fixed size, in bytes, every slot file is written at — whether it holds
  /// a real [WrappedKey] or random filler for an empty slot.
  ///
  /// Derived from `sodium`'s actual secretbox sizes rather than hardcoded,
  /// so it can never silently drift out of sync with the primitive in use:
  /// 1-byte salt-length prefix + salt + 1-byte nonce-length prefix + nonce +
  /// (wrapped data key + secretbox MAC) — exactly the shape
  /// [WrappedKey.pack] produces.
  int get _slotFileBytes =>
      1 +
      kVaultSaltBytes +
      1 +
      sodium.crypto.secretBox.nonceBytes +
      _kWrappedDataKeyBytes +
      sodium.crypto.secretBox.macBytes;

  /// Creates the on-disk layout if it does not already exist.
  ///
  /// Both slot files are created here, at [_slotFileBytes] each, filled
  /// with structurally-valid-but-meaningless filler — the same shape
  /// [writeSlots] would leave an empty slot in. This is what makes "a vault
  /// that has never had a decoy" indistinguishable from "a vault whose
  /// decoy hasn't been unlocked yet": the two slot files exist with the
  /// same size from the moment the vault is created, before any
  /// environment is provisioned.
  ///
  /// Safe to call on an existing store: does not touch files that already
  /// exist.
  ///
  /// Also sweeps any orphaned `.tmp-*` files left behind by a write that
  /// crashed between [_writeAtomic]'s temp-file write and its rename. Those
  /// orphans are harmless to confidentiality on their own — a stray temp
  /// file carries no plaintext and (being slot-agnostic, see
  /// [_writeAtomic]) says nothing about which environment was mid-write —
  /// but the vault's guarantee is about what the filesystem *shows*, not
  /// only about what decrypts: a `.tmp-` file sitting in `entries/` is a
  /// permanent, visible mark that some write was once interrupted, making a
  /// vault that has crashed mid-write distinguishable from one that never
  /// has. Swept here rather than in [list] or [get] — on every read would
  /// be wasted work for a condition [init] already clears once per process
  /// lifetime (or app launch), and widens the surface for no benefit.
  Future<void> init() async {
    await _slotsDir.create(recursive: true);
    await _entriesDir.create(recursive: true);

    for (var i = 0; i < 2; i++) {
      final file = _slotFile(i);
      if (!await file.exists()) {
        await _writeAtomic(file, _emptySlotFiller());
      }
    }

    await _sweepOrphanedTempFiles();
  }

  /// Deletes any leftover `.tmp-*` files under [_slotsDir] and
  /// [_entriesDir] — see [init]'s doc comment for why this matters beyond
  /// tidiness.
  Future<void> _sweepOrphanedTempFiles() async {
    for (final dir in [_slotsDir, _entriesDir]) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        if (!entity.uri.pathSegments.last.contains('.tmp-')) continue;
        try {
          await entity.delete();
        } on FileSystemException {
          // Already gone (e.g. a concurrent init()) — fine, the end state
          // ("no orphaned temp file") is what we wanted.
        }
      }
    }
  }

  /// Reads both slot files, returning the [WrappedKey] for each, or `null`
  /// for a slot that is empty.
  ///
  /// There is no on-disk marker for "empty" — every slot file is
  /// [_slotFileBytes] of what is either a real wrapped key or random
  /// filler (see [init], [writeSlots]). A slot's emptiness is therefore not
  /// observable from its file alone; a caller only learns a slot was empty
  /// indirectly, by [tryUnlock]-style logic failing to authenticate against
  /// it for every passphrase it tries. This method always returns a
  /// [WrappedKey] for a well-formed slot file — distinguishing real from
  /// filler is the unlock path's job, not this store's.
  Future<List<WrappedKey?>> readSlots() async {
    final result = <WrappedKey?>[];
    for (var i = 0; i < 2; i++) {
      final bytes = await _slotFile(i).readAsBytes();
      try {
        result.add(WrappedKey.unpack(bytes));
      } on MalformedWrappedKeyException {
        // A slot file that isn't even a well-formed WrappedKey (nor
        // plausible random filler, since unpack tolerates arbitrary bytes
        // as long as the length prefixes fit) is corrupt. Surface that
        // distinctly from "wrong passphrase" so a caller doesn't mistake
        // disk damage for there being no environment there — see
        // MalformedWrappedKeyException's doc comment.
        rethrow;
      }
    }
    return result;
  }

  /// Overwrites both slot files.
  ///
  /// [slots] must have exactly two entries; `null` means that slot should
  /// become (or remain) empty. An empty slot is written as a well-formed,
  /// unparseable-as-real dummy [WrappedKey] (see [_emptySlotFiller]) at
  /// [_slotFileBytes] — never as a shorter file, an all-zero file, a
  /// deleted one, or raw unstructured random bytes — so the file is the
  /// same size and shape whether or not an environment is actually there.
  /// Each slot is written independently via a temp-file-then-rename so a
  /// crash mid-write cannot corrupt the other slot or leave a half-written
  /// file in place of either.
  Future<void> writeSlots(List<WrappedKey?> slots) async {
    if (slots.length != 2) {
      throw ArgumentError.value(slots, 'slots', 'must have exactly 2 entries');
    }

    for (var i = 0; i < 2; i++) {
      final slot = slots[i];
      final bytes =
          slot != null ? _padToSlotSize(slot.pack()) : _emptySlotFiller();
      await _writeAtomic(_slotFile(i), bytes);
    }
  }

  /// Generates filler for an empty slot: a packed [WrappedKey] built from
  /// fresh random salt, nonce and ciphertext, at exactly the sizes a real
  /// one would have.
  ///
  /// Raw random bytes will not do here: [WrappedKey.unpack]'s first byte is
  /// a salt-length prefix, so an arbitrary random byte there (0-255) would
  /// usually demand a salt longer than the buffer actually has room for,
  /// making an "empty" slot fail to parse at all — a crash-shaped tell that
  /// doesn't even require knowing a passphrase to notice. Building a
  /// well-formed dummy (mirroring vault_session.dart's `_dummySlotFor`)
  /// keeps the file both the right size *and* parseable, so an empty slot
  /// and a real one are indistinguishable by [readSlots] — only attempting
  /// to unwrap it with a passphrase (and failing to authenticate) tells
  /// them apart, exactly like a wrong passphrase on a real slot.
  Uint8List _emptySlotFiller() {
    final nonceBytes = sodium.crypto.secretBox.nonceBytes;
    final ciphertextBytes =
        _kWrappedDataKeyBytes + sodium.crypto.secretBox.macBytes;
    final dummy = WrappedKey(
      salt: sodium.randombytes.buf(kVaultSaltBytes),
      nonce: sodium.randombytes.buf(nonceBytes),
      ciphertext: sodium.randombytes.buf(ciphertextBytes),
    );
    return _padToSlotSize(dummy.pack());
  }

  /// Pads a packed [WrappedKey] to exactly [_slotFileBytes] with trailing
  /// random bytes, so that the file written is always exactly that size
  /// even if a future change alters the packed length slightly.
  ///
  /// Throws if the packed key is already too large: that would mean
  /// [_slotFileBytes] no longer matches reality and needs updating
  /// deliberately, not silently truncating a real key.
  Uint8List _padToSlotSize(Uint8List packed) {
    if (packed.length > _slotFileBytes) {
      throw StateError(
        'packed WrappedKey (${packed.length} bytes) exceeds '
        '_slotFileBytes ($_slotFileBytes) — update _slotFileBytes',
      );
    }
    if (packed.length == _slotFileBytes) return packed;

    final padding = sodium.randombytes.buf(_slotFileBytes - packed.length);
    final out = BytesBuilder();
    out.add(packed);
    out.add(padding);
    return out.toBytes();
  }

  /// Seals [bytes] under [dataKey] and stores them as a new entry, returning
  /// the [VaultEntry] metadata (including the freshly-generated id).
  ///
  /// [slot] identifies which environment this belongs to only for the
  /// caller's bookkeeping — it is never written to disk. The entry file's
  /// name is a random id, unrelated to [slot], [name], or [bytes], and its
  /// content is two independently-sealed regions (metadata, then data) so
  /// that reading the metadata never requires touching the (potentially
  /// large) sealed content.
  ///
  /// Written via a temp file in `entries/`, then renamed into place — the
  /// id is only visible under its real name once the full, sealed entry
  /// exists on disk. A failure at any point before the rename leaves only
  /// an orphaned temp file containing ciphertext, never plaintext, and
  /// never an entry that [list] or [get] can see.
  Future<VaultEntry> put(
    Uint8List dataKey,
    int slot,
    String name,
    Uint8List bytes,
  ) async {
    final id = _newEntryId();
    final addedAt = DateTime.now().toUtc();

    // secretBox requires a SecureKey, not a raw Uint8List — see
    // vault_keys.dart's `kek`. [dataKey] arrives as a Uint8List per this
    // class's public interface, so it's copied into a SecureKey here and
    // disposed (zeroed) as soon as sealing is done.
    final key = SecureKey.fromList(sodium, dataKey);
    try {
      final metaNonce =
          sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
      final metaPlaintext = _packMeta(name, bytes.length, addedAt);
      final metaCiphertext = sodium.crypto.secretBox.easy(
        message: metaPlaintext,
        nonce: metaNonce,
        key: key,
      );

      final dataNonce =
          sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
      final dataCiphertext = sodium.crypto.secretBox.easy(
        message: bytes,
        nonce: dataNonce,
        key: key,
      );

      final out = BytesBuilder();
      _writeLengthPrefixed(out, metaNonce);
      _writeLengthPrefixed(out, metaCiphertext);
      _writeLengthPrefixed(out, dataNonce);
      out.add(dataCiphertext); // runs to end; length implied

      await _writeAtomic(_entryFile(id), out.toBytes());

      return VaultEntry(
        id: id,
        name: name,
        sizeBytes: bytes.length,
        addedAt: addedAt,
      );
    } finally {
      key.dispose();
    }
  }

  /// Recovers the plaintext content of entry [id] in [slot], sealed under
  /// [dataKey].
  ///
  /// Throws [VaultEntryNotFoundException] if no entry file exists for [id].
  /// Throws [VaultStoreException] if [dataKey] cannot open it — wrong key
  /// (wrong slot, wrong environment) or corruption; see
  /// [VaultStoreException]'s doc comment for why those are not
  /// distinguished.
  Future<Uint8List> get(Uint8List dataKey, int slot, String id) async {
    final file = _entryFile(id);
    if (!await file.exists()) {
      throw VaultEntryNotFoundException(id);
    }

    final bytes = await file.readAsBytes();
    final sections = _unpackEntrySections(bytes);

    final key = SecureKey.fromList(sodium, dataKey);
    try {
      sodium.crypto.secretBox.openEasy(
        cipherText: sections.metaCiphertext,
        nonce: sections.metaNonce,
        key: key,
      );
      return sodium.crypto.secretBox.openEasy(
        cipherText: sections.dataCiphertext,
        nonce: sections.dataNonce,
        key: key,
      );
    } on SodiumException {
      throw VaultStoreException('failed to open entry $id');
    } finally {
      key.dispose();
    }
  }

  /// Lists every entry in [slot] that [dataKey] can open.
  ///
  /// Scans every file under `entries/` — there is no slot-indexed
  /// directory or index to scan instead, because an index naming which
  /// entries belong to a slot would itself be the kind of artefact this
  /// store is designed not to produce (its size would reveal how many
  /// entries exist per slot). Entries belonging to other slots simply fail
  /// to authenticate under [dataKey] and are skipped silently, the same way
  /// a wrong passphrase fails silently in [unwrapDataKey].
  Future<List<VaultEntry>> list(Uint8List dataKey, int slot) async {
    final out = <VaultEntry>[];
    if (!await _entriesDir.exists()) return out;

    final key = SecureKey.fromList(sodium, dataKey);
    try {
      await for (final entity in _entriesDir.list()) {
        if (entity is! File) continue;
        // Ignore stray temp files from an interrupted write — they never
        // reached a valid id-named path, so they are not entries.
        final base = entity.uri.pathSegments.last;
        if (!base.endsWith('.bin')) continue;
        final id = base.substring(0, base.length - '.bin'.length);
        if (!_looksLikeEntryId(id)) continue;

        Uint8List bytes;
        try {
          bytes = await entity.readAsBytes();
        } on FileSystemException {
          // Entry vanished (concurrent delete) between the listing and the
          // read — not this slot's business, just skip it.
          continue;
        }

        _EntrySections sections;
        try {
          sections = _unpackEntrySections(bytes);
        } on VaultStoreException {
          // Not a well-formed entry file at all; skip rather than throw, so
          // one corrupt file doesn't take down listing for every other
          // environment sharing this directory.
          continue;
        }

        Uint8List metaPlaintext;
        try {
          metaPlaintext = sodium.crypto.secretBox.openEasy(
            cipherText: sections.metaCiphertext,
            nonce: sections.metaNonce,
            key: key,
          );
        } on SodiumException {
          // Belongs to a different slot/environment, or wrong key — not an
          // error, just not ours.
          continue;
        }

        final meta = _unpackMeta(metaPlaintext);
        out.add(VaultEntry(
          id: id,
          name: meta.name,
          sizeBytes: meta.sizeBytes,
          addedAt: meta.addedAt,
        ));
      }
      return out;
    } finally {
      key.dispose();
    }
  }

  /// Deletes entry [id] from [slot].
  ///
  /// [slot] is accepted for API symmetry with the rest of this class but is
  /// not otherwise used: the entry file itself does not record which slot
  /// it belongs to (see [list]), and deleting by id alone is safe because
  /// ids are random and never reused. Deleting an id that does not exist is
  /// a no-op, not an error — the end state ("no entry with this id") is the
  /// same either way.
  Future<void> delete(int slot, String id) async {
    final file = _entryFile(id);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Destroys [slot] by overwriting its key file with fresh dummy filler
  /// (see [_emptySlotFiller]), discarding the only copy of the wrapped data
  /// key.
  ///
  /// This does not touch `entries/` at all. The sealed file contents for
  /// that environment remain exactly where they were, indistinguishable
  /// from any other entry — they are simply unrecoverable now that the
  /// wrapped key protecting them is gone, which is the entire point: wiping
  /// a KB-sized key file is something flash storage can do in a single
  /// write, while the on-disk guarantee people reach for instinctively
  /// ("overwrite the file contents") cannot be honoured on flash with
  /// wear-levelling, so this does not pretend to offer it. The other slot's
  /// file is untouched.
  Future<void> destroySlot(int slot) async {
    await _writeAtomic(_slotFile(slot), _emptySlotFiller());
  }

  /// Generates a random, unguessable entry id — hex-encoded so it is a
  /// filesystem-safe string on every supported platform.
  String _newEntryId() {
    final bytes = sodium.randombytes.buf(_kEntryIdBytes);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  bool _looksLikeEntryId(String s) =>
      s.length == _kEntryIdBytes * 2 && RegExp(r'^[0-9a-f]+$').hasMatch(s);

  /// Writes [bytes] to [file] by first writing to a sibling temp file and
  /// then renaming it into place.
  ///
  /// Rename is atomic on POSIX filesystems (and NTFS, within the same
  /// volume): the target either has its old content or its new content,
  /// never a partial write. A crash or power loss between the temp write
  /// and the rename leaves only an orphaned temp file — never a truncated
  /// or half-written file at the real path — so a reader never observes an
  /// in-progress write.
  Future<void> _writeAtomic(File file, Uint8List bytes) async {
    final tmp = File('${file.path}.tmp-${_newEntryId()}');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  Uint8List _packMeta(String name, int sizeBytes, DateTime addedAt) {
    final nameBytes = utf8.encode(name);
    final out = BytesBuilder();
    _writeLengthPrefixed(out, Uint8List.fromList(nameBytes));
    _writeUint64(out, sizeBytes);
    _writeUint64(out, addedAt.millisecondsSinceEpoch);
    return out.toBytes();
  }

  _Meta _unpackMeta(Uint8List bytes) {
    var offset = 0;
    final nameLen = _readUint32(bytes, offset);
    offset += 4;
    if (offset + nameLen > bytes.length) {
      throw VaultStoreException('malformed entry metadata: truncated name');
    }
    final name = utf8.decode(bytes.sublist(offset, offset + nameLen));
    offset += nameLen;

    final sizeBytes = _readUint64(bytes, offset);
    offset += 8;
    final addedAtMillis = _readUint64(bytes, offset);
    offset += 8;

    return _Meta(
      name: name,
      sizeBytes: sizeBytes,
      addedAt: DateTime.fromMillisecondsSinceEpoch(addedAtMillis, isUtc: true),
    );
  }

  _EntrySections _unpackEntrySections(Uint8List bytes) {
    var offset = 0;

    final metaNonceLen = _readUint32(bytes, offset);
    offset += 4;
    final metaNonce = _readSlice(bytes, offset, metaNonceLen);
    offset += metaNonceLen;

    final metaCiphertextLen = _readUint32(bytes, offset);
    offset += 4;
    final metaCiphertext = _readSlice(bytes, offset, metaCiphertextLen);
    offset += metaCiphertextLen;

    final dataNonceLen = _readUint32(bytes, offset);
    offset += 4;
    final dataNonce = _readSlice(bytes, offset, dataNonceLen);
    offset += dataNonceLen;

    // dataCiphertext runs to the end of the buffer.
    if (offset > bytes.length) {
      throw VaultStoreException('malformed entry: truncated');
    }
    final dataCiphertext = bytes.sublist(offset);

    return _EntrySections(
      metaNonce: metaNonce,
      metaCiphertext: metaCiphertext,
      dataNonce: dataNonce,
      dataCiphertext: dataCiphertext,
    );
  }

  void _writeLengthPrefixed(BytesBuilder out, Uint8List bytes) {
    _writeUint32(out, bytes.length);
    out.add(bytes);
  }

  void _writeUint32(BytesBuilder out, int value) {
    final b = ByteData(4)..setUint32(0, value, Endian.big);
    out.add(b.buffer.asUint8List());
  }

  void _writeUint64(BytesBuilder out, int value) {
    final b = ByteData(8)..setUint64(0, value, Endian.big);
    out.add(b.buffer.asUint8List());
  }

  int _readUint32(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) {
      throw VaultStoreException('malformed entry: truncated length prefix');
    }
    return ByteData.sublistView(bytes, offset, offset + 4)
        .getUint32(0, Endian.big);
  }

  int _readUint64(Uint8List bytes, int offset) {
    if (offset + 8 > bytes.length) {
      throw VaultStoreException('malformed entry: truncated field');
    }
    return ByteData.sublistView(bytes, offset, offset + 8)
        .getUint64(0, Endian.big);
  }

  Uint8List _readSlice(Uint8List bytes, int offset, int length) {
    if (offset + length > bytes.length) {
      throw VaultStoreException('malformed entry: truncated section');
    }
    return bytes.sublist(offset, offset + length);
  }
}

class _Meta {
  _Meta({required this.name, required this.sizeBytes, required this.addedAt});

  final String name;
  final int sizeBytes;
  final DateTime addedAt;
}

class _EntrySections {
  _EntrySections({
    required this.metaNonce,
    required this.metaCiphertext,
    required this.dataNonce,
    required this.dataCiphertext,
  });

  final Uint8List metaNonce;
  final Uint8List metaCiphertext;
  final Uint8List dataNonce;
  final Uint8List dataCiphertext;
}
