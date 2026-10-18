"""The Raspberry Pi A/B initramfs hooks, run against a fake root with the
commands they call stubbed out."""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

HOOKS = Path(__file__).resolve().parents[2] / "packaging" / "ota" / "pi" / "mkinitfs"
DATA_HOOK = HOOKS / "hooks-cleanup" / "50-marathon-ab.sh"
GUARD_HOOK = HOOKS / "hooks" / "05-marathon-tryboot-guard.sh"
# The initramfs runs them with busybox ash; dash is the closest host shell.
SHELL = shutil.which("dash") or "sh"

STUB = """#!/bin/sh
echo "$(basename "$0") $*" >> "$STUB_LOG"
case "$(basename "$0") $*" in
"parted -s "*" print free") [ -n "$STUB_FREE" ] && printf ' 1 x\\n 30.0GB 31.0GB 1GB Free Space\\n\\n' || printf ' 6 x\\n\\n' ;;
"mount -t ext4"*) exit "${STUB_MOUNT_RC:-0}" ;;
e2fsck*) exit "${STUB_E2FSCK_RC:-0}" ;;
"cryptsetup isLuks "*) [ -n "$STUB_LUKS" ] ;;
"cryptsetup -q --force-password luksFormat "*) exit "${STUB_FORMAT_RC:-0}" ;;
"cryptsetup open "*) IFS= read -r pass; [ "$pass" = "$STUB_PIN" ] ;;
"plymouth --ping") [ -z "$STUB_NO_PLYMOUTH" ] ;;
"plymouth ask-for-password "*)
    for arg; do case $arg in --command=*) cmd=${arg#--command=} ;; esac; done
    answer=$(head -n1 "$STUB_ANSWERS"); sed -i 1d "$STUB_ANSWERS"
    printf '%s' "$answer" | $cmd ;;
"unl0kr "*) head -n1 "$STUB_ANSWERS"; sed -i 1d "$STUB_ANSWERS" ;;
esac
"""


@unittest.skipUnless(shutil.which("od"), "needs od")
class HookCase(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        bin_dir = self.root / "stub-bin"
        bin_dir.mkdir()
        self.bin_dir = bin_dir
        for name in ("parted", "e2fsck", "resize2fs", "mount", "umount", "modprobe", "reboot",
                     "cryptsetup", "plymouth", "mke2fs"):
            self.stub(name)
        self.log = self.root / "calls"
        self.log.touch()
        (self.root / "dev").mkdir()
        (self.root / "dev/kmsg").touch()
        self.dev = self.root / "dev/mmcblk0p6"
        self.dev.touch()
        (self.root / "dev/disk/by-partlabel").mkdir(parents=True)
        (self.root / "dev/disk/by-partlabel/marathon_data").symlink_to("../../mmcblk0p6")
        sysroot = self.root / "sysroot"
        (sysroot / "var/lib/app").mkdir(parents=True)
        (sysroot / "var/lib/app/state").write_text("slot var")
        (sysroot / "home/user").mkdir(parents=True)
        (sysroot / "home/user/notes").write_text("slot home")
        (sysroot / "etc").mkdir()
        part = self.root / "sys/devices/mmc/mmcblk0/mmcblk0p6"
        part.mkdir(parents=True)
        (part / "partition").write_text("6\n")
        (self.root / "sys/class/block").mkdir(parents=True)
        (self.root / "sys/class/block/mmcblk0p6").symlink_to(part)
        self.dt = self.root / "proc/device-tree/chosen/bootloader"
        self.dt.mkdir(parents=True)
        self.trial(False)
        self.answers = self.root / "answers"
        self.answers.touch()
        self.env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                        MARATHON_AB_TEST_ROOT=str(self.root), STUB_LOG=str(self.log),
                        STUB_ANSWERS=str(self.answers), STUB_LUKS="", STUB_PIN="",
                        STUB_NO_PLYMOUTH="")

    def stub(self, name):
        stub = self.bin_dir / name
        stub.write_text(STUB)
        stub.chmod(0o755)

    def trial(self, on):
        (self.dt / "tryboot").write_bytes(bytes([0, 0, 0, 1 if on else 0]))

    def run_hook(self, hook, **env):
        result = subprocess.run([SHELL, str(hook)], env={**self.env, **env},
                                capture_output=True, text=True, timeout=30)
        return result.returncode, self.log.read_text().splitlines()

    @property
    def data(self):
        return self.root / "marathon-data"

    def seeded(self):
        self.data.mkdir()
        (self.data / ".marathon-seeded").touch()

    @property
    def mapper(self):
        return f"{self.root}/dev/mapper/marathon_data"


