import json
import os
import re
import sys


IMPORT_RE = re.compile(r"^import\\s+([A-Za-z0-9_.]+)(?:\\s+([0-9]+\\.[0-9]+))?\\s*$")

VERSION_MAP = {
    "QtQuick": "2.0",
    "QtQuick.Controls": "2.0",
    "QtQuick.Layouts": "1.0",
    "QtQml": "2.0",
    "QtQml.Models": "2.0",
    "MarathonOS.Shell": "1.0",
}


def version_for(module: str) -> str | None:
    if module.startswith("MarathonUI."):
        return "2.0"
    return VERSION_MAP.get(module)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: build_qml_dependencies.py ROOT OUT", file=sys.stderr)
        return 1

    root = sys.argv[1]
    out_path = sys.argv[2]
    modules: dict[str, str] = {}

    for dirpath, _, filenames in os.walk(root):
        for filename in filenames:
            if not filename.endswith(".qml"):
                continue
            path = os.path.join(dirpath, filename)
            with open(path, "r", encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line.startswith("import "):
                        continue
                    match = IMPORT_RE.match(line)
                    if not match:
                        continue
                    module = match.group(1)
                    version = match.group(2)
                    if module.startswith('"') or module.startswith("."):
                        continue
                    if version:
                        modules[module] = version
                        continue
                    mapped = version_for(module)
                    if mapped:
                        modules.setdefault(module, mapped)

    data = [
        {"name": name, "type": "module", "version": modules[name]}
        for name in sorted(modules)
    ]
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=4, sort_keys=True)
        handle.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
