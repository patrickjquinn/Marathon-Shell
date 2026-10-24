//! Desktop entries (`.desktop` files) as the home grid's native apps.

use std::cmp::Reverse;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QStringList, QVariant};
use freedesktop_entry_parser::Entry;

#[cxx_qt::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    #[namespace = "marathon::desktop"]
    extern "Rust" {
        /// The apps in these folders' entries; with `phone_only`, those
        /// that work on a phone.
        fn scan(paths: &QStringList, phone_only: bool) -> QList_QVariant;
        /// One entry, even one kept off the grid; empty if it is no app.
        fn parse(path: &QString) -> QMap_QString_QVariant;
        /// The apps the Store found phone-ready in Flathub's `AppStream`.
        fn phone_apps_path() -> QString;
        /// The command runs a Keel app under `marathon-keel-host`.
        fn is_keel_hosted(command: &QString) -> bool;
    }
}

const FALLBACK_ICON: &str = "layout-grid";

// Wayland only: an app that needs an X server would spin on its splash.
const X11_ONLY: &[&str] = &[
    "xterm", "uxterm", "xclock", "xcalc", "xeyes", "xlogo", "xev", "xinit", "xrdb", "xfontsel",
    "xkbcomp", "xkill", "xset", "xsetbg", "xsetroot", "xrandr", "xdpyinfo",
];

// Desktop tools that ship ordinary entries but are no phone app.
const DEV_TOOLS: &[&str] = &[
    "alacritty",
    "foot",
    "footclient",
    "foot-server",
    "htop",
    "btop",
    "lxterminal",
    "xterm",
    "uxterm",
    "qterminal",
    "marathon-test",
    "marathon-dev",
    "marathon-camera-dev-pre",
];

// Adaptive apps that do not say so in their entry.
const ADAPTIVE: &[&str] = &[
    "org.gnome.Calendar",
    "org.gnome.Calls",
    "org.gnome.Chess",
    "org.gnome.Contacts",
    "org.gnome.Loupe",
    "org.gnome.Maps",
    "org.gnome.Music",
    "org.gnome.Papers",
    "org.gnome.Snapshot",
    "org.gnome.TextEditor",
    "org.gnome.Weather",
    "org.gnome.clocks",
    "org.gnome.font-viewer",
    "sm.puri.Chatty",
    "sm.puri.Phosh",
    "org.sigxcpu.Phosh",
    "org.kde.angelfish",
    "org.kde.calindori",
    "org.kde.kalk",
    "org.kde.kasts",
    "org.kde.kclock",
    "org.kde.koko",
    "org.kde.neochat",
    "org.kde.tokodon",
    "org.gnome.Console",
    "io.github.tchx84.Flatseal",
    "page.codeberg.libre_menteur.LibreMenteur",
];

const WINDOW_FLAGS: &[&str] = &[
    "--new-window",
    "-new-window",
    "--new-tab",
    "-new-tab",
    "--new-instance",
    "-new-instance",
];

#[derive(Debug, Default, PartialEq)]
struct App {
    id: String,
    name: String,
    icon: String,
    exec: String,
    flatpak_ref: Option<String>,
    categories: Vec<String>,
    keywords: Vec<String>,
    // Form-factor hints: X-Purism-FormFactor, then X-KDE-FormFactors.
    purism: Vec<String>,
    kde: Vec<String>,
    shown: bool,
}

impl App {
    fn is_flatpak(&self) -> bool {
        self.exec.starts_with("FLATPAK:")
    }

    fn fits_a_phone(&self, phone_apps: &HashSet<String>) -> bool {
        let has = |list: &[String], words: &[&str]| {
            list.iter()
                .any(|v| words.iter().any(|w| v.to_lowercase().contains(w)))
        };
        if DEV_TOOLS.contains(&self.id.to_lowercase().as_str()) {
            return false;
        }
        phone_apps.contains(&self.id)
            || has(&self.purism, &["mobile"])
            || has(&self.kde, &["handset", "phone"])
            || self
                .categories
                .iter()
                .any(|c| c.eq_ignore_ascii_case("mobile") || c.eq_ignore_ascii_case("phone"))
            || ADAPTIVE.contains(&self.id.as_str())
    }

