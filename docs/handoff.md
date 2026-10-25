# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in brood's `docs/devlog.md`; decisions in brood's `docs/decisions/`; the open backlog is
[`../issues.md`](../issues.md). Read this to pick the work back up cold.

## State when written — 2026-10-26, early morning

Everything in brood and bedit is committed and pushed. Two new packages are committed
LOCALLY only (no GitHub repo, not on hive) — creating those is the user's call.

### Goal (the user's asks this session)

Work through the general-purpose gap analysis (`../brood/docs/general-purpose-gaps.md`):
"1) fix this. 2) fix this. 3) a) what can we do here … j) … 4) fix this. and everything else".
Answers given along the way: SQLite as a WASM component package; the error convention per
"ROADMAP's plan" (which turned out to be stale — see Decisions).

### Done — brood (origin/main, all via the worktree `~/.cache/brood-wt-defwarn`)

- Crypto (ADR-448), UDP (ADR-449), TLS ALPN + HTTP/1.1 keep-alive (ADR-451), DAP server
  `nest dap` (ADR-452), `nest profile` folded stacks, `std/tz` — earlier in the session.
- `b6611b4b` tempo/new, tempo/parse, tempo/parse-span, resolver/resolve answer a failure, not
  `[:ok]`/`[:error]` (ADR-310's own rule). Docs say gap 8 was already decided.
- `519653f2` the large-project queue is done bar re-timing; `language.md` says how to make
  the checker a CI gate.
- `bdbf8232` + `613f35bb` **ADR-453**: WASI preview 2 by grant (`%wasm-load src grants`:
  `:dirs` `[host guest]`/`[host guest :write]`, `:env`, `:args`, `:stdio`; never network),
  interface exports (`iface#fn`, bare alias when unique), guest resources as tokens +
  `%wasm-release`, enums/variants/records lower as they lift. Fixture: a real wit-bindgen
  guest committed built (`tests/support/wasm-guest.wasm`, source beside it);
  `tests/wasm_wasi_test.blsp`.
- `fdd21746` **ADR-454**: `include-bytes`; an include resolves against the package of the
  file naming it (dev now matches release). Same commit fixed main's red: the register
  worker's direct self-call is revalidated after ADR-450 (an alias called the old body),
  KI-303's archive section, `caar`..`cdddr` in bare-names + doc catalogue, `sv-seconds`
  given the 400 rounds 128 calls need.
- `89267d84` gaps 3 and 5 updated.

### Done — packages (local git only)

- `~/src/broodlang/observe-otlp` (`a568d86`): OTLP/HTTP JSON provider for `observe` — logs,
  errors as `exception.*` log records, metrics; `from-environment` reads `OTEL_*`. 12 tests.
- `~/src/broodlang/sqlite` (`e473c69`): SQLite 3.50 as a component (`native/`, rusqlite
  bundled, built with wasi-sdk 25 in `~/.local/share`; `make wasm`), a connection PROCESS
  per handle, `open/execute/execute-batch/query/query-one/query-rows/transaction/close`.
  12 tests, run with the worktree's nest. `:brood ">= 0.44.0"` — **needs a brood release with
  ADR-453/454 before it can be used or published.**

## Next

1. Confirm brood CI is green at `89267d84` (or later). Main was red all evening from other
   commits; the fixes are in `fdd21746`. `optional_defaults_test` failed once in CI and passes
   here — watch it.
2. Ask the user: create GitHub repos `broodlang/observe-otlp` and `broodlang/sqlite`, cut brood
   0.44.0, publish both to hive.
3. Gaps still open (`general-purpose-gaps.md`): M2 shared IC tables and the other runtime
   memory items (benchmark-gated — the test machine); re-timing the 2026-10-23 load-path work;
   a C embedding API; `:wasm-build` build-on-fetch; HTTP/2, gRPC, Redis, MySQL packages;
   W3C `traceparent`.
4. The installed nest (`~/.local/bin`, 0.43.0 `ad576651`) predates everything above;
   `make install` from a clean worktree when wanted.

## Decisions

- **Gap 8 (errors) was a stale ROADMAP line.** ADR-310/315 chose failure VALUES over
  `[:ok]`/`[:error]` tuples and rejected `result`/`unwrap` by name; building the tuple plan
  would have reversed a recorded decision. Only the stragglers were converted.
- WASI: clocks and randomness come with any grants map; the network never does.
- A package ships a component by `include-bytes` (the package hash is the pin); no `:native`
  manifest clause.
- SQLite runs on `unix-none` (no locks): one handle per file, and the handle is a process.

## Traps

- **No benchmarks, stress runs or heavy brood suites on this desktop** (global CLAUDE.md);
  bedit's `nest test` and a single brood test file are fine. Push brood with `--no-verify`.
- Brood work goes in a worktree with its OWN `target/` — never the primary checkout's, which
  other sessions rebuild. Check `nest --version` before trusting a run; `target/debug/brood`
  is only rebuilt by `cargo build --bin brood`.
- Brood ADR numbers collide across sessions: `git grep '^## ADR-NNN' origin/main` before
  pushing. Next free after this session: 455.
- Main's CI keeps only one pending run; rapid pushes cancel the ones queued behind. A red
  run can hide behind a column of "cancelled".
- The checker carries an argument's type through a function that may return it (`native-name`
  returned `export` in its else branch): pass a typed value at the call site.
- `nest format` takes no file arguments: `nest format --changed [--check]`.

## Environment

- bedit `~/src/broodlang/bedit` on `main`, clean, equal to origin/main.
- brood primary `~/src/broodlang/brood`: other sessions' work — leave it. This session's
  worktree is `~/.cache/brood-wt-defwarn` (branch `docs-wasm`, at origin/main); remove it with
  `git worktree remove` when done.
- Installed this session: Rust target `wasm32-wasip2`; wasi-sdk 25 in `~/.local/share`.
