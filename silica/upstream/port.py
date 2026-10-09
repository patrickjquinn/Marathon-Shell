#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
"""Import and audit Keel's ports of Silica's BSD QML.

The pristine files of the current release are in
upstream/sailfishsilica-qt5-1.2.156/ (only files whose own header is BSD;
see keel/silica/PROVENANCE.md). A port in qml/ or qml/private/ is that file
with, in this order:

  1. SPDX lines (copyright holders from the header, BSD-3-Clause, and
     Shipwright when the port is modified), prepended;
  2. the upstream licence header, byte for byte;
  3. one "// Upstream: ..." line naming the file and release, and for a
     modified port "// Modified by Shipwright for Qt 6: <summary>" lines;
  4. the upstream body, where every edit is marked with a comment
     containing "Modified by Shipwright for Qt 6".

  port.py import <upstream path> [<dest dir>]   start a port (mechanical
                                                Qt 6 edits applied, marked)
  port.py strings                               regenerate the engineering
                                                English table (silicastrings.inc)
  port.py check [--markdown]                    verify every port's header
                                                and list verbatim / modified
  port.py catalogue                             the per-file catalogue for
                                                PROVENANCE.md (Markdown)
"""
import difflib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RELEASE = "sailfishsilica-qt5-1.2.156"
UPSTREAM = os.path.join(HERE, RELEASE)
SILICA = os.path.dirname(HERE)
UPSTREAM_TAG = "// Upstream: %s (Sailfish OS 5.2.0.15) " % RELEASE
MARK = "Modified by Shipwright for Qt 6"


def split_header(text):
    """Returns (header, body) where header is the leading comment block."""
    m = re.match(r"(\s*(?:/\*.*?\*/[ \t]*\n?|//[^\n]*\n)+)", text, re.S)
    if not m:
        return "", text
    return m.group(1), text[m.end():]


def holders(header):
    out = []
    for line in header.splitlines():
        m = re.search(r"Copyright\s*(?:\(C\)|\(c\)|©)\s*([0-9][0-9 ,\-]*[0-9])\s+(.*?)\s*\.?\s*$", line)
        if m:
            years = re.sub(r"\s+", "", m.group(1)).replace(",", ", ")
            who = m.group(2).rstrip(".")
            if "All rights reserved" in who:
                who = who.split("All rights reserved")[0].strip().rstrip(".")
            out.append("%s %s" % (years, who))
    return out


def spdx_lines(header, modified):
    # REUSE-IgnoreStart
    lines = ["// SPDX-FileCopyrightText: %s" % h for h in holders(header)]
    if modified:
        lines.append("// SPDX-FileCopyrightText: 2026 Patrick Quinn")
    lines.append("// SPDX-License-Identifier: BSD-3-Clause")
    # REUSE-IgnoreEnd
    return "\n".join(lines) + "\n"


def qualify_screen(body):
    """Qt 6: an unqualified `Screen` resolves to Qt Quick's attached Screen,
    which lacks sizeCategory, topCutout, the size enums and has 0 width
    outside a window. Qualify Silica's Screen and import Silica as KeelSilica."""
    new, n = re.subn(r"(?<![\w.])Screen\.", "KeelSilica.Screen.", body)
    if not n:
        return body, 0
    imports = list(re.finditer(r"^import [^\n]*\n", new, re.M))
    at = imports[-1].end() if imports else 0
    line = "import Sailfish.Silica 1.0 as KeelSilica // %s: see Screen below\n" % MARK
    return new[:at] + line + new[at:], n


def qualify_private_imports(body):
    """Qt 6 / qt_add_qml_module: Keel's Silica QML is served from resources,
    where a directory import of "private" does not resolve to the
    Sailfish.Silica.private module (whose qmldir lives there) as it does on
    the file system. Import the module by name instead."""
    n = 0

    def repl(m):
        nonlocal n
        n += 1
        target = "Sailfish.Silica.private" if m.group(1) == "private" else "Sailfish.Silica"
        alias = m.group(2) or ""
        return 'import %s 1.0%s // %s: was import "%s"%s' % (target, alias, MARK, m.group(1), alias)

    body = re.sub(r'^import "(private|\.\.)"( as \w+)?[ \t]*$', repl, body, flags=re.M)
    return body, n


