# DeadDrop Vault Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in encrypted vault inside DeadDrop that stores received files at rest, with a second passphrase that opens a decoy environment indistinguishable from the real one.

**Architecture:** A passphrase runs through Argon2id to a key-encryption key, which unwraps a per-environment data key; file contents and metadata are sealed with that data key using the XSalsa20-Poly1305 construction already in `crypto.dart`. Unlock always performs a fixed number of derivations so a wrong passphrase costs the same as a right one. The vault is a section reached from the home screen, never a launch gate.

**Tech Stack:** Flutter 3.24.5, Riverpod, `sodium_libs_sumo` (Argon2id), `flutter_secure_storage`, `path_provider`.

**Spec:** `docs/superpowers/specs/2026-10-24-vault-coercion-resistance-design.md`

## Global Constraints

- **Zero home-grown cryptography.** libsodium only, via `sodium_libs`. Argon2id through `crypto_pwhash`; content sealing reuses the existing `PrecalculatedBox`/`secretbox` construction.
- **Zero network.** No feature may require connectivity.
- **Argon2id parameters:** `opsLimit = 3`, `memLimit = 64 MB`, `outLen = 32`, `alg = CryptoPwhashAlgorithm.argon2id13`. Re-tuning is allowed only with the justification recorded in the plan and the spec updated.
- **Identical timing.** Both environments use the same parameters. A wrong passphrase must cost the same as a correct one, measured to first paint. No artificial delay after failure.
- **Flutter 3.24.5**, pinned in `.fvmrc`. `sodium_libs` stays at `2.2.1+6`; do not bump it.
- **No new runtime dependency** without recording why in the task that adds it.
- `flutter analyze` clean, `dart format`, single quotes, no `print`. Commits as `type: description`.
- Docs continue to mark these features **not implemented** until Task 10.

## Review Focus

Inputs the spec implies but no feature test naturally exercises. Each has a test pinned to the task that owns the code.

1. **Wrong passphrase must cost the same as a correct one** — the headline property; a sequential unlock leaks which environment matched. *(Task 3)*
2. **Vault opened, app backgrounded, reopened** — an unlocked vault that survives backgrounding leaves the real environment exposed to whoever picks up the phone. *(Task 7)*
3. **Storage full or write fails mid-save** — a half-written encrypted file must not corrupt the environment index or leave plaintext behind. *(Task 5)*
4. **Zero-byte and very large files** — chunk and seal boundaries, and the existing 32 MB transfer ceiling does not apply to vault storage. *(Task 5)*
5. **Same filename stored twice** — must not collide, overwrite, or reveal the collision through an error the decoy would not produce. *(Task 5)*

---

## File Structure

| File | Responsibility |
|---|---|
| `app/lib/src/vault/pwhash.dart` | Argon2id wrapper; the only place `crypto_pwhash` is called |
| `app/lib/src/vault/vault_keys.dart` | Key hierarchy: derive KEK, wrap/unwrap data keys |
| `app/lib/src/vault/vault_store.dart` | On-disk layout, sealed file read/write, environment index |
| `app/lib/src/vault/vault_session.dart` | Unlock/lock lifecycle, holds the open environment |
| `app/lib/src/vault/passphrase_strength.dart` | Entropy estimation and the minimum threshold |
| `app/lib/ui/vault/vault_page.dart` | Vault section: unlock screen, file list |
| `app/lib/ui/vault/vault_setup_page.dart` | Create vault, add decoy, strength meter |
| `app/lib/ui/settings/settings_page.dart` | Settings shell; Security section (real environment only) |
| `app/test/vault/*_test.dart` | One test file per src unit above |

Existing files modified: `main.dart` (sumo init + providers), `home_page.dart` (Settings and Vault entries), `receive_page.dart` (save destination), `identity_store.dart` / `tofu_store.dart` (environment scoping).

---

### Task 0: Spike — confirm Argon2id is usable on the pinned stack

Throwaway. Nothing here is kept; it answers whether the rest of the plan is buildable as written.

`pwhash` lives under `sodium_libs_sumo`, a different import and a different initialiser (`SodiumSumoInit`) from the plain `SodiumInit.init()` the app calls today, and the package ships a `SodiumSumoUnavailable` exception, so it is not guaranteed present.

