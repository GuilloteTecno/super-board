#!/usr/bin/env bash
# Runs the super-collect custom-source tests (onboard's "➕ Add another source"). No network.
#   bash tests/test-collect-custom.sh
set -euo pipefail
# python3 may be a Windows Store stub: put a working `python3` shim on PATH (also covers shebangs).
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/super-board-python.sh"; sb_python_init || exit 1
sb_python_shim
exec python3 "$(cd "$(dirname "$0")" && pwd)/test_collect_custom.py"
