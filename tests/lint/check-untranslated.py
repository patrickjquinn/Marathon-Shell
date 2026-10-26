#!/usr/bin/env python3
"""Flag user-facing QML string literals not wrapped in qsTr/qsTrId.

check-untranslated.py [file-or-dir ...]   (default: shell/qml marathon-silica apps)
Mark a line `// i18n: not user-facing` to exempt it. `description` in *Actions.qml
files is the text Keel hands to agents, not shown to people, so it is skipped there.
Directories named tests, test, build or build-apps are skipped when walking a directory.
A value whose literal starts on the next line is also caught.
"""

import re
import sys
from pathlib import Path

PROPS = (r"(?:text|title|label|description|placeholderText|valueText|subtitle|message|header|hint|summary|"
         r"placeholder|tooltip|toolTip|errorText|helperText|buttonText|okText|cancelText|"
         r"Accessible\.name|Accessible\.description)")
ASSIGN = re.compile(r"(?<![\w.])" + PROPS + r"\s*:\s*(?P<value>.*)$")
LITERAL = re.compile(r'^(?:[^"\']*?\?\s*)?(?P<q>["\'])(?P<s>(?:\\.|(?!(?P=q)).)*)(?P=q)')
LETTERS = re.compile(r"[^\W\d_]", re.UNICODE)
MARKER = "i18n: not user-facing"
DEFAULT_ROOTS = ("shell/qml", "marathon-silica", "apps")
SKIP_PARTS = {"tests", "test", "build", "build-apps"}


def hits(path):
    out = []
    in_block = False
    agent_file = path.name.endswith("Actions.qml")
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for n, line in enumerate(lines, 1):
        if in_block:
            in_block = "*/" not in line
            continue
        stripped = line.strip()
        if stripped.startswith("/*"):
            in_block = "*/" not in stripped
            continue
        if stripped.startswith("//") or MARKER in line:
            continue
        m = ASSIGN.search(line)
        if not m:
            continue
        if not m.group("value").strip() and n < len(lines):
            m = ASSIGN.search(line + lines[n].strip())
        if agent_file and line[m.start():].startswith("description"):
            continue
        lit = LITERAL.match(m.group("value").strip())
        if lit and LETTERS.search(lit.group("s")):
            out.append((n, lit.group("s")))
    return out


def collect(args):
    files = []
    for arg in args:
        p = Path(arg)
        if p.is_dir():
            files += [f for f in sorted(p.rglob("*.qml")) if not SKIP_PARTS & set(f.parts)]
        elif p.suffix == ".qml":
            files.append(p)
    return files


def main(argv):
    found = 0
    for f in collect(argv[1:] or DEFAULT_ROOTS):
        for n, text in hits(f):
            print(f'{f}:{n}: "{text}"')
            found += 1
    if found:
        print(f"{found} untranslated string(s): wrap in qsTr() or mark // {MARKER}", file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