**Files:**
- Create: `app/test/vault/spike_pwhash_test.dart` (deleted at the end of the task)

- [ ] **Step 1: Add `sodium_libs_sumo` usage to a scratch test**

Derive a key with `opsLimit: 3`, `memLimit: 64 * 1024 * 1024`, `outLen: 32`, `alg: CryptoPwhashAlgorithm.argon2id13`. Assert the same password and salt produce identical bytes, and a different salt produces different bytes.

- [ ] **Step 2: Measure and record**

Print wall-clock time for one derivation and for four sequential derivations. Record peak memory if obtainable.

Run: `make test 2>&1 | grep -i pwhash`

- [ ] **Step 3: Decide and record**

Write findings into the plan under this task: whether sumo init works in `flutter_tester`, the timing, and whether 4 × 64 MB is survivable. **If a fixed count of 4 derivations exceeds ~2s or risks OOM on a 2 GB device, stop and report** — Task 3's design depends on it and the parameters may need re-tuning with the spec updated.

- [ ] **Step 4: Delete the spike file and commit the findings only**

```bash
rm app/test/vault/spike_pwhash_test.dart
git add docs/superpowers/plans/2026-10-24-vault-coercion.md
git commit -m "docs: record Argon2id spike findings"
```

#### Findings (run 2026-10-24, `flutter_tester` in the dev container, x86_64 under Docker on Apple Silicon)

**The plan is buildable as written. Proceed.**

| Measurement | Result |
|---|---|
| Argon2id available on the pinned stack | Yes |
| One derivation (ops=3, mem=64 MB) | 243–343 ms |
| **Four sequential derivations** | **612 ms** (~153 ms each) |
| Deterministic for the same password + salt | Yes |
| Different salt → different key | Yes |

Against the stop condition — *"if 4 derivations exceed ~2s or risk OOM, stop
and report"* — 612 ms clears it comfortably. The parameters in Global
Constraints stand unchanged.

**Import and init differ from the rest of the app.** `pwhash` is sumo-only:

```dart
import 'package:sodium/sodium_sumo.dart';          // not sodium_libs.dart
final sodium = await SodiumSumoInit.init2(loader); // not SodiumInit.init()
```

Task 7 must migrate `main()` to `SodiumSumoInit`. `sodium_libs` ships a
`SodiumSumoUnavailable` exception, so the vault must degrade gracefully if
sumo is missing at runtime — Send and Receive do not depend on it.

**Per-derivation cost drops under repetition** (343 ms alone, 153 ms in a loop
of four), presumably allocator warmth. Task 10's timing bound should be derived
from steady-state measurements, not a single cold run.

**Caveat:** measured on x86_64 emulation under Docker on Apple Silicon, which
is not the target. A low-end Android device will be slower and has far less
memory headroom. Re-measure on real hardware before Task 10 fixes its bound;
4 × 64 MB concurrent allocation is still the risk worth watching.

---

### Task 1: Argon2id wrapper

**Files:**
- Create: `app/lib/src/vault/pwhash.dart`
- Test: `app/test/vault/pwhash_test.dart`

**Interfaces:**
- Consumes: `SodiumSumo` from `sodium_libs_sumo`
- Produces: `const int kVaultSaltBytes = 16;`
  `Uint8List deriveKek(SodiumSumo sodium, String passphrase, Uint8List salt)` → 32 bytes
  `Uint8List newSalt(SodiumSumo sodium)` → `kVaultSaltBytes` random bytes

- [ ] **Step 1: Write the failing tests**

```dart
test('deriveKek is deterministic for the same passphrase and salt', () { ... });
test('deriveKek differs when the salt differs', () { ... });
test('deriveKek differs when the passphrase differs', () { ... });
test('deriveKek returns 32 bytes', () { ... });
test('newSalt returns kVaultSaltBytes of non-constant output', () { ... });
```

- [ ] **Step 2: Run to verify they fail**

Run: `make test 2>&1 | grep -A2 pwhash_test`
Expected: FAIL, `deriveKek` undefined

- [ ] **Step 3: Implement `deriveKek` and `newSalt` in `app/lib/src/vault/pwhash.dart`**

