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

### The real window

Everything above is headless. After it, the same job runs `tools/ci/real-window.sh` (the
driver is `tools/ci/real-window.blsp`): bedit started through `main` on a file — the editor
`nest run FILE` runs, with its startup, init file, fonts, timers and lifeline supervisor — in a
window on the runner's own desktop, no `BROOD_GUI_HEADLESS`, with a throwaway `HOME`,
`USERPROFILE` and XDG dirs. What it relies on: a GitHub-hosted macOS runner is a logged-in GUI
session (the Aqua session the runner agent runs in), and a hosted Windows runner runs its jobs
in an interactive desktop session, so a window opens on both; neither is documented as a
promise by GitHub, so a change on their side shows up here as "the editor opened no window".

1. it waits for the window and the loop, captures the window (`gui/capture`: the live
   window's frame rasterised by its own renderer, brood ADR-609 — no screen-recording
   permission is involved) and fails when the first text row is only background;
2. **loop input**: it types `loop-input ` and C-x C-s as the window delivers keys to the loop
   (sent to the loop's mailbox by its registered name), waits for the file ON DISK to start
   with them, captures again and fails unless the first text row's pixels changed;
3. **OS input**: it types `os-input ` and C-x C-s through the OS's own input — System Events'
   `keystroke` on macOS, `WScript.Shell.SendKeys` on Windows — and waits for the file to have
   it. That is the window's real keyboard path, the frontend's key translation included. It
   is TRIED and reported, not required, on both: a hosted macOS runner may refuse it
   (Accessibility permission for `osascript`, error 1002) and Windows's foreground lock may
   keep the window from taking the keys. The log says which (`OS input: NOT proven …`). (Until
   2026-11-09 the driver waited for the OS-typed word at the START of the file, though the keys
   land at point, after the loop phase's word; with that fixed, both runners' OS typing was
   seen arriving on the first run — a candidate for `require` once it holds.)

The step has a timeout (the driver kills the editor past `REAL_WINDOW_TIMEOUT_MS`, the step's
`timeout-minutes` backs it), and the pictures (`before.png`, `after.png`, `os-input.png`,
`failure.png` on a failure), the file as saved (`saved.txt`) and everything the editor printed
(`editor.log`) are uploaded as the `real-window-<os>` artifact whether it passed or not.

Linux gets the same check in a job of its own, `real-window-linux`, twice: under a private
Xvfb, where the OS input is REQUIRED — xdotool gives the window the input focus
(XSetInputFocus, which needs no window manager), puts the pointer over it, and types through
XTEST to whatever has the focus, as a real keyboard does. Each xdotool call is its own command:
in one chained call (`search … type …`) `type` and `key` default to the window `search` found
and send XSendEvent events, which are synthetic and which winit, reading keys through XInput2,
never sees — CI's first runs typed with exit 0 and the file never changed. The log says which
window had the focus before and after the keys. And under a headless Weston
(`weston --backend=headless`), where only the loop input runs (no input tool reaches a headless
Weston), so winit's Wayland backend opens, paints and saves too. Locally:
`tools/ci/real-window.sh nest /tmp/rw x11` (needs `xvfb-run` and `xdotool`; opens nothing on
your screen).

What it does not prove: what the compositor does with the frame after the window presents
it (the capture is the app's own rasterisation — ADR-609's limit), a GPU window (CI builds
the CPU painter), the mouse, an input method, and on macOS and Windows the OS keyboard path
whenever the log says `NOT proven`.

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
| a save survives a crash mid-write | ✅ `file/replace`: a synced temp file renamed over the file (brood ADR-621), owner, mode and a symlink kept | ⚠️ a plain write in place (`file/replace` is `fs::write` off Unix: a rename there loses the file's DACL, and `ReplaceFileW` is untried) — see Not fixed |
| auto-save sidecars: location, recovery | ✅ | ✅ |
| auto-save sidecars: owner-only | ✅ mode 0600 | ✅ a one-entry DACL (brood `file/spit-private`, KI-365 fixed; `recover_test` reads the sidecar's ACL back with `icacls`) |
| terminal buffers (C-x p t, M-x claude) | ✅ `sh -c` under a pty | ✅ `cmd.exe` under ConPTY (brood KI-369 fixed, ADR-597); a password read is found by the prompt's text, since ConPTY has no echo mode to ask |
| a real window: opens on the desktop, paints (captured, not blank), typed keys reach the loop, C-x C-s writes the file | ✅ `real-window.sh` | ✅ `real-window.sh` (Linux too: Xvfb and headless Weston) |
| the OS keyboard reaching that window | tried each run (System Events), reported, not required | tried each run (SendKeys), reported, not required; Linux: required, xdotool (XTEST) under Xvfb |
| font discovery, file watching (auto-revert) | not run — headless | not run — headless |

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

- Tests aged files with GNU `touch -d "1 hour ago"`, which macOS's `touch` does not read,
  then with `touch -t`, which a Windows desktop does not have at all (the PowerShell step
  found it); they use brood's `file/set-mtime` now, no program.

- M-x mur-browse opened URLs with `open` / `xdg-open` through `sh`; it uses brood's `os/open`
  now (on Windows the URL protocol handler), started detached.
- M-!, M-|, compile and the project shell named `sh`; they run through brood's platform shell
  now (`cmd.exe` on Windows, the line passed raw).
- Terminal buffers and the line-mode REPL need a pty, which Windows lacked in brood (KI-369);
  brood drives ConPTY now (ADR-597), and the terminal runs its command through the platform
  shell (`os/shell-spawn-pty`). A Windows older than 10 1809 has no ConPTY: the buffer says
  the program cannot start, on its screen.
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
- A save on Windows is not atomic. brood's `file/replace`, which every save goes through
  (`file-save`, `charset/save`), renames a synced temp file over the file on Unix, but off Unix
  it is a plain write: the file is truncated, then written (brood ADR-621, Limits). A crash, a
  power cut or a full disk between the two leaves the file empty or cut short, and the text is
  then only in the buffer and in its auto-save sidecar if the idle beat wrote one (`#file#`, M-x
  recover-this-file) — edits made after that sidecar are lost with the editor. A program reading the file while it is
  written can see half of it. Fixing it is brood's (`ReplaceFileW`, which keeps the DACL).
- Not run anywhere but Linux: font discovery, file watching, a language server,
  git and mur themselves (their test files are not in the smoke set), and the remote / collab
  node links.
