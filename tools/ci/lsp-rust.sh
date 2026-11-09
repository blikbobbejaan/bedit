#!/usr/bin/env bash
# bedit's LSP features against a REAL rust-analyzer (.github/workflows/ci.yml,
# `lsp-rust-analyzer`): inlay hints, semantic tokens (and a delta), code lenses, refresh
# requests and a lens click that runs its command. tools/ci/lsp-rust.blsp is the driver and
# says what each check proves; this is the glue that makes sure the server is there.
#
#   tools/ci/lsp-rust.sh NEST
#
# Fails when rust-analyzer or cargo is missing: in CI a skipped run would read as a pass.
# LSP_RUST_DEADLINE_MS bounds the driver (default 300000).
set -euo pipefail

nest="${1:?usage: lsp-rust.sh NEST}"

command -v rust-analyzer >/dev/null || { echo "lsp-rust.sh: rust-analyzer is not on PATH" >&2; exit 2; }
command -v cargo >/dev/null || { echo "lsp-rust.sh: cargo is not on PATH" >&2; exit 2; }
# a rustup proxy passes `command -v` for a component that is not installed: ask it
rust-analyzer --version

# Headless, and nothing of the runner's own config: the driver opens no window, and the
# editor's state goes to a scratch home.
export BROOD_GUI_HEADLESS=1
scratch="$(mktemp -d)"
export XDG_CONFIG_HOME="$scratch/config" XDG_STATE_HOME="$scratch/state" XDG_DATA_HOME="$scratch/data"

"$nest" run tools/ci/lsp-rust.blsp