UTF-8 encode the passphrase to `Int8List` for the `password` parameter. Use the parameters from Global Constraints. This file is the only place `crypto_pwhash` is called.

- [ ] **Step 4: Run to verify they pass**

- [ ] **Step 5: Commit** — `feat(vault): Argon2id key derivation`

---

### Task 2: Key hierarchy — wrap and unwrap data keys

Self-destruct destroys the wrapped key rather than the files, so the data key must be independently wrappable.

**Files:**
- Create: `app/lib/src/vault/vault_keys.dart`
- Test: `app/test/vault/vault_keys_test.dart`

**Interfaces:**
- Consumes: `deriveKek`, `newSalt` (Task 1)
- Produces: `class WrappedKey { Uint8List salt, nonce, ciphertext; Uint8List pack(); static WrappedKey unpack(Uint8List); }`
  `WrappedKey wrapDataKey(SodiumSumo, String passphrase, Uint8List dataKey)`
  `Uint8List? unwrapDataKey(SodiumSumo, String passphrase, WrappedKey)` — null when the passphrase does not match
  `Uint8List newDataKey(SodiumSumo)` → 32 bytes

- [ ] **Step 1: Write the failing tests**

```dart
test('wrap then unwrap with the same passphrase returns the data key', () { ... });
test('unwrap with a wrong passphrase returns null, does not throw', () { ... });
test('pack/unpack round-trips a WrappedKey', () { ... });
test('two wraps of the same key differ (fresh salt and nonce)', () { ... });
```

Returning `null` rather than throwing matters: a thrown exception is easy to turn into a distinguishable error path.

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement in `app/lib/src/vault/vault_keys.dart`**

Seal the data key with `secretBox` under the KEK. Authentication failure is the "wrong passphrase" signal; catch it and return null.

- [ ] **Step 4: Run to verify they pass**

- [ ] **Step 5: Commit** — `feat(vault): wrap and unwrap environment data keys`

---

### Task 3: Unlock with constant derivation count

Owns Review Focus #1.

**Files:**
- Create: `app/lib/src/vault/vault_session.dart`
- Test: `app/test/vault/vault_session_test.dart`

**Interfaces:**
- Consumes: `wrapDataKey`, `unwrapDataKey`, `WrappedKey` (Task 2)
- Produces: `const int kVaultEnvironmentSlots = 2;`
  `class UnlockResult { int? slotIndex; Uint8List? dataKey; bool get ok; }`
  `UnlockResult tryUnlock(SodiumSumo, String passphrase, List<WrappedKey?> slots)`

- [ ] **Step 1: Write the failing tests**

```dart
test('unlocks slot 0 with the real passphrase', () { ... });
test('unlocks slot 1 with the decoy passphrase', () { ... });
test('returns not-ok for an unknown passphrase', () { ... });
test('attempts exactly kVaultEnvironmentSlots derivations regardless of outcome', () {
  // inject a counting wrapper; assert the count is equal for
  // real, decoy and wrong passphrases
});
test('an empty slot costs the same as a filled one', () {
  // a vault with no decoy must not be distinguishable from one with a decoy
});
```

The last two are the headline property. A real vault with no decoy must spend the same work as one with a decoy, or the absence of a decoy is detectable.

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement `tryUnlock` in `app/lib/src/vault/vault_session.dart`**

Always iterate all `kVaultEnvironmentSlots`, never short-circuit on a match, and derive against a dummy `WrappedKey` for empty slots so the work is identical. Return the first match after the loop completes.

- [ ] **Step 4: Run to verify they pass**

- [ ] **Step 5: Commit** — `feat(vault): constant-cost unlock across environment slots`

---

### Task 4: Passphrase strength

**Files:**
- Create: `app/lib/src/vault/passphrase_strength.dart`
- Test: `app/test/vault/passphrase_strength_test.dart`

**Interfaces:**
- Produces: `class StrengthResult { double entropyBits; bool meetsMinimum; String advice; }`
  `StrengthResult estimateStrength(String passphrase)`
  `const double kMinimumEntropyBits = 60;`
  `List<String> generatePassphrase(SodiumSumo sodium, {int words = 5})`

- [ ] **Step 1: Write the failing tests**

