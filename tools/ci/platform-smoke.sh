#!/usr/bin/env bash
# bedit's macOS / Windows smoke run (.github/workflows/ci.yml, `platform-smoke`): the
# checker over the whole project, the boot check, and the test files where the OS shows
# through. Linux runs the full suite (brood's package-ci); this is the part of it whose
# answer could differ on another OS, so it is the part run there. On Windows it ends with
# tools/ci/windows-proofs.blsp: a crashing grammar quarantined, file/replace on FAT32, a
# SUBST drive and a UNC share.
#
#   tools/ci/platform-smoke.sh path/to/nest
#
# Headless (BROOD_GUI_HEADLESS=1): a runner has no display, and the clipboard, fonts and
# window all answer as they do with none. The shell history goes to a temp file
# (BSHELL_HISTORY): a test's commands never land in a real history.
#
# Every step is a GATE: `nest check` (weekly, see below) exits non-zero on any warning, and `set -e` stops the
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

# The whole-project checker on this OS: in the weekly full run (and on dispatch) only, when
# the caller sets PLATFORM_CHECK=1. It is most of this script's time on Windows (~90 s of a
# debug-built nest), and Linux runs the same check on every push; what only another OS's
# checker would report (an OS-gated branch) is rare enough for once a week.
if [ "${PLATFORM_CHECK:-0}" = 1 ]; then
  echo "== nest check"
  "$nest" check
else
  echo "== nest check: skipped (per push; the weekly run has PLATFORM_CHECK=1)"
fi

echo "== nest run --check-boot"
"$nest" run --check-boot

echo "== platform smoke on $(uname -s): ${smoke[*]}"
"$nest" test "${smoke[@]}"

# Windows only: what brood does there that its unit tests reach only as compiled code
# (tools/ci/windows-proofs.blsp says what each proof checks). A proof whose setup this runner
# cannot give (no C compiler, no admin rights for a VHD, no admin share) is SKIPPED with a
# warning, never passed; one that runs is a gate.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) ;;
  *) exit 0 ;;
esac

proofs_scratch="$(mktemp -d)"
not_proven() {
  echo "::warning title=Windows proof skipped::$*"
  echo "== NOT proven: $*"
}
drive_free() {
  # Git Bash shows drive X: as /x/
  [ ! -d "/$(echo "$1" | tr 'A-Z' 'a-z')/" ]
}
free_letter() {
  local letter
  for letter in "$@"; do
    if drive_free "$letter"; then
      echo "$letter"
      return 0
    fi
  done
  return 1
}

# 1. a crashing grammar quarantined: by its vetting child, and by a runtime it crashed
compiler="$(command -v gcc || command -v clang || true)"
if [ -n "$compiler" ]; then
  echo "== a crashing grammar on Windows (built with $compiler)"
  mkdir -p "$proofs_scratch/state" "$proofs_scratch/cache"
  XDG_STATE_HOME="$(cygpath -w "$proofs_scratch/state")" \
    XDG_CACHE_HOME="$(cygpath -w "$proofs_scratch/cache")" \
    "$nest" run tools/ci/windows-proofs.blsp -- grammar "$(cygpath -w "$compiler")"
else
  not_proven "the grammar quarantine: no gcc or clang on PATH to build a crashing grammar"
fi

# 2. file/replace (an editor's save) where ReplaceFileW may be refused
replace_dirs=()

# a FAT32 volume: a VHD made, formatted and mounted by diskpart (admin, which a hosted runner is)
vhd="$(cygpath -w "$proofs_scratch")\\bedit-fat.vhd"
if fat_letter="$(free_letter R Q P O)"; then
  printf '%s\r\n' "create vdisk file=\"$vhd\" maximum=100 type=fixed" "select vdisk file=\"$vhd\"" \
    "attach vdisk" "create partition primary" "format fs=fat32 quick label=BEDITFAT" \
    "assign letter=$fat_letter" >"$proofs_scratch/fat.txt"
  if powershell -NoProfile -NonInteractive -Command \
    "diskpart /s '$(cygpath -w "$proofs_scratch/fat.txt")'; exit \$LASTEXITCODE" &&
    ! drive_free "$fat_letter"; then
    echo "== $fat_letter: is $(powershell -NoProfile -NonInteractive -Command "(Get-Volume -DriveLetter $fat_letter).FileSystem" | tr -d '\r')"
    replace_dirs+=("$fat_letter:\\")
  else
    not_proven "file/replace on FAT32: diskpart could not make and mount the VHD"
  fi
else
  not_proven "file/replace on FAT32: no free drive letter"
fi

# a SUBST drive over a scratch directory
mkdir -p "$proofs_scratch/subst" "$proofs_scratch/share"
subst_letter=""
if subst_letter="$(free_letter S T U V)" && subst "$subst_letter:" "$(cygpath -w "$proofs_scratch/subst")"; then
  replace_dirs+=("$subst_letter:\\")
else
  subst_letter=""
  not_proven "file/replace on a SUBST drive: subst failed"
fi

# a UNC path through this machine's own admin share (\\localhost\D$\…)
share_dir="$(cygpath -w "$proofs_scratch/share")"
unc="\\\\localhost\\${share_dir:0:1}\$${share_dir:2}"
if [ -d "$(cygpath -u "$unc")" ]; then
  replace_dirs+=("$unc")
else
  not_proven "file/replace on a network share: $unc is not reachable (no admin share)"
fi

if [ "${#replace_dirs[@]}" -gt 0 ]; then
  echo "== file/replace in: ${replace_dirs[*]}"
  "$nest" run tools/ci/windows-proofs.blsp -- replace "${replace_dirs[@]}"
fi

# put the machine back
if [ -n "$subst_letter" ]; then
  MSYS2_ARG_CONV_EXCL='*' subst "$subst_letter:" /d >/dev/null 2>&1 || true
fi
if [ -f "$proofs_scratch/bedit-fat.vhd" ]; then
  printf '%s\r\n' "select vdisk file=\"$vhd\"" "detach vdisk" >"$proofs_scratch/detach.txt"
  powershell -NoProfile -NonInteractive -Command \
    "diskpart /s '$(cygpath -w "$proofs_scratch/detach.txt")'" >/dev/null 2>&1 || true
fi
