#!/usr/bin/env python3
"""Guard: Python tests/scripts must launch children with sys.executable / a resolved bash.

On Windows the literal "python3" resolves to the Microsoft Store stub (exit 9009),
and no bash shim helps a native CreateProcess call.
"""
import ast
from pathlib import Path
import unittest

PACK = Path(__file__).resolve().parents[1]
RUNNERS = {"run_cmd", "run", "Popen", "check_output", "check_call", "call"}


def is_py3(node):
    # "bash" is banned too: CreateProcess finds WSL's System32\bash.exe before Git Bash.
    return isinstance(node, ast.Constant) and node.value in {"python3", "bash"}


def offenders(path):
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    found = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.List, ast.Tuple)) and node.elts and is_py3(node.elts[0]):
            found.append(node.lineno)
        elif isinstance(node, ast.Call) and node.args and is_py3(node.args[0]):
            name = getattr(node.func, "attr", getattr(node.func, "id", ""))
            if name in RUNNERS:
                found.append(node.lineno)
    return found


class NoPython3Literal(unittest.TestCase):
    def test_no_literal_python3_argv(self):
        bad = []
        for folder in ("tests", "scripts"):
            for path in sorted((PACK / folder).glob("*.py")):
                if path.name == "_compat.py":  # the helper that probes python3 / recognises bash on purpose
                    continue
                for line in offenders(path):
                    bad.append(f"{path.relative_to(PACK).as_posix()}:{line}")
        self.assertEqual(bad, [], 'use sys.executable / _compat.BASH instead of literal "python3" / "bash" argv')


if __name__ == "__main__":
    unittest.main()