```dart
test('rejects known-weak passphrases', () {
  for (final weak in ['Password1!', 'MiCasa2024', '123456', 'deaddrop']) {
    expect(estimateStrength(weak).meetsMinimum, isFalse, reason: weak);
  }
});
test('accepts a generated five-word passphrase', () { ... });
test('a six-digit PIN does not meet the minimum', () { ... });
test('generatePassphrase returns distinct words from the wordlist', () { ... });
test('generatePassphrase uses libsodium randomness, not dart:math', () { ... });
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement in `app/lib/src/vault/passphrase_strength.dart`**

Estimate entropy, do not score composition: `Password1!` satisfies every composition rule and is weak. A compact approach that passes the tests above: detect dictionary words, keyboard runs, repeats and digit-suffix patterns, and charge reduced entropy for them. Bundle a short EFF-style wordlist as a Dart constant — no new dependency.

`kMinimumEntropyBits = 60` is this plan's call: it rejects every example above and accepts a four-word generated passphrase. Record it in the spec if changed.

- [ ] **Step 4: Run to verify they pass**

- [ ] **Step 5: Commit** — `feat(vault): passphrase strength estimation and generation`

---

### Task 5: Encrypted store on disk

Owns Review Focus #3, #4, #5.

**Files:**
- Create: `app/lib/src/vault/vault_store.dart`
- Test: `app/test/vault/vault_store_test.dart`

**Interfaces:**
- Consumes: `WrappedKey` (Task 2)
- Produces: `class VaultEntry { String id, name; int sizeBytes; DateTime addedAt; }`
  `class VaultStore { VaultStore(Directory root); Future<void> init(); Future<List<WrappedKey?>> readSlots(); Future<void> writeSlots(List<WrappedKey?>); Future<VaultEntry> put(Uint8List dataKey, int slot, String name, Uint8List bytes); Future<Uint8List> get(Uint8List dataKey, int slot, String id); Future<List<VaultEntry>> list(Uint8List dataKey, int slot); Future<void> delete(int slot, String id); Future<void> destroySlot(int slot); }`

- [ ] **Step 1: Write the failing tests**

```dart
test('put then get round-trips the bytes', () { ... });
test('get with the wrong data key fails and does not return plaintext', () { ... });
test('stores a zero-byte file and returns it unchanged', () { ... });                 // RF#4
test('stores a 64 MB file (above the 32 MB transfer ceiling)', () { ... });           // RF#4
test('two files with the same name both survive and are distinct', () { ... });       // RF#5
test('a failed write leaves no plaintext and no index entry', () { ... });            // RF#3
test('destroySlot makes that slot unreadable and leaves the other intact', () { ... });
test('on-disk layout does not reveal how many slots hold data', () { ... });
```

The last one is the anti-artefact requirement: filenames, directory structure and file count must not differ between a one-environment and a two-environment vault.

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement `VaultStore` in `app/lib/src/vault/vault_store.dart`**

Content and metadata are both sealed under the data key — filenames never hit disk in the clear. Entry ids are random, not derived from the name, so identical names cannot collide and the id leaks nothing. Writes go to a temp file and are renamed into place so a failure cannot leave a partial entry. `destroySlot` deletes the wrapped key for that slot and nothing else; the sealed bytes stay but are unreadable.

Both slot files are created at `init()` with the same size whether or not a decoy exists.

- [ ] **Step 4: Run to verify they pass**

- [ ] **Step 5: Commit** — `feat(vault): encrypted on-disk store`

---

### Task 6: Environment-scoped identity and TOFU

The spec's call: shared state would expose the real identity fingerprint inside the decoy and let an attacker correlate every file ever sent.

**Files:**
- Modify: `app/lib/src/identity_store.dart`, `app/lib/src/tofu_store.dart`
- Modify: `app/lib/main.dart` (providers take the active environment)
- Test: `app/test/vault/environment_scoping_test.dart`

**Interfaces:**
- Produces: `IdentityStore(Sodium sodium, {int? environmentSlot})` and `TofuStore({int? environmentSlot})`; storage keys become `deaddrop_identity_ed25519_env<N>` / `deaddrop_tofu_known_senders_env<N>`, with the current unsuffixed keys kept for `environmentSlot == null` (the no-vault case).

- [ ] **Step 1: Write the failing tests**

```dart
test('identities in different environments are different', () { ... });
test('the no-vault identity keeps the existing storage key', () { ... });   // no migration
test('TOFU entries do not leak between environments', () { ... });
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Add the optional `environmentSlot` to both stores**

