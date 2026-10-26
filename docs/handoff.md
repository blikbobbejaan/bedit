# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in brood's `docs/devlog.md`; decisions in brood's `docs/decisions/`; the open backlog is
[`../issues.md`](../issues.md). Read this to pick the work back up cold.

## State when written — 2026-10-26, morning

Released and published; everything committed and pushed.

- **brood v0.44.0** (tag on `bd75fb95`, merged into main as `0884b0b0`): WASI by grant
  (ADR-453), `include-bytes` (ADR-454), typed parameters, sorted collections, process
  registry and groups, `defapp`/`defstatem`, crypto, UDP, TLS ALPN, `nest dap`, std `vcs`,
  `os/shell-split`, `path/substitute`. The CHANGELOG had recorded about a quarter of the 229
  commits since 0.43.0; the release commit filled it in, including two **breaking** changes
  (`gen/start-link`/`gen/start-named` gone, ADR-433; tempo/resolver answer failures).
- **bedit v0.7.0** (`f85847ca`): the floor is brood 0.44.0 — the first release since v0.6.1
  that a released toolchain can run. All 59 issues from the 2026-09-23 review are fixed.
- **hive**: `observe-otlp 0.1.0` and `sqlite 0.1.0` published; repos
  `broodlang/observe-otlp` and `broodlang/sqlite` created (public).
- **path/substitute moved to brood std** (`efd919d1`): `path/expand-env`, `path/escape-env`,
  `path/substitute`, `path/substitute-start` (Emacs's `substitute-in-file-name`; a `keep?`
  predicate keeps path pure, ADR-234). bedit's `filename.blsp` is now the prompt's layer only.

## Next

1. The installed nest is 0.44.0 (`bd75fb95`, GUI build); its worktree has been removed.
2. `todo.md` is stale except one bug: a slight jitter when editing a markdown file. No commit
   addresses it; reproduce before assuming it is gone.
3. Brood gaps still open (`../brood/docs/general-purpose-gaps.md`): runtime memory items
   (benchmark-gated — the test machine), re-timing the load-path work, a C embedding API,
   `:wasm-build` build-on-fetch, HTTP/2 / gRPC / Redis / MySQL packages, W3C `traceparent`.
4. `toolchain.blsp` (marker file → compile/test/run commands) was weighed for std and left
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
  Next free: 455.
- A release's CHANGELOG is checked only for its heading — read `git log vPREV..` and fill
  in what is missing before tagging.
- `nest format` takes no file arguments: `nest format --changed [--check]`.
