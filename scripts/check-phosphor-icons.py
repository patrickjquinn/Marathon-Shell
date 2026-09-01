#!/usr/bin/env python3
"""Lint every `icon: "<name>"` / `"icon": "<name>"` ref against the
Phosphor glyph table.

A missing glyph silently renders as empty text (Icon.qml line 21:
`text: Phosphor.Glyphs[name] || ""`). Every audit pass since launch has
caught at least one of these — the gallery `sparkles`, music `library`,
and quick-settings `signal-high` were live for months because nothing
in the build pipeline rejected an unknown name.

Run from the repo root:
    python3 scripts/check-phosphor-icons.py [--strict]

Exit 0 if every reference resolves, non-zero if any don't.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys


GLYPH_TABLE = pathlib.Path("marathon-ui/Core/PhosphorGlyphs.js")
# `icon:` / `"icon":` was the only shape checked, so every glyph passed
# through the OTHER two spellings went unchecked -- `iconName:` (the
# MEmptyState / MActiveFrame / MHubRow API) and Icon's own `name:`. That
# blind spot let "wifi-off" ship blank in five places, including the
# shell's "No network connection" toast, while this script reported OK.
ICON_REF = re.compile(
    r"""[\"']?icon(?:Name)?[\"']?\s*:\s*[\"']([a-z][a-z0-9\-]*)[\"']"""
)
# `name:` is only an icon reference inside an Icon/MIcon block, so it is
# matched separately against a running brace depth rather than by regex.
NAME_REF = re.compile(r"""^\s*name\s*:\s*["']([a-z][a-z0-9\-]*)["']""")
ICON_BLOCK = re.compile(r"""\b(?:M?Icon)\s*\{""")
EXEMPT = {
    # `auto` and the QML-side dynamic names below are passed straight
    # through to Image{ source: } not to the Phosphor glyph lookup.
    "auto", "back", "forward",
}
SKIP_DIRS = {
    "build", "build-ui", "build-apps", ".claude", ".git",
    "node_modules",
}


def load_glyph_names() -> set[str]:
    text = GLYPH_TABLE.read_text()
    return set(re.findall(r'"([a-z0-9\-]+)":\s*"\\u', text))


def iter_qml(root: pathlib.Path):
    for p in root.rglob("*.qml"):
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        yield p


# Shadow QML in the duranium-build tree gets installed onto the image
# instead of (or alongside) the Marathon-Shell-source app — caught the
# Store `cloud-download` bug. Scan those too when the path exists.
EXTRA_ROOTS = [
    pathlib.Path.home() / "duranium-build/duranium/marathon-extras",
]


def iter_extra_qml():
    for root in EXTRA_ROOTS:
        if not root.exists():
            continue
        for p in root.rglob("*.qml"):
            yield p


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--strict", action="store_true",
        help="fail (exit 1) on any missing reference",
    )
    args = ap.parse_args()

    glyphs = load_glyph_names()
    bad: list[tuple[pathlib.Path, int, str]] = []
    for path in list(iter_qml(pathlib.Path("."))) + list(iter_extra_qml()):
        try:
            icon_depth = None   # brace depth at which the open Icon{} sits
            depth = 0
            for lineno, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
                for m in ICON_REF.finditer(line):
                    name = m.group(1)
                    if name in EXEMPT or name in glyphs:
                        continue
                    bad.append((path, lineno, name))

                if icon_depth is not None:
                    m = NAME_REF.match(line)
                    if m:
                        name = m.group(1)
                        if name not in EXEMPT and name not in glyphs:
                            bad.append((path, lineno, name))

                if icon_depth is None and ICON_BLOCK.search(line):
                    icon_depth = depth
                depth += line.count("{") - line.count("}")
                if icon_depth is not None and depth <= icon_depth:
                    icon_depth = None
        except (PermissionError, OSError):
            continue

    if not bad:
        print(f"phosphor-icons: OK — every reference resolves "
              f"({len(glyphs)} glyphs in the table)")
        return 0

    print(f"phosphor-icons: FAIL — {len(bad)} unresolved reference(s):",
          file=sys.stderr)
    for path, lineno, name in bad:
        print(f"  {path}:{lineno}: icon: {name!r} not in PhosphorGlyphs",
              file=sys.stderr)
    return 1 if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