Keep the unsuffixed key when the slot is null so existing installs are untouched — there are no vaults in the wild, and the no-vault path must not change behaviour.

- [ ] **Step 4: Run to verify they pass, and the existing suite still passes**

Run: `make test`
Expected: the 46 pre-existing tests still pass.

- [ ] **Step 5: Commit** — `refactor(vault): scope identity and TOFU to an environment`

---

### Task 7: Vault session lifecycle and providers

Owns Review Focus #2.

**Files:**
- Create: `app/lib/ui/vault/vault_controller.dart`
- Modify: `app/lib/main.dart` (sumo init, vault providers)
- Test: `app/test/vault/vault_controller_test.dart`

**Interfaces:**
- Consumes: `tryUnlock` (Task 3), `VaultStore` (Task 5)
- Produces: `class VaultState { bool exists, unlocked; int? slot; List<VaultEntry> entries; String? error; }`
  `class VaultController extends StateNotifier<VaultState>` with `Future<bool> unlock(String passphrase)`, `void lock()`, `Future<void> createVault(String passphrase)`, `Future<void> addDecoy(String passphrase)`
  `final vaultControllerProvider = StateNotifierProvider<VaultController, VaultState>(...)`

- [ ] **Step 1: Write the failing tests**

```dart
test('unlock with the real passphrase exposes the real entries', () { ... });
test('unlock with the decoy passphrase exposes the decoy entries', () { ... });
test('lock() clears the data key and the entry list from memory', () { ... });
test('the vault locks when the app is backgrounded', () { ... });            // RF#2
test('createVault does not require a decoy', () { ... });
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement the controller, and switch `main()` to `SodiumSumoInit`**

Observe `AppLifecycleState.paused` and lock. `sodium_libs_sumo` can throw `SodiumSumoUnavailable`; when it does, the vault feature is unavailable and the rest of the app must still work — Send and Receive do not depend on it.

- [ ] **Step 4: Run to verify they pass**

- [ ] **Step 5: Commit** — `feat(vault): session lifecycle and providers`

---

### Task 8: Vault UI — setup, unlock, file list

**Files:**
- Create: `app/lib/ui/vault/vault_page.dart`, `app/lib/ui/vault/vault_setup_page.dart`
- Create: `app/lib/ui/settings/settings_page.dart`
- Modify: `app/lib/ui/home_page.dart`
- Test: `app/test/vault/vault_ui_test.dart`

**Interfaces:**
- Consumes: `vaultControllerProvider` (Task 7), `estimateStrength`, `generatePassphrase` (Task 4)

- [ ] **Step 1: Write the failing widget tests**

```dart
testWidgets('home shows no Vault entry before setup', (t) async { ... });
testWidgets('home shows a Vault entry once a vault exists', (t) async { ... });
testWidgets('the decoy environment shows no Security section in Settings', (t) async { ... });
testWidgets('setup refuses a passphrase below the minimum', (t) async { ... });
testWidgets('setup offers a generated passphrase', (t) async { ... });
```

The third is the behavioural tell the whole feature rests on.

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Build the three screens and wire the home entries**

Settings is reachable always; its **Security** section renders only when the open environment is slot 0. Decoy setup states plainly that an empty decoy is worse than none. Self-destruct is off by default and its copy says an attacker can trigger it deliberately.

No biometric unlock. The passphrase is typed every time.

- [ ] **Step 4: Run to verify they pass**

- [ ] **Step 5: Commit** — `feat(vault): setup, unlock and file list UI`

---

### Task 8b: Attempt counter, rate limiting and self-destruct

The spec requires rate limiting, and self-destruct needs something to count. Without this task Task 8 ships a setting with nothing behind it.

**Files:**
- Create: `app/lib/src/vault/attempt_guard.dart`
- Modify: `app/lib/ui/vault/vault_controller.dart` (Task 7)
- Test: `app/test/vault/attempt_guard_test.dart`

**Interfaces:**
- Consumes: `VaultStore.destroySlot` (Task 5)
- Produces: `class AttemptGuard { Future<Duration> penaltyBeforeNextAttempt(); Future<void> recordFailure(); Future<void> recordSuccess(); Future<int> failureCount(); }`
  `const int kSelfDestructThreshold = 10;`

- [ ] **Step 1: Write the failing tests**

```dart
test('the first few attempts are not delayed', () { ... });
test('the penalty grows with consecutive failures', () { ... });
test('a success resets the counter', () { ... });
test('the counter survives a restart', () { ... });
test('the counter is global, not per environment', () {
  // a per-environment counter would reveal which environment was targeted
});
test('with self-destruct off, reaching the threshold does nothing', () { ... });
test('with self-destruct on, reaching the threshold destroys every slot', () {
  // a surviving decoy would prove there was something to erase
});
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Implement `AttemptGuard` in `app/lib/src/vault/attempt_guard.dart`**