def import_private_module(rel, body):
    """Qt 6: a file in Sailfish.Silica.private's own directory sees the other
    QML files there, but not the module's native (C++) types, which Silica's
    private QML used through that implicit import. Import the module."""
    if not rel.startswith("private/") or not rel.endswith(".qml"):
        return body, 0
    if re.search(r"^import Sailfish\.Silica\.private 1\.0\s*(//.*)?$", body, re.M):
        return body, 0
    imports = list(re.finditer(r"^import [^\n]*\n", body, re.M))
    at = imports[-1].end() if imports else 0
    line = "import Sailfish.Silica.private 1.0 // %s: native types of this module\n" % MARK
    return body[:at] + line + body[at:], 1


def block_end(text, start):
    """Index just past the brace block that opens at text[start] == '{'."""
    depth = 0
    i = start
    in_str = None
    while i < len(text):
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == in_str:
                in_str = None
        elif c in "\"'":
            in_str = c
        elif c == "/" and text[i:i + 2] == "//":
            i = text.index("\n", i)
            continue
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(text)


# Parameters of the signals whose handlers Silica's BSD QML writes without
# declaring them (Qt Quick's and Silica's own), by handler name.
SIGNAL_PARAMS = {
    "Pressed": ["mouse"], "Released": ["mouse"], "Clicked": ["mouse"],
    "DoubleClicked": ["mouse"], "PressAndHold": ["mouse"], "PositionChanged": ["mouse"],
    "Wheel": ["wheel"], "LinkActivated": ["link"], "LinkHovered": ["link"],
    "ValueLinkActivated": ["link"], "ColorClicked": ["color"],
    "MonthActivated": ["month", "year"], "PageCompleted": ["page"],
    "PageError": ["errorString"],
    "UpdateModel": ["modelObject", "fromDate", "toDate", "primaryMonth"],
    "AnimateFlick": ["duration", "position"],
    "InitializeItem": ["item"],
}


def handler_functions(body):
    """Qt 6: handlers in Connections must be functions (`function onFoo()`),
    and signal parameters are no longer injected into handlers (deprecated,
    warned at run time). Rewrite both forms, declaring the parameters the
    handler uses."""
    out = []
    n = 0
    pos = 0
    handler = re.compile(r"^([ \t]*)on([A-Z]\w*)[ \t]*:[ \t]*", re.M)
    connections = []
    for m in re.finditer(r"\bConnections\s*\{", body):
        connections.append((m.end() - 1, block_end(body, m.end() - 1)))

    def in_connections(i):
        return any(a < i < b for a, b in connections)

    for m in handler.finditer(body):
        if m.start() < pos:
            continue
        indent, name = m.group(1), m.group(2)
        start = m.end()
        if body.startswith("function", start) or body.startswith("(", start):
            continue
        if body[start] == "{":
            end = block_end(body, start)
            code = body[start + 1:end - 1]
            block = True
        else:
            # An expression handler, possibly continued on following lines.
            end = body.index("\n", start)
            while True:
                code = body[start:end]
                nxt = body[end + 1:body.find("\n", end + 1)] if body.find("\n", end + 1) > 0 else ""
                open_parens = code.count("(") - code.count(")") + code.count("[") - code.count("]")
                cont = open_parens > 0 or re.search(r"(&&|\|\||[-+*/?:,.=(])\s*$", code) \
                    or re.match(r"\s*(&&|\|\||[-+*/?:.])", nxt)
                if not cont or body.find("\n", end + 1) < 0:
                    break
                end = body.find("\n", end + 1)
            code = body[start:end]
            block = False
        known = SIGNAL_PARAMS.get(name, [])
        used = [i for i, p in enumerate(known) if re.search(r"(?<![\w.])%s(?!\w)" % p, code)]
        params = ", ".join(known[:max(used) + 1]) if used else ""
        conn = in_connections(m.start())
        if not conn and not used:
            continue
        comment = "// %s: %s" % (MARK, "Connections handler as a function" if conn
                                   else "signal parameter declared")
        if conn:
            head = "%sfunction on%s(%s) " % (indent, name, params)
        else:
            head = "%son%s: function(%s) " % (indent, name, params)
        if block:
            new = indent + comment + "\n" + head + "{" + code + "}"
        elif "\n" in code:
            new = indent + comment + "\n" + head + "{\n" + indent + "    " + code.strip() + "\n" + indent + "}"
        else:
            new = indent + comment + "\n" + head + "{ " + code.strip() + " }"
        out.append(body[pos:m.start()])
        out.append(new)
        pos = end
        n += 1
    out.append(body[pos:])
    return "".join(out), n