    fn to_qt(&self) -> QMap<QMapPair_QString_QVariant> {
        let list = |items: &[String]| {
            QVariant::from(&items.iter().map(QString::from).collect::<QStringList>())
        };
        let text = |s: &str| QVariant::from(&QString::from(s));
        let mut map = QMap::<QMapPair_QString_QVariant>::default();
        map.insert(QString::from("id"), text(&self.id));
        map.insert(QString::from("name"), text(&self.name));
        map.insert(QString::from("icon"), text(&self.icon));
        map.insert(QString::from("exec"), text(&self.exec));
        map.insert(
            QString::from("type"),
            text(if self.is_flatpak() {
                "flatpak"
            } else {
                "native"
            }),
        );
        map.insert(QString::from("categories"), list(&self.categories));
        map.insert(QString::from("keywords"), list(&self.keywords));
        if let Some(r) = &self.flatpak_ref {
            map.insert(QString::from("flatpakRef"), text(r));
        }
        map
    }
}

fn scan(paths: &QStringList, phone_only: bool) -> QList<QVariant> {
    let paths: Vec<PathBuf> = QList::<QString>::from(paths)
        .iter()
        .map(|p| PathBuf::from(p.to_string()))
        .collect();
    let phone_apps = read_phone_apps(&cached_phone_apps());
    let mut icons = Icons::new();
    scan_apps(&paths, &mut icons)
        .filter(|app| app.shown && (!phone_only || app.fits_a_phone(&phone_apps)))
        .map(|app| QVariant::from(&app.to_qt()))
        .collect()
}

pub(crate) fn parse(path: &QString) -> QMap<QMapPair_QString_QVariant> {
    read_app(Path::new(&path.to_string()), &mut Icons::new())
        .map(|app| app.to_qt())
        .unwrap_or_default()
}

fn phone_apps_path() -> QString {
    QString::from(cached_phone_apps().to_string_lossy().as_ref())
}

const KEEL_HOST: &str = "marathon-keel-host ";

pub(crate) fn is_keel_hosted(command: &QString) -> bool {
    command.to_string().starts_with(KEEL_HOST)
}

fn scan_apps<'a>(paths: &'a [PathBuf], icons: &'a mut Icons) -> impl Iterator<Item = App> + 'a {
    paths
        .iter()
        .flat_map(|dir| {
            let mut entries: Vec<PathBuf> = fs::read_dir(dir)
                .into_iter()
                .flatten()
                .flatten()
                .map(|e| e.path())
                .filter(|p| p.extension().is_some_and(|e| e == "desktop"))
                .collect();
            entries.sort_by_key(|p| p.to_string_lossy().to_lowercase());
            entries
        })
        .filter_map(|path| read_app(&path, icons))
}

fn read_app(path: &Path, icons: &mut Icons) -> Option<App> {
    let entry = Entry::parse(fs::read(path).ok()?).ok()?;
    let desktop = entry.section("Desktop Entry")?;
    let get = |key: &str| desktop.attr(key).last().map(String::as_str);
    let list = |key: &str| get(key).map(split).unwrap_or_default();
    let yes = |key: &str| get(key).is_some_and(|v| v.eq_ignore_ascii_case("true"));
    if get("Type").is_some_and(|t| t != "Application") {
        return None;
    }
    let raw_exec = get("Exec")?;
    let mut exec = clean_exec(raw_exec)?;
    let binary = exec
        .split_whitespace()
        .find(|t| !t.starts_with('-'))
        .map(file_name)
        .unwrap_or_default();
    if X11_ONLY.contains(&binary) {
        return None;
    }
    let id = path.file_stem()?.to_string_lossy().into_owned();
    // A Keel app runs under marathon-keel-host.
    let sailjail = entry.section("X-Sailjail");
    let keel =
        sailjail.is_some() || raw_exec.starts_with("sailfish-qml ") || yes("X-Marathon-KeelHost");
    if keel {
        // Sandboxed by its Sailjail permissions when it names itself.
        let jail = sailjail.and_then(|s| {
            let named = |key| s.attr(key).last().filter(|v| !v.is_empty());
            let permissions = split(s.attr("Permissions").last()?).join(",");
            Some(format!(
                " --sailjail {permissions} --org {} --app {}",
                named("OrganizationName")?,
                named("ApplicationName")?
            ))
        });
        exec = format!(
            "{KEEL_HOST}--app-id {id}{} -- {exec}",
            jail.unwrap_or_default()
        );
    }
    let mut app = App {
        name: get("Name")?.to_owned(),
        icon: icons.resolve(get("Icon").unwrap_or_default()),
        flatpak_ref: get("X-Flatpak").map(str::to_owned),
        categories: list("Categories"),
        keywords: list("Keywords"),
        purism: list("X-Purism-FormFactor"),
        kde: list("X-KDE-FormFactors"),
        shown: !yes("NoDisplay") && !yes("Hidden"),
        id,
        exec,
    };
    if app.is_flatpak() && app.flatpak_ref.is_none() {
        // Older exports have no X-Flatpak: the ref ends the command.
        app.flatpak_ref = app
            .exec
            .split_whitespace()
            .rev()
            .find(|t| !t.starts_with('-') && t.contains('.'))
            .map(str::to_owned);
    }
    Some(app)
}

