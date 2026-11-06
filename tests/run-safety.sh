#!/usr/bin/env bash
# Offline release checks. Keep test-* / test_* suites offline; paid evals live in evals/.
# Run every suite even after a failure, then fail the whole gate if any suite failed.
set -uo pipefail
cd "$(dirname "$0")/.."

for tool in bash git jq node curl tar; do
  command -v "$tool" >/dev/null || { echo "Missing test dependency: $tool" >&2; exit 1; }
done
# shellcheck source=../scripts/super-board-python.sh
. "$(pwd)/scripts/super-board-python.sh"
sb_python_init || exit 1
# python3 broken (Windows Store stub)? Give child shells and shebangs a working `python3` too.
_had_shim=${SB_PYTHON_SHIM_DIR:-}
sb_python_shim || exit 1
if [ -z "$_had_shim" ] && [ -n "${SB_PYTHON_SHIM_DIR:-}" ]; then
  trap 'rm -rf "$SB_PYTHON_SHIM_DIR"' EXIT
fi

# SB_SUITE_TIMEOUT=<seconds> bounds each suite (a hung suite fails instead of stalling the gate).
run_suite() {
  if [ -n "${SB_SUITE_TIMEOUT:-}" ] && command -v timeout >/dev/null 2>&1; then timeout "$SB_SUITE_TIMEOUT" "$@"; else "$@"; fi
}

shopt -s nullglob
suites=(tests/test-*.sh tests/test_*.py)
[ "${#suites[@]}" -gt 0 ] || { echo 'No safety suites found' >&2; exit 1; }
failed=()
for suite in "${suites[@]}"; do
  echo "::group::$suite"
  case "$suite" in
    *.sh) run_suite bash "$suite" ;;
    *.py) run_suite "$SB_PYTHON" "$suite" ;;
  esac
  rc=$?
  echo '::endgroup::'
  if [ "$rc" -ne 0 ]; then
    failed+=("$suite")
    echo "::error::$suite failed (exit $rc)"
  fi
done
if [ "${#failed[@]}" -gt 0 ]; then
  printf 'Failed suite: %s\n' "${failed[@]}" >&2
  exit 1
fi
echo "PASS: ${#suites[@]} safety suites"
