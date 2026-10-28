#!/usr/bin/env python3
"""Fail when a test exists that no CTest registration runs.

Reads the CMake files reachable from the root CMakeLists.txt through
add_subdirectory(), ignoring conditions: a suite registered only when its
dependencies are found still counts. Reports
  * QtTest / QtQuickTest mains not built into an executable add_test() runs
  * tst_*.qml files under no directory a registered runner takes as -input,
    and TestCase functions QtQuickTest skips (only test_* run)
  * test_*.py and tests/lint/*.sh scripts no add_test() names
  * Rust #[test]s outside a cargo test --workspace run, or in a file no
    crate root reaches through mod declarations
  * add_test() arguments naming source-tree paths that do not exist

Usage: check-test-reachability.py [source root]
Exit: 0 all reached, 1 something unreached, 2 could not run.
"""

import fnmatch
import re
import sys
import tomllib
from pathlib import Path

# golden/: generators' expected output, compared as text, not run.
PRUNE = {"third-party", "thirdparty", "target", "node_modules", "golden"}
QTEST_MAIN = re.compile(r"\b(QTEST_(GUILESS_|APPLESS_)?MAIN|QUICK_TEST_MAIN(_WITH_SETUP)?)\s*\(")
RUST_TEST = re.compile(r"#\[(\w+::)?test\]")
QML_SKIPPED_FN = re.compile(r"\bfunction\s+(test(?!_)\w*)\s*\(")
EXE_KEYWORDS = {"WIN32", "MACOSX_BUNDLE", "EXCLUDE_FROM_ALL", "MANUAL_FINALIZATION",
                "PRIVATE", "PUBLIC", "INTERFACE"}


def lex(text):
    """CMake command invocations as (name, [args]); args keep quotes stripped."""
    text = re.sub(r"#\[(=*)\[.*?\]\1\]", "", text, flags=re.S)
    commands = []
    i, n = 0, len(text)
    ident = re.compile(r"([A-Za-z_]\w*)[ \t]*\(")
    while i < n:
        c = text[i]
        if c == "#":
            i = text.find("\n", i)
            i = n if i < 0 else i
            continue
        m = ident.match(text, i)
        if not m or (i > 0 and (text[i - 1].isalnum() or text[i - 1] == "_")):
            i += 1
            continue
        i = m.end()
        args, depth, tok = [], 0, None
        while i < n:
            c = text[i]
            if c == '"':
                j = i + 1
                buf = []
                while j < n and text[j] != '"':
                    if text[j] == "\\" and j + 1 < n:
                        j += 1
                    buf.append(text[j])
                    j += 1
                args.append("".join(buf))
                i = j + 1
                continue
            if c == "#":
                i = text.find("\n", i)
                i = n if i < 0 else i
                continue
            if c == "(":
                depth += 1
            elif c == ")":
                if depth == 0:
                    i += 1
                    break
                depth -= 1
            elif not c.isspace():
                j = i
                while j < n and not text[j].isspace() and text[j] not in '()"#':
                    j += 1
                args.append(text[i:j])
                i = j
                continue
            i += 1
        else:
            raise ValueError("unterminated command " + m.group(1))
        commands.append((m.group(1).lower(), args))
    return commands


def expand(value, env):
    for _ in range(8):
        new = re.sub(r"\$\{(\w+)\}", lambda m: env.get(m.group(1), m.group(0)), value)
        if new == value:
            break
        value = new
    return value


class Model:
    def __init__(self):
        self.targets = {}  # name -> set of source paths
        self.tests = []  # (args, working dir)
        self.visited = set()

    def load(self, directory, env):
        listfile = directory / "CMakeLists.txt"
        if not listfile.is_file() or listfile in self.visited:
            return
        self.visited.add(listfile)
        env = dict(env, CMAKE_CURRENT_SOURCE_DIR=str(directory), CMAKE_CURRENT_LIST_DIR=str(directory))
        self.run(lex(listfile.read_text(errors="replace")), directory, env)

    def run(self, commands, directory, env):
        i = 0
        while i < len(commands):
            name, args = commands[i]
            if name == "foreach":
                depth, j = 1, i + 1
                while j < len(commands) and depth:
                    depth += {"foreach": 1, "endforeach": -1}.get(commands[j][0], 0)
                    j += 1
                body = commands[i + 1:j - 1]
                var = args[0]
                items = [x for a in args[1:] for x in expand(a, env).split(";") if x]
                if items[:2] == ["IN", "ITEMS"]:
                    items = items[2:]
                elif items[:1] in (["IN"], ["RANGE"]):
                    items = ["${%s}" % var]
                for item in items or [""]:
                    self.run(body, directory, dict(env, **{var: item}))
                i = j
                continue
            self.command(name, [expand(a, env) for a in args], directory, env)
            i += 1

    def path(self, value, directory):
        p = Path(value)
        return (p if p.is_absolute() else directory / p).resolve()

    def command(self, name, args, directory, env):
        if name == "set" and args:
            env[args[0]] = ";".join(a for a in args[1:] if a not in ("CACHE", "PARENT_SCOPE"))
        elif name == "add_subdirectory" and args:
            self.load(self.path(args[0], directory), env)
        elif name in ("add_executable", "qt_add_executable", "qt6_add_executable") and args:
            sources = self.targets.setdefault(args[0], set())
            for a in args[1:]:
                for part in a.split(";"):
                    if part and part not in EXE_KEYWORDS:
                        sources.add(self.path(part, directory))
        elif name == "target_sources" and args:
            for a in args[1:]:
                for part in a.split(";"):
                    if part and part not in EXE_KEYWORDS:
                        self.targets.setdefault(args[0], set()).add(self.path(part, directory))
        elif name == "add_test" and args:
            workdir = directory
            if "WORKING_DIRECTORY" in args:
                workdir = self.path(args[args.index("WORKING_DIRECTORY") + 1], directory)
            if args[0] == "NAME" and "COMMAND" in args:
                args = args[args.index("COMMAND") + 1:]
            else:
                args = args[1:]
            self.tests.append((args, workdir))


