# Handoff — what to do next, and the traps

**Replaced each session; this is the *current* picture, not history.** The narrative lives
in brood's `docs/devlog.md` (bedit's own [`devlog.md`](devlog.md) stops in July); decisions
in brood's `docs/decisions.md`; the open backlog is [`../issues.md`](../issues.md). Read
this to pick the work back up cold.

## State when written — 2026-10-19, afternoon

- **The std/bedit boundary (brood ADR-417).** A std module has to be a mechanism, have a
  user besides one application, and need to version with the kernel. Ten modules failed
  that and moved here with their tests: `editor/org` → `org`, `editor/transient` →
  `transient-core`, `editor/section` → `section`, `editor/formbuf` → `formbuf`, the format
  highlighters → `lex-configs` / `lex-shell` / `lex-dotenv` / `lex-dockerfile` /
  `lex-markdown`, and `mime` → `mail-message`. The new names avoid std's own (`markdown`,
  and `mime` on 0.41). CLAUDE.md's prime directive now separates a *capability* the
  language lacks (goes to Brood) from a *feature* (stays here) and lists the three
  questions. The highlighters and the mail parser become hive packages only when a second
  project wants them.
- **brood v0.42.0** is tagged (`b3deae5a`); its release workflow and CI passed, and it is
  installed (`nest 0.42.0`). `BEDIT_REF` points at bedit `00987e01` (the migration).
- **bedit v0.6.0** is released, published to hive and installed (`~/.local/bin/bedit`).
  It also carries the `format`/`term` fix that never shipped as 0.5.2.
- **The whole ecosystem moved to `:brood ">= 0.42.0"`** and the latest package releases,
  each tagged and published: store 0.6.2, s3 0.4.6, observe 0.1.2, store-postgres 0.8.1,
  hatch 0.28.1, observe-appsignal 0.1.2, observe-local 0.2.0 and mail 0.3.0 (both now on
  hatch ^0.28.1; were ^0.23), and the four themes 0.3.5. hive and mur-forge pin each
  package at its release commit. Every app (b2d, pong, pong2, swarm, brood-chat,
  brood-life, brood-terminal, mylife, zubr, zubr-relay, brood-benchmark) checks and tests
  green on 0.42.0. `mail-local` / `mail-mailjet` are archived (folded into mail 0.2) and
  were left alone.
- **hive** is deployed as Fly release v282 (hive `779c062`: brood `b3deae5a` in the
  Dockerfile, every package pinned at its 0.42 release). Live `/reference` lists 0.42.0;
  `/health` ok. The `fly deploy` client hung after pushing the image (the rollout itself
  completed) and was killed — confirm a deploy with `fly releases --app brood`, never the
  client's exit.
- brood's `scripts/release-ecosystem.blsp` now lists the whole train in dependency order;
  `PUBLISH=1 brood scripts/release-ecosystem.blsp` is the next release's path.
- Every repo is clean and in sync with origin, except hive's untracked `HANDOFF.md`
  (another session's note on the hatch accounts work; left for its owner).
- `issues.md` has no open items.

## Traps

1. **The disk is tight** (87% on 2026-10-19, ~80 GB free). A GUI `make install` needs ~6 GB
   under `target/release-fast`. Delete a worktree's `debug/` target once it is pushed.
2. **Another brood session pushes to `main` often** (the tier-0 / ADR-416 work). Expect to
   `git pull --rebase` before a push; its devlog and ADR appends conflict with yours at the
   file's end — keep both sides. Check `docs/decisions/adr-400-499.md` for the next free
   ADR number right before committing, not when you start.
3. **brood's pre-push hook refuses a nest whose baked-in std is older than the tree**
   (rebuild after a rebase), and runs `nest format --check` over all of std.
4. **`make smoke-bedit` with a plain debug nest fails six Ruby/Elixir mode tests** — no
   grammars. Build `cargo build -p nest --features brood/treesit-grammars` and call
   `NEST=… ./scripts/smoke-bedit.sh` directly (`make` did not pass `NEST` through).
5. **A mode's loading can only be checked in the built binary** (`make build` +
   `BEDIT=./bedit tools/check-modes.sh`).

## Work queue

1. Try `*lsp-log*` and the echo area live against Expert in an Elixir project.
2. HTML-only mail shows its raw HTML in `*Message*` (with a note). An HTML→text converter
   would let it render. Ask ADR-417's questions first: hatch's `web/markdown` and the
   docsite render HTML, so a converter may have users beyond bedit — or it lives here.
3. If a second project wants the `lex-*` highlighters or `mail-message`, extract them to
   hive packages (ADR-417).

## How to verify a change here

1. `nest check` clean; `BROOD_GUI_HEADLESS=1 nest test` (or per file); `nest test --failed`
   for the loop.
2. `nest format --changed` before committing — CI checks it.
3. `make check-modes` after a mode/service change; `make drive` for the live pty drivers.
4. After a brood change: `make install` (GUI) in brood, then `make install` here, then all
   of the above.
