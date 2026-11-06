#!/usr/bin/env bash
# Exercise aggregation with tiny fixtures; never recursively run the actual suite.
set -euo pipefail
PACK=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests"
mkdir -p "$WORK/scripts"
cp "$PACK/tests/run-safety.sh" "$WORK/tests/"
cp "$PACK/scripts/super-board-python.sh" "$WORK/scripts/"
fail() { echo "FAIL: $1" >&2; exit 1; }
if bash "$WORK/tests/run-safety.sh" >/dev/null 2>&1; then fail 'empty suite passed'; fi
printf 'exit 3\n' > "$WORK/tests/test-a-failure.sh"
printf 'echo reached\n' > "$WORK/tests/test-z-success.sh"
printf 'print("python reached")\n' > "$WORK/tests/test_python.py"
rc=0
out=$(bash "$WORK/tests/run-safety.sh" 2>&1) || rc=$?
[ "$rc" -eq 1 ] || fail "failed suite did not fail gate: $rc"
[[ "$out" == *reached* && "$out" == *'python reached'* ]] || fail 'failure hid later suites'
rm "$WORK/tests/test-a-failure.sh"
bash "$WORK/tests/run-safety.sh" >/dev/null || fail 'passing suites failed'

# A broken python3 (Windows Store stub, exit 9009) must not stop .py suites: resolver falls back.
REAL=""
for c in python3 python; do
  command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys;sys.exit(sys.version_info[0]!=3)' >/dev/null 2>&1 && { REAL=$(command -v "$c"); break; }
done
[ -n "$REAL" ] || fail 'no real python for stub test'
mkdir -p "$WORK/stub"
printf '#!/usr/bin/env bash
exit 9
' > "$WORK/stub/python3"
printf '#!/usr/bin/env bash
exec "%s" "$@"
' "$REAL" > "$WORK/stub/python"
chmod +x "$WORK/stub/python3" "$WORK/stub/python"
out=$(env -u SB_PYTHON PATH="$WORK/stub:$PATH" bash "$WORK/tests/run-safety.sh" 2>&1) || fail "stubbed python3 broke the runner: $out"
[[ "$out" == *'python reached'* ]] || fail 'stubbed python3: .py suite did not run'
echo 'PASS: test-safety-runner.sh (empty, failure, continuation, success, python3 stub)'