class DataHookTest(HookCase):
    def test_does_nothing_without_a_data_partition(self):
        (self.root / "dev/disk/by-partlabel/marathon_data").unlink()
        rc, calls = self.run_hook(DATA_HOOK)
        self.assertEqual(rc, 0)
        self.assertEqual(calls, [])

    def test_first_boot_encrypts_grows_seeds_and_mounts(self):
        rc, calls = self.run_hook(DATA_HOOK, STUB_FREE="1")
        self.assertEqual(rc, 0, calls)
        sysroot = self.root / "sysroot"
        self.assertIn("parted -f -s /dev/mmcblk0 resizepart 6 100%", calls)
        self.assertIn("cryptsetup -q --force-password luksFormat --type luks2 --pbkdf pbkdf2 "
                      f"--pbkdf-force-iterations 1000 {self.dev}", calls)
        self.assertIn(f"mke2fs -q -F -t ext4 {self.mapper}", calls)
        self.assertIn(f"e2fsck -f -p {self.mapper}", calls)
        self.assertIn(f"resize2fs {self.mapper}", calls)
        self.assertEqual((self.data / "lib/app/state").read_text(), "slot var")
        self.assertEqual((self.data / "home/user/notes").read_text(), "slot home")
        self.assertTrue((self.data / ".marathon-seeded").exists())
        self.assertTrue((self.data / "lib/marathon-ab/etc/upper").is_dir())
        self.assertTrue((self.data / "lib/marathon-ab/etc/work").is_dir())
        mounts = [c for c in calls if c.startswith("mount")]
        etc = f"{sysroot}/var/lib/marathon-ab/etc"
        self.assertEqual(mounts, [
            f"mount -t ext4 -o ro {self.dev} {self.data}",
            f"mount -t ext4 -o rw,noatime {self.mapper} {self.data}",
            f"mount --move {self.data} {sysroot}/var",
            f"mount --bind {sysroot}/var/home {sysroot}/home",
            f"mount -t overlay overlay -o lowerdir={sysroot}/etc,upperdir={etc}/upper,workdir={etc}/work "
            f"{sysroot}/etc",
        ])
        self.assertIn("modprobe overlay", calls)

    def test_only_lost_and_found_is_still_fresh(self):
        (self.data / "lost+found").mkdir(parents=True)
        rc, calls = self.run_hook(DATA_HOOK, STUB_FREE="1")
        self.assertEqual(rc, 0, calls)
        self.assertTrue(any("luksFormat" in c for c in calls), calls)

    def test_data_already_there_stays_unencrypted(self):
        (self.data / "home/user").mkdir(parents=True)
        rc, calls = self.run_hook(DATA_HOOK, STUB_FREE="1")
        self.assertEqual(rc, 0, calls)
        self.assertFalse(any("luksFormat" in c or c.startswith("mke2fs") for c in calls), calls)
        self.assertIn(f"mount -t ext4 -o rw,noatime {self.dev} {self.data}", calls)

    def test_a_failed_encryption_leaves_it_unencrypted(self):
        rc, calls = self.run_hook(DATA_HOOK, STUB_FREE="1", STUB_FORMAT_RC="1")
        self.assertEqual(rc, 0, calls)
        self.assertIn(f"mke2fs -q -F -t ext4 {self.dev}", calls)
        self.assertIn(f"mount -t ext4 -o rw,noatime {self.dev} {self.data}", calls)

    def test_later_boots_neither_grow_nor_reseed(self):
        self.seeded()
        rc, calls = self.run_hook(DATA_HOOK)
        self.assertEqual(rc, 0, calls)
        self.assertFalse(any("resizepart" in c or c.startswith("resize2fs") for c in calls), calls)
        self.assertFalse(any("luksFormat" in c for c in calls), calls)
        self.assertIn(f"e2fsck -p {self.dev}", calls)
        self.assertFalse((self.data / "lib/app").exists())
        self.assertTrue(any(c.startswith("mount -t overlay") for c in calls))

    def test_a_trial_boot_that_cannot_mount_data_reboots(self):
        self.trial(True)
        rc, calls = self.run_hook(DATA_HOOK, STUB_MOUNT_RC="32")
        self.assertEqual(rc, 1)
        self.assertEqual(calls[-1], "reboot -f")
        self.assertIn("cannot mount", (self.root / "dev/kmsg").read_text())

    def test_a_committed_boot_that_cannot_mount_data_carries_on(self):
        rc, calls = self.run_hook(DATA_HOOK, STUB_MOUNT_RC="32")
        self.assertEqual(rc, 1)
        self.assertNotIn("reboot -f", calls)

    def test_file_system_errors_fail_a_trial_boot(self):
        self.seeded()
        self.trial(True)
        rc, calls = self.run_hook(DATA_HOOK, STUB_E2FSCK_RC="4")
        self.assertEqual(rc, 1)
        self.assertEqual(calls[-1], "reboot -f")
        self.assertFalse(any(c.startswith("mount -t ext4 -o rw") for c in calls), calls)

    def test_repaired_errors_are_fine(self):
        rc, _ = self.run_hook(DATA_HOOK, STUB_E2FSCK_RC="1")
        self.assertEqual(rc, 0)


