#!/usr/bin/env bash
# bedit's REAL-window check (.github/workflows/ci.yml, `platform-smoke` and `real-window-linux`):
# the editor started through `main` on a file, in a window on a real display — no
# BROOD_GUI_HEADLESS — typed into, saved with C-x C-s, the file read back from disk and the
# window captured (`gui/capture`) and checked not blank. tools/ci/real-window.blsp is the
# driver and says what each step proves; this is the glue that gives it a display.
#
#   tools/ci/real-window.sh NEST OUT-DIR [desktop|x11|wayland]
#
#   desktop   the session the runner already has: macOS's logged-in GUI session, Windows's
#             interactive desktop (the default)
#   x11       a private Xvfb (xvfb-run), WAYLAND_DISPLAY removed so the window cannot land on
#             a desktop of the caller's
#   wayland   a private headless Weston (`weston --backend=headless`), DISPLAY removed
#
# OUT-DIR gets before.png / after.png (and os-input.png, failure.png), saved.txt (the file
# as the editor wrote it) and editor.log (everything the editor and the driver printed).
#
# REAL_WINDOW_OS_INPUT (require | try | off) says whether the driver also types through the
# OS's own input (xdotool on X11, SendKeys on Windows, System Events on macOS); by default
# `require` under x11 when xdotool is installed, `try` on a desktop, `off` under wayland (no
# input tool reaches a headless Weston). REAL_WINDOW_TIMEOUT_MS bounds the whole run
# (default 300000): past it the editor is killed and the check fails.
set -euo pipefail

nest="${1:?usage: real-window.sh NEST OUT-DIR [desktop|x11|wayland]}"
out="${2:?usage: real-window.sh NEST OUT-DIR [desktop|x11|wayland]}"
display_kind="${3:-desktop}"

mkdir -p "$out"
log="$out/editor.log"
: >"$log"

# The point of the run is a window on a display, never one painted offscreen.
unset BROOD_GUI_HEADLESS

run_driver() {
  # $1: the OS-input mode; the rest: what to run the driver under (xvfb-run …), if anything.
  local os_input="$1"
  shift
  echo "== real window ($display_kind), OS input: $os_input"
  set +e
  "$@" "$nest" run tools/ci/real-window.blsp -- "$out" --os-input "$os_input" 2>&1 | tee -a "$log"
  local code="${PIPESTATUS[0]}"
  set -e
  if [ "$code" != 0 ]; then
    echo "== real window FAILED (exit $code): $log has the editor's output; the pictures are in $out" >&2
    ls -l "$out" >&2 || true
  fi
  return "$code"
}

case "$display_kind" in
  desktop)
    run_driver "${REAL_WINDOW_OS_INPUT:-try}"
    ;;
  x11)
    command -v xvfb-run >/dev/null || { echo "real-window.sh: xvfb-run is not installed" >&2; exit 2; }
    unset WAYLAND_DISPLAY
    if command -v xdotool >/dev/null; then default_input=require; else default_input=off; fi
    # -a: a free display number; 24-bit colour, so the picture's colours are the theme's
    run_driver "${REAL_WINDOW_OS_INPUT:-$default_input}" \
      xvfb-run -a -s "-screen 0 1280x800x24 -nolisten tcp"
    ;;
  wayland)
    command -v weston >/dev/null || { echo "real-window.sh: weston is not installed" >&2; exit 2; }
    unset DISPLAY
    if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "$XDG_RUNTIME_DIR" ]; then
      XDG_RUNTIME_DIR="$(mktemp -d)"
      chmod 700 "$XDG_RUNTIME_DIR"
      export XDG_RUNTIME_DIR
    fi
    socket="bedit-real-window-$$"
    weston --backend=headless --renderer=pixman --width=1280 --height=800 --idle-time=0 \
      --socket="$socket" >"$out/weston.log" 2>&1 &
    weston_pid=$!
    trap 'kill "$weston_pid" 2>/dev/null || true' EXIT
    waited=0
    until [ -S "$XDG_RUNTIME_DIR/$socket" ]; do
      if ! kill -0 "$weston_pid" 2>/dev/null || [ "$waited" -ge 100 ]; then
        echo "real-window.sh: weston did not start (its log follows)" >&2
        cat "$out/weston.log" >&2
        exit 1
      fi
      sleep 0.1
      waited=$((waited + 1))
    done
    export WAYLAND_DISPLAY="$socket"
    run_driver "${REAL_WINDOW_OS_INPUT:-off}"
    ;;
  *)
    echo "real-window.sh: unknown display kind '$display_kind' (desktop, x11 or wayland)" >&2
    exit 2
    ;;
esac