fn split(value: &str) -> Vec<String> {
    value
        .split(';')
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .collect()
}

fn file_name(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

/// The command the compositor runs for an entry's `Exec`, or `None` for a
/// D-Bus-activated service.
fn clean_exec(exec: &str) -> Option<String> {
    let mut stripped = String::with_capacity(exec.len());
    let mut chars = exec.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '%' && chars.peek().is_some_and(|n| "fFuUdDnNickvm".contains(*n)) {
            chars.next();
        } else {
            stripped.push(c);
        }
    }
    let mut cleaned = stripped
        .split_whitespace()
        .filter(|t| !WINDOW_FLAGS.contains(t))
        .collect::<Vec<_>>()
        .join(" ");
    if cleaned.is_empty() {
        return None;
    }
    if let Some(app_id) = cleaned.strip_prefix("gapplication launch ") {
        // org.gnome.Calculator runs as gnome-calculator.
        let parts: Vec<&str> = app_id.trim().split('.').collect();
        return Some(match parts.as_slice() {
            [.., vendor, name] if parts.len() >= 3 => {
                format!("{}-{}", vendor.to_lowercase(), name.to_lowercase())
            }
            [_, name] => name.to_lowercase(),
            _ => cleaned,
        });
    }
    if cleaned.contains("--gapplication-service") {
        return None;
    }
    if let Some(rest) = cleaned.strip_prefix("/usr/bin/flatpak run ") {
        cleaned = format!("flatpak run {rest}");
    }
    if cleaned.starts_with("flatpak run ") {
        return Some(format!("FLATPAK:{cleaned}"));
    }
    if cleaned.starts_with("snap run ") || cleaned.starts_with("/snap/bin/") {
        return Some(format!("SNAP:{cleaned}"));
    }
    if cleaned.starts_with('/') {
        let (binary, args) = cleaned.split_once(' ').unwrap_or((&cleaned, ""));
        return Some(
            format!("{} {args}", file_name(binary))
                .trim_end()
                .to_owned(),
        );
    }
    Some(cleaned)
}

/// Icon names to files, looked up once per scan.
struct Icons {
    dirs: Vec<PathBuf>,
    found: HashMap<String, String>,
}

impl Icons {
    fn new() -> Self {
        let home = marathon_rt::dirs::home();
        let local = home.join(".local/share");
        let bases = [
            local.join("icons"),
            "/usr/share/icons".into(),
            local.join("flatpak/exports/share/icons"),
            "/var/lib/flatpak/exports/share/icons".into(),
        ];
        let themes = ["hicolor", "PiXtrix", "Adwaita", "gnome", "AdwaitaLegacy"];
        let contexts = ["apps", "categories", "devices", "places", "legacy"];
        let mut sized = Vec::new();
        for theme in themes {
            for base in &bases {
                for entry in fs::read_dir(base.join(theme))
                    .into_iter()
                    .flatten()
                    .flatten()
                {
                    if let Some(size) = entry.file_name().to_str().and_then(icon_size) {
                        sized.extend(contexts.map(|c| (Reverse(size), entry.path().join(c))));
                    }
                }
            }
        }
        sized.sort_by_key(|(size, _)| *size);
        let mut dirs: Vec<PathBuf> = sized.into_iter().map(|(_, dir)| dir).collect();
        dirs.extend([
            "/var/lib/snapd/desktop/icons".into(),
            "/usr/share/pixmaps".into(),
        ]);
        dirs.retain(|d| d.is_dir());
        Self {
            dirs,
            found: HashMap::new(),
        }
    }

    fn resolve(&mut self, name: &str) -> String {
        if let Some(path) = self.found.get(name) {
            return path.clone();
        }
        let path = self.find(name).unwrap_or_else(|| FALLBACK_ICON.to_owned());
        self.found.insert(name.to_owned(), path.clone());
        path
    }

    fn find(&self, name: &str) -> Option<String> {
        let is_file = |p: &Path| p.is_file().then(|| p.to_string_lossy().into_owned());
        if name.is_empty() {
            return None;
        }
        if name.starts_with('/')
            || [".svg", ".png", ".xpm", ".jpg"]
                .iter()
                .any(|e| name.ends_with(e))
        {
            if let Some(path) = is_file(Path::new(name)) {
                return Some(path);
            }
            if name.starts_with('/') {
                return None;
            }
        }
        self.dirs.iter().find_map(|dir| {
            ["png", "svg", "xpm", "jpg", ""].iter().find_map(|ext| {
                is_file(&dir.join(if ext.is_empty() {
                    name.to_owned()
                } else {
                    format!("{name}.{ext}")
                }))
            })
        })
    }
}