def do_import(rel, dest=None):
    src = os.path.join(UPSTREAM, rel)
    text = open(src, encoding="utf-8").read()
    header, body = split_header(text)
    if "Redistribution and use" not in header:
        sys.exit("%s: header is not BSD; not importing" % rel)
    body, nscreen = qualify_screen(body)
    body, nprivate = qualify_private_imports(body)
    body, nmodule = import_private_module(rel, body)
    body, nhandlers = handler_functions(body)
    notes = []
    if nhandlers:
        notes.append("signal handlers in Connections written as functions, and handlers "
                     "that use signal parameters declare them (%d places)" % nhandlers)
    if nmodule:
        notes.append("imports Sailfish.Silica.private for the module's native types")
    if nprivate:
        notes.append('directory imports ("private", "..") import the module by name')
    if nscreen:
        notes.append("`Screen.` qualified as `KeelSilica.Screen.` (%d places; Qt Quick's "
                     "attached Screen shadows Silica's in Qt 6)" % nscreen)
    modified = bool(notes)
    if dest is None:
        dest = os.path.join(SILICA, "qml", os.path.dirname(rel))
    out = os.path.join(dest, os.path.basename(rel))
    with open(out, "w", encoding="utf-8") as f:
        f.write(spdx_lines(header, modified))
        f.write(header)
        f.write(UPSTREAM_TAG + rel + "\n")
        for n in notes:
            f.write("// %s: %s.\n" % (MARK, n))
        f.write(body)
    print("%s -> %s%s" % (rel, os.path.relpath(out, SILICA), " (modified)" if modified else ""))


def ports():
    for sub in ("qml", os.path.join("qml", "private")):
        d = os.path.join(SILICA, sub)
        for name in sorted(os.listdir(d)):
            p = os.path.join(d, name)
            if not os.path.isfile(p) or not name.endswith((".qml", ".js")):
                continue
            text = open(p, encoding="utf-8").read()
            m = re.search(r"^" + re.escape(UPSTREAM_TAG) + r"(\S+)", text, re.M)
            if m:
                yield os.path.relpath(p, SILICA), m.group(1), text


def check(markdown=False):
    errors = 0
    rows = []
    for path, rel, text in ports():
        src = os.path.join(UPSTREAM, rel)
        if not os.path.exists(src):
            print("ERROR %s: no upstream file %s" % (path, rel)); errors += 1; continue
        up = open(src, encoding="utf-8").read()
        up_header, up_body = split_header(up)
        body = text
        while body.startswith("// SPDX-"):
            body = body.split("\n", 1)[1]
        if not body.startswith(up_header):
            print("ERROR %s: upstream licence header not kept verbatim" % path); errors += 1; continue
        rest = body[len(up_header):]
        rest_lines = rest.splitlines(keepends=True)
        if not rest_lines or not rest_lines[0].startswith(UPSTREAM_TAG):
            print("ERROR %s: missing Upstream line after the header" % path); errors += 1; continue
        rest_lines.pop(0)
        notes = []
        while rest_lines and rest_lines[0].startswith("// " + MARK + ":"):
            notes.append(rest_lines.pop(0))
        port_body = "".join(rest_lines)
        diff = [l for l in difflib.unified_diff(up_body.splitlines(), port_body.splitlines(), lineterm="", n=0)
                if not l.startswith(("---", "+++", "@@"))]
        changed = len([l for l in diff if l.startswith("+")])
        removed = len([l for l in diff if l.startswith("-")])
        modified = bool(diff)
        if modified and not notes:
            print("ERROR %s: modified but no '%s:' note" % (path, MARK)); errors += 1
        if modified and "SPDX-FileCopyrightText: 2026 Patrick Quinn" not in text.split(up_header)[0]:
            print("ERROR %s: modified but no Shipwright SPDX line" % path); errors += 1
        if not modified and notes:
            print("ERROR %s: notes but body unchanged" % path); errors += 1
        rows.append((path, rel, "modified" if modified else "verbatim", changed, removed))
    nverb = sum(1 for r in rows if r[2] == "verbatim")
    if markdown:
        print("| Keel file | Upstream file | Port | Lines added / removed |")
        print("| --- | --- | --- | --- |")
        for path, rel, kind, a, r in rows:
            print("| `%s` | `%s` | %s | %s |" % (path, rel, kind, "%d / %d" % (a, r) if kind == "modified" else ""))
    else:
        for path, rel, kind, a, r in rows:
            print("%-9s %-45s +%d -%d" % (kind, path, a, r))
    print("%d ports: %d verbatim, %d modified; %d error(s)" % (len(rows), nverb, len(rows) - nverb, errors),
          file=sys.stderr)
    return 1 if errors else 0


