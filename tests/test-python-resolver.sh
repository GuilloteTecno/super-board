#!/usr/bin/env bash
# sb_python_resolve must pick a Python 3 that actually runs (Windows Store stubs exit 9009).
set -euo pipefail
PACK=$(cd "$(dirname "$0")/.." && pwd)
LIB="$PACK/scripts/super-board-python.sh"
fail() { echo "FAIL: $1" >&2; exit 1; }
[ -f "$LIB" ] || fail "scripts/super-board-python.sh missing"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
# A real interpreter to wrap: whatever works here right now.
REAL=""
for c in "${SB_PYTHON:-}" python3 python; do
  [ -n "$c" ] && command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys;sys.exit(sys.version_info[0]!=3)' >/dev/null 2>&1 && { REAL=$(command -v "$c"); break; }
done
[ -n "$REAL" ] || fail "no real python3 for the test"

mkstub() { # dir exit-code file
  printf '#!/usr/bin/env bash\necho "stub: Python was not found" >&2\nexit %s\n' "$2" > "$W/$1/$3"
  chmod +x "$W/$1/$3"
}
mkwrap() { printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$REAL" > "$W/$1/$2"; chmod +x "$W/$1/$2"; }

run_resolve() { # extra-env... ; echoes result, rc via global
  ( unset SB_PYTHON; env "$@" bash -c '. "$0"; sb_python_resolve' "$LIB" )
}
BASE_PATH="/usr/bin:/bin"

# 1 — working python3 wins
mkdir -p "$W/a"; mkwrap a python3; mkwrap a python
out=$(run_resolve PATH="$W/a:$BASE_PATH") || fail "case1 rc"
[ "$out" = python3 ] || fail "case1: expected python3, got '$out'"

# 2 — python3 is a 9009 stub; python works
mkdir -p "$W/b"; mkstub b 9 python3; mkwrap b python
out=$(run_resolve PATH="$W/b:$BASE_PATH") || fail "case2 rc"
[ "$out" = python ] || fail "case2: expected python, got '$out'"

# 3 — SB_PYTHON override wins even when python3 works
mkdir -p "$W/c"; mkwrap c python3; mkwrap c mypy
out=$(run_resolve PATH="$W/c:$BASE_PATH" SB_PYTHON="$W/c/mypy") || fail "case3 rc"
[ "$out" = "$W/c/mypy" ] || fail "case3: expected override, got '$out'"

# 4 — a broken override falls through to the next candidate
out=$(run_resolve PATH="$W/c:$BASE_PATH" SB_PYTHON="$W/c/nonexistent") || fail "case4 rc"
[ "$out" = python3 ] || fail "case4: expected python3, got '$out'"

# 5 — nothing works: non-zero + message
mkdir -p "$W/d"; mkstub d 9 python3; mkstub d 9 python
rc=0; err=$(run_resolve PATH="$W/d:$BASE_PATH" 2>&1) || rc=$?
[ "$rc" -ne 0 ] || fail "case5: should fail"
[[ "$err" == *"Missing test dependency: python 3"* ]] || fail "case5 message: '$err'"

# 6 — sourcing exports SB_PYTHON
mkdir -p "$W/e"; mkstub e 9 python3; mkwrap e python
out=$( unset SB_PYTHON; PATH="$W/e:$BASE_PATH" bash -c '. "$0"; sb_python_init; echo "$SB_PYTHON"' "$LIB" )
[ "$out" = python ] || fail "case6: SB_PYTHON='$out'"

# 7 — sb_python_shim: with a broken python3, a `python3` on PATH (and behind `#!/usr/bin/env python3`
#     shebangs) runs the resolved interpreter; with a working python3 it adds nothing.
out=$( unset SB_PYTHON SB_PYTHON_SHIM_DIR; PATH="$W/e:$BASE_PATH"
       . "$LIB"; sb_python_init; sb_python_shim
       printf 'import sys
print(sys.version_info[0])
' > "$W/v.py"; python3 "$W/v.py" )
[ "$out" = 3 ] || fail "case7: shimmed python3 did not run python 3: '$out'"
out=$( unset SB_PYTHON SB_PYTHON_SHIM_DIR; PATH="$W/a:$BASE_PATH"; . "$LIB"; sb_python_init; sb_python_shim; echo "${SB_PYTHON_SHIM_DIR:-none}" )
[ "$out" = none ] || fail "case7b: a shim was created although python3 works: '$out'"

echo 'PASS: test-python-resolver.sh (python3, stub fallback, override, none, export, shim)'