/// A theme size directory's pixel size (`86x86`, `128x128@2`); scalable
/// ranks above every bitmap.
fn icon_size(dir: &str) -> Option<u32> {
    if dir == "scalable" {
        return Some(u32::MAX);
    }
    let (size, scale) = dir.split_once('@').unwrap_or((dir, "1"));
    let (width, _) = size.split_once('x')?;
    width.parse::<u32>().ok()?.checked_mul(scale.parse().ok()?)
}

fn cached_phone_apps() -> PathBuf {
    marathon_rt::dirs::cache().join("marathon-store/phone-apps.json")
}

/// Desktop ids in the Store's `{"apps": [...]}`.
fn read_phone_apps(path: &Path) -> HashSet<String> {
    #[derive(serde::Deserialize)]
    struct PhoneApps {
        apps: Vec<String>,
    }
    let Some(list) = fs::read(path)
        .ok()
        .and_then(|b| serde_json::from_slice::<PhoneApps>(&b).ok())
    else {
        return HashSet::new();
    };
    list.apps
        .into_iter()
        .map(|id| id.strip_suffix(".desktop").map(str::to_owned).unwrap_or(id))
        .filter(|id| !id.is_empty())
        .collect()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn entry(dir: &Path, file: &str, text: &str) -> PathBuf {
        let path = dir.join(file);
        fs::write(&path, text).unwrap();
        path
    }

    fn app(text: &str) -> Option<App> {
        let dir = tempfile::tempdir().unwrap();
        read_app(&entry(dir.path(), "app.desktop", text), &mut Icons::new())
    }

    fn exec_of(exec: &str) -> Option<String> {
        app(&format!(
            "[Desktop Entry]\nType=Application\nName=A\nExec={exec}\n"
        ))
        .map(|a| a.exec)
    }

    #[test]
    fn an_entry_reads_as_an_app() {
        let a = app("[Desktop Entry]\n# a comment\nType=Application\nName=Test App\nName[de]=Test\nExec=test-app --flag\nCategories=Utility;Development;\nKeywords=Web;Internet;\n\n[Desktop Action New]\nName=Action\nExec=action-app\n").unwrap();
        assert_eq!(
            (a.id.as_str(), a.name.as_str(), a.exec.as_str()),
            ("app", "Test App", "test-app --flag")
        );
        assert_eq!(a.categories, ["Utility", "Development"]);
        assert_eq!(a.keywords, ["Web", "Internet"]);
        assert_eq!(a.icon, FALLBACK_ICON);
        assert!(a.shown && !a.is_flatpak());
    }

    #[test]
    fn what_is_no_app_is_refused() {
        assert!(
            app("[Desktop Entry]\nType=Link\nName=L\nExec=x\nURL=https://example.com\n").is_none()
        );
        assert!(app("[Desktop Entry]\nType=Application\nExec=x\n").is_none());
        assert!(app("[Desktop Entry]\nType=Application\nName=N\n").is_none());
        assert!(app("[Other]\nName=N\nExec=x\n").is_none());
        assert!(exec_of("xterm -e top").is_none());
        assert!(exec_of("/usr/bin/xclock").is_none());
        assert!(exec_of("foo --gapplication-service").is_none());
        assert!(read_app(Path::new("/nonexistent/path.desktop"), &mut Icons::new()).is_none());
    }

    #[test]
    fn hidden_entries_still_launch_but_stay_off_the_grid() {
        let a = app("[Desktop Entry]\nType=Application\nName=N\nExec=x\nNoDisplay=true\n").unwrap();
        assert!(!a.shown);
        assert!(
            !app("[Desktop Entry]\nType=Application\nName=N\nExec=x\nHidden=True\n")
                .unwrap()
                .shown
        );
    }

    #[test]
    fn commands_lose_what_the_compositor_cannot_honour() {
        assert_eq!(
            exec_of("myapp --verbose %U --file=%f").as_deref(),
            Some("myapp --verbose --file=")
        );
        assert_eq!(
            exec_of("firefox --new-window %u").as_deref(),
            Some("firefox")
        );
        assert_eq!(
            exec_of("my-new-window-app --some-flag").as_deref(),
            Some("my-new-window-app --some-flag")
        );
        assert_eq!(
            exec_of("/usr/bin/my-program --arg").as_deref(),
            Some("my-program --arg")
        );
        assert_eq!(
            exec_of("gapplication launch org.gnome.Calculator").as_deref(),
            Some("gnome-calculator")
        );
        assert_eq!(
            exec_of("snap run foo").as_deref(),
            Some("SNAP:snap run foo")
        );
    }

    #[test]
    fn flatpaks_are_typed_with_their_ref() {
        let a = app("[Desktop Entry]\nType=Application\nName=F\nExec=/usr/bin/flatpak run --branch=stable --command=f org.test.App @@u %U @@\n").unwrap();
        assert!(a.exec.starts_with("FLATPAK:flatpak run "));
        assert_eq!(a.flatpak_ref.as_deref(), Some("org.test.App"));
        let b = app("[Desktop Entry]\nType=Application\nName=F\nExec=flatpak run org.a.B\nX-Flatpak=org.a.B\n").unwrap();
        assert_eq!(b.flatpak_ref.as_deref(), Some("org.a.B"));
    }

    #[test]
    fn keel_apps_run_under_the_keel_host() {
        let jailed = app("[Desktop Entry]\nType=Application\nName=Foo\nExec=sailfish-qml harbour-foo\n\n[X-Sailjail]\nPermissions=Internet;Pictures\nOrganizationName=org.example\nApplicationName=foo\n").unwrap();
        assert_eq!(jailed.exec, "marathon-keel-host --app-id app --sailjail Internet,Pictures --org org.example --app foo -- sailfish-qml harbour-foo");
        let qml = exec_of("sailfish-qml harbour-foo").unwrap();
        assert_eq!(
            qml,
            "marathon-keel-host --app-id app -- sailfish-qml harbour-foo"
        );
        let keyed = app(
            "[Desktop Entry]\nType=Application\nName=P\nExec=pacific\nX-Marathon-KeelHost=true\n",
        )
        .unwrap();
        assert_eq!(keyed.exec, "marathon-keel-host --app-id app -- pacific");
        assert_eq!(exec_of("foot").as_deref(), Some("foot"));
        assert!(is_keel_hosted(&QString::from(&keyed.exec)));
        assert!(!is_keel_hosted(&QString::from(
            "marathon-app-runner --app-id foo"
        )));
    }

    #[test]
    fn only_phone_apps_pass_the_phone_filter() {
        let dir = tempfile::tempdir().unwrap();
        let body =
            |extra: &str| format!("[Desktop Entry]\nType=Application\nName=N\nExec=x\n{extra}\n");
        entry(dir.path(), "org.gnome.Calls.desktop", &body(""));
        entry(
            dir.path(),
            "purism.desktop",
            &body("X-Purism-FormFactor=Workstation;Mobile;"),
        );
        entry(
            dir.path(),
            "kde.desktop",
            &body("X-KDE-FormFactors=desktop;handset"),
        );
        entry(dir.path(), "cat.desktop", &body("Categories=GTK;Mobile;"));
        entry(dir.path(), "desk.desktop", &body("Categories=Office;"));
        entry(
            dir.path(),
            "foot.desktop",
            &body("X-Purism-FormFactor=Mobile;"),
        );
        entry(dir.path(), "org.flathub.Phone.desktop", &body(""));
        let phone = read_phone_apps(&entry(
            dir.path(),
            "phone-apps.json",
            r#"{"apps":["org.flathub.Phone.desktop",""]}"#,
        ));
        let paths = [dir.path().to_owned()];
        let mut icons = Icons::new();
        let ids: Vec<String> = scan_apps(&paths, &mut icons)
            .filter(|a| a.fits_a_phone(&phone))
            .map(|a| a.id)
            .collect();
        assert_eq!(
            ids,
            [
                "cat",
                "kde",
                "org.flathub.Phone",
                "org.gnome.Calls",
                "purism"
            ]
        );
        assert_eq!(scan_apps(&paths, &mut icons).count(), 7);
        assert_eq!(read_phone_apps(&dir.path().join("missing.json")), HashSet::new());
    }

    #[test]
    fn icons_fall_back_alike() {
        let mut icons = Icons::new();
        for name in ["", "nonexistent-icon-xyz-12345", "/nonexistent/icon.png"] {
            assert_eq!(icons.resolve(name), FALLBACK_ICON);
        }
        let dir = tempfile::tempdir().unwrap();
        let file = entry(dir.path(), "i.svg", "<svg/>");
        assert_eq!(
            icons.resolve(&file.to_string_lossy()),
            file.to_string_lossy()
        );
    }
}
