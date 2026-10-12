import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE / "marathon-sailfish-install"

SPEC = """
Name: harbour-hello
Version: 1.0
Release: 1
Summary: Hello
License: MIT
BuildArch: noarch
%description
hello
%install
mkdir -p %{buildroot}/usr/share/harbour-hello/qml %{buildroot}/usr/share/applications
echo 'import Sailfish.Silica 1.0' > %{buildroot}/usr/share/harbour-hello/qml/harbour-hello.qml
cat > %{buildroot}/usr/share/applications/harbour-hello.desktop <<EOT
[Desktop Entry]
Type=Application
Name=Hello
Exec=%EXEC%
Icon=harbour-hello

[X-Sailjail]
Permissions=Internet
OrganizationName=org.example
ApplicationName=hello
EOT
%files
/usr/share/harbour-hello
/usr/share/applications/harbour-hello.desktop
"""


def build_rpm(workdir, exec_line, compression):
    spec = Path(workdir) / "hello.spec"
    spec.write_text(SPEC.replace("%EXEC%", exec_line))
    subprocess.run(["rpmbuild", "-bb", "--quiet", "--define", f"_topdir {workdir}/rpm",
                    "--define", f"_binary_payload {compression}", str(spec)],
                   check=True, capture_output=True)
    return next(Path(workdir, "rpm", "RPMS").rglob("*.rpm"))


@unittest.skipUnless(shutil.which("rpmbuild"), "needs rpmbuild")
class InstallTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.root = Path(self.tmp) / "root"
        self.root.mkdir()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_tool(self, *args):
        return subprocess.run([sys.executable, str(TOOL), "--root", str(self.root), *args],
                              capture_output=True, text=True)

    def test_installs_a_qml_only_app(self):
        for compression in ("w9.gzdio", "w6.xzdio"):
            with self.subTest(compression=compression):
                rpm = build_rpm(self.tmp, "sailfish-qml harbour-hello", compression)
                r = self.run_tool(str(rpm))
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertTrue((self.root / "usr/share/harbour-hello/qml/harbour-hello.qml").exists())
                self.assertTrue((self.root / "usr/share/applications/harbour-hello.desktop").exists())
                shutil.rmtree(Path(self.tmp) / "rpm")

    def test_uninstall_removes_the_files(self):
        rpm = build_rpm(self.tmp, "sailfish-qml harbour-hello", "w9.gzdio")
        self.assertEqual(self.run_tool(str(rpm)).returncode, 0)
        r = self.run_tool("--uninstall", "harbour-hello")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse((self.root / "usr/share/applications/harbour-hello.desktop").exists())
        self.assertFalse((self.root / "usr/share/harbour-hello").exists())

    def test_refuses_a_native_binary_it_cannot_run(self):
        rpm = build_rpm(self.tmp, "harbour-hello", "w9.gzdio")
        r = self.run_tool(str(rpm))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("rebuilt", r.stderr)
        self.assertFalse((self.root / "usr/share/applications/harbour-hello.desktop").exists())


if __name__ == "__main__":
    unittest.main()
