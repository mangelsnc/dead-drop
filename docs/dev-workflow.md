# Parallel-Work Discipline (Agent Workflow)

> **Status:** enforced from 2026-10-21.
> **Audience:** every agent and human committing to this repo from the shared
> Teros workspace.

This document is the **single source of truth** for how we work on DeadDrop in
parallel without destroying each other's uncommitted work.

---

## The problem we're solving

The Teros workspace has **one shared git checkout** at
`/workspace/dead-drop`. Five agents (Marco, Nora, Quinn, Diseñador,
Coordinador) plus the occasional human work on this repo **at the same
time**.

If two agents share that checkout and one runs `git checkout <other-branch>`,
the working tree is switched out from under the other agent. **Uncommitted
changes are lost.** This has already happened twice in one day (see PR #37
notes — Marco lost in-progress edits on `fix/ed25519` when the checkout was
switched to `main` and then to `feat/file-info-tile-metadata`).

This is not a tooling bug. It's a discipline gap. This doc closes it.

---

## The golden rule

> **Never run `git checkout`, `git switch`, `git reset --hard`, `git clean`,
> or `git stash` against `/workspace/dead-drop`.**
>
> The shared checkout stays on `main`, untouched, forever. It exists only as
> a reference and as the parent for worktrees. **All real work happens in
> your own per-agent directory.**

If you find yourself about to type a branch-switching command against
`/workspace/dead-drop`, **stop**. You are about to destroy a teammate's
work.

---

## The mechanism: per-agent worktrees

Each agent works in **its own git worktree**, rooted at the shared checkout.
Worktrees share the `.git` object store (no re-download, no duplicate
packfiles) but have **independent working trees and independent HEADs** —
so your branch switch never affects anyone else.

### Naming convention

```
/workspace/dead-drop-<agent-name>[-<task-slug>]
```

Examples:

| Path | Who | What |
|---|---|---|
| `/workspace/dead-drop-marco` | Marco | default worktree |
| `/workspace/dead-drop-nora` | Nora | default worktree |
| `/workspace/dead-drop-quinn` | Quinn | default worktree |
| `/workspace/dead-drop-design` | Diseñador | default worktree |
| `/workspace/dead-drop-coordinator` | Coordinador | default worktree |
| `/workspace/dead-drop-marco-ed25519` | Marco | one-off for the ed25519 fix |

Use the per-task variant when you need two parallel worktrees at once.
Otherwise reuse your default.

### Creating your worktree (one-time setup)

```bash
cd /workspace/dead-drop
git worktree add /workspace/dead-drop-<you> -b <your-branch>
```

Example (Marco starting the ed25519 fix):

```bash
cd /workspace/dead-drop
git fetch origin
git worktree add /workspace/dead-drop-marco -b fix/ed25519 origin/main
cd /workspace/dead-drop-marco
# ... work normally: edit, commit, push ...
```

The shared checkout at `/workspace/dead-drop` **does not change branch**.
Your new worktree is on `fix/ed25519`; the shared one is still on `main`.

### Day-to-day inside your worktree

Inside `/workspace/dead-drop-<you>` everything works exactly like a normal
clone: `git status`, `git add`, `git commit`, `git push`, `git pull`,
`git checkout -b`, etc. The only difference is that your `.git` is a small
file pointing back to the shared object store.

### Cleaning up when the task is done

Once your PR is merged:

```bash
cd /workspace/dead-drop
git worktree remove /workspace/dead-drop-<you>[-<task>]
git branch -d <your-branch>     # if it's fully merged
```

Or, if you want to keep your default worktree around for the next task,
just switch its branch — **your** worktree, your rules:

```bash
cd /workspace/dead-drop-<you>
git checkout main
git pull
git checkout -b feat/next-thing
```

### Listing existing worktrees

```bash
cd /workspace/dead-drop
git worktree list
```

Run this before creating a new one to avoid collisions.

---

