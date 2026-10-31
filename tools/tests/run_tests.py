"""Run the docs check and Godot suites; fail on engine errors even when a process exits with zero."""
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


def godot_script(script: str) -> list[str]:
    return [args.godot, "--headless", "--path", str(root), "--script", script]


def uncached_classes() -> list[str]:
    """Return class_name declarations missing from Godot's global class cache; --script runs cannot see them."""
    cache = root / ".godot" / "global_script_class_cache.cfg"
    known = set(re.findall(r'"class": &"(\w+)"', cache.read_text(encoding="utf-8"))) if cache.exists() else set()
    missing = []
    for script in root.rglob("*.gd"):
        folders = [folder for folder in script.relative_to(root).parents if folder != Path(".")]
        if any(folder.name.startswith(".") or (root / folder / ".gdignore").exists() for folder in folders):
            continue
        declared = re.search(r"^class_name\s+(\w+)", script.read_text(encoding="utf-8", errors="replace"), re.M)
        if declared and declared[1] not in known:
            missing.append(declared[1])
    return missing


missing = uncached_classes()
if missing:
    print(f"Rescanning Godot class cache for: {', '.join(sorted(missing))}", flush=True)
    try:
        subprocess.run([args.godot, "--headless", "--editor", "--quit", "--path", str(root)], capture_output=True, timeout=300)
    except (subprocess.TimeoutExpired, OSError) as error:
        print(f"Class cache rescan failed: {error}", flush=True)

suites = [
    # The docs minimum is a floor against checking nothing; the count changes with ordinary doc edits.
    ("docs", [sys.executable, "-X", "utf8", str(root / "tools/tests/check_docs.py")], r"Docs check passed \((\d+) references\)", 100),
    ("tools/tests/check_scripts.gd", godot_script("tools/tests/check_scripts.gd"), r"Script compilation: (\d+) scripts, 0 failures", 208),
    ("features/battle/tests/hex_grid_smoke.gd", godot_script("features/battle/tests/hex_grid_smoke.gd"), r"Battle smoke passed \((\d+) checks\)", 93),
    ("tools/battles/tests/editor_smoke.gd", godot_script("tools/battles/tests/editor_smoke.gd"), r"Editor smoke passed \((\d+) checks\)", 121),
    ("features/battle/tests/run_regressions.gd", godot_script("features/battle/tests/run_regressions.gd"), r"A_star regressions: (\d+) checks, 0 failures", 1056),
]
total = 0
failed = False
for name, command, success_pattern, minimum in suites:
    try:
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=90)
        output = result.stdout + result.stderr
        match = re.search(success_pattern, output)
        passed = result.returncode == 0 and match is not None and int(match[1]) >= minimum and re.search(r"SCRIPT ERROR:|(?:^|\n)ERROR:|FAIL:|leaked at exit", output) is None
    except (subprocess.TimeoutExpired, OSError) as error:
        output = str(error)
        match = None
        passed = False
    log = logs / (Path(name).stem + ".log")
    log.write_text(output, encoding="utf-8")
    if passed:
        total += int(match[1])
        print(f"PASS {name}: {match[1]} checks", flush=True)
    else:
        failed = True
        print(f"FAIL {name}\n{output}", flush=True)
print(f"Total: {total} passed checks; logs: {logs}")
sys.exit(1 if failed else 0)
