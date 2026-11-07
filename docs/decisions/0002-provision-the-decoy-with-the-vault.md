# 2. Provision the decoy when the vault is created

**Status:** accepted, 2026-11-07
**Decided by:** the project owner, who also found the defect, while
adding a decoy to an existing vault on macOS.

## Context

The decoy (slot 1) is provisioned separately, from Settings → Security →
"Set up decoy", after the real environment (slot 0) already exists. Three
problems follow from that, and the owner hit all three in one sitting.

### The interface cannot say whether a decoy exists

By design, it cannot know. `VaultStore.init` writes both slot files at
creation, each `_slotFileBytes` of either a wrapped key or random filler,
and `readSlots` has no way to tell them apart — "a slot's emptiness is
therefore not observable from its file alone". That indistinguishability
is what makes the vault coercion-resistant: an attacker reading the disk
cannot prove a second environment exists.

The price is that the app cannot either. So Settings offers "Set up
decoy" unconditionally, which reads as "you have no decoy" and is not a
claim the app is in a position to make. The owner reasonably concluded
from the option's presence that no decoy existed.

### Creating a decoy silently replaces the one that may be there

`addDecoy` writes `[slots[0], wrapped]`, overwriting slot 1 whatever was
in it, with no confirmation. Measured on 2026-11-07:

| | |
|---|---|
| decoy before replacement | 1 file |
| old decoy passphrase after | does not open |
| new decoy | 0 files |
| files left in `entries/` | 1 |

The old decoy's data key was wrapped in the slot that was overwritten, so
its files are unrecoverable. They remain on disk as an orphan, which is
itself a residue: a vault whose slot 1 holds nothing but whose `entries/`
contains files nobody can open is distinguishable from one that never had
a decoy. That is the property `init`'s `.tmp-` sweep exists to protect,
applied inconsistently here.

### Settings is asymmetric between the two environments

This is the serious one. `settings_page.dart` renders the Security
section only when `state.slot == 0`:

```dart
final isRealEnvironment = state.unlocked && state.slot == 0;
```

The file's own doc comment calls this "the single behavioural property
the whole coercion-resistance design rests on", reasoning that a
greyed-out control would tell an attacker the feature exists.

But the asymmetry runs both ways. Inside the decoy there is no Security
section; inside the real environment there is. An attacker who opens
Settings in an environment the owner has just unlocked under duress, and
finds no Security section, learns they are *not* in the real one. The
design stops the decoy from revealing that a real environment exists, and
replaces it with the real environment revealing that it is the real one.

Two tests currently pin this asymmetry as intended behaviour
(`vault_ui_test.dart`: "the decoy environment shows no Security section",
"the real environment shows a Security section").

## Decision

Provision both environments when the vault is created. The setup flow
asks for two passphrases — one for the real environment, one for the
decoy — and writes both slots.

Settings then renders the same sections in both environments, because
there is no longer anything for the real one to have that the decoy does
not: no "set up decoy" (it exists), and what remains applies to whichever
environment is open.

## Consequences

**The question disappears rather than being answered.** The app never
needs to report whether a decoy exists, which it cannot do, because the
answer is always yes.

**Nothing is silently overwritten.** Replacing a decoy becomes changing
its passphrase, an explicit act on a thing known to exist.

**The interface stops distinguishing the environments.** The disk already
goes to some length to make the two slots identical; the interface
undoes that. This aligns them.

**Setup asks for two passphrases instead of one.** Two phrases to write
down at the one moment that most deserves care. The owner judged this
acceptable; it is the main cost.

**Neither environment is steered towards content at creation.** An
earlier draft of this proposal had the flow walk the user into the decoy
to add files, carried over from today's behaviour, where the decoy is
created long after the real environment has accumulated content and an
empty decoy is conspicuous. At creation both are empty, so there is no
asymmetry to fix and nothing to steer. Keeping the decoy credible as the
real environment fills up remains the user's responsibility, as
`docs/security.md` already states.

**Existing vaults are not migrated.** A vault created before this change
has a slot 1 that may or may not hold anything, and no migration is
written for it: the owner decided on 2026-11-07 that every vault in
existence holds test data. A vault made before the change keeps whatever
slot 1 it had, and the new Settings — which no longer offers to set up a
decoy — gives its owner no way to provision one. Nothing is lost that
anyone is keeping, and nothing is silently converted.

This is a decision about today's installs, not a property of the design.
If a vault holding real data exists before 2027-02-10, migrating it needs
its own decision.

**What this does not fix.** The orphaned entry files measured above are a
separate defect with its own fix, and the residue a wipe leaves on
flash — already documented in `docs/security.md` — is unaffected.

## Alternatives considered

**Warn before replacing, and rename the option.** Changing "Set up decoy"
to "Set or replace decoy", with a confirmation. Cheap, honest, and
available today. It addresses the overwrite but leaves the Settings
asymmetry untouched, which is the actual security defect.

**Remember in the app that a decoy was created.** Correct only within one
session; a restart loses it. Persisting it to disk reintroduces exactly
the marker the slot design removes.

**Count the slot files.** Both always exist, from vault creation onwards.
They say nothing.
