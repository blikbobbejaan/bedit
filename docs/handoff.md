# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in brood's `docs/devlog.md`; decisions in brood's `docs/decisions/`; the open backlog is
`todo.md` and the Next list below. Read this to pick the work back up cold.

## State when written — 2026-10-29

- **brood v0.47.0** (ADR-506: 115 bare names moved into their modules; another session migrated
  every sibling project). **v0.48.0** (ADR-507, `buffer-edit`'s tag before its transform; the
  floor since `d299d348`): bedit main passes its full suite on it, 3370 tests.
- **bedit v0.8.1** (`630cbec5`): the ADR-506 migration, floor 0.47.0, and a line's end-of-line
  note starting after the completion preview instead of under it. Released and on hive.
- Installed: nest 0.48.0 (`a67f4889`) and bedit main (`d299d348`: the word-index fix and the
  `:font` setting, unreleased).
- **Typing lag, measured** (`tools/probe-typing.blsp`: the real ui-run loop, keys pressed on a
  typist's schedule, timed from press to drawn frame). With contracts off, as a release runs,
  keys settle at p50 ~11 ms and max ~20 ms headless. The bad part was the first seconds in
  a large file: 100–460 ms keys while the completion preview's word-index task ran. That was
  a brood runtime effect, filed as **brood KI-307**: a process with a big live heap stalls
  allocating processes beside it. `ce74415c` builds the index a line at a time, and the
  worst key fell to 18–20 ms. KI-307 still applies to every other off-loop task (tree warm,
  diagnostics, LSP JSON), and its root cause is for the test machine. `nest run` arms
  contracts, which put p50 at 20–35 ms, so measure with `BROOD_CONTRACTS=0`.
- **The "puffy" font, measured**: swash already hints vertically only (like GNOME's
  "slight"), so hinting is not the cause. Hack at 15 px is a heavy face: 25–40% more ink
  than Ubuntu Sans Mono, the desktop's monospace. `ff1be044` adds `:font` / `:font-size` to
  init.blsp. Themes no longer carry a font, so a theme switch keeps the configured one. Nothing
  was checked on screen: no window is opened on this machine.

## Earlier — 2026-10-28, evening

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
- Installed: nest 0.46.0 (`7d7e8d99`, GUI build: ADR-505, wasmtime 50, minimum Rust 1.97; tagged
  by another session before CI finished — bedit passed its full suite on it) and bedit main.

## Next

1. **Brood ADR-505, released in 0.46.0** (`8260983f`): a
   builtin that would call Brood from Rust (a record's `num/add` & co. under `+ - * /`, its
   `compare-to` under `<`, `->seq` / `->count` under `first` / `rest` / `count` / `empty?`)
   hands the call back to the engine, so a `receive` in the method parks; an alias of
   `proc/interruptible` is a region too. Still nested: `isolate`'s thunk (a frame for it is
   the global snapshot, stamp and reap on every exit), contracts, macro expansion, the loader,
   the `*err*` port, and a callback reached from JIT-compiled code (first park blocks, then
   the latch). bedit's full suite passed on it.
2. **Benchmark on the benchmark machine** (never measured — this desktop runs none):
   ADR-502, `make ab BASE=11601fe6 ROWS="nqueens pipeline json reduce"` (a closure reducer's
   fold over a vector or range walks in Brood; if slow, keep the Rust loop outside interrupt
   windows); and ADR-505's offer, a store before and after each native call through
   `dispatch` and the tier-0 machine (`make ab BASE=d3b0e654` with a native-call-heavy row).
3. `todo.md`: every feature listed there is built (region wrap and the electric-pair toggle,
   the markdown preview, `aside` panes, window swapping), and the markdown jitter is fixed
   (`1615ae23`): a wrapped pane scrolls by screen rows (`:top-row`), so typing at the bottom
   of a paragraph no longer lurches it up. Still by lines in wrapped text: the wheel and
   trackpad (a step over a paragraph jumps), the scrollbar and `ed-max-top`.
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
