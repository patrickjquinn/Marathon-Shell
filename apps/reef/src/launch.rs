// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Opening an installed app from its page (`Reef.open`), as the launcher
//! would.
//!
//! The app's launcher entry is the first `.desktop` file under
//! `/usr/share/applications` that its package installs and that the
//! launcher shows (not `NoDisplay=true`; an add-on such as Pilot's gesture
//! patch has none). It is started with `lca-tool --triggerdesktop`, from
//! libcontentaction, which every Sailfish OS has (`libcontentaction-qt5`)
//! and which Sailfish itself uses to start an app from another: it runs
//! the entry's `Exec` through `invoker --single-instance`, so a running
//! app comes to the front instead of starting twice, and the app keeps its
//! sandbox (its `Exec` goes through `sailjail` or its booster, as from the
//! launcher; checked on a Jolla Phone with Calculator and Shoal Camera on
//! 11 October 2026). `invoker` stays attached to the app, so `lca-tool` is
//! started in a process group of its own and Reef does not wait for it.

use std::path::Path;
use std::process::{Command, Stdio};

/// Packages whose page offers no Open: Reef itself is already open.
const NOT_OPENED: &[&str] = &["shipwright-reef"];

/// The launcher entry of `package`, by file name
/// (`shipwright-shoal-camera.desktop`), or `None` when it has none or is
/// not installed. `root` is the system root (`jobs::sysroot`).
///
/// The usual case, a launcher entry named after the package, is one file
/// read; only otherwise is the package's file list asked of `rpm`, which
/// took 20 to 30 ms on the GUI thread each time an installed app's page
/// opened (Jolla Phone, 27 October 2026).
pub fn desktop_entry(root: &Path, package: &str) -> Option<String> {
    if NOT_OPENED.contains(&package) {
        return None;
    }
    let own = format!("{package}.desktop");
    if std::fs::read_to_string(root.join("usr/share/applications").join(&own))
        .is_ok_and(|text| shown(&text))
    {
        return Some(own);
    }
    let out = reef_backend::c_locale(&mut Command::new("rpm"))
        .args(["-q", "--qf", "[%{FILENAMES}\\n]", package])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()
        .filter(|o| o.status.success())?;
    let files = String::from_utf8_lossy(&out.stdout);
    pick(&files, |path| {
        std::fs::read_to_string(root.join(path.trim_start_matches('/'))).ok()
    })
}

/// The first shown `.desktop` file under `/usr/share/applications` among
/// `files` (one path a line); `read` gives a file's contents.
fn pick(files: &str, read: impl Fn(&str) -> Option<String>) -> Option<String> {
    files
        .lines()
        .map(str::trim)
        .filter(|f| {
            f.starts_with("/usr/share/applications/")
                && f.ends_with(".desktop")
                && !f["/usr/share/applications/".len()..].contains('/')
        })
        .find(|f| read(f).is_some_and(|text| shown(&text)))
        .and_then(|f| f.rsplit('/').next())
        .map(str::to_owned)
}

/// Whether a desktop entry is an application the launcher shows.
fn shown(entry: &str) -> bool {
    let mut in_entry = false;
    let mut application = false;
    for line in entry.lines().map(str::trim) {
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }
        match line.split_once('=').map(|(k, v)| (k.trim(), v.trim())) {
            Some(("NoDisplay" | "Hidden", v)) if v.eq_ignore_ascii_case("true") => return false,
            Some(("Type", v)) => application = v == "Application",
            _ => {}
        }
    }
    application
}

/// Runs `cmd` with the person's own group instead of Reef's effective
/// `privileged` group (Reef is started privileged to talk to `PackageKit`).
/// A program started with an effective group other than its real one runs
/// in secure mode: systemd and libdbus then ignore `XDG_RUNTIME_DIR` and
/// `DBUS_SESSION_BUS_ADDRESS` and cannot reach the person's session.
pub fn as_person(cmd: &mut Command) -> &mut Command {
    use std::os::unix::process::CommandExt;
    // SAFETY: getgid has no preconditions and cannot fail.
    let gid = unsafe { libc::getgid() };
    cmd.gid(gid)
}

/// Starts the app of `entry` (a file name from [`desktop_entry`]).
pub fn open(entry: &str) -> std::io::Result<()> {
    use std::os::unix::process::CommandExt;
    let mut child = as_person(&mut Command::new("/usr/bin/lca-tool"))
        .args(["--triggerdesktop", entry])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        // Not in Reef's group: closing Reef does not take the app with it.
        .process_group(0)
        .spawn()?;
    // Reaped when it ends (with the app), without holding Reef up.
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_entry_named_after_the_package_needs_no_rpm() {
        let root = std::env::temp_dir().join(format!("reef-launch-{}", std::process::id()));
        let apps = root.join("usr/share/applications");
        std::fs::create_dir_all(&apps).unwrap();
        std::fs::write(
            apps.join("shipwright-shoal-keys.desktop"),
            "[Desktop Entry]\nType=Application\nName=Keys\n",
        )
        .unwrap();
        std::fs::write(
            apps.join("hidden-thing.desktop"),
            "[Desktop Entry]\nType=Application\nNoDisplay=true\n",
        )
        .unwrap();
        assert_eq!(
            desktop_entry(&root, "shipwright-shoal-keys").as_deref(),
            Some("shipwright-shoal-keys.desktop")
        );
        assert_eq!(
            desktop_entry(&root, "shipwright-reef"),
            None,
            "Reef is open already"
        );
        // Hidden: not offered by the fast path (rpm, absent here, finds
        // nothing either).
        assert_eq!(desktop_entry(&root, "hidden-thing"), None);
        std::fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn finds_the_shown_launcher_entry() {
        let files = "/usr/bin/shipwright-shoal-camera\n\
                     /usr/share/applications/shipwright-shoal-camera-qr.desktop\n\
                     /usr/share/applications/shipwright-shoal-camera.desktop\n\
                     /usr/share/applications/sub/other.desktop\n";
        let read = |path: &str| {
            Some(match path {
                p if p.ends_with("camera-qr.desktop") => {
                    "[Desktop Entry]\nType=Application\nNoDisplay=true\n".to_string()
                }
                _ => "[Desktop Entry]\nType=Application\nName=Camera\n\n[X-Sailjail]\nNoDisplay=true\n"
                    .to_string(),
            })
        };
        assert_eq!(
            pick(files, read).as_deref(),
            Some("shipwright-shoal-camera.desktop"),
            "NoDisplay in another section does not hide it"
        );
        // An add-on installs no launcher entry.
        assert_eq!(
            pick("/usr/share/patchmanager/patches/x/patch.json\n", |_| None),
            None
        );
        // A link, not an application.
        assert_eq!(
            pick("/usr/share/applications/x.desktop\n", |_| Some(
                "[Desktop Entry]\nType=Link\n".into()
            )),
            None
        );
        assert_eq!(desktop_entry(Path::new("/"), "shipwright-reef"), None);
    }
}
