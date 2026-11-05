#!/usr/bin/env bash
# bedit's macOS / Windows smoke run (.github/workflows/ci.yml, `platform-smoke`): the
# checker over the whole project, the boot check, and the test files where the OS shows
# through. Linux runs the full suite (brood's package-ci); this is the part of it whose
# answer could differ on another OS, so it is the part run there.
#
#   tools/ci/platform-smoke.sh path/to/nest
#
# Headless (BROOD_GUI_HEADLESS=1): a runner has no display, and the clipboard, fonts and
# window all answer as they do with none. The shell history goes to a temp file
# (BSHELL_HISTORY): a test's commands never land in a real history.
#
# Every step is a GATE: `nest check` exits non-zero on any warning, and `set -e` stops the
# run there — the platforms differ in what the checker sees (an OS-gated branch), so a
# finding only one OS reports fails that OS's job.
set -euo pipefail

nest="${1:?usage: platform-smoke.sh NEST}"
export BROOD_GUI_HEADLESS=1
BSHELL_HISTORY="$(mktemp -d)/bshell-history.blsp"
export BSHELL_HISTORY

smoke=(
  # find-file / save: CRLF kept, a byte-order mark kept, .editorconfig's end_of_line and
  # charset applied to a new file — the line-ending bugs Emacs has had per OS.
  tests/conventions_test.blsp
  tests/editorconfig_test.blsp
  # typed paths: `~`, `$VAR`, `//` restarts, names with `$` and spaces, read under a
  # directory — what a find-file prompt makes of what a person types.
  tests/filename_test.blsp
  # M-! / M-| spawn a shell command off the loop, and C-g stops it.
  tests/shell_command_test.blsp
  # terminal buffers: a real shell under a pty (ConPTY on Windows, brood KI-369) answers
  # keys on its screen, and a program that cannot start is said there.
  tests/terminal_test.blsp
  # password reads: by the pty's echo mode on Unix; on Windows ConPTY knows none, so the
  # screen says nil and the prompt's text decides (brood ADR-570, ADR-597).
  tests/passwd_test.blsp
  # the project shell: a line through the platform's shell, C-c C-c ending it (a signal
  # on Unix, the process tree stopped on Windows).
  tests/bshell_test.blsp
  # M-x compile and every results buffer: error locations, a Windows drive's included.
  tests/compile_test.blsp
  # LSP file URIs (a drive, a UNC share, VS Code's c%3A), the walk up to a project root
  # ending at the filesystem's top, and a URL handed to the desktop's opener (stubbed).
  tests/platform_test.blsp
  # the kill ring over the OS clipboard seam, including a clipboard that never answers.
  tests/clipboard_test.blsp
  # keys: the emacs / vim profiles, and init.blsp's key strings parsed onto the layers.
  tests/keymaps_test.blsp
  tests/userkeys_test.blsp
  # startup: a font that is not installed is said (with this OS's way to list fonts),
  # and a theme's font files are not read by a daemon.
  tests/startup_test.blsp
  # auto-save sidecars: where they go, owner-only (0600; on Windows the one-entry DACL,
  # read back with icacls), and put back by M-x recover-this-file.
  tests/recover_test.blsp
)

echo "== nest check"
"$nest" check

echo "== nest run --check-boot"
"$nest" run --check-boot

echo "== platform smoke on $(uname -s): ${smoke[*]}"
"$nest" test "${smoke[@]}"
