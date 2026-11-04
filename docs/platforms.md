# bedit on macOS and Windows — what is proven, and what is not

bedit's design avoids several classes of Emacs's per-platform bugs by standing on Brood:
paths are one `/` form, files are bytes (no text-mode newline translation), the clipboard and
keys come through one gui seam, spawning is one `os/cmd`. Until 2026-11-04 that was a claim:
CI built and tested on Linux only. This file says what is now RUN on each OS, and what is still
only claimed.

## What runs

`.github/workflows/ci.yml`'s `platform-smoke` job, on `macos-15` and `windows-latest`: a `nest`
built from brood for that OS with the gui, headless (`BROOD_GUI_HEADLESS=1`), runs
`tools/ci/platform-smoke.sh` —

1. `nest check` over the whole project;
2. `nest run --check-boot` — every module loads and `:main` resolves;
3. the smoke set (the script says what each file is there for): `conventions_test` and
   `editorconfig_test` (save with CRLF, with a BOM, a new file's `end_of_line` / `charset`),
   `filename_test` (typed paths: `~`, `$VAR`, `//`, names with `$` and spaces),
   `shell_command_test` (M-! spawning, C-g stopping it), `clipboard_test` (the kill ring over
   the clipboard seam), `keymaps_test` and `userkeys_test` (key profiles, init.blsp key
   strings), `startup_test` (the missing-font warning), `recover_test` (auto-save sidecars).

Below it, brood's own CI runs its platform smoke set on both OSes (brood
`docs/build-and-ci.md`), including the gui's key translation unit tests — macOS's
Option-as-Meta and Windows's AltGr (brood ADR-541).

## Per concern

| concern | macOS | Windows |
|---|---|---|
| paths: home, temp, absolute, `~` (brood ADR-592) | ✅ | ✅ — `C:/…` roots; the home is `%USERPROFILE%` when no `HOME` |
| CRLF and BOM kept through find-file / save | ✅ | ✅ |
| names with spaces and non-ASCII | ✅ | ✅ |
| shell commands (M-!, M-\|, compile, the project shell) | ✅ | ⚠️ only where an `sh` is on PATH (Git for Windows, MSYS2) — brood KI-364 |
| clipboard seam | ✅ | ✅ |
| key mapping (Option-as-Meta, AltGr) | ✅ brood unit tests | ✅ brood unit tests |
| missing-font warning | ✅ (names Font Book) | ✅ (names the Fonts settings) |
| auto-save sidecars: location, recovery | ✅ | ✅ |
| auto-save sidecars: owner-only | ✅ | ❌ not private beyond the directory's ACL — brood KI-365 |
| terminal buffers (C-x p t, M-x claude) | not in the set | ❌ no pty on Windows (brood's `spawn_pty` is Unix only) |
| a real window, font discovery, file watching (auto-revert) | not run — headless | not run — headless |

## Fixed on the way

- bedit's config directory, LSP home and mur lookup read `$HOME` directly; on Windows a native
  shell sets none. They use `path/home` now.
- A projectless eval child started in `/tmp`, which Windows lacks; it starts in
  `path/temp-root`.
- The missing-font warning told every user to run `fc-list`, which exists on Linux only.
