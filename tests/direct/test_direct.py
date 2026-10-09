#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
"""Direct mode on a host (ADR-0016): a Keel app against keel-test-compositor,
a headless Lipstick stand-in that speaks wl_shell + qt_surface_extension the
way Lipstick does (keel/testcompositor).

Checks, for any Keel app:
  * the main window arrives as a wl_shell surface shown full screen, with
    no CATEGORY, and draws;
  * the cover arrives as a second wl_shell surface of the same process,
    carrying CATEGORY=cover as a qt_extended_surface generic property that a
    Qt 5.6 compositor can decode, sent before the cover's first buffer;
  * the main window carries what Lipstick reads from a Silica window, in
    Qt 5's QDataStream format: WINID, BACKGROUND_VISIBLE (Lipstick draws the
    ambience behind it), SAILFISH_HAVE_COVER and SAILFISH_COVER_WINDOW
    "__winref:<the cover's WINID>"; the cover is not full screen;
  * onscreen_visibility Hidden keeps the main window's and the cover's
    surfaces, and showing them again redraws them (Keel's keel-wl-shell
    integration; Qt's own wl-shell destroys a hidden window's surface). The
    window stays exposed: Lipstick also sends Hidden to apps on screen;
  * turning the output (Lipstick's device rotation) makes the app report a
    new content orientation (wl_surface.set_buffer_transform);
  * no keel-shell process exists;
  * qt_extended_surface.close ends the app.
With the test app (harbour-keeldirect, --test-app) also: direct mode was
chosen by Keel's launcher, the ambience came from dconf, activation follows
keyboard focus, the cover status follows activation, a press reaches the
page, and SIGTERM becomes Shell.closeRequested.

With --booster and --invoker the app is launched the way Lipstick launches
it, `invoker --type=keel APP`, through booster-keel (keel/booster); the test
then also checks that the app runs inside the booster's process.

Usage: test_direct.py --compositor BIN --app BIN [--test-app]
                      [--qml-import DIR] [--data-dir DIR] [--platform P]
                      [--booster BIN --invoker BIN]
Exit status 0 on success, 77 when the Qt Wayland client plugin is missing.
"""

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

FAKE_DCONF = """#!/bin/sh
# Fake dconf for the direct-mode test: one ambience, no changes.
# Keel dumps each directory it reads (keel/silica/plugin/cpp/dconfambience.cpp
# kDirs); dconf answers a dump with keys relative to that directory.
case "$1" in
dump)
    case "$2" in
    /desktop/jolla/theme/)
        printf '[/]\\ncolor_scheme=%s\\n[color]\\nhighlight=%s\\n' "'dark'" "'#ff8800'" ;;
    /desktop/sailfish/silica/)
        printf '[/]\\ntheme_pixel_ratio=1.0\\n' ;;
    esac
    ;;
watch) exec sleep 3600 ;;
esac
"""

EXPECTED_HIGHLIGHT = "#ff8800"
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


class Failure(Exception):
    pass


