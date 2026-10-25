# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in brood's `docs/devlog.md`; decisions in brood's `docs/decisions/`; the open backlog is
[`../issues.md`](../issues.md). Read this to pick the work back up cold.

## State when written — 2026-10-25, evening

Everything below is committed and pushed. **No test was run on this machine** (the rule at the
time; it now allows ordinary tests, see Traps); CI ran them, and both repos are green.

### Goal (the user's asks this session)

- Held keys "like other systems … it has to work really well", in the window, over
  `--attach`, and in every terminal ("can you do it so that it works for everything").
- A thorough review of the language-server client, fix issues, refactor for cleanliness;
  then "can't we recover after the fact if two are started the same time? … and what
  about the clearing out. can we make it slick".
- In a find-file prompt, Backspace after `foo/` removes the whole `foo/` (Emacs).
- Killing a buffer shows the buffer used before it (Emacs `other-buffer`).

### Done — brood (`~/src/broodlang/brood`, origin/main)

- `296b4baa` GUI `Keyboard` per window (`crates/lisp/src/host/gui/backend/keyboard.rs`),
  `gui/key-repeats` ({:delivered :dropped :delay :interval} ms).
- `62470cda` (+ another session's fix `9366d5ef`/`6b660f4a`: `table/new`/`table/get`/
  `table/put`, which my commit had wrong) — `--attach` client ships whether a key is held.
- `2c58289f` kitty keyboard protocol in terminals.
- `61bf93db` GUI: Shift let go mid-repeat ends `(` with its key-up (`KeyMessage::Restroke`).
- `ccfc83d0` terminal held keys INFERRED where the protocol says nothing (tmux, legacy, text/
  Enter/Tab/Backspace): `crates/lisp/src/builtins/terminal/native/keyboard.rs` `Inbox`,
  `REPEAT_GAP` 70 ms, `RELEASE_AFTER` 140 ms; typed text never dropped (paste arrives as keys).
- `35074a9c` `std/editor/lineedit.blsp` `lineedit-delete-backward`: in `:path` mode at end of
  line after `/`, deletes the whole component.
- Installed: `nest 0.43.0 (35074a9c)` (another session has pushed more since, e.g. `3caefacc`).

### Done — bedit (`~/src/broodlang/bedit`, main = origin/main `994daa02`)

- `4c5e47a4`, `1ed1be6f` M-x latency shows key repeats.
- `f0173fea` init keys via std `settings`; `42270ffd` LSP per server; `de79c686` fuzzy match
  colours (these three were an earlier session's uncommitted work, finished and committed).
- `5276d655` kill-buffer → `pool/ed-kill-replacement` (MRU, not shown elsewhere).
- `03ae59d4` LSP server table `lsp/*lsp-server-specs*` (alternatives, root markers, add-ons,
  shared servers + toolchain identity `lsp-commands/ed-lsp-identity`).
- `eb8555b8` review fixes: entries keyed by CONNECTION (`:lsp-servers {conn entry}`),
  `:lsp-synced {[conn uri] …}`, `:lsp-diags {path {conn [items raw]}}`; detach clears marks;
  didClose for gone buffers (`ed-lsp-close-gone`); dead shared server detached whole.
- `994daa02` merge servers started together (`ed-lsp-merge-into-host`, run when caps
  arrive in `ed-ev-lsp-capabilities`); monitor each connection; new core registry
  `model/register-down-handler` + `ed-run-down-handlers`, called from `input/ed-ev-down`
  for a pid that backs no slot; `ed-lsp-server-down` clears entry/marks/pending lookups.
- `1a35124d`, `3ebde1d8`, `be96fc3b` — CI had been red since `de79c686`; fixed: C-c C-c
  committed in the repo of the buffer selected after closing *git-commit* (now
  `gitcore/git-launch-op-in` with the message's root), the lost "does not offer code
  actions" refusal, and stale/racy tests. **bedit CI green at `be96fc3b`.** All bedit
  stashes dropped.

## Next

1. GPU subpixel text is only a proposal — do not start it unasked.
2. The two LSP limits are built (see Done): a merged-away server's lookups are re-asked of
   the host (`ed-lsp-reroute-pending`; dropped only when the text moved), and a file's
   project root is learnt per folder (`:lsp-roots`, `ed-lsp-learn-roots`) so a nested
   project starts its own server. Tests in `tests/lsp_test.blsp`; CI green at `7bdec657`, brood green at `ebe8b906`.

## Decisions

- Terminal inference never drops typed text (no bracketed paste is enabled; a paste arrives
  as keys). Tapped keys get no key-up in legacy terminals.
- Shared LSP servers only for specs marked `:shared` (rust-analyzer, gopls, python,
  typescript), only after the server's caps say `workspaceFolders` supported with change
  notifications, and only when `ed-lsp-identity` (resolved command path + toolchain pin file
  contents) matches. Expert, ruby-lsp, brood-lsp, clangd stay one process per project.
- Root markers are tried in order up the whole tree (first marker wins over nearer later
  ones), never at or above `$HOME`.
- A dead server is said once and its projects marked tried; `M-x lsp-connect` is the retry.

## Traps

- **No benchmarks, stress runs or heavy brood suites on this desktop** (global CLAUDE.md);
  bedit's `nest test` and a single brood test file are fine. Push brood with `--no-verify` (its pre-push hook runs tests).
- Brood work goes in a worktree (`git worktree add ~/.cache/brood-wt-X origin/main -b X`,
  `ln -s ~/src/broodlang/brood/target …/target`, copy `config.mk`); other sessions use the
  primary checkout (it currently has another session's uncommitted edits — leave them).
  Worktrees `brood-wt-perf`, `brood-wt-vcs`, `brood-b2d-handoff` are NOT this session's.
- In a Bash call that also runs `nest`/`cargo`, `$(…)` shell variables can come out empty
  (hook wrapper); use the Edit tool or literal line numbers.
- When splicing files with `head -n N; …; tail -n +M`, check the boundary lines — one
  dropped `(describe …` opener cost a round.
- The checker does not see a binding used only inside a `#{…}` set literal (reports it
  unused); build the set with `conj`.
- `nest format` takes no file arguments: `nest format --changed [--check]`.
- bedit's primary checkout: update with stash push → `git merge --ff-only origin/main` →
  `stash apply`, so another session's uncommitted edits survive.

## Environment

- bedit `~/src/broodlang/bedit` on `main`, clean, equal to origin/main.
- brood primary `~/src/broodlang/brood`: another session's uncommitted edits (README.md,
  ROADMAP.md, breakage/…) — not this session's.
- No background processes from this session are running.