## Acceptable fallback: full clones

If for any reason `git worktree` is unavailable (e.g. resource limits in the
sandbox, see note below), a **full independent clone** is an acceptable
substitute:

```bash
git clone https://github.com/mangelsnc/dead-drop.git /workspace/dead-drop-<you>
```

Clones are heavier (full `.git` duplication) but give the same isolation.
Several agents already use them (`dead-drop-marco`, `dd-chunkcount-nora`,
`dd-fix5-work`, `dd-design-accessibility`, `dd-scarlett-docs`). **Both
patterns satisfy the golden rule** as long as the shared checkout is left
alone.

> **Note (2026-10-21):** the workspace hit `Resource temporarily unavailable`
> on `git clone` earlier today. If that happens, prefer `git worktree add`
> (much cheaper) or reuse an existing per-agent directory.

---

## What is NOT allowed

- ❌ `git checkout <branch>` inside `/workspace/dead-drop`
- ❌ `git switch <branch>` inside `/workspace/dead-drop`
- ❌ `git reset --hard` inside `/workspace/dead-drop` (unless you are the
  coordinator recovering from a verified-broken state, and you've pinged the
  team first)
- ❌ `git stash` / `git stash pop` inside `/workspace/dead-drop`
- ❌ Editing files directly in `/workspace/dead-drop` and committing from
  there
- ❌ Relying on "I'll be quick, nobody will notice" — you will not be quick,
  and somebody will notice because their work just vanished

---

## What IS allowed against the shared checkout

- ✅ `git fetch` (read-only on the working tree)
- ✅ `git worktree add / list / remove` (this is its intended purpose)
- ✅ `git log`, `git show`, `git diff` (read-only inspection)
- ✅ Reading files directly with your file tools

---

## If you need a quick one-off commit

Use the **GitHub API** (via the `github_create-or-update-file` tool) on a
fresh branch cut from `main`. This is what Marco did to save his ed25519
work, and it's the right tool for small, self-contained changes that don't
need local testing. **Do not** switch the shared checkout just to commit a
one-liner.

---

## Migration plan for existing directories

The following directories already exist and are **compliant** with this
discipline (they're independent clones or worktrees — the shared checkout is
untouched):

- `/workspace/dead-drop-marco` (clone)
- `/workspace/dd-chunkcount-nora` (clone)
- `/workspace/dd-fix5-work` (clone)
- `/workspace/dd-design-accessibility` (clone)
- `/workspace/dd-scarlett-docs` (clone)
- `/workspace/dd-ctequals-work` (worktree, currently dangling — will be
  cleaned up or re-registered)

Going forward, prefer the `/workspace/dead-drop-<agent>` naming so it's
immediately obvious whose directory is whose. Existing `dd-*` directories
may finish their current task, then be removed and recreated under the
standard name on the next task.

---

## Enforcement

- The **Coordinador** (me) checks `git -C /workspace/dead-drop status` and
  `git -C /workspace/dead-drop branch --show-current` as part of the regular
  board sweep. If the shared checkout is on anything other than `main`, or
  has uncommitted changes, that's a ** Sev-2 incident** and I will find out
  who did it.
- Repeated violations get escalated to Scarlett with a timeline.
- If your work is destroyed because somebody violated this rule, **ping the
  Coordinador immediately** with the branch you were on and roughly what you
  lost. `git reflog` in the shared checkout can often recover commits that
  were "lost" by a branch switch — but only if we act quickly.

---

## TL;DR

1. `/workspace/dead-drop` is **read-only**. Branch = `main`. Forever.
2. Your work happens in `/workspace/dead-drop-<you>` (worktree preferred,
   clone acceptable).
3. Create with `git worktree add /workspace/dead-drop-<you> -b <branch>`.
4. Clean up with `git worktree remove` when merged.
5. Small one-off fixes → use the GitHub API, not the shared checkout.
6. Violations = Sev-2. Report losses immediately.
