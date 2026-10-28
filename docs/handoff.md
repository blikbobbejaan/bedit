# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in brood's `docs/devlog.md`; decisions in brood's `docs/decisions/`; the open backlog is
`todo.md` and the Next list below. Read this to pick the work back up cold.

## State when written — 2026-10-28, evening

Released and published; everything of bedit's committed and pushed.

- **brood v0.45.0** (tag on `ad737a7d`, cut by another session): C-g through a busy update
  (ADR-491/493/494/502), every error a map and `catch` by pattern (ADR-501), hygiene at every
  binding site (ADR-500), nested quasiquote (ADR-503), tree handles owned per process
  (ADR-495), injection `:exclude` (ADR-496), fuzzy ranking (ADR-497), `diff/map-line` and
  friends (ADR-499), vt rows of several colours painted in order (PR #6).
- **bedit v0.8.0** (`efae0fa8`): the floor is brood 0.45.0. Since 0.7.0: the time machine
  (C-x v t, git and mur), fuzzy file finding with Emacs-style ranking and frequency, the
  long-lines policy (`:long-lines`, `M-x toggle-truncate-lines`), completion that merges
  mid-word, the terminal's completion preview no longer taking a program's keys (PR #1).
  Binaries for Linux x86_64 / arm64 and macOS arm64 on the GitHub release; on hive.
- Installed: nest 0.45.0 (`ad737a7d`, GUI build) and bedit 0.8.0.

## Next

1. **In flight — brood branch `native-redirect`** (worktree `~/.cache/brood-wt-redirect`, not
   merged): a builtin that calls Brood back from Rust (`num/add` and `compare-to` on records,
   `->seq` / `->count`, `apply` as a value) hands the call to the engine instead, so a
   `receive` under it parks; `isolate` as a frame; an alias of `proc/interruptible`. Review,
   merge onto main, delete the worktree.
2. **Benchmark ADR-502 on the benchmark machine**: `make ab BASE=11601fe6 ROWS="nqueens
   pipeline json reduce"`. A closure reducer's fold over a vector or range now walks in Brood;
   never measured. If it is slow: keep the Rust loop outside interrupt windows.
3. `todo.md`: every feature listed there is built (region wrap and the electric-pair toggle,
   the markdown preview, `aside` panes, window swapping). One bug is unconfirmed: a slight
   jitter when editing a markdown file. Reproduce before assuming it is gone.
4. Dormant Brood lead: `docs/fuzz-diag-overrides-anomaly.md` (compiled code and source
   disagreeing, July). The code it hit was rewritten on 2026-10-18 and it no longer reproduces.
5. Multiplayer (`docs/remote-multiplayer-plan.md`, Open): a CRDT for offline divergence,
   per-participant undo, one real cross-machine run of `--listen`.
6. Brood gaps still open (`../brood/docs/general-purpose-gaps.md`): runtime memory items
   (benchmark-gated), a C embedding API, `:wasm-build` build-on-fetch, HTTP/2 / gRPC / Redis /
   MySQL packages, W3C `traceparent`.
7. `toolchain.blsp` (marker file → compile/test/run commands) was weighed for std and left
   in bedit: mostly data, no second user yet. Revisit if one appears.

## Decisions

- **bedit takes no package dependencies.** A feature is a brood abstraction with a thin bedit
  layer, or wholly bedit; packages only as optional runtime installs (`M-x package-list`).
- Brood releases are cut from the last CI-green commit and merged back, so another session's
  untested push on main never rides into a tag.
- Gap 8 (errors) was a stale ROADMAP line: failure VALUES (ADR-310/315), not tuples.

## Traps

- **No benchmarks, stress runs or heavy brood suites on this desktop**; bedit's per-file
  `nest test` and a single brood test file are fine. Push brood with `--no-verify`.
- Brood work goes in a worktree with its OWN `target/` (none is open from this session).
  Rebuild after every std edit: the binary embeds std.
- `nest publish` can hit the http client's fixed 30 s timeout on a transient registry stall;
  `nest search NAME` says whether it landed (releases are immutable) — then just retry.
- Brood ADR numbers collide across sessions: `git grep '^## ADR-NNN' origin/main` first.
  Next free: 505 (check first — sessions run in parallel).
- A release's CHANGELOG is checked only for its heading — read `git log vPREV..` and fill
  in what is missing before tagging.
- `nest format` takes no file arguments: `nest format --changed [--check]`.