The delay goes **before** the attempt, not after a failure: a post-failure pause is itself an observable signal. Store the count via `flutter_secure_storage` under a key present whether or not a vault exists, so its existence is not an artefact.

`kSelfDestructThreshold = 10` follows the spec's §4.8 example. Self-destruct is off by default; when on, it destroys **all** slots.

- [ ] **Step 4: Run to verify they pass**

- [ ] **Step 5: Commit** — `feat(vault): attempt rate limiting and optional self-destruct`

---

### Task 9: Save received files to the vault

**Files:**
- Modify: `app/lib/ui/receive/receive_page.dart:203-213`
- Test: `app/test/vault/receive_to_vault_test.dart`

**Interfaces:**
- Consumes: `vaultControllerProvider` (Task 7)

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('with no vault, only Save to device is offered', (t) async { ... });
testWidgets('with a vault, both destinations are offered', (t) async { ... });
test('saving to the vault writes no plaintext to disk', () { ... });
```

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Add the destination choice to the completion screen**

Keep `saveFile()` as the device path. The vault path never touches `FilePicker` and never writes plaintext. When no vault exists the second option is absent, not disabled.

- [ ] **Step 4: Run to verify they pass**

- [ ] **Step 5: Commit** — `feat(vault): choose device or vault when saving a received file`

---

### Task 10: Timing equality test and documentation

The feature's headline property, and the point where the docs stop saying "not implemented".

**Files:**
- Create: `app/test/vault/timing_test.dart`
- Modify: `docs/technical-spec.md` (§3.4, §4.2, §4.4, §4.8, §5.1), `docs/security.md`, `README.md`

- [ ] **Step 1: Write the timing test**

```dart
test('real, decoy and wrong passphrase unlock within a tight bound', () {
  // N repetitions each; assert the spread between medians is under the bound
});
test('a decoy with few files and a real vault with many paint within the bound', () {
  // RF: render time must not leak content volume
});
```

Pick the bound from the Task 0 measurements and state it in the test. It must be tight enough to fail if someone reintroduces a short-circuit in `tryUnlock`.

- [ ] **Step 2: Run to verify they pass**

If they do not, that is a real finding — report it rather than widening the bound.

- [ ] **Step 3: Update the spec sections listed in the design doc**

§3.4 PIN → passphrase; §4.2 PIN minimums → entropy minimum; §4.4 app-generated decoy → user-supplied; §4.8 self-destruct destroys wrapped keys, off by default; §5.1 record the mobile-first inversion.

- [ ] **Step 4: Move the three features from "planned" to "implemented"**

In `docs/security.md` and the `README.md` status block — only the parts that actually shipped. Self-destruct ships off by default; say so.

- [ ] **Step 5: Run the full suite and analyze**

Run: `make test && make analyze`
Expected: all pass, no issues.

- [ ] **Step 6: Commit** — `feat(vault): timing guarantees and documentation`

---

## Notes for the executor

- **Task 0 gates everything.** If Argon2id cannot run four times within budget on the pinned stack, stop and report; Tasks 3 and 10 depend on that answer.
- The branch is `feat/vault-coercion`, cut from `v0.2.0`. That tag is the rollback point if this work stalls.
- Nothing here changes the transfer protocol. If a task seems to require touching `crypto.dart`, `fountain.dart`, `qrframe.dart` or `emitter.dart`/`receiver.dart`, stop and ask — that is a sign the task was misread.
