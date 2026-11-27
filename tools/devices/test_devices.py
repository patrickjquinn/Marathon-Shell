#!/usr/bin/env python3
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import devices  # noqa: E402

try:
    import jsonschema
    import referencing
except ImportError:
    jsonschema = None

ROOT = devices.ROOT
COPIED = ["devices", "socs", "packaging/packages", "scripts/flash", devices.SHELL_KEYS_SRC.as_posix(),
          devices.POWER_SRC.as_posix()]


@unittest.skipIf(jsonschema is None, "needs the jsonschema module")
class Check(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for rel in COPIED:
            src, dst = ROOT / rel, self.root / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            (shutil.copytree if src.is_dir() else shutil.copy)(src, dst)
        for wrapper in (ROOT / "scripts").glob("build-*-image.sh"):
            shutil.copy(wrapper, self.root / "scripts" / wrapper.name)

    def tearDown(self):
        self.tmp.cleanup()

    def errors(self):
        return devices.Checker(self.root, jsonschema, referencing).run()

    def edit(self, rel, old, new, count=1):
        path = self.root / rel
        text = path.read_text()
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, count))

    def assertError(self, fragment):
        errors = self.errors()
        self.assertTrue(any(fragment in e for e in errors), f"no error with {fragment!r} in {errors}")

    def test_tree_is_valid(self):
        self.assertEqual(self.errors(), [])

    def test_msaa_on_a_stack_that_cannot(self):
        self.edit("devices/purism/librem5/device.toml", "[profile]\n", "[profile]\ngpu_msaa = 4\n")
        self.assertError("can't do MSAA")

    def test_gles_above_the_stack(self):
        self.edit("devices/pine64/pinephone/device.toml", "[profile]\n", '[profile]\ngles_level = "3.0"\n')
        self.assertError("above mesa-lima's 2.0")

    def test_stack_the_soc_lacks(self):
        self.edit("devices/raspberry/pi5/device.toml", "[profile]\n", '[profile]\ngpu_stack = "mesa-etnaviv"\n')
        self.assertError("not one of bcm2712's stacks")

    def test_low_depth_panel_without_dither(self):
        self.edit("devices/hackberrypi/cm5/device.toml", "panel_depth = 6\n", "")
        self.assertError("needs profile.panel_depth = 6")

    def test_schema_violation(self):
        self.edit("devices/qemu/aarch64/device.toml", 'status = "working"', 'status = "great"')
        self.assertError("status: 'great' is not one of")

    def test_display_technology_outside_the_enum(self):
        self.edit("devices/hackberrypi/cm5/device.toml", "[profile]\n", '[profile]\ndisplay_technology = "plasma"\n')
        self.assertError("display_technology: 'plasma' is not one of")

    def test_carrier_on_a_bootable_image(self):
        self.edit("devices/zinwa/q25/device.toml", 'bootloader = "none"', 'bootloader = "systemd-boot"')
        self.assertError("build.bootloader must be \"none\"")

    def test_carrier_dtb_outside_the_dtbs(self):
        self.edit("devices/zinwa/q25/device.toml", 'dtb = "mediatek/mt8781-zinwa-q25.dtb"', 'dtb = "../linux.efi"')
        self.assertError("boot/carrier/dtb")

    def test_directory_mismatch(self):
        self.edit("devices/oneplus/enchilada/device.toml", 'codename = "enchilada"', 'codename = "fajita"')
        self.assertError("vendor/codename must match the directory path")

    def test_overlay_without_manifest(self):
        shutil.copytree(self.root / "packaging/packages/device-raspberry-pi5-marathon",
                        self.root / "packaging/packages/device-pine64-pinetab-marathon")
        self.assertError("no devices/<vendor>/<codename>/device.toml names this package")

    def test_scale_dpi_drift(self):
        self.edit("packaging/packages/device-pine64-pinephone-marathon/greetd-marathon.toml",
                  "MARATHON_FORCE_DPI=270", "MARATHON_FORCE_DPI=260", count=-1)
        self.assertError("display.scale_dpi 270")

    def test_profile_change_without_apkbuild_change(self):
        self.edit("devices/purism/librem5/device.toml", "brightness_floor = 0.28", "brightness_floor = 0.3")
        self.assertError("device-profile.conf sha512 is stale")

    def test_checked_in_profile_is_refused(self):
        (self.root / "packaging/packages/device-raspberry-pi5-marathon/device-profile.conf").write_text("GPU_MSAA=4\n")
        self.assertError("delete the checked-in copy")

    def test_profile_the_overlay_does_not_ship(self):
        self.edit("devices/oneplus/enchilada/device.toml", "[hardware]", "[profile]\ncpu_governor = \"ondemand\"\n\n[hardware]")
        self.assertError("does not ship device-profile.conf but the manifest has a [profile]")

    def test_kernel_version_drift(self):
        self.edit("devices/purism/librem5/device.toml", 'version = "6.6.139"', 'version = "6.6.1"')
        self.assertError("kernel version 6.6.1 but its APKBUILD has pkgver 6.6.139")

    def test_shell_reads_a_key_the_schema_lacks(self):
        self.edit(devices.SHELL_KEYS_SRC.as_posix(), 'v.text("MARATHON_DEVICE_ID"',
                  'v.text("MARATHON_X", "NEW_KEY", ""); v.text("MARATHON_DEVICE_ID"')
        self.assertError("profile has no new_key")

    def test_schema_key_nothing_reads(self):
        self.edit(devices.SHELL_KEYS_SRC.as_posix(), '"WAKE_ON_KEY"', '"WAKE_KEY"')
        self.assertError("profile key wake_on_key is read by neither")