def files(root):
    stack = [root]
    while stack:
        d = stack.pop()
        if (d / "CMakeCache.txt").exists():
            continue
        for p in sorted(d.iterdir()):
            if p.is_dir():
                if not p.name.startswith(".") and p.name not in PRUNE:
                    stack.append(p)
            elif p.is_file():
                yield p


def rust_module_tree(package):
    src = package / "src"
    roots = [src / "lib.rs", src / "main.rs", package / "build.rs"]
    roots += sorted(src.glob("bin/*.rs")) + sorted(src.glob("bin/*/main.rs"))
    roots += sorted((package / "tests").glob("*.rs"))
    roots = [r for r in roots if r.is_file()]
    mod_re = re.compile(r'^\s*(?:#\[path\s*=\s*"([^"]+)"\]\s*)?(?:pub(?:\([^)]*\))?\s+)?mod\s+(\w+)\s*;', re.M)
    reached, stack = set(), [(r, True) for r in roots]
    while stack:
        f, is_root = stack.pop()
        if f in reached:
            continue
        reached.add(f)
        base = f.parent if is_root or f.name == "mod.rs" else f.parent / f.stem
        for m in mod_re.finditer(f.read_text(errors="replace")):
            if m.group(1):
                candidates = [f.parent / m.group(1)]
            else:
                candidates = [base / (m.group(2) + ".rs"), base / m.group(2) / "mod.rs"]
            stack += [(c.resolve(), False) for c in candidates if c.is_file()]
    return reached


def check(root):
    model = Model()
    model.load(root, {"CMAKE_SOURCE_DIR": str(root), "PROJECT_SOURCE_DIR": str(root)})
    problems = []

    tokens = [a for args, _ in model.tests for a in args]
    run_targets = set()
    for t in tokens:
        run_targets.add(t)
        run_targets.update(re.findall(r"\$<TARGET_FILE:([^>]+)>", t))
    built = set()
    for name in run_targets & model.targets.keys():
        built |= model.targets[name]

    named, inputs = set(), set()
    for args, workdir in model.tests:
        for k, a in enumerate(args):
            if "$" in a or "<" in a:
                continue
            p = model.path(a, workdir)
            if not p.is_relative_to(root) or p == root:
                continue
            if k and args[k - 1] == "-input":
                inputs.add(p)
            if p.exists():
                named.add(p)
            elif "/" in a:
                problems.append(f"add_test runs {p.relative_to(root)}, which does not exist")
    for p in named:
        if p.name == "run.sh" and "-input" in p.read_text(errors="replace"):
            inputs.add(p.parent)

    cargo_runs = {workdir for args, workdir in model.tests if "test" in args and "--workspace" in args}
    workspace_members = set()
    for ws in cargo_runs:
        manifest = ws / "Cargo.toml"
        if manifest.is_file():
            parsed = tomllib.loads(manifest.read_text())
            if "package" in parsed:
                workspace_members.add(ws.resolve())
            members = parsed.get("workspace", {}).get("members", [])
            for pattern in members:
                workspace_members |= {p.resolve() for p in ws.glob(pattern) if (p / "Cargo.toml").is_file()}

    all_files = list(files(root))
    def rel(p):
        return p.relative_to(root).as_posix()

    for p in all_files:
        if p.suffix == ".cpp" and QTEST_MAIN.search(p.read_text(errors="replace")):
            if p.resolve() not in built:
                problems.append(f"{rel(p)}: not a source of any executable add_test runs")
        elif p.suffix == ".qml" and p.name.startswith("tst_"):
            if not any(p.is_relative_to(d) for d in inputs):
                problems.append(f"{rel(p)}: no registered qmltestrunner takes its directory as -input")
            for fn in QML_SKIPPED_FN.findall(p.read_text(errors="replace")):
                problems.append(f"{rel(p)}: {fn}() never runs, QtQuickTest only runs test_* functions")
        elif (p.suffix == ".py" and p.name.startswith("test_")) or (
            p.suffix == ".sh" and p.parent == root / "tests" / "lint"
        ):
            if p.resolve() not in named:
                problems.append(f"{rel(p)}: no add_test runs it")
        elif p.name == "Cargo.toml" and "package" in tomllib.loads(p.read_text()):
            package = p.parent.resolve()
            tests = [f for f in all_files if f.suffix == ".rs" and f.is_relative_to(p.parent)
                     and RUST_TEST.search(f.read_text(errors="replace"))]
            if not tests:
                continue
            if package not in workspace_members:
                problems.append(f"{rel(p.parent)}: has #[test]s but is in no workspace add_test runs cargo test --workspace on")
            tree = rust_module_tree(package)
            for f in tests:
                if f.resolve() not in tree:
                    problems.append(f"{rel(f)}: has #[test]s but no mod declaration reaches it")
    return problems


def main(argv):
    root = Path(argv[1] if len(argv) > 1 else Path(__file__).resolve().parents[2]).resolve()
    if not (root / "CMakeLists.txt").is_file():
        print(f"{root}: no CMakeLists.txt", file=sys.stderr)
        return 2
    try:
        problems = check(root)
    except (ValueError, IndexError, tomllib.TOMLDecodeError) as e:
        print(f"could not read the build files: {e}", file=sys.stderr)
        return 2
    for line in sorted(set(problems)):
        print(line)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
