# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in brood's `docs/devlog.md` (bedit's own [`devlog.md`](devlog.md) stops in July); decisions
in brood's `docs/decisions.md`; the open backlog is [`../issues.md`](../issues.md). Read
this to pick the work back up cold.

## State when written — 2026-10-19, morning

- **brood** `v0.41.0` is tagged (`f9878a63`): `std/mime`, `(string/bytes-> b :lossy)`, and
  a backward rope search that walks back from point instead of scanning from offset 0.
  The work was done in the worktree `~/.cache/brood-wt-mime` (branch `mime`), because a
  brood session was live in `~/src/broodlang/brood` with uncommitted `json` work.
- **bedit** requires `brood >= 0.41.0`. It carries mail (`src/mail.blsp`): mbox-mode moved
  out of `languages`, eml-mode, and C-c C-v — the message at point decoded in `*Message*`,
  RET on an attachment saves it.
- **LSP**: a server's `window/logMessage` goes to `*lsp-log*` only (capped at 2 MB of
  text); progress and `showMessage` reach the echo area, deduplicated. Expert's indexer
  (`Could not expand alias: …`) no longer floods the echo area. Not yet watched live against
  Expert — its engine had not started within three minutes in the test run.
- **mbox motion** (C-c C-n / C-c C-p) costs the distance to the next message, not the file:
  ~1 ms at the bottom of a 45 MB mailbox (was 55 / 135 ms). `tools/profile-mbox.blsp`
  measures it.
- **`format` → `formatter`, `term` → `terminal`.** brood ships modules by both names, and
  a release resolves std's first, so every call into bedit's (format-buffer, format-on-save,
  every terminal) landed in std's — dark in the v0.5.1 binary. brood 0.41.0's `nest
  release` refuses such a bundle. `terminal` now loads with `main`.
- **brood CI on `main` was red from 0.41.0 on** (the other session's json / browser-tab
  work), with two failures. Both are fixed in brood `c76336ef` (2026-10-19), pushed from the worktree:
  - `tests/project_test.blsp` now purges its `brood-gate-` / `brood-shadow-` temp
    prefixes, which `temp_purge_coverage_test.blsp` demanded.
  - `boot.rs PROVIDED_PRELUDE_IMAGE` is listed as `OneMachine` in
    `crates/lisp/tests/process_wide_statics.rs`.

  Both passed locally. CI on `c76336ef` itself was cancelled, because the other session pushed
  `e9ddd4c6` (feat(tab)) on top within minutes. Run `39215546916` covers both commits and
  was still running at the restart. **Check it first**:
  `gh run view 39215546916 -R broodlang/brood`. A new failure there is most likely from
  e9ddd4c6, so classify it before touching anything.
- **The other brood session is LIVE again** (it pushed e9ddd4c6 on 2026-10-19). Keep using the
  worktree `~/.cache/brood-wt-mime`, which is now detached at origin/main. Its `target`
  symlink points at `~/.cache/brood-wt-mime-target`, which holds a debug test build, not a
  nest. The pre-push hook fell back to the installed nest 0.41.0, and that was fine.
- **bedit v0.5.2 is not cut.** The installed v0.5.1 has formatting and terminals dark (the
  `format`/`term` std clash). The fix is on main (`8490c904`). The user has not yet said whether
  to release. If yes: follow `71d75a42 release: v0.5.1` (bump `project.blsp`, tag, push,
  `make install`).
- `issues.md` has no open items.

## Traps

1. **The disk is tight** (85% on 2026-10-19, 93 GB free; it hit 81 MB free on 10-18). A GUI `make install` needs ~6 GB under `target/release-fast`.
   Delete a worktree's `debug/` target once it is pushed; never build into the primary
   brood checkout's `target/` while its session is live.
2. **brood's pre-push hook looks for `./target/{release-fast,release,debug}/nest`.** A
   worktree built with `CARGO_TARGET_DIR` elsewhere is invisible to it, and it falls back
   to the installed nest — whose baked-in std is older, so the checker gate refuses.
   Symlink `target` in the worktree to the build dir first. It also runs `cargo fmt --check`.
3. **A mode's loading can only be checked in the built binary** (`make build` +
   `BEDIT=./bedit tools/check-modes.sh`). `x.eml` and `x.mbox` are fixtures there now.

## Work queue

1. Confirm brood CI is green on main (run `39215546916` or later). The v0.41.0 release run
   succeeded, and `BEDIT_REF` is already bumped to `42633ab`.
2. Ask the user about cutting bedit v0.5.2.
3. Try `*lsp-log*` and the echo area live against Expert in an Elixir project.
4. HTML-only mail shows its raw HTML in `*Message*` (with a note). An HTML→text in brood's
   std (the prime directive) would let it render.

## How to verify a change here

1. `nest check` clean; the suite per file (the bare `nest test` is blocked by a hook), with
   `BROOD_GUI_HEADLESS=1`; `nest test --failed` for the loop.
2. `nest format --changed` before committing — CI checks it.
3. `make check-modes` after a mode/service change; `make drive` for the live pty drivers.
4. After a brood change: `make install` (GUI) from a brood **worktree** with the `target`
   symlink, then `make install` here, then all of the above.
