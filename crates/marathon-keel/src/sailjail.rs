//! A Sailfish app's `[X-Sailjail]` permissions as a bubblewrap sandbox, in
//! place of Sailfish's firejail profiles (sailfishos/sailjail-permissions).

/// bwrap's arguments up to, not including, the command.
pub fn bwrap_args(
    permissions: &[String],
    organization: &str,
    application: &str,
    home: &str,
    runtime_dir: &str,
) -> Vec<String> {
    let has = |p: &str| permissions.iter().any(|x| x == p);
    let mut a: Vec<String> = [
        "--die-with-parent",
        "--new-session",
        "--unshare-pid",
        "--unshare-ipc",
    ]
    .map(String::from)
    .to_vec();
    let mut add = |args: &[&str]| a.extend(args.iter().map(|s| (*s).to_owned()));
    if !has("Internet") {
        add(&["--unshare-net"]);
    }
    for dir in ["/etc", "/lib", "/bin", "/sbin"] {
        add(&["--ro-bind-try", dir, dir]);
    }
    add(&[
        "--ro-bind",
        "/usr",
        "/usr",
        "--proc",
        "/proc",
        "--dev",
        "/dev",
        "--dev-bind-try",
        "/dev/dri",
        "/dev/dri",
    ]);
    add(&[
        "--ro-bind-try",
        "/sys",
        "/sys",
        "--ro-bind-try",
        "/run/dbus",
        "/run/dbus",
        "--tmpfs",
        "/tmp",
    ]);
    // Home is private; the app writes only its own directories, as Sailjail allows.
    add(&["--tmpfs", home]);
    for base in ["/.local/share", "/.cache", "/.config"] {
        let own = format!("{home}{base}/{organization}/{application}");
        add(&["--bind", &own, &own]);
    }
    let dconf = format!("{home}/.config/dconf");
    add(&[
        "--ro-bind-try",
        &dconf,
        &dconf,
        "--bind",
        runtime_dir,
        runtime_dir,
    ]);
    for (permission, folder) in [
        ("Pictures", "Pictures"),
        ("Music", "Music"),
        ("Videos", "Videos"),
        ("Documents", "Documents"),
        ("Downloads", "Downloads"),
        ("Audio", "Music"),
    ] {
        if has(permission) {
            let path = format!("{home}/{folder}");
            add(&["--bind-try", &path, &path]);
        }
    }
    if has("Camera") {
        for i in 0..4 {
            let dev = format!("/dev/video{i}");
            add(&["--dev-bind-try", &dev, &dev]);
        }
    }
    if has("RemovableMedia") {
        add(&["--bind-try", "/run/media", "/run/media"]);
    }
    a
}
