"""PostToolUse hook: keep files written by agent tools LF-only, as .gitattributes (eol=lf) requires."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except ValueError:
        return
    tool_input = payload.get("tool_input") or {}
    tool_response = payload.get("tool_response") or {}
    path = tool_input.get("file_path") or (tool_response.get("filePath") if isinstance(tool_response, dict) else None)
    if not path:
        return
    try:
        target = Path(path).resolve()
        target.relative_to(ROOT)
    except (OSError, ValueError):
        return
    if ".git" in target.relative_to(ROOT).parts or not target.is_file():
        return
    data = target.read_bytes()
    # Binary files and already-normalized text stay untouched.
    if b"\r\n" not in data or b"\0" in data:
        return
    target.write_bytes(data.replace(b"\r\n", b"\n"))


main()
