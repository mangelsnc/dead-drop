/// utils.dart — shared helpers for the DeadDrop protocol core.
///
/// Security-relevant utilities that are needed by more than one module
/// live here exactly once. Duplicated security code drifts; a single
/// implementation is the only way to guarantee both sides of a comparison
/// behave identically after any future change.
library;

import 'dart:typed_data';

/// Compares two byte strings in constant time.
///
/// Used for values where a timing side channel would leak information to
/// an attacker who can observe comparison duration — e.g. the receiver
/// public key in the session header, or the manifest hash of the received
/// file. The loop always runs over the full length of [a] and accumulates
/// differences with OR, so the running time does not depend on where (or
/// whether) the inputs differ. The length check short-circuits, but
/// lengths in this protocol are fixed public constants, so that reveals
/// nothing.
bool constantTimeEquals(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    result |= a[i] ^ b[i];
  }
  return result == 0;
}
