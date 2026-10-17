#!/usr/bin/env python3
"""Marathon device manifests: devices/<vendor>/<codename>/device.toml + socs/<soc>.toml.

  devices.py check              validate the manifests against their schemas,
                                the overlay aports and the shell
  devices.py profile <package>  print the package's device-profile.conf
  devices.py pins <target>      print "file url sha512" for each binary the
                                build target pins

Exit: 0 ok, 1 invalid, 2 could not run.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = Path("packaging/packages")
SHELL_KEYS_SRC = Path("shell/src/managers/deviceprofile.cpp")
SESSION_SRC = PACKAGES / "marathon-shell/marathon-shell-session"


class Tree:
    def __init__(self, root: Path):
        self.root = root
        self.socs = {p.stem: _toml(p) for p in sorted((root / "socs").glob("*.toml"))}
        self.devices = {p.parent.relative_to(root / "devices").as_posix(): _toml(p)
                        for p in sorted((root / "devices").glob("*/*/device.toml"))}
        schema = json.loads((root / "devices/device.schema.json").read_text())
        self.profile_keys = list(schema["$defs"]["profile"]["properties"])

    def profile(self, device: dict) -> dict:
        return {**self.socs.get(device["soc"], {}).get("profile", {}), **device.get("profile", {})}

    def render_profile(self, where: str) -> str:
        device = self.devices[where]
        merged = self.profile(device)
        unknown = sorted(set(merged) - set(self.profile_keys))
        if unknown:
            raise ValueError(f"devices/{where}: unknown profile keys {unknown}")
        lines = [
            f"# Marathon device profile: {device['name']}",
            f"# Generated from devices/{where}/device.toml and socs/{device['soc']}.toml",
            "# by tools/devices/devices.py. Edit the manifests, not this file.",
            "",
            f"DEVICE_ID={device['id']}",
        ]
        lines += [f"{key.upper()}={_conf_value(merged[key])}" for key in self.profile_keys if key in merged]
        return "\n".join(lines) + "\n"

    def by_package(self, package: str) -> str:
        found = [where for where, d in self.devices.items() if d.get("package") == package]
        if len(found) != 1:
            raise KeyError(f"{len(found)} manifests name package {package!r}")
        return found[0]

    def pins(self, target: str) -> list[dict]:
        seen: dict[str, dict] = {}
        for device in self.devices.values():
            if device["build"]["target"] == target:
                for pin in device.get("kernel", {}).get("pins", []):
                    seen[pin["file"]] = pin
        return list(seen.values())


def _toml(path: Path) -> dict:
    return tomllib.loads(path.read_text(encoding="utf-8"))


def _conf_value(value) -> str:
    if isinstance(value, bool):
        return "1" if value else "0"
    return str(value)


def parse_conf(text: str) -> dict[str, str]:
    """KEY=VALUE pairs the way DeviceProfile reads them."""
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line or line.startswith("="):
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        if len(value) >= 2 and value[0] in "\"'" and value[-1] == value[0]:
            value = value[1:-1]
        out[key] = value
    return out


class Apkbuild:
    def __init__(self, path: Path):
        text = path.read_text()
        self.pkgver = _var(text, "pkgver")
        self.depends = _var(text, "depends").split()
        self.sources = [s.split("::")[0].rsplit("/", 1)[-1] for s in _var(text, "source").split()]
        sums = (line.split(None, 1) for line in _var(text, "sha512sums").splitlines() if line.strip())
        self.sha512 = {name: digest for digest, name in sums}


def _var(text: str, name: str) -> str:
    m = re.search(rf'^{name}="(.*?)"', text, re.S | re.M) or re.search(rf"^{name}=(\S*)", text, re.M)
    return m.group(1) if m else ""


def _gles(version: str) -> tuple[int, int]:
    major, minor = version.split(".")
    return int(major), int(minor)


class Checker:
    def __init__(self, root: Path, jsonschema, referencing):
        self.root = root
        self.errors: list[str] = []
        schemas = {name: json.loads((root / name).read_text())
                   for name in ("devices/device.schema.json", "socs/soc.schema.json")}
        registry = referencing.Registry().with_resources(
            (s["$id"], referencing.Resource.from_contents(s)) for s in schemas.values())
        self.validators = {}
        for name, schema in schemas.items():
            jsonschema.Draft202012Validator.check_schema(schema)
            self.validators[name] = jsonschema.Draft202012Validator(schema, registry=registry)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def validate(self, document: dict, schema: str, where: str) -> None:
        for problem in sorted(self.validators[schema].iter_errors(document), key=lambda e: list(e.path)):
            location = "/".join(str(part) for part in problem.path) or "(top)"
            self.error(where, f"{location}: {problem.message}")

    def run(self) -> list[str]:
        try:
            tree = Tree(self.root)
        except (OSError, tomllib.TOMLDecodeError) as exc:
            return [f"cannot load manifests: {exc}"]
        for stem, soc in tree.socs.items():
            self.validate(soc, "socs/soc.schema.json", f"socs/{stem}.toml")
            if soc.get("id") != stem:
                self.error(f"socs/{stem}.toml", "id must match the file name")
        for where, device in tree.devices.items():
            before = len(self.errors)
            self.validate(device, "devices/device.schema.json", f"devices/{where}/device.toml")
            if len(self.errors) == before:
                self.check_device(tree, where, device)
        self.check_unique(tree)
        self.check_packages(tree)
        self.check_shell_keys(tree)
        return self.errors

    def check_device(self, tree: Tree, where: str, device: dict) -> None:
        at = f"devices/{where}/device.toml"
        vendor, codename = where.split("/")
        if (device["vendor"], device["codename"]) != (vendor, codename):
            self.error(at, "vendor/codename must match the directory path")
        if device["id"] != f"{vendor}-{codename}":
            self.error(at, f"id must be {vendor}-{codename}")
        soc = tree.socs.get(device["soc"])
        if soc is None:
            self.error(at, f"soc {device['soc']!r} has no socs/{device['soc']}.toml")
            return

        build = device["build"]
        for key in ("wrapper", "flash"):
            if key in build and not (self.root / build[key]).is_file():
                self.error(at, f"build.{key} {build[key]} does not exist")
        wrapper = self.root / build.get("wrapper", "")
        if wrapper.is_file() and not re.search(rf"(build-image\.sh\"?|MARATHON_TARGET_DEVICE=)\s*{re.escape(build['target'])}\b",
                                               wrapper.read_text()):
            self.error(at, f"{build['wrapper']} does not build target {build['target']}")

        if "layers_on" in device:
            base = tree.devices.get(device["layers_on"])
            if base is None:
                self.error(at, f"layers_on {device['layers_on']!r} has no manifest")
            elif base["build"]["target"] != build["target"]:
                self.error(at, f"build.target must be {base['build']['target']}, the target of the device it layers on")

        profile = tree.profile(device)
        stack_name = profile.get("gpu_stack")
        if stack_name:
            stack = soc["gpu"]["stacks"].get(stack_name)
            if stack is None:
                self.error(at, f"gpu_stack {stack_name!r} is not one of {device['soc']}'s stacks {sorted(soc['gpu']['stacks'])}")
            else:
                if "gles_level" in profile and _gles(profile["gles_level"]) > _gles(stack["gles_max"]):
                    self.error(at, f"gles_level {profile['gles_level']} is above {stack_name}'s {stack['gles_max']}")
                if profile.get("gpu_msaa", 0) > 0 and not stack["msaa"]:
                    self.error(at, f"gpu_msaa {profile['gpu_msaa']} on {stack_name}, which can't do MSAA at a usable frame rate")
        depth = device["display"].get("depth_bits", 8)
        if depth < 8 and profile.get("panel_depth") != depth:
            self.error(at, f"a {depth}-bit panel needs profile.panel_depth = {depth} so the shell dithers")

        package = device.get("package")
        apkbuild = None
        if package:
            if package != f"device-{device['id']}-marathon":
                self.error(at, f"package must be device-{device['id']}-marathon")
            path = self.root / PACKAGES / package / "APKBUILD"
            if not path.is_file():
                self.error(at, f"package {package} has no {path.relative_to(self.root)}")
            else:
                apkbuild = Apkbuild(path)
        if apkbuild:
            self.check_overlay(tree, where, device, apkbuild)
        self.check_scale_dpi(at, device, profile)
        self.check_pinned_versions(at, device)

    def check_overlay(self, tree: Tree, where: str, device: dict, apkbuild: Apkbuild) -> None:
        at = f"devices/{where}/device.toml"
        package = device["package"]
        script = device["boot"].get("script")
        if script and script not in apkbuild.sources:
            self.error(at, f"boot.script {script} is not a source of {package}")
        base = tree.devices.get(device.get("layers_on", ""))
        if base and base.get("package") not in apkbuild.depends:
            self.error(at, f"{package} must depend on {base.get('package')}, the overlay it layers on")
        ships = "device-profile.conf" in apkbuild.sources
        if ships != ("profile" in device):
            self.error(at, f"{package} {'ships' if ships else 'does not ship'} device-profile.conf but the manifest "
                           f"{'has no' if ships else 'has a'} [profile]")
        if (self.root / PACKAGES / package / "device-profile.conf").exists():
            self.error(f"{PACKAGES}/{package}/device-profile.conf",
                       "is generated from the manifests at build time; delete the checked-in copy")
        if ships:
            digest = hashlib.sha512(tree.render_profile(where).encode()).hexdigest()
            if apkbuild.sha512.get("device-profile.conf") != digest:
                self.error(f"{PACKAGES}/{package}/APKBUILD",
                           f"device-profile.conf sha512 is stale; the manifests now generate {digest} "
                           "(update it and bump pkgrel)")

    def check_scale_dpi(self, at: str, device: dict, profile: dict) -> None:
        want = device["display"].get("scale_dpi")
        if want is None:
            return
        found = set()
        if "force_dpi" in profile:
            found.add(float(profile["force_dpi"]))
        package = device.get("package")
        source = (PACKAGES / package / "greetd-marathon.toml") if package else SESSION_SRC
        if (self.root / source).is_file():
            found |= {float(v) for v in re.findall(r"MARATHON_FORCE_DPI=([0-9.]+)", (self.root / source).read_text())}
        if float(want) not in found:
            self.error(at, f"display.scale_dpi {want} is set neither by profile.force_dpi nor MARATHON_FORCE_DPI in {source}")

    def check_pinned_versions(self, at: str, device: dict) -> None:
        entries = [("kernel", device["kernel"])] if "kernel" in device else []
        entries += [(f"firmware {f['package']}", f) for f in device.get("firmware", [])]
        for label, entry in entries:
            path = self.root / PACKAGES / entry["package"] / "APKBUILD"
            if not path.is_file():
                continue
            apkbuild = Apkbuild(path)
            if "version" in entry and entry["version"] != apkbuild.pkgver:
                self.error(at, f"{label} version {entry['version']} but its APKBUILD has pkgver {apkbuild.pkgver}")
            if "sha512" in entry and apkbuild.sha512.get(entry["file"]) != entry["sha512"]:
                self.error(at, f"{label}: {entry['file']} sha512 differs from its APKBUILD's")

    def check_unique(self, tree: Tree) -> None:
        for key in ("id", "package"):
            seen: dict[str, str] = {}
            for where, device in tree.devices.items():
                value = device.get(key)
                if value is None:
                    continue
                if value in seen:
                    self.error(f"devices/{where}/device.toml", f"{key} {value!r} is also used by devices/{seen[value]}")
                seen[value] = where

    def check_packages(self, tree: Tree) -> None:
        named = {d.get("package") for d in tree.devices.values()}
        for aport in sorted((self.root / PACKAGES).glob("device-*-marathon")):
            if aport.name not in named:
                self.error(f"{PACKAGES}/{aport.name}", "no devices/<vendor>/<codename>/device.toml names this package")

    def check_shell_keys(self, tree: Tree) -> None:
        """The schema's profile keys are exactly the keys the shell and its session read."""
        read = set(re.findall(r'conf\.value\("MARATHON_\w+",\s*QStringLiteral\("([A-Z0-9_]+)"\)',
                              (self.root / SHELL_KEYS_SRC).read_text()))
        read |= set(re.findall(r"\^\[\[:space:\]\]\*([A-Z0-9_]+)\[\[:space:\]\]\*=", (self.root / SESSION_SRC).read_text()))
        declared = {key.upper() for key in tree.profile_keys} | {"DEVICE_ID"}
        for key in sorted(read - declared):
            self.error("devices/device.schema.json", f"profile has no {key.lower()}, which the shell reads as {key}")
        for key in sorted(declared - read):
            self.error("devices/device.schema.json", f"profile key {key.lower()} is read by neither "
                                                    f"{SHELL_KEYS_SRC} nor {SESSION_SRC}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--root", type=Path, default=ROOT)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("check")
    sub.add_parser("profile").add_argument("package")
    sub.add_parser("pins").add_argument("target")
    args = parser.parse_args(argv)
    root = args.root.resolve()

    if args.command == "profile":
        tree = Tree(root)
        sys.stdout.write(tree.render_profile(tree.by_package(args.package)))
        return 0
    if args.command == "pins":
        for pin in Tree(root).pins(args.target):
            print(pin["file"], pin["url"], pin["sha512"])
        return 0

    try:
        import jsonschema
        import referencing
    except ImportError:
        print("devices.py check: needs the jsonschema module (apk add py3-jsonschema, dnf install python3-jsonschema)",
              file=sys.stderr)
        return 2
    errors = Checker(root, jsonschema, referencing).run()
    for message in errors:
        print(f"error: {message}")
    if errors:
        print(f"{len(errors)} problem(s) found")
        return 1
    print(f"devices: {len(Tree(root).devices)} valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