class Profile(unittest.TestCase):
    def setUp(self):
        self.tree = devices.Tree(ROOT)

    def test_device_keys_override_the_soc(self):
        device = {**self.tree.devices["purism/librem5"]}
        device["profile"] = {**device["profile"], "gpu_stack": "vivante-blob"}
        self.assertEqual(self.tree.profile(device)["gpu_stack"], "vivante-blob")
        self.assertEqual(self.tree.profile(device)["gles_level"], "2.0")

    def test_format(self):
        conf = devices.parse_conf(self.tree.render_profile("hackberrypi/cm5"))
        self.assertEqual(conf["DEVICE_ID"], "hackberrypi-cm5")
        self.assertEqual(conf["WAKE_ON_KEY"], "1")
        self.assertEqual(conf["DOZE_DPMS"], "0")
        self.assertEqual(conf["BRIGHTNESS_FLOOR"], "0.1")
        self.assertNotIn("RENDER_NODE", conf)

    def test_unknown_key_is_refused(self):
        self.tree.devices["raspberry/pi5"]["profile"]["frobnicate"] = True
        with self.assertRaises(ValueError):
            self.tree.render_profile("raspberry/pi5")


class Carrier(unittest.TestCase):
    def setUp(self):
        self.tree = devices.Tree(ROOT)

    def test_q25_keeps_its_names(self):
        self.assertEqual(devices.parse_conf(self.tree.render_carrier("zinwa-q25")), {
            "CARRIER_NAME": "q25",
            "CARRIER_DTB": "mediatek/mt8781-zinwa-q25.dtb",
            "CARRIER_CMDLINE": "/usr/lib/kernel-cmdline.d/50-device-zinwa-q25.conf",
        })

    def test_mp01(self):
        conf = devices.parse_conf(self.tree.render_carrier("minimal-mp01"))
        self.assertEqual(conf["CARRIER_NAME"], "mp01")
        self.assertEqual(conf["CARRIER_DTB"], "mediatek/mt6789-minimal-mp01-vendor.dtb")
        self.assertEqual(conf["CARRIER_CMDLINE"], "/usr/lib/kernel-cmdline.d/50-device-minimal-mp01.conf")

    def test_the_system_boots_after_the_pin_by_default(self):
        for target in ("zinwa-q25", "minimal-mp01"):
            self.assertNotIn("CARRIER_BOOT_BEHIND_PIN", devices.parse_conf(self.tree.render_carrier(target)))

    def test_the_jolla_boots_behind_the_pin(self):
        conf = devices.parse_conf(self.tree.render_carrier("jolla-jp2601"))
        self.assertEqual(conf["CARRIER_BOOT_BEHIND_PIN"], "1")

    def test_target_without_a_carrier(self):
        self.assertEqual(self.tree.render_carrier("raspberry-pi5"), "")
        self.assertEqual(self.tree.render_carrier("no-such-target"), "")


if __name__ == "__main__":
    unittest.main()
