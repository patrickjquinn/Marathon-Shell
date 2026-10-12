#!/usr/bin/env python3
"""Query the AT-SPI tree of the running shell and its apps.

  a11y.py                 print "<app>\t<role>\t<name>" for every showing item
                          (text fields add their content: "<name>: <text>")
  a11y.py --all           ... including items that are not showing
  a11y.py find NAME [APP] print the screen centre "x y" of the first showing
                          item called NAME (optionally only in app APP);
                          exit 1 if there is none

Reads DBUS_SESSION_BUS_ADDRESS. App windows report window coordinates, so
E2E_APP_Y (where the shell places app surfaces) is added to them.
"""
import os
import sys

from gi.repository import Gio, GLib

STATE_SHOWING = 25
ACC = "org.a11y.atspi.Accessible"


def call(conn, bus, path, iface, method, args=None, reply="(v)"):
    return conn.call_sync(bus, path, iface, method, args, GLib.VariantType(reply),
                          Gio.DBusCallFlags.NONE, 3000, None).unpack()


def connect():
    session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    addr = call(session, "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress",
                reply="(s)")[0]
    return Gio.DBusConnection.new_for_address_sync(
        addr, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
        | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)


def items(conn, show_all=False):
    """Yield (app, role, name, bus, path) depth-first."""

    def prop(bus, path, name):
        return call(conn, bus, path, "org.freedesktop.DBus.Properties", "Get",
                    GLib.Variant("(ss)", (ACC, name)))[0]

    def walk(app, bus, path, depth):
        if depth > 60:
            return
        try:
            if depth > 0 and not show_all:
                states = call(conn, bus, path, ACC, "GetState", reply="(au)")[0]
                if not (states and states[0] & (1 << STATE_SHOWING)):
                    return
            name = prop(bus, path, "Name")
            role = call(conn, bus, path, ACC, "GetRoleName", reply="(s)")[0]
            if role in ("text", "entry", "paragraph"):
                try:
                    typed = call(conn, bus, path, "org.a11y.atspi.Text", "GetText",
                                 GLib.Variant("(ii)", (0, -1)), reply="(s)")[0]
                    if typed and typed != name:
                        name = f"{name}: {typed}" if name else typed
                except GLib.Error:
                    pass
            kids = call(conn, bus, path, ACC, "GetChildren", reply="(a(so))")[0]
        except GLib.Error:
            return
        if name:
            yield app, role, name, bus, path
        for b, p in kids:
            yield from walk(app, b, p, depth + 1)

    root = call(conn, "org.a11y.atspi.Registry", "/org/a11y/atspi/accessible/root", ACC,
                "GetChildren", reply="(a(so))")[0]
    for bus, path in root:
        try:
            app = prop(bus, path, "Name")
        except GLib.Error:
            continue
        yield from walk(app, bus, path, 0)


def main():
    conn = connect()
    args = [a for a in sys.argv[1:] if a != "--all"]
    if args and args[0] == "find":
        want, want_app = args[1], (args[2] if len(args) > 2 else None)
        for app, _role, name, bus, path in items(conn):
            if (name != want and not name.startswith(want + ", ")) or (want_app and app != want_app):
                continue
            x, y, w, h = call(conn, bus, path, "org.a11y.atspi.Component", "GetExtents",
                              GLib.Variant("(u)", (0,)), reply="((iiii))")[0]
            if w > 0 and h > 0:
                if app != "Marathon Shell":
                    y += int(os.environ.get("E2E_APP_Y", "0"))
                print(x + w // 2, y + h // 2)
                return 0
        return 1
    for app, role, name, _bus, _path in items(conn, "--all" in sys.argv):
        print(f"{app}\t{role}\t{name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
