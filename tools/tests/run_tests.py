"""Run Godot suites and fail on engine errors even when their process exits with zero."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--godot", default=os.environ.get("GODOT_BINARY") or shutil.which("godot") or "Z:/Godot/Godot_v4.7-stable_win64_console.exe")
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
logs = Path(tempfile.mkdtemp(prefix="a_star_tests_"))
suites = [
    ("features/battle/tests/hex_grid_smoke.gd", r"Battle smoke passed \((\d+) checks\)", 93),
    ("tools/battles/tests/editor_smoke.gd", r"Editor smoke passed \((\d+) checks\)", 42),
    ("features/battle/tests/run_regressions.gd", r"A_star regressions: (\d+) checks, 0 failures", 547),
]
total = 0
failed = False
for script, success_pattern, minimum in suites:
    try:
        result = subprocess.run([args.godot, "--headless", "--path", str(root), "--script", script], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
        output = result.stdout + result.stderr
        match = re.search(success_pattern, output)
        passed = result.returncode == 0 and match is not None and int(match[1]) >= minimum and re.search(r"SCRIPT ERROR:|(?:^|\n)ERROR:|FAIL:|leaked at exit", output) is None
    except (subprocess.TimeoutExpired, OSError) as error:
        output = str(error)
        match = None
        passed = False
    log = logs / (Path(script).stem + ".log")
    log.write_text(output, encoding="utf-8")
    if passed:
        total += int(match[1])
        print(f"PASS {script}: {match[1]} checks", flush=True)
    else:
        failed = True
        print(f"FAIL {script}\n{output}", flush=True)
print(f"Total: {total} passed checks; logs: {logs}")
sys.exit(1 if failed else 0)
