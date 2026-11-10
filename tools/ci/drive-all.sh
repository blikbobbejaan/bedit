#!/usr/bin/env bash
# Every live driver (tools/drive-*.blsp, tools/README.md) in CI (.github/workflows/drive.yml):
# the real editor over a pty, or its own loop over a scripted frontend, asserting on what it
# paints — the wiring `nest test` cannot see. `make drive` stops at the first failure; this
# runs each one, so one red driver does not hide the rest, and keeps each one's output.
#
#   tools/ci/drive-all.sh NEST OUT [tools/drive-x.blsp ...]
#
# NEST's directory goes first on PATH: a pty driver starts the editor with the `nest` it finds
# there (`drive.blsp`), and the sandbox finds its runtime beside it. OUT gets one log per
# driver and summary.txt. With no drivers named, every tools/drive-*.blsp runs.
# DRIVE_TIMEOUT_S bounds each driver (default 600). Exits non-zero when any driver failed.
set -uo pipefail

nest="${1:?usage: drive-all.sh NEST OUT [driver ...]}"
out="${2:?usage: drive-all.sh NEST OUT [driver ...]}"
shift 2

nest_dir="$(cd "$(dirname "$nest")" && pwd)"
export PATH="$nest_dir:$PATH"
command -v nest >/dev/null || { echo "drive-all.sh: no nest in $nest_dir" >&2; exit 2; }

# Nothing of the runner's own config: each driver's editor keeps its state in a scratch home
# (a driver that needs two sessions to share one, drive-progress, makes its own).
export BROOD_GUI_HEADLESS=1
scratch="$(mktemp -d)"
export XDG_CONFIG_HOME="$scratch/config" XDG_STATE_HOME="$scratch/state" XDG_DATA_HOME="$scratch/data"

mkdir -p "$out"
out="$(cd "$out" && pwd)"
# the drivers find their harness and entry points from the project root
cd "$(dirname "$0")/../.." || exit 2
timeout_s="${DRIVE_TIMEOUT_S:-600}"

if [ "$#" -gt 0 ]; then
  drivers=("$@")
else
  drivers=(tools/drive-*.blsp)
fi

passed=()
failed=()
for driver in "${drivers[@]}"; do
  name="$(basename "$driver" .blsp)"
  log="$out/$name.log"
  echo "::group::$name"
  start=$(date +%s)
  timeout --kill-after=30 "$timeout_s" nest run "$driver" > "$log" 2>&1
  status=$?
  seconds=$(( $(date +%s) - start ))
  cat "$log"
  echo "::endgroup::"
  if [ "$status" -eq 0 ]; then
    passed+=("$name")
    echo "ok    $name (${seconds}s)" | tee -a "$out/summary.txt"
  else
    failed+=("$name")
    reason="exit $status"
    [ "$status" -eq 124 ] && reason="timed out after ${timeout_s}s"
    echo "FAIL  $name ($reason, ${seconds}s)" | tee -a "$out/summary.txt"
    echo "::error title=$name failed::$reason — see the $name.log artifact"
  fi
done

echo "${#passed[@]} passed, ${#failed[@]} failed" | tee -a "$out/summary.txt"
[ "${#failed[@]}" -eq 0 ]