# Names that Silica's BSD QML uses but that are not BSD QML of this release:
# the proprietary C++ plugin's types (Keel's clean-room natives) and the
# non-BSD QML files (Keel's stand-ins). Collected from Keel's sources.
def native_names():
    names = {}
    cpp = os.path.join(SILICA, "plugin", "cpp")
    for sub, label in (("private", "private C++"), ("", "C++")):
        d = os.path.join(cpp, sub)
        for name in sorted(os.listdir(d)):
            if name.endswith(".h"):
                for n in re.findall(r"QML_NAMED_ELEMENT\((\w+)\)", open(os.path.join(d, name)).read()):
                    if not n.startswith("Keel"):
                        names.setdefault(n, label)
    names.setdefault("LinkParser", "private Rust (CXX-Qt)")
    for n in ("Theme", "SilicaItem", "SilicaControl", "TouchBlocker", "ApplicationWindow", "Cover",
              "CoverAction", "CoverActionList", "TextEditor"):
        names.setdefault(n, "Keel QML")
    ported = set(os.path.basename(r) for _, r, _ in ports())
    for sub in ("private",):
        d = os.path.join(SILICA, "qml", sub)
        for name in sorted(os.listdir(d)):
            if name.endswith(".qml") and name not in ported:
                names.setdefault(name[:-4], "private Keel QML")
    names.setdefault("ColorBackground", "Background Keel QML")
    names.setdefault("Corners", "Background Keel QML")
    return names


def code_only(body):
    body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
    return "\n".join(l.split("//")[0] if not l.strip().startswith("//%") else "" for l in body.splitlines())


def header_variants():
    variants = {}
    for root, _, files in os.walk(UPSTREAM):
        for name in files:
            if name.endswith((".qml", ".js")):
                rel = os.path.relpath(os.path.join(root, name), UPSTREAM)
                header, _ = split_header(open(os.path.join(root, name), encoding="utf-8").read())
                norm = re.sub(r"Copyright \(C\)[^\n]*\n", "", header)
                norm = re.sub(r"\s+", " ", norm)
                variants.setdefault(norm, []).append((rel, header))
    return sorted(variants.values(), key=lambda v: -len(v))