class Compositor:
    def __init__(self, binary, workdir, size="540x960"):
        self.log_path = os.path.join(workdir, "compositor.jsonl")
        self.socket = "keel-direct-test-%d" % os.getpid()
        self.proc = subprocess.Popen(
            [binary, "--socket", self.socket, "--log", self.log_path, "--size", size],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        line = self.proc.stdout.readline()
        if not line.startswith("ready"):
            raise Failure("compositor did not start: %r" % line)
        self._pos = 0
        self.events = []

    def send(self, command):
        self.proc.stdin.write(command + "\n")
        self.proc.stdin.flush()

    def poll(self):
        with open(self.log_path) as f:
            f.seek(self._pos)
            data = f.read()
        # Keep a partial last line for later.
        cut = data.rfind("\n") + 1
        self._pos += len(data[:cut].encode())
        for line in data[:cut].splitlines():
            if line.strip():
                self.events.append(json.loads(line))
        return self.events

    def wait_for(self, predicate, timeout, what):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for ev in self.poll():
                if predicate(ev):
                    return ev
            time.sleep(0.02)
        raise Failure("timed out waiting for " + what)

    def stop(self):
        if self.proc.poll() is None:
            try:
                self.send("quit")
                self.proc.wait(3)
            except (BrokenPipeError, subprocess.TimeoutExpired):
                self.proc.kill()


class App:
    def __init__(self, argv, env):
        self.lines = []
        self.proc = subprocess.Popen(argv, env=env, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True)
        self._thread = threading.Thread(target=self._read, daemon=True)
        self._thread.start()

    def _read(self):
        for line in self.proc.stdout:
            self.lines.append(line.rstrip("\n"))

    def reports(self, name):
        out = []
        for line in list(self.lines):
            i = line.find("KEELTEST ")
            if i >= 0:
                key, _, value = line[i + 9:].partition("=")
                if key == name:
                    out.append(value)
        return out

    def wait_report(self, name, value, timeout):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if value in self.reports(name):
                return
            if self.proc.poll() is not None:
                break
            time.sleep(0.02)
        tail = "\n".join("    " + l for l in self.lines[-25:])
        raise Failure("app did not report %s=%s (got %s); its last output:\n%s"
                      % (name, value, self.reports(name), tail))

    def stop(self):
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()


def keel_shell_running():
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/comm" % pid) as f:
                if f.read().strip() == "keel-shell":
                    return True
        except OSError:
            pass
    return False


def check(condition, message):
    if not condition:
        raise Failure(message)
    print("ok -", message)


def run(args):
    workdir = tempfile.mkdtemp(prefix="keel-direct-")
    runtime = os.path.join(workdir, "runtime")
    os.mkdir(runtime, 0o700)
    dconf = os.path.join(workdir, "dconf")
    with open(dconf, "w") as f:
        f.write(FAKE_DCONF)
    os.chmod(dconf, 0o755)

    env = dict(os.environ)
    # The host desktop's session must not reach the app: on a GNOME session
    # Qt 6.10+ loads its GTK 3 platform theme, which cannot open the test
    # compositor's display (no xdg-shell), and an input-method module would
    # connect to the desktop's. Lipstick sets none of these.
    for var in ("XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "DESKTOP_SESSION",
                "QT_QPA_PLATFORMTHEME", "QT_IM_MODULE", "QT_IM_MODULES", "GTK_IM_MODULE", "DISPLAY"):
        env.pop(var, None)
    env["XDG_RUNTIME_DIR"] = runtime
    os.environ["XDG_RUNTIME_DIR"] = runtime
    compositor = Compositor(args.compositor, workdir)
    env["WAYLAND_DISPLAY"] = compositor.socket
    for k in ("KEEL_SHELL", "KEEL_SHELL_DBUS", "QT_WAYLAND_SHELL_INTEGRATION", "DISPLAY",
              "QT_QPA_PLATFORM"):
        env.pop(k, None)
    # Keel's launcher must choose wl-shell itself; the platform is the
    # Wayland client (shm on a host without a GPU unless --platform says).
    env["KEEL_DIRECT"] = "1"
    env["QT_QPA_PLATFORM"] = args.platform
    env["KEEL_DCONF"] = dconf
    env["XDG_CONFIG_HOME"] = os.path.join(workdir, "config")
    env["XDG_CACHE_HOME"] = os.path.join(workdir, "cache")
    if args.qml_import:
        env["QML_IMPORT_PATH"] = args.qml_import
    if args.data_dir:
        env["KEEL_SAILFISHAPP_DATADIR"] = args.data_dir
    env.setdefault("QT_LOGGING_RULES", "qt.qpa.wayland*=false")
    # The app's reports (console.log, debug level) go to stderr even where
    # Qt would log to journald or the system's qtlogging.ini turns debug
    # output off (Fedora's does).
    env["QT_FORCE_STDERR_LOGGING"] = "1"
    env["QT_LOGGING_RULES"] += ";js.debug=true;qml.debug=true;default.debug=true"
    if args.keel_plugins:
        # keel-wl-shell from the build tree (installed into Qt's plugins on a phone).
        env["QT_PLUGIN_PATH"] = args.keel_plugins

    app = None
    booster = None
    app_bin = args.app
    if args.booster:
        # The host's glibc refuses to dlopen() a PIE; Sailfish's does not
        # (tools/perf/clear-pie-flag.py).
        app_bin = os.path.join(workdir, os.path.basename(args.app))
        subprocess.run([sys.executable, os.path.join(REPO, "tools", "perf", "clear-pie-flag.py"), args.app,
                        app_bin], check=True)
        benv = dict(env)
        benv["KEEL_BOOSTER_PRELOAD"] = os.path.join(REPO, "keel", "booster", "preload.qml")
        booster = App([args.booster], benv)
        sock = os.path.join(runtime, "mapplauncherd", "_default", "keel", "socket")
        deadline = time.monotonic() + 20
        while not os.path.exists(sock) and time.monotonic() < deadline:
            time.sleep(0.05)
        check(os.path.exists(sock), "booster-keel listens on mapplauncherd/_default/keel/socket")
        time.sleep(2)

    def launch():
        argv = [app_bin] + args.app_args
        if args.booster:
            argv = [args.invoker, "--type=keel", "--wait-term"] + argv
        mark = len(compositor.poll())
        proc = App(argv, env)
        if not args.booster:
            return proc, proc.proc.pid
        try:
            first = compositor.wait_for(lambda e: e["ev"] == "surface" and compositor.events.index(e) >= mark,
                                        args.timeout, "a surface from the boosted app")
        except Failure:
            print("--- invoker output ---\n" + "\n".join(proc.lines[-40:]))
            print("--- booster output ---\n" + "\n".join(booster.lines[-40:]))
            proc.stop()
            raise
        return proc, first["pid"]

    try:
        launched = time.monotonic()
        app, pid = launch()

        def ev_is(kind, **fields):
            return lambda e: e["ev"] == kind and all(e.get(k) == v for k, v in fields.items())

        main = compositor.wait_for(
            lambda e: e["ev"] == "buffer" and e["pid"] == pid and e["category"] == "" and e["drawn"],
            args.timeout, "the main window's first drawn buffer")
        print("ok - main window drawn %.0f ms after launch" % ((main["t"] - launched) * 1000))
        if args.booster:
            exe = os.path.basename(os.readlink("/proc/%d/exe" % pid))
            check(exe == os.path.basename(args.booster), "the app runs in the booster's process (%s)" % exe)
            check(pid != booster.proc.pid, "in a booster instance, not in the daemon")
        main_id = main["surface"]
        events = compositor.poll()
        check(any(e["ev"] == "shell_surface" and e["surface"] == main_id for e in events),
              "main window is a wl_shell surface")
        check(any(e["ev"] == "shell_state" and e["surface"] == main_id and e["state"] == "fullscreen"
                  for e in events), "main window asked for full screen")

        cover_prop = compositor.wait_for(
            lambda e: e["ev"] == "property" and e["name"] == "CATEGORY" and e["pid"] == pid,
            args.timeout, "CATEGORY on a window")
        check(cover_prop["value"] == "cover", "CATEGORY is 'cover'")
        check(cover_prop["lipstickCompatible"], "CATEGORY decodes as a Qt 5 QString (Lipstick)")
        check(not cover_prop["mapped"], "CATEGORY arrives before the cover's first buffer")
        cover_id = cover_prop["surface"]
        check(cover_id != main_id, "cover is a separate surface")
        cover_buf = compositor.wait_for(ev_is("buffer", surface=cover_id), args.timeout,
                                        "the cover's first buffer")
        check(cover_buf["category"] == "cover", "cover surface mapped with CATEGORY=cover")
        print("ok - cover %dx%d, mapped %.0f ms after launch"
              % (cover_buf["width"], cover_buf["height"], (cover_buf["t"] - launched) * 1000))
        check(any(e["ev"] == "shell_surface" and e["surface"] == cover_id for e in compositor.poll()),
              "cover is a wl_shell surface")
        check(not any(e["ev"] == "property" and e["surface"] == main_id and e["name"] == "CATEGORY"
                      for e in compositor.poll()), "main window has no CATEGORY")
        # What Lipstick reads from a Silica app window (lipstick-jolla-home
        # WindowWrapper.qml, Switcher.qml; lipstick windowproperty.cpp).
        def prop(surface, name):
            return compositor.wait_for(
                lambda e: e["ev"] == "property" and e["surface"] == surface and e["name"] == name,
                args.timeout, "%s on surface %d" % (name, surface))
        cover_winid = prop(cover_id, "WINID")
        check(cover_winid["type"] == 3 and cover_winid["lipstickCompatible"], "cover has a WINID (uint)")
        main_winid = prop(main_id, "WINID")
        check(main_winid["type"] == 3 and main_winid["value"] != cover_winid["value"],
              "main window has its own WINID (uint)")
        bg = prop(main_id, "BACKGROUND_VISIBLE")
        check(bg["value"] is True and bg["lipstickCompatible"],
              "main window asks Lipstick for the ambience background (BACKGROUND_VISIBLE)")
        check(prop(main_id, "SAILFISH_HAVE_COVER")["value"] is True, "main window says it has a cover")
        link = prop(main_id, "SAILFISH_COVER_WINDOW")
        check(link["value"] == "__winref:%d" % cover_winid["value"],
              "main window links its cover (SAILFISH_COVER_WINDOW %s)" % link["value"])
        check(not any(e["ev"] == "shell_state" and e["surface"] == cover_id and e["state"] == "fullscreen"
                      for e in compositor.poll()), "cover is not full screen")

        # Lipstick hides windows that leave the screen (display off, the
        # switcher) with onscreen_visibility Hidden and shows them again
        # with FullScreen (the app) or Minimized (a cover in the switcher).
        # The main window: hidden (display off), then shown again with a
        # fresh frame.
        mark = len(compositor.poll())
        compositor.send("visibility %d 0" % main_id)
        time.sleep(1.0)
        check(not any(e["ev"] == "surface_destroyed" and e["surface"] == main_id
                      for e in compositor.poll()[mark:]),
              "main window keeps its surface while Lipstick hides it")
        mark = len(compositor.poll())
        compositor.send("visibility %d 5" % main_id)
        compositor.wait_for(
            lambda e: e["ev"] == "buffer" and e["surface"] == main_id and compositor.events.index(e) >= mark,
            args.timeout, "the main window drawn again after it is shown")
        print("ok - main window drawn again when Lipstick shows it")
        # The cover: Lipstick shows it only with the app in the background,
        # and Keel draws it only then, when its content changes (keel-wl-shell
        # KeelCoverExposure; on the phone a cover follows its app's state in
        # the switcher). Hidden and shown again, it keeps its surface, so
        # Lipstick still has its last frame; showing it does not force a
        # redundant one.
        compositor.send("focus 0")
        mark = len(compositor.poll())
        compositor.send("visibility %d 0" % cover_id)
        time.sleep(1.0)
        compositor.send("visibility %d 4" % cover_id)
        time.sleep(1.0)
        check(not any(e["ev"] == "surface_destroyed" and e["surface"] == cover_id
                      for e in compositor.poll()[mark:]),
              "cover keeps its surface while Lipstick hides and shows it")
        compositor.send("focus %d" % main_id)

        # (A booster's waiting instance is connected too, but has no surface.)
        pids = {e["pid"] for e in compositor.poll() if e["ev"] == "surface"}
        check(pids == {pid}, "every surface belongs to the app process (pid %d)" % pid)
        check(not keel_shell_running(), "no keel-shell process")

        if args.test_app:
            app.wait_report("mode", "direct", 5)
            print("ok - Keel chose direct mode")
            app.wait_report("platform", args.platform, 5)
            app.wait_report("highlightColor", EXPECTED_HIGHLIGHT, 5)
            print("ok - ambience read from dconf (highlightColor %s)" % EXPECTED_HIGHLIGHT)
            app.wait_report("active", "true", 5)
            print("ok - activation follows keyboard focus")

        # Device rotation: Lipstick turns the output (portrait primary,
        # landscape = WL_OUTPUT_TRANSFORM_270); an app whose page allows
        # landscape reports its content orientation as the buffer transform
        # of its main window. Apps that stay in portrait report nothing.
        mark = len(compositor.poll())
        compositor.send("transform 270")
        try:
            bt = compositor.wait_for(
                lambda e: e["ev"] == "buffer_transform" and e["surface"] == main_id
                and compositor.events.index(e) >= mark, args.timeout if args.test_app else 3,
                "a content orientation (buffer transform) after rotating")
        except Failure:
            if args.test_app:
                raise
            bt = None
            print("ok - (the app stays in portrait: no content orientation change)")
        if bt:
            check(bt["degrees"] in (90, 270), "landscape content orientation reported (buffer transform %d)"
                  % bt["transform"])
        if args.test_app:
            app.wait_report("deviceOrientation", "2", 5)  # Orientation.Landscape
            app.wait_report("orientation", "2", 5)
            print("ok - page rotated to landscape")
        check(not any(e["ev"] == "buffer_transform" and e["surface"] == cover_id
                      for e in compositor.poll()), "cover keeps Lipstick's orientation")
        mark = len(compositor.poll())
        compositor.send("transform 0")
        if bt:
            compositor.wait_for(
                lambda e: e["ev"] == "buffer_transform" and e["surface"] == main_id and e["degrees"] == 0
                and compositor.events.index(e) >= mark, args.timeout, "portrait again")
            print("ok - back to portrait")

        if args.test_app:
            compositor.send("focus 0")
            app.wait_report("active", "false", 5)
            app.wait_report("coverStatus", "active", 5)
            print("ok - in the background: inactive, cover status Active")
            compositor.send("focus %d" % main_id)
            app.wait_report("active", "true", 5)
            app.wait_report("coverStatus", "inactive", 5)
            print("ok - activated again: cover status Inactive")
            # Let the page's rotation back to portrait settle (the page
            # blocks input while it turns), then press the fifth list item:
            # header plus four items down.
            time.sleep(1.0)
            y = 110 + 4.5 * 80
            compositor.send("press %d 200 %d" % (main_id, y))
            app.wait_report("pressed", "true", 5)
            compositor.send("release %d" % main_id)
            app.wait_report("pressed", "false", 5)
            print("ok - a press reaches the page")

        compositor.send("close %d" % main_id)
        try:
            code = app.proc.wait(10)
        except subprocess.TimeoutExpired:
            raise Failure("app did not quit after qt_extended_surface.close")
        check(code == 0, "app quit after Lipstick's close (status %d)" % code)

        if args.test_app:
            # SIGTERM (Lipstick's terminateProcess) is a close request too.
            if args.booster:
                time.sleep(2)  # the next booster instance preloads
            app, pid = launch()
            # The main window's buffer: the cover may be drawn before the main
            # window is shown, which is when the SIGTERM handler is installed.
            compositor.wait_for(lambda e: e["ev"] == "buffer" and e["pid"] == pid and e["category"] == "",
                                args.timeout, "the second run's first main window buffer")
            os.kill(pid, signal.SIGTERM)
            app.wait_report("closeRequested", "true", 5)
            code = app.proc.wait(10)
            check(code == 0, "SIGTERM: closeRequested, then a clean exit (status %d)" % code)
    except Failure:
        if app:
            print("--- app output ---\n" + "\n".join(app.lines[-60:]))
        print("--- compositor log ---")
        for e in compositor.poll()[-60:]:
            print(json.dumps(e))
        raise
    finally:
        if app:
            app.stop()
        if booster:
            booster.stop()
        compositor.stop()
        shutil.rmtree(workdir, ignore_errors=True)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--compositor", required=True)
    p.add_argument("--app", required=True)
    p.add_argument("--test-app", action="store_true", help="the app is harbour-keeldirect")
    p.add_argument("--qml-import")
    p.add_argument("--data-dir")
    p.add_argument("--platform", default="wayland")
    p.add_argument("--timeout", type=float, default=30)
    p.add_argument("--booster", help="booster-keel; launch through it with --invoker")
    p.add_argument("--invoker", help="mapplauncherd's invoker")
    p.add_argument("--qt-version", help="the Qt the app was built against (default: qmake on PATH)")
    p.add_argument("--qt-plugins", help="that Qt's plugin directory (default: qmake on PATH)")
    p.add_argument("--keel-plugins", help="Qt plugin directory with Keel's keel-wl-shell integration")
    p.add_argument("app_args", nargs="*")
    args = p.parse_args()

    def qmake_query(key):
        return subprocess.run(["sh", "-c", "for q in qmake6 /usr/lib/qt6/bin/qmake qmake; do "
                               "command -v $q >/dev/null 2>&1 && exec $q -query %s; done" % key],
                              capture_output=True, text=True).stdout.strip()

    plugin_dirs = [args.qt_plugins] if args.qt_plugins else qmake_query("QT_INSTALL_PLUGINS").split()
    # Qt 6.4-6.9 ship libqwayland-{generic,egl}.so; Qt 6.10 merged them into
    # libqwayland.so.
    wayland_plugins = ("libqwayland-generic.so", "libqwayland-egl.so", "libqwayland.so")
    if plugin_dirs and not any(os.path.exists(os.path.join(d, "platforms", f))
                               for d in plugin_dirs for f in wayland_plugins):
        print("SKIP: the Qt 6 Wayland client plugin is not installed (qt6-wayland / qt6-qtwayland)")
        return 77
    # Direct mode tags windows through qt_extended_surface (Lipstick's window
    # properties), which Keel's keel-wl-shell integration speaks itself; Qt's
    # own wl-shell spoke it up to 6.8 and does not hide windows the way
    # Lipstick expects, so the test needs the plugin.
    if not (args.keel_plugins and os.path.exists(
            os.path.join(args.keel_plugins, "wayland-shell-integration", "libkeel-wl-shell.so"))):
        print("SKIP: Keel's keel-wl-shell integration was not built (Qt Wayland client private headers)")
        return 77
    try:
        run(args)
    except Failure as e:
        print("FAIL:", e)
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
