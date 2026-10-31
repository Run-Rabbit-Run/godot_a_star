"""Check that relative markdown links resolve and `FILE.md «Section»` references name existing headings."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKIP = {".git", ".godot", "addons", "build", "logs"}
LINK = re.compile(r"\]\(([^)#\s]+)")
REFERENCE = re.compile(r"([A-Z_]+\.md)(?:\]\(([^)]*)\))?((?:,?\s*«[^»]+»)+)")
DATE_SUFFIX = re.compile(r"\s*[—(]\s*\d{4}-\d\d-\d\d\)?\s*$")


def markdown_files() -> list[Path]:
    return [p for p in ROOT.rglob("*.md") if not SKIP & set(p.relative_to(ROOT).parts)]


def headings(path: Path) -> set[str]:
    return {DATE_SUFFIX.sub("", line.lstrip("# ").strip())
            for line in path.read_text(encoding="utf-8").split("\n") if line.startswith("#")}


def main() -> int:
    files = markdown_files()
    by_name: dict[str, list[Path]] = {}
    for path in files:
        by_name.setdefault(path.name, []).append(path)
    checked, problems = 0, []
    for path in files:
        text = path.read_text(encoding="utf-8")
        where = path.relative_to(ROOT).as_posix()
        for match in LINK.finditer(text):
            if match[1].startswith(("http://", "https://", "mailto:")):
                continue
            checked += 1
            if not (path.parent / match[1]).exists():
                problems.append(f"{where}: broken link {match[1]}")
        for match in REFERENCE.finditer(text):
            name, target, sections = match[1], match[2], match[3]
            if target:
                target_path = (path.parent / target).resolve()
            elif len(by_name.get(name, [])) == 1:
                target_path = by_name[name][0]
            else:
                continue  # README.md and other ambiguous bare names
            if not target_path.exists():
                continue  # reported as a broken link above
            known = headings(target_path)
            for section in re.findall(r"«([^»]+)»", sections):
                checked += 1
                if section not in known:
                    problems.append(f"{where}: {name} has no section «{section}»")
    for problem in problems:
        print(f"FAIL: {problem}")
    if problems:
        return 1
    print(f"Docs check passed ({checked} references)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
