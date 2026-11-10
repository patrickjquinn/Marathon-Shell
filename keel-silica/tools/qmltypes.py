#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
"""Type descriptions (.qmltypes) for Keel's QML modules that register their
types in C++ at run time.

Those plugins (the Nemo modules and their legacy org.nemomobile URIs, and
Keel's own `Keel` module) call qmlRegisterType() in registerTypes(uri): one
binary serves several URIs, which Qt's declarative registration (QML_ELEMENT)
cannot do. qmltyperegistrar therefore writes nothing for them, and qmllint and
Qt Creator see none of their types. This tool asks the built plugins
themselves (qmlplugindump, which loads them) and keeps the result in the
source tree next to each module's qmldir, as upstream ships its
plugins.qmltypes; CMake installs them with the modules.

  qmltypes.py --qml <keel build>/qml --write   regenerate the files
  qmltypes.py --qml <keel build>/qml --check   fail if one differs from the
                                               plugin (ctest keel_qmltypes)

Run --write after changing what a plugin registers. A file records the Qt
release that wrote it; --check skips files from another Qt release, whose
qmlplugindump output differs in detail.
"""
import argparse
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KEEL = os.path.dirname(HERE)

# (URI, version to dump: the highest the plugin registers, file in keel/)
MODULES = [
    ("Keel", "1.0", "silica/plugin/keel.qmltypes"),
    ("Nemo.Configuration", "1.0", "nemo-compat/qmldir/nemoconfiguration.qmltypes"),
    ("Nemo.DBus", "2.0", "nemo-compat/qmldir/nemodbus.qmltypes"),
    ("Nemo.KeepAlive", "1.2", "nemo-compat/qmldir/keepaliveplugin.qmltypes"),
    ("Nemo.Ngf", "1.0", "nemo-compat/qmldir/nemongf.qmltypes"),
    ("Nemo.Notifications", "1.0", "nemo-compat/qmldir/nemonotifications.qmltypes"),
    ("Nemo.Policy", "1.0", "nemo-compat/qmldir/nemopolicy.qmltypes"),
    ("org.nemomobile.configuration", "1.0", "nemo-compat/qmldir/org.nemomobile.configuration.qmltypes"),
    ("org.nemomobile.dbus", "2.0", "nemo-compat/qmldir/org.nemomobile.dbus.qmltypes"),
    ("org.nemomobile.keepalive", "1.1", "nemo-compat/qmldir/org.nemomobile.keepalive.qmltypes"),
    ("org.nemomobile.lipstick", "0.1", "nemo-compat/qmldir/keellipstick.qmltypes"),
    ("org.nemomobile.ngf", "1.0", "nemo-compat/qmldir/org.nemomobile.ngf.qmltypes"),
    ("org.nemomobile.notifications", "1.0", "nemo-compat/qmldir/org.nemomobile.notifications.qmltypes"),
    ("org.nemomobile.policy", "1.0", "nemo-compat/qmldir/org.nemomobile.policy.qmltypes"),
    ("org.nemomobile.accounts", "1.0", "platform/accounts/nemoaccounts.qmltypes"),
]

HEADER = """// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The types {uri} {version} registers at run time, as its plugin reports them
// (qmlplugindump, Qt {qt}). For QML tooling only. Regenerate with
// keel/tools/qmltypes.py --write; ctest keel_qmltypes checks it.
"""


def qt_version(qmake):
    out = subprocess.run([qmake, "-query", "QT_VERSION"], capture_output=True, text=True, check=True)
    return out.stdout.strip()


def dump(dumper, uri, version, qml_dir, qt):
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
    proc = subprocess.run([dumper, "-nonrelocatable", uri, version, qml_dir],
                          capture_output=True, text=True, env=env, timeout=120)
    if proc.returncode != 0 or "Module {" not in proc.stdout:
        raise RuntimeError("qmlplugindump %s %s failed (%d):\n%s" % (uri, version, proc.returncode, proc.stderr[-2000:]))
    body = proc.stdout[proc.stdout.index("import QtQuick.tooling"):]
    # qmlplugindump's own comment names the build directory; drop it.
    body = re.sub(r"\n// This file describes.*?\n\n", "\n\n", body, count=1, flags=re.S)
    return HEADER.format(uri=uri, version=version, qt=qt) + "\n" + modernise(body)


def modernise(body):
    """qmlplugindump writes the Qt 5 dialect; Qt 6's tools read the one
    qmltyperegistrar writes: C++ type names (QString, not string) and
    export revisions encoded as (major << 8) | minor."""
    body = body.replace('type: "string"', 'type: "QString"')

    def component(text):
        exports = re.search(r"exports: \[([^\]]*)\]", text)
        if not exports:
            return text
        versions = re.findall(r'"[^"]* (\d+)\.(\d+)"', exports.group(1))
        encoded = ", ".join(str(int(a) << 8 | int(b)) for a, b in versions)
        return re.sub(r"exportMetaObjectRevisions: \[[^\]]*\]",
                      "exportMetaObjectRevisions: [%s]" % encoded, text, count=1)

    # One component at a time: its exports and their revisions.
    parts = re.split(r"(?=\n    Component \{)", body)
    return "".join(component(p) for p in parts)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--qml", required=True, help="the qml/ directory of a Keel build")
    ap.add_argument("--qmake", default=os.environ.get("QMAKE6") or "qmake6")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    a = ap.parse_args()

    qt = qt_version(a.qmake)
    bindir = subprocess.run([a.qmake, "-query", "QT_INSTALL_BINS"], capture_output=True, text=True).stdout.strip()
    dumper = os.path.join(bindir, "qmlplugindump")
    stale = 0
    for uri, version, rel in MODULES:
        path = os.path.join(KEEL, rel)
        text = dump(dumper, uri, version, a.qml, qt)
        if a.write:
            with open(path, "w") as f:
                f.write(text)
            print("wrote %s" % rel)
            continue
        try:
            old = open(path).read()
        except FileNotFoundError:
            print("missing: %s (run qmltypes.py --write)" % rel)
            stale += 1
            continue
        written_by = re.search(r"\(qmlplugindump, Qt (\d+\.\d+)", old)
        if written_by and written_by.group(1) != ".".join(qt.split(".")[:2]):
            print("skip: %s was written by Qt %s, this is Qt %s" % (rel, written_by.group(1), qt))
            continue
        if old != text:
            print("stale: %s no longer matches what %s registers (run qmltypes.py --write)" % (rel, uri))
            stale += 1
        else:
            print("ok: %s" % rel)
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