class EncryptedDataTest(HookCase):
    def setUp(self):
        super().setUp()
        self.seeded()
        self.open = (f"cryptsetup open --perf-no_read_workqueue --perf-no_write_workqueue "
                     f"{self.dev} marathon_data")

    def asks(self, calls):
        return [c for c in calls if c.startswith("plymouth ask-for-password")]

    def test_without_a_pin_it_opens_by_itself(self):
        rc, calls = self.run_hook(DATA_HOOK, STUB_LUKS="1")
        self.assertEqual(rc, 0, calls)
        self.assertIn(self.open, calls)
        self.assertEqual(self.asks(calls), [])
        self.assertIn(f"e2fsck -p {self.mapper}", calls)
        self.assertIn(f"mount -t ext4 -o rw,noatime {self.mapper} {self.data}", calls)

    def test_the_pin_opens_it_after_a_wrong_one(self):
        self.answers.write_text("000000\n123456\n")
        rc, calls = self.run_hook(DATA_HOOK, STUB_LUKS="1", STUB_PIN="123456")
        self.assertEqual(rc, 0, calls)
        self.assertEqual(self.asks(calls), [
            f"plymouth ask-for-password --prompt=Enter PIN --number-of-tries=1 --command={self.open}",
            f"plymouth ask-for-password --prompt=Wrong PIN. Try again --number-of-tries=1 --command={self.open}",
        ])
        self.assertIn(f"mount -t ext4 -o rw,noatime {self.mapper} {self.data}", calls)

    def note(self):
        return self.data / "lib/marathon-data-key/boot-unlocked"

    def test_a_typed_pin_leaves_a_note_for_this_boot(self):
        (self.root / "proc/sys/kernel/random").mkdir(parents=True)
        (self.root / "proc/sys/kernel/random/boot_id").write_text("boot-1\n")
        self.answers.write_text("123456\n")
        rc, calls = self.run_hook(DATA_HOOK, STUB_LUKS="1", STUB_PIN="123456")
        self.assertEqual(rc, 0, calls)
        self.assertEqual(self.note().read_text(), "boot-1\n")
        self.assertEqual(self.note().stat().st_mode & 0o777, 0o600)

    def test_without_a_pin_there_is_no_note(self):
        rc, calls = self.run_hook(DATA_HOOK, STUB_LUKS="1")
        self.assertEqual(rc, 0, calls)
        self.assertFalse(self.note().exists())

    def test_unl0kr_asks_when_plymouth_is_not_running(self):
        self.stub("unl0kr")
        self.answers.write_text("123456\n")
        rc, calls = self.run_hook(DATA_HOOK, STUB_LUKS="1", STUB_PIN="123456",
                                  STUB_NO_PLYMOUTH="1")
        self.assertEqual(rc, 0, calls)
        self.assertIn("unl0kr ", calls)
        self.assertEqual(self.asks(calls), [])
        self.assertIn(f"mount -t ext4 -o rw,noatime {self.mapper} {self.data}", calls)

    def test_with_nothing_to_ask_it_mounts_nothing(self):
        self.trial(True)
        rc, calls = self.run_hook(DATA_HOOK, STUB_LUKS="1", STUB_PIN="123456",
                                  STUB_NO_PLYMOUTH="1", PATH=f"{self.bin_dir}:/usr/bin:/bin")
        self.assertEqual(rc, 1)
        self.assertEqual(calls[-1], "reboot -f")
        self.assertFalse(any(c.startswith("mount") for c in calls), calls)


class GuardHookTest(HookCase):
    def wait_for_reboot(self):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if "reboot -f" in self.log.read_text():
                return True
            time.sleep(0.05)
        return False

    def test_a_stuck_trial_boot_reboots(self):
        self.trial(True)
        rc, _ = self.run_hook(GUARD_HOOK, MARATHON_AB_GUARD_SECS="0")
        self.assertEqual(rc, 0)
        self.assertTrue(self.wait_for_reboot())
        self.assertIn("stuck in the initramfs", (self.root / "dev/kmsg").read_text())

    def test_a_committed_boot_is_left_alone(self):
        rc, calls = self.run_hook(GUARD_HOOK, MARATHON_AB_GUARD_SECS="0")
        self.assertEqual(rc, 0)
        time.sleep(0.3)
        self.assertEqual(self.log.read_text(), "")


if __name__ == "__main__":
    unittest.main()
