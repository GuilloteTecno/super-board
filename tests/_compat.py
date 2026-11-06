"""Windows-safe helpers shared by test_*.py (stdlib only)."""
import os
from pathlib import Path
import re
import shutil
import subprocess

# Fixture repos must not inherit a global core.autocrlf=true (it turns checked-out files into CRLF).
os.environ.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.autocrlf", GIT_CONFIG_VALUE_0="false")

# Native CreateProcess searches System32 first, so a bare "bash" can hit WSL's launcher
# instead of Git Bash. Resolve through PATH once.
BASH = shutil.which("bash") or "bash"


def bash_path(path):
    """Forward-slash form (C:/x/y): backslashes are eaten when a path is handed to bash."""
    return Path(path).as_posix()


def _ensure_python3_shim():
    """Fake gh/codex scripts start with '#!/usr/bin/env python3'. Where python3 is the Windows
    Store stub, put a working one on PATH (run-safety.sh normally does; this covers direct runs)."""
    import atexit
    import subprocess
    import sys
    import tempfile
    if os.environ.get("SB_PYTHON_SHIM_DIR") or os.name != "nt":
        return
    try:
        ok = subprocess.run(["python3", "-c", "import sys; sys.exit(sys.version_info[0] != 3)"],
                            capture_output=True).returncode == 0
    except OSError:
        ok = False
    if ok:
        return
    shim = tempfile.mkdtemp(prefix="sb-py3-")
    atexit.register(shutil.rmtree, shim, ignore_errors=True)
    with open(os.path.join(shim, "python3"), "w", newline="\n") as f:
        f.write('#!/bin/sh\nexec "%s" "$@"\n' % Path(sys.executable).as_posix())
    os.environ["PATH"] = shim + os.pathsep + os.environ["PATH"]
    os.environ["SB_PYTHON_SHIM_DIR"] = shim


_ensure_python3_shim()


def symlink_or_skip(case, link, target, **kwargs):
    """Create a symlink, or skip the calling test where the OS denies it (Windows without
    Developer Mode). The rest of the suite still runs."""
    try:
        Path(link).symlink_to(target, **kwargs)
    except (OSError, NotImplementedError) as error:
        case.skipTest("symlinks unavailable here: %s" % error)


# --- bash.exe argument quoting (Windows only) --------------------------------------------------
# Started from a native process, MSYS bash.exe re-parses its command line: unquoted [ ] { } * ?
# are globbed, so a JSON argument like [{"number":1}] arrives mangled. Single-quote every
# argument that is not plainly safe; this is the form the MSYS runtime parses literally.
_SAFE = re.compile(r"^[A-Za-z0-9_./:=,+@%-]+$")
_orig_list2cmdline = subprocess.list2cmdline


def _msys_quote(arg):
    if arg and _SAFE.match(arg):
        return arg
    return "'" + arg.replace("'", "'" + '"' + "'" + '"' + "'") + "'"


def _list2cmdline(seq):
    seq = list(seq)
    if seq and os.path.basename(str(seq[0])).lower() in ("bash", "bash.exe"):
        return " ".join([_orig_list2cmdline([seq[0]])] + [_msys_quote(str(a)) for a in seq[1:]])
    return _orig_list2cmdline(seq)


if os.name == "nt":
    subprocess.list2cmdline = _list2cmdline


def native_path(path):
    """Translate a path printed by a bash child (MSYS /tmp/x) into one this process can open."""
    if os.name != "nt":
        return path
    out = subprocess.run([BASH, "-c", 'cygpath -m "$1"', "x", path], capture_output=True, text=True)
    return out.stdout.strip() or path
