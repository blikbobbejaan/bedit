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

1. `nest check` over the whole project — a gate: it exits non-zero on any warning, so a
   finding only one OS's checker reports fails that OS's job;
2. `nest run --check-boot` — every module loads and `:main` resolves;
3. the smoke set (the script says what each file is there for): `conventions_test` and
   `editorconfig_test` (save with CRLF, with a BOM, a new file's `end_of_line` / `charset`),
   `filename_test` (typed paths: `~`, `$VAR`, `//`, names with `$` and spaces),
   `shell_command_test` (M-! spawning, C-g stopping it), `bshell_test` (the project shell: a
   line through the platform's shell, C-c C-c ending it), `compile_test` (error locations,
   `C:\src\a.c:12:5:` included), `platform_test` (LSP file URIs with a drive, a UNC share and
   VS Code's `c%3A`; the walk up to a project root ending at the filesystem's top; a URL handed
   to the desktop's opener — a stub, no browser is started), `clipboard_test` (the kill ring
   over the clipboard seam), `keymaps_test` and `userkeys_test` (key profiles, init.blsp key
   strings), `startup_test` (the missing-font warning), `recover_test` (auto-save sidecars,
   their owner-only permission read back on both OSes).

That script runs under bash — on Windows Git Bash, which sets `HOME` and puts `sh` on `PATH`,
neither of which a Windows desktop launch has. So Windows runs a second step under
PowerShell with `HOME` removed and Git's `sh` taken off `PATH` (the step fails if either is
still there): the boot check, then `shell_command_test`, `bshell_test`, `compile_test`,
`platform_test`, `recover_test` and `startup_test`, so the home really comes from
`%USERPROFILE%` and no shell command can lean on `sh`.

Every run sends the project shell's history to a temp file (`BSHELL_HISTORY`); run the suite
locally the same way, with `HOME` a temp directory too, or a test's commands land in your own
history.

Below it, brood's own CI runs its platform smoke set on both OSes (brood
`docs/build-and-ci.md`), including the gui's key translation unit tests — macOS's
Option-as-Meta and Windows's AltGr (brood ADR-541).

## Per concern

| concern | macOS | Windows |
|---|---|---|
| paths: home, temp, absolute, `~` (brood ADR-592) | ✅ | ✅ — `C:/…` and `//server/share/` roots, a root its own parent; the home is `%USERPROFILE%` when no `HOME` (run with `HOME` unset) |
| absolute-path checks (find-file, results jumps, git file prompts, completion, marginalia) | ✅ | ✅ `path/absolute?`, so `C:/x` is not read as relative |
| the walk up to a project root | ✅ | ✅ ends at `C:/` |
| LSP file URIs | ✅ | ✅ `file:///C:/x`, a server's `file:///c%3A/x` read back (brood `path/to-file-uri` / `from-file-uri`) — unit-tested; no language server is run in CI |
| compile / results locations | ✅ | ✅ a drive path (`C:\src\a.c:12:5:`) is one file |
| CRLF and BOM kept through find-file / save | ✅ | ✅ |
| names with spaces and non-ASCII | ✅ | ✅ |
| shell commands (M-!, M-\|, compile, the project shell) | ✅ `sh -c` | ✅ `cmd.exe /d /s /c` after `chcp 65001` (UTF-8 output), the line passed raw, in a hidden console of its own (brood `os/shell-cmd`, KI-364 fixed) — written in cmd's language there; a line with a newline in it is refused (cmd runs one line) |
| C-c C-c in the project shell | ✅ SIGINT to the command's group | ✅ the command's whole tree stopped (brood `os/interrupt`; Windows has no SIGINT for a piped child) |
| finding programs (`nest`, `mur`, LSP servers) | ✅ | ✅ PATHEXT applied (`tsc` finds `tsc.cmd`, `nest` beside the editor is `nest.exe`) |
| a URL to the browser (M-x mur-browse) | ✅ `open` | ✅ the URL handler, detached and out of the editor's Job Object — CI checks the hand-over through a stub, not a browser |
| clipboard seam | ✅ | ✅ |
| key mapping (Option-as-Meta, AltGr) | ✅ brood unit tests | ✅ brood unit tests |
| missing-font warning | ✅ (names Font Book) | ✅ (names the Fonts settings) |
| auto-save sidecars: location, recovery | ✅ | ✅ |
| auto-save sidecars: owner-only | ✅ mode 0600 | ✅ a one-entry DACL (brood `file/spit-private`, KI-365 fixed; `recover_test` reads the sidecar's ACL back with `icacls`) |
| terminal buffers (C-x p t, M-x claude) | not in the set | ❌ no pty on Windows (brood KI-369, ConPTY); the command says so instead of failing |
| a real window, font discovery, file watching (auto-revert) | not run — headless | not run — headless |

## Fixed on the way

- bedit's config directory, LSP home and mur lookup read `$HOME` directly; on Windows a native
  shell sets none. They use `path/home` now.
- A projectless eval child started in `/tmp`, which Windows lacks; it starts in
  `path/temp-root`.
- The missing-font warning told every user to run `fc-list`, which exists on Linux only.
- On Windows, C-g on a running M-! killed only the shell; the command it started kept
  running and kept the output pipe open, so the task waited it out. Brood's `os/cmd` now runs
  the child in a Job Object (brood ADR-592).
- On Windows, `$HOME` is `C:\Users\…` while the editor names the home `C:/Users/…`; a typed
  `/x/C:/y` now starts over at the drive, as Emacs reads it there (brood ADR-592).

- Tests aged files with GNU `touch -d "1 hour ago"`, which macOS's `touch` does not read;
  they use `touch -t`.

- M-x mur-browse opened URLs with `open` / `xdg-open` through `sh`; it uses brood's `os/open`
  now (on Windows the URL protocol handler), started detached.
- M-!, M-|, compile and the project shell named `sh`; they run through brood's platform shell
  now (`cmd.exe` on Windows, the line passed raw).
- C-c C-c in the project shell sent SIGINT, which Windows has no way to deliver to a piped
  child; it uses `os/interrupt`, which stops the command's tree there, and a command already
  gone is no error.
- LSP URIs were built as `file://` + the path, so a Windows path went out as `file://C:/x`
  (a host named `C:`) and a server's `file:///c%3A/x` came back as `/c:/x`.
- Absolute paths were recognised by a leading `/`, so `C:/x` was joined under the project
  root in results jumps, git file prompts, completion and the file marginalia.
- Error locations split `C:\src\a.c:12:5:` at the drive's colon.
- The eval child beside the editor was looked for as `nest`, never `nest.exe`; the eval
  child's default directory and the Erlang cookie path were fixed when the module loaded,
  before a desktop launch's environment was known; they are asked when used.
- The share name and sudo's prompt read `$USER`, which Windows does not set; they use
  `os/user-name` (`%USERNAME%` there).

## Not fixed
- Terminal buffers and the line-mode REPL need a pty; Windows has none in brood (KI-369: ConPTY
  needs a second child type in brood's subprocess registry). bedit says so when one is asked for.
- Not run anywhere but Linux: a real window, font discovery, file watching, a language server,
  git and mur themselves (their test files are not in the smoke set), and the remote / collab
  node links.