def catalogue():
    natives = native_names()
    private_qml = set(n[:-4] for n in os.listdir(os.path.join(UPSTREAM, "private")) if n.endswith(".qml"))
    variants = header_variants()
    variant_of = {}
    print("### Licence header variants\n")
    print("Every BSD file's header is one of these, apart from its `Copyright (C)` lines (which")
    print("name Jolla Ltd., Open Mobile Platform LLC or Nokia Corporation and the years). Each")
    print("port keeps its own file's header byte for byte; the full texts are also in")
    print("`upstream/%s/`.\n" % RELEASE)
    for i, files in enumerate(variants, 1):
        for rel, _ in files:
            variant_of[rel] = i
        print("Variant %d (%d files), as in `%s`:\n" % (i, len(files), files[0][0]))
        print("```")
        print(files[0][1].rstrip("\n"))
        print("```\n")
    print("### Files\n")
    print("Columns: the Keel port; port kind (verbatim, or modified with the edits marked")
    print("\"Modified by Shipwright for Qt 6\"); header variant; types from `Sailfish.Silica.private`")
    print("(native types, Keel's stand-ins for non-BSD files, and Silica's own private BSD QML);")
    print("other non-BSD Silica types (Keel's clean-room C++ or QML); the Qt 5 to Qt 6 edits.\n")
    print("| Upstream file | Keel file | Port | Header | Private module types | Other non-BSD types | Qt 6 edits |")
    print("| --- | --- | --- | --- | --- | --- | --- |")
    by_rel = {}
    for path, rel, text in ports():
        by_rel[rel] = (path, text)
    for root, _, files in sorted(os.walk(UPSTREAM)):
        for name in sorted(files):
            if not name.endswith((".qml", ".js")):
                continue
            rel = os.path.relpath(os.path.join(root, name), UPSTREAM)
            up = open(os.path.join(root, name), encoding="utf-8").read()
            _, body = split_header(up)
            code = code_only(body)
            used_priv, used_other = [], []
            js_aliases = set(re.findall(r'^import\s+"[^"]+\.js"\s+as\s+(\w+)', code, re.M))
            for n in sorted(set(natives) | private_qml):
                if n == os.path.splitext(name)[0] or n in js_aliases:
                    continue
                if re.search(r"(?<![\w.\"/])%s\b(?!\s*:)" % re.escape(n), code):
                    kind = natives.get(n, "private BSD QML")
                    if "private" in kind or n in private_qml:
                        used_priv.append("%s (%s)" % (n, kind) if n in natives else n)
                    else:
                        used_other.append("%s (%s)" % (n, kind))
            for js in re.findall(r'^import\s+"(?:private/)?(\w+\.js)"', code, re.M):
                used_priv.append(js)
            if rel in by_rel:
                path, text = by_rel[rel]
                notes = [l.split(MARK + ":", 1)[1].strip().rstrip(".")
                         for l in text.splitlines() if l.startswith("// " + MARK + ":")]
                kind = "modified" if notes else "verbatim"
                keel = "`%s`" % path
            else:
                notes, kind, keel = [], "not ported", "-"
            print("| `%s` | %s | %s | %d | %s | %s | %s |" % (
                rel, keel, kind, variant_of.get(rel, 0), ", ".join(used_priv) or "-",
                ", ".join(used_other) or "-", "; ".join(notes) or "-"))


def strings():
    """Engineering English of every qsTrId() in the BSD QML (the `//%`
    comment before it), as a C++ table for Keel's fallback translator."""
    table = {}
    for root, _, files in os.walk(UPSTREAM):
        for name in sorted(files):
            if not name.endswith((".qml", ".js")):
                continue
            lines = open(os.path.join(root, name), encoding="utf-8").read().splitlines()
            pending = None
            for line in lines:
                m = re.search(r'//%\s*"((?:[^"\\]|\\.)*)"', line)
                if m:
                    pending = m.group(1)
                for tid in re.findall(r'qsTrId\("([^"]+)"', line):
                    if pending is not None:
                        table.setdefault(tid, pending)
                    pending = None
    out = ["// Generated by keel/silica/upstream/port.py strings from the //% comments",
           # REUSE-IgnoreStart
           "// in Silica's BSD QML (%s). Do not edit." % RELEASE,
           "// SPDX-FileCopyrightText: 2012-2021 Jolla Ltd.",
           "// SPDX-FileCopyrightText: 2019-2021 Open Mobile Platform LLC",
           "// SPDX-License-Identifier: BSD-3-Clause"]
           # REUSE-IgnoreEnd
    for tid in sorted(table):
        out.append('{ "%s", "%s" },' % (tid, table[tid]))
    path = os.path.join(SILICA, "plugin", "cpp", "private", "silicastrings.inc")
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("%d strings -> %s" % (len(table), os.path.relpath(path, SILICA)))


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "import":
        for rel in sys.argv[2:]:
            do_import(rel)
    elif len(sys.argv) >= 2 and sys.argv[1] == "strings":
        strings()
    elif len(sys.argv) >= 2 and sys.argv[1] == "catalogue":
        catalogue()
    elif len(sys.argv) >= 2 and sys.argv[1] == "check":
        sys.exit(check("--markdown" in sys.argv))
    else:
        sys.exit(__doc__)
