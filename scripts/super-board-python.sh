#!/usr/bin/env bash
# Resolve a Python 3 that actually runs. On Windows, `python3` is often the
# Microsoft Store stub (exit 9009) while `python` or `py -3` is the real one.
# Source this file, then call `sb_python_init` (exports SB_PYTHON) or use
# `sb_python_resolve` to print the command. Order: $SB_PYTHON, python3, python, py -3.

_sb_py_ok() {
  "$1" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1
}

sb_python_resolve() {
  local c exe
  if [ -n "${SB_PYTHON:-}" ] && _sb_py_ok "$SB_PYTHON"; then
    printf '%s\n' "$SB_PYTHON"; return 0
  fi
  for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && _sb_py_ok "$c"; then
      printf '%s\n' "$c"; return 0
    fi
  done
  if command -v py >/dev/null 2>&1; then
    exe=$(py -3 -c 'import sys; print(sys.executable)' 2>/dev/null | tr -d '\r') || exe=""
    if [ -n "$exe" ] && _sb_py_ok "$exe"; then
      printf '%s\n' "$exe"; return 0
    fi
  fi
  echo "Missing test dependency: python 3" >&2
  return 1
}

sb_python_init() {
  local r
  r=$(sb_python_resolve) || return 1
  SB_PYTHON=$r
  # Windows consoles/pipes default to cp1252; the toolkit prints UTF-8 (check marks, emoji).
  export SB_PYTHON PYTHONUTF8=1 PYTHONIOENCODING=utf-8
}

# When python3 does not run (Windows Store stub) put a `python3` shim on PATH that execs the
# resolved interpreter, so scripts, `#!/usr/bin/env python3` shebangs and fakes keep working.
# No-op when python3 works or a shim is already on PATH. Creates one temp dir per process tree.
sb_python_shim() {
  local d exe
  if command -v python3 >/dev/null 2>&1 && _sb_py_ok python3; then return 0; fi
  [ -n "${SB_PYTHON:-}" ] || sb_python_init || return 1
  d=$(mktemp -d) || return 1
  exe=$(command -v "$SB_PYTHON") || exe=$SB_PYTHON   # absolute: tests run with a trimmed PATH
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$exe" > "$d/python3"
  chmod +x "$d/python3"
  SB_PYTHON_SHIM_DIR=$d
  PATH="$d:$PATH"
  export PATH SB_PYTHON_SHIM_DIR
}

# Git for Windows: a native jq.exe ends every output line with CRLF, and `read -r`/$(...) loops
# then carry a stray \r. Ask it not to translate (-b); other platforms keep the real jq untouched.
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*) jq() { command jq -b "$@"; } ;;
esac
