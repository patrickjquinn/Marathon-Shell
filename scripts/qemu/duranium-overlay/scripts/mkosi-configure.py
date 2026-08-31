#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later

import json
import os
import subprocess
import sys


def main() -> int:
    for var in ("PMOS_DEVICE", "PMOS_VARIANT", "RELEASE"):
        if not os.environ.get(var):
            print(f"Error: {var} is not set", file=sys.stderr)
            return 1

    device = os.environ["PMOS_DEVICE"]
    variant = os.environ["PMOS_VARIANT"]
    release = os.environ["RELEASE"]
    srcdir = os.environ["SRCDIR"]

    config = json.load(sys.stdin)

    result = subprocess.run(
        [f"{srcdir}/scripts/pmaports.py",
         # mkosi.configure scripts don't have network access
         "--skip-fetch",
         "--device", device,
         "--ui", variant,
         "--release", release],
        stdout=subprocess.PIPE,
        check=True,
    )
    pmaports = json.loads(result.stdout)

    image = config.get("Image")

    if image == "main":
        # main needs arch/sector size from deviceinfo
        for key in ("Architecture", "SectorSize"):
            if pmaports.get(key):
                config[key] = pmaports[key]
        # Bootloader override: Raspberry Pi devices boot via the RPi
        # firmware chain (config.txt + cmdline.txt + start.elf reading
        # kernel + initrd directly from /boot/firmware/). systemd-boot
        # never runs and isn't installed. Override duranium's default
        # Bootloader=systemd-boot to Bootloader=none for these devices
        # so mkosi doesn't try to copy a non-existent systemd-boot EFI
        # binary into the ESP.
        if device.startswith("raspberry-pi") or device.startswith("rpi"):
            config["Bootloader"] = "none"
            # NB: leave UnifiedKernelImages alone — mkosi's enum
            # validator rejects "false"/False; the UKI ends up
            # written to /boot but the Pi firmware ignores it and
            # boots via cmdline.txt + start.elf instead. Small waste
            # of disk space, no functional impact.
            #
            # Clear Devicetrees= — duranium's top-level mkosi.conf
            # sets `Devicetrees=*` to pack ALL DTBs into the boot
            # entry, but mkosi only supports that with UKI builds.
            # The Pi firmware loads its DTBs directly from
            # /boot/firmware/, so we don't need mkosi to manage them.
            config["Devicetrees"] = []
    elif image == "base":
        # base gets device+UI packages resolved from pmaports
        existing = config.get("Packages", [])
        dynamic = pmaports.get("Packages", [])
        # Inject Marathon's per-device overlay aport if packaging/
        # has one for this device. The aport (e.g.
        # device-oneplus-enchilada-marathon) carries the marathon
        # runtime stack + device-specific configs (greetd, dtbo,
        # config.txt edits). Check mkosi.packages/ for a matching
        # apk before injecting — qemu-aarch64 and other generic
        # targets don't ship an overlay, and apk will fail if we
        # add a non-existent package to the world.
        marathon_overlay = f"device-{device}-marathon"
        pkg_dir = os.path.join(srcdir, "mkosi.packages")
        prefix = f"{marathon_overlay}-"
        has_overlay = os.path.isdir(pkg_dir) and any(
            f.startswith(prefix) and f.endswith(".apk")
            for f in os.listdir(pkg_dir)
        )
        if has_overlay:
            config["Packages"] = list(dict.fromkeys(existing + dynamic + [marathon_overlay]))
        else:
            config["Packages"] = list(dict.fromkeys(existing + dynamic))
    elif image == "default-initrd":
        # pmaports emits InitrdPackages to distinguish base-image pkgs from
        # initramfs pkgs. for the initrd image, these need to go in Packages.
        existing = config.get("Packages", [])
        dynamic = pmaports.get("InitrdPackages", [])
        config["Packages"] = list(dict.fromkeys(existing + dynamic))
    else:
        print(f"Error: unexpected image name '{image}'", file=sys.stderr)
        return 1

    json.dump(config, sys.stdout, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
