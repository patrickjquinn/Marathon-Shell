#!/usr/bin/env python3
"""Rootless block-device image restore via UDisks2.

usage: _udisks2_restore.py <image-path> <block-dev>

Calls org.freedesktop.UDisks2.Block.OpenForRestore on <block-dev>
(unmounts any mounted partitions first) and streams <image-path> into
the returned file descriptor. Polkit prompts the user for their own
password via the desktop's polkit agent — no sudo needed.

This is what GNOME Disks' "Restore Disk Image" function uses
internally; the CLI surface around it is just a thin wrapper.
"""
from __future__ import annotations

import os
import sys
import time

from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.UDisks2"
BLOCK_DEVICES_PATH = "/org/freedesktop/UDisks2/block_devices"
BLOCK_IFACE = "org.freedesktop.UDisks2.Block"
FS_IFACE = "org.freedesktop.UDisks2.Filesystem"
PARTITION_TABLE_IFACE = "org.freedesktop.UDisks2.PartitionTable"
PROPS_IFACE = "org.freedesktop.DBus.Properties"


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def child_partitions(bus, parent_path: str) -> list[str]:
    """Return all UDisks2 block paths whose `Table` property points at us."""
    proxy = Gio.DBusProxy.new_sync(
        bus, Gio.DBusProxyFlags.NONE, None,
        BUS_NAME, "/org/freedesktop/UDisks2",
        "org.freedesktop.DBus.ObjectManager", None,
    )
    objects = proxy.call_sync(
        "GetManagedObjects", None,
        Gio.DBusCallFlags.NONE, 10 * 60 * 1000, None,
    ).unpack()[0]
    children: list[str] = []
    for path, ifaces in objects.items():
        part = ifaces.get("org.freedesktop.UDisks2.Partition")
        if part and part.get("Table") == parent_path:
            children.append(path)
    return children


def unmount_partition(bus, part_path: str) -> None:
    proxy = Gio.DBusProxy.new_sync(
        bus, Gio.DBusProxyFlags.NONE, None,
        BUS_NAME, part_path, FS_IFACE, None,
    )
    mountpoints = proxy.get_cached_property("MountPoints")
    if mountpoints is None or len(mountpoints) == 0:
        # Re-read in case object was just registered.
        return
    print(f"==> unmounting {part_path}")
    try:
        proxy.call_sync(
            "Unmount",
            GLib.Variant("(a{sv})", ({"force": GLib.Variant("b", True)},)),
            Gio.DBusCallFlags.NONE, 10 * 60 * 1000, None,
        )
    except GLib.Error as e:
        if "not mounted" in str(e).lower():
            return
        raise


def open_for_restore(bus, dev_path: str) -> int:
    """Call Block.OpenForRestore — returns an int fd we own."""
    print(f"==> requesting OpenForRestore on {dev_path}")
    connection = bus
    reply, fd_list = connection.call_with_unix_fd_list_sync(
        BUS_NAME, dev_path, BLOCK_IFACE,
        "OpenForRestore",
        GLib.Variant("(a{sv})", ({},)),
        None,
        Gio.DBusCallFlags.NONE, 10 * 60 * 1000, None,
        None,
    )
    handle = reply.unpack()[0]
    return fd_list.get(handle)


def rescan(bus, dev_path: str) -> None:
    print(f"==> rescanning partition table on {dev_path}")
    bus.call_sync(
        BUS_NAME, dev_path, BLOCK_IFACE,
        "Rescan",
        GLib.Variant("(a{sv})", ({},)),
        None,
        Gio.DBusCallFlags.NONE, 10 * 60 * 1000, None,
    )


def human(n: int) -> str:
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024  # type: ignore[assignment]
    return f"{n:.1f} PiB"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 64
    image = sys.argv[1]
    dev = sys.argv[2]

    if not os.path.isfile(image):
        die(f"image not found: {image}")

    # Translate /dev/sda → /org/freedesktop/UDisks2/block_devices/sda
    dev_name = os.path.basename(dev)
    dev_path = f"{BLOCK_DEVICES_PATH}/{dev_name}"

    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    # Sanity check: refuse to clobber the host root device.
    root_src = os.popen("findmnt -no SOURCE / 2>/dev/null").read().strip()
    if root_src:
        root_disk = os.popen(f"lsblk -no PKNAME {root_src} 2>/dev/null").read().strip() \
                    or os.path.basename(root_src)
        if root_disk == dev_name or dev_name.startswith(root_disk):
            die(f"refusing: {dev} is the host root device (/dev/{root_disk})")

    image_size = os.path.getsize(image)
    print(f"==> image: {image} ({human(image_size)})")
    print(f"==> target: {dev}  ({dev_path})")

    # Unmount any mounted partitions on the target.
    for part_path in child_partitions(bus, dev_path):
        unmount_partition(bus, part_path)

    fd = open_for_restore(bus, dev_path)
    print(f"==> writing image (fd {fd}); this asks polkit for your user password")

    written = 0
    chunk = 4 * 1024 * 1024  # 4 MiB — same as `dd bs=4M`
    last_print = time.monotonic()
    with open(image, "rb") as src, os.fdopen(fd, "wb", buffering=0) as dst:
        while True:
            buf = src.read(chunk)
            if not buf:
                break
            dst.write(buf)
            written += len(buf)
            now = time.monotonic()
            if now - last_print > 1.0 or written == image_size:
                pct = 100 * written / image_size
                rate = written / max(1, now - last_print) if last_print else 0
                # Keep last_print accurate for next rate calc.
                last_print = now
                print(f"    {human(written)} / {human(image_size)}  ({pct:.1f}%)", flush=True)
        os.fsync(dst.fileno())

    print("==> sync done; rescanning partition table")
    rescan(bus, dev_path)
    print("==> flash complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
