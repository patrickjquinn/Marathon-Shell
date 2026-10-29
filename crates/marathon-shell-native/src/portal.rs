//! xdg-desktop-portal's backends, `org.freedesktop.impl.portal.desktop.marathon`
//! at /org/freedesktop/portal/desktop: Settings serves the ambience in the
//! namespaces each toolkit reads inside a Flatpak (org.freedesktop.appearance,
//! GTK's org.gnome.desktop.interface and KDE's org.kde.kdeglobals.*);
//! `FileChooser` opens the shell's picker sheet (`FileChooser`, QML
//! `FileChooserPortal`) for Flatpaks and Android's pickers through deckardd,
//! one request at a time.

#![allow(
    clippy::unused_self,
    clippy::needless_pass_by_value,
    clippy::used_underscore_binding,
    reason = "D-Bus methods: zbus hands them owned arguments and the portal's unused ones"
)]

use std::collections::{BTreeMap, HashMap};
use std::pin::Pin;
use std::sync::{LazyLock, Mutex, OnceLock};

use cxx_qt::Threading;
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QStringList};
use zbus::object_server::SignalEmitter;
use zbus::{fdo, interface};
use zbus::{
    DeserializeDict, ObjectPath, OwnedObjectPath, OwnedVariant as OwnedValue, Type,
    Variant as Value,
};

use crate::theme::{self, Color};
use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    unsafe extern "RustQt" {
        #[qobject]
        type FileChooser = super::FileChooserRust;

        /// mode ("open", "save", "saveMany"), title, acceptLabel, multiple,
        /// directory, filters [{name, globs, mimes}], filterIndex, folder,
        /// name, files (SaveMany), choices [{id, label, options [{id, label}], value}]
        #[qsignal]
        fn requested(self: Pin<&mut FileChooser>, request: &QMap_QString_QVariant);
        /// The request went (the app closed it, or a newer one replaced it).
        #[qsignal]
        fn closed(self: Pin<&mut FileChooser>);

        /// paths: the files chosen; for SaveMany the folder. filter_index:
        /// the filter in effect, -1 for none. choices: id -> value.
        #[qinvokable]
        fn accept(
            self: &FileChooser,
            paths: &QStringList,
            filter_index: i32,
            choices: &QMap_QString_QVariant,
        );
        #[qinvokable]
        fn cancel(self: &FileChooser);
    }

    impl cxx_qt::Threading for FileChooser {}
    impl cxx_qt::Initialize for FileChooser {}
}

use qobject::FileChooser;

const NAME: &str = "org.freedesktop.impl.portal.desktop.marathon";
const PATH: &str = "/org/freedesktop/portal/desktop";

// Marathon's UI faces: Source Sans 3 stands in for Sail Sans Pro.
const SANS: &str = "Source Sans 3";
const MONO: &str = "JetBrains Mono";

#[derive(Clone, Debug, PartialEq)]
enum V {
    U(u32),
    I(i32),
    F(f64),
    B(bool),
    S(String),
    Rgb(f64, f64, f64),
}

impl V {
    fn value(&self) -> OwnedValue {
        let v = match self {
            Self::U(x) => Value::from(*x),
            Self::I(x) => Value::from(*x),
            Self::F(x) => Value::from(*x),
            Self::B(x) => Value::from(*x),
            Self::S(x) => Value::from(x.clone()),
            Self::Rgb(r, g, b) => Value::from((*r, *g, *b)),
        };
        OwnedValue::try_from(v).unwrap_or_else(|_| OwnedValue::from(0u32))
    }
}

type Namespaces = BTreeMap<String, BTreeMap<String, V>>;

static CURRENT: LazyLock<Mutex<Namespaces>> = LazyLock::new(|| Mutex::new(settings(None, 1)));

fn current() -> std::sync::MutexGuard<'static, Namespaces> {
    CURRENT.lock().unwrap_or_else(|_| std::process::abort())
}

/// `QFont::toString`'s form, which kdeglobals stores and `KFontSettingsData` parses.
fn kde_font(family: &str, points: u32) -> V {
    V::S(format!("{family},{points},-1,5,400,0,0,0,0,0,0,0,0,0,0,1"))
}

/// Every namespace served for an ambience. scheme: 0 no preference, 1
/// dark, 2 light. GTK 3 stays on upstream Adwaita; GTK 4 and KDE consume the
/// generated semantic colours.
fn settings(accent: Option<Color>, scheme: u32) -> Namespaces {
    let s = |x: &str| V::S(x.to_owned());
    let theme = "Adwaita";
    let mut fdo = BTreeMap::from([
        ("color-scheme".to_owned(), V::U(scheme)),
        ("contrast".to_owned(), V::U(0)),
        ("reduced-motion".to_owned(), V::U(0)),
    ]);
    let mut gnome = BTreeMap::from([
        (
            "color-scheme".to_owned(),
            s(match scheme {
                1 => "prefer-dark",
                2 => "prefer-light",
                _ => "default",
            }),
        ),
        (
            "gtk-theme".to_owned(),
            V::S(if scheme == 1 {
                format!("{theme}-dark")
            } else {
                theme.to_owned()
            }),
        ),
        ("icon-theme".to_owned(), s("Adwaita")),
        ("font-name".to_owned(), V::S(format!("{SANS} 11"))),
        ("document-font-name".to_owned(), V::S(format!("{SANS} 11"))),
        ("monospace-font-name".to_owned(), V::S(format!("{MONO} 10"))),
        ("text-scaling-factor".to_owned(), V::F(1.0)),
        ("cursor-theme".to_owned(), s("Adwaita")),
        ("cursor-size".to_owned(), V::I(24)),
        ("gtk-decoration-layout".to_owned(), s(":")),
        ("overlay-scrolling".to_owned(), V::B(true)),
        ("gtk-enable-primary-paste".to_owned(), V::B(false)),
        ("enable-animations".to_owned(), V::B(true)),
    ]);
    let mut kde: BTreeMap<String, BTreeMap<String, V>> = BTreeMap::from([
        (
            "General".to_owned(),
            BTreeMap::from([
                ("font".to_owned(), kde_font(SANS, 11)),
                ("menuFont".to_owned(), kde_font(SANS, 11)),
                ("toolBarFont".to_owned(), kde_font(SANS, 11)),
                ("taskbarFont".to_owned(), kde_font(SANS, 11)),
                ("smallestReadableFont".to_owned(), kde_font(SANS, 9)),
                ("fixed".to_owned(), kde_font(MONO, 10)),
            ]),
        ),
        (
            "KDE".to_owned(),
            BTreeMap::from([("widgetStyle".to_owned(), s("Breeze"))]),
        ),
        (
            "Icons".to_owned(),
            BTreeMap::from([("Theme".to_owned(), s("breeze"))]),
        ),
        (
            "WM".to_owned(),
            BTreeMap::from([("activeFont".to_owned(), kde_font(SANS, 11))]),
        ),
    ]);
    if let Some(accent) = accent {
        fdo.insert(
            "accent-color".to_owned(),
            V::Rgb(accent.red.into(), accent.green.into(), accent.blue.into()),
        );
        gnome.insert("accent-color".to_owned(), s(theme::gnome_accent(accent)));
        for (group, keys) in theme::kde_colors(&theme::palette(accent, scheme != 2)) {
            kde.entry(group)
                .or_default()
                .extend(keys.into_iter().map(|(k, v)| (k, V::S(v))));
        }
        kde.entry("General".to_owned())
            .or_default()
            .insert("ColorScheme".to_owned(), s("Marathon"));
    }
    let mut out = Namespaces::from([
        ("org.freedesktop.appearance".to_owned(), fdo),
        ("org.gnome.desktop.interface".to_owned(), gnome),
        (
            "org.gnome.desktop.wm.preferences".to_owned(),
            BTreeMap::from([("button-layout".to_owned(), s(":"))]),
        ),
    ]);
    out.extend(
        kde.into_iter()
            .map(|(g, keys)| (format!("org.kde.kdeglobals.{g}"), keys)),
    );
    out
}

/// Whether a namespace matches `ReadAll`'s filters ("" or "prefix.*" globs).
fn matches(ns: &str, filters: &[String]) -> bool {
    filters.is_empty()
        || filters.iter().any(|f| {
            f.is_empty()
                || f == ns
                || f.strip_suffix('*')
                    .is_some_and(|p| p.ends_with('.') && ns.starts_with(p))
        })
}

/// A new ambience: write GTK 4 and KDE files first, then announce what
/// changed. KDE's platform theme reloads the whole palette when
/// General/ColorScheme changes and ignores the colour keys themselves, as
/// xdg-desktop-portal-kde signals it, so colours are announced through that
/// key alone.
pub(crate) fn set_ambience(highlight: Option<Color>, color_scheme: &str) {
    let scheme = match color_scheme {
        "lightondark" => 1,
        "darkonlight" => 2,
        _ => 0,
    };
    io::spawn(async move {
        if let Some(h) = highlight {
            if let Err(e) = blocking::unblock(move || theme::write(h, scheme != 2)).await {
                log::warn("portal", format_args!("writing native app themes: {e}"));
            }
        }
        let next = settings(highlight, scheme);
        let changes: Vec<(String, String, V)> = {
            let mut cur = current();
            let prev = std::mem::replace(&mut *cur, next.clone());
            let mut kde_changed = false;
            let mut out = Vec::new();
            for (ns, keys) in &next {
                for (k, v) in keys {
                    if prev.get(ns).and_then(|p| p.get(k)) == Some(v) {
                        continue;
                    }
                    let kde_colors = ns.starts_with("org.kde.kdeglobals.Colors:")
                        || ns == "org.kde.kdeglobals.WM";
                    if kde_colors || (ns == "org.kde.kdeglobals.General" && k == "ColorScheme") {
                        kde_changed = true;
                    } else {
                        out.push((ns.clone(), k.clone(), v.clone()));
                    }
                }
            }
            if let Some(v) = next
                .get("org.kde.kdeglobals.General")
                .and_then(|g| g.get("ColorScheme"))
                .filter(|_| kde_changed)
            {
                out.push((
                    "org.kde.kdeglobals.General".into(),
                    "ColorScheme".into(),
                    v.clone(),
                ));
            }
            out
        };
        let Ok(bus) = io::session_bus().await else {
            return;
        };
        let Ok(emitter) = SignalEmitter::new(&bus, PATH) else {
            return;
        };
        for (ns, key, v) in changes {
            if let Err(e) =
                Settings::setting_changed(&emitter, &ns, &key, Value::from(v.value())).await
            {
                log::warn("portal", format_args!("SettingChanged {ns} {key}: {e}"));
            }
        }
    });
}

struct Settings;

#[interface(name = "org.freedesktop.impl.portal.Settings")]
impl Settings {
    #[zbus(property, name = "version")]
    fn version(&self) -> u32 {
        2
    }

    fn read_all(&self, namespaces: Vec<String>) -> HashMap<String, HashMap<String, OwnedValue>> {
        current()
            .iter()
            .filter(|(ns, _)| matches(ns, &namespaces))
            .map(|(ns, keys)| {
                (
                    ns.clone(),
                    keys.iter().map(|(k, v)| (k.clone(), v.value())).collect(),
                )
            })
            .collect()
    }

    fn read_one(&self, namespace: &str, key: &str) -> fdo::Result<OwnedValue> {
        current()
            .get(namespace)
            .and_then(|keys| keys.get(key))
            .map(V::value)
            .ok_or_else(|| fdo::Error::Failed("Requested setting not found".into()))
    }

    fn read(&self, namespace: &str, key: &str) -> fdo::Result<OwnedValue> {
        self.read_one(namespace, key)
    }

    #[zbus(signal)]
    async fn setting_changed(
        emitter: &SignalEmitter<'_>,
        namespace: &str,
        key: &str,
        value: Value<'_>,
    ) -> zbus::Result<()>;
}

// The FileChooser.

type Filter = (String, Vec<(u32, String)>);
type Choice = (String, String, Vec<(String, String)>, String);

#[derive(DeserializeDict, Type, Default)]
#[zbus(signature = "dict")]
struct Options {
    accept_label: Option<String>,
    multiple: Option<bool>,
    directory: Option<bool>,
    filters: Option<Vec<Filter>>,
    current_filter: Option<Filter>,
    choices: Option<Vec<Choice>>,
    current_name: Option<String>,
    current_folder: Option<Vec<u8>>,
    current_file: Option<Vec<u8>>,
    files: Option<Vec<Vec<u8>>>,
    modal: Option<bool>,
}

/// The portal's byte strings (ay) end with a NUL.
fn path_of(bytes: Option<&[u8]>) -> String {
    let b = bytes.unwrap_or_default();
    String::from_utf8_lossy(b.strip_suffix(&[0]).unwrap_or(b)).into_owned()
}

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Open,
    Save,
    SaveMany,
}

type Answer = (u32, HashMap<String, OwnedValue>);

struct Pending {
    handle: OwnedObjectPath,
    mode: Mode,
    filters: Vec<Filter>,
    files: Vec<String>,
    reply: async_channel::Sender<Answer>,
}

static PENDING: Mutex<Option<Pending>> = Mutex::new(None);
static QT: OnceLock<cxx_qt::CxxQtThread<FileChooser>> = OnceLock::new();

fn pending() -> std::sync::MutexGuard<'static, Option<Pending>> {
    PENDING.lock().unwrap_or_else(|_| std::process::abort())
}

/// Ends the request in flight: 0 chosen, 1 cancelled, 2 gone.
fn finish(response: u32, results: HashMap<String, OwnedValue>) {
    let Some(p) = pending().take() else { return };
    p.reply.try_send((response, results)).ok();
    let handle = p.handle;
    io::spawn(async move {
        if let Ok(bus) = io::session_bus().await {
            bus.object_server()
                .remove::<Request, _>(handle.as_ref())
                .await
                .ok();
        }
    });
}

fn gone(handle: &ObjectPath<'_>) {
    let matches_current = pending()
        .as_ref()
        .is_some_and(|request| request.handle.as_ref() == handle.as_str());
    if !matches_current {
        return;
    }
    finish(2, HashMap::new());
    if let Some(qt) = QT.get() {
        qt.queue(FileChooser::closed).ok();
    }
}

fn owned(v: Value<'_>) -> OwnedValue {
    OwnedValue::try_from(v).unwrap_or_else(|_| OwnedValue::from(false))
}

/// A Request: xdg-desktop-portal closes it when the app gives up.
struct Request {
    handle: OwnedObjectPath,
}

#[interface(name = "org.freedesktop.impl.portal.Request")]
impl Request {
    fn close(&self) {
        gone(&self.handle.as_ref());
    }
}

struct Chooser;

impl Chooser {
    #[allow(
        clippy::too_many_lines,
        reason = "portal request validation and response construction form one protocol transaction"
    )]
    async fn request(
        &self,
        mode: Mode,
        handle: ObjectPath<'_>,
        app_id: String,
        parent_window: String,
        title: String,
        o: Options,
    ) -> fdo::Result<Answer> {
        if pending().is_some() {
            let old_handle = pending().as_ref().map(|request| request.handle.clone());
            if let Some(old_handle) = old_handle {
                gone(&old_handle.as_ref());
            }
        }
        let filters = o.filters.unwrap_or_default();
        let files: Vec<String> = o
            .files
            .unwrap_or_default()
            .iter()
            .map(|f| {
                let p = path_of(Some(f));
                p.rsplit('/').next().unwrap_or_default().to_owned()
            })
            .collect();
        let filter_index = o
            .current_filter
            .as_ref()
            .and_then(|c| filters.iter().position(|f| f.0 == c.0))
            .map_or(if filters.is_empty() { -1 } else { 0 }, |i| {
                i32::try_from(i).unwrap_or(0)
            });
        let mut folder = path_of(o.current_folder.as_deref());
        let mut name = o.current_name.unwrap_or_default();
        let file = path_of(o.current_file.as_deref());
        if let Some((dir, base)) = file.rsplit_once('/') {
            (folder, name) = (dir.to_owned(), base.to_owned());
        }
        let shown_filters: Vec<Value<'_>> = filters
            .iter()
            .map(|(n, patterns)| {
                let of = |t: u32| {
                    patterns
                        .iter()
                        .filter(|p| p.0 == t)
                        .map(|p| p.1.clone())
                        .collect::<Vec<_>>()
                };
                Value::from(HashMap::from([
                    ("name", Value::from(n.clone())),
                    ("globs", Value::from(of(0))),
                    ("mimes", Value::from(of(1))),
                ]))
            })
            .collect();
        let choices: Vec<Value<'_>> = o
            .choices
            .unwrap_or_default()
            .into_iter()
            .map(|(id, label, options, initial)| {
                let options: Vec<Value<'_>> = options
                    .into_iter()
                    .map(|(i, l)| Value::from(HashMap::from([("id", i), ("label", l)])))
                    .collect();
                Value::from(HashMap::from([
                    ("id", Value::from(id)),
                    ("label", Value::from(label)),
                    ("options", Value::from(options)),
                    ("value", Value::from(initial)),
                ]))
            })
            .collect();
        let request: HashMap<String, OwnedValue> = [
            (
                "mode",
                Value::from(match mode {
                    Mode::Open => "open",
                    Mode::Save => "save",
                    Mode::SaveMany => "saveMany",
                }),
            ),
            ("title", Value::from(title)),
            (
                "acceptLabel",
                Value::from(o.accept_label.unwrap_or_default()),
            ),
            (
                "multiple",
                Value::from(mode == Mode::Open && o.multiple.unwrap_or(false)),
            ),
            (
                "directory",
                Value::from(mode == Mode::SaveMany || o.directory.unwrap_or(false)),
            ),
            ("filters", Value::from(shown_filters)),
            ("filterIndex", Value::from(filter_index)),
            ("folder", Value::from(folder)),
            ("name", Value::from(name)),
            ("files", Value::from(files.clone())),
            ("choices", Value::from(choices)),
            ("appId", Value::from(app_id)),
            ("parentWindow", Value::from(parent_window)),
            ("modal", Value::from(o.modal.unwrap_or(true))),
        ]
        .into_iter()
        .map(|(k, v)| (k.to_owned(), owned(v)))
        .collect();

        let (tx, rx) = async_channel::bounded(1);
        let handle = OwnedObjectPath::from(handle);
        let bus = io::session_bus().await?;
        bus.object_server()
            .at(
                handle.as_ref(),
                Request {
                    handle: handle.clone(),
                },
            )
            .await?;
        *pending() = Some(Pending {
            handle,
            mode,
            filters,
            files,
            reply: tx,
        });
        let qt = QT
            .get()
            .ok_or_else(|| fdo::Error::Failed("no file chooser".into()))?;
        qt.queue(move |obj| obj.requested(&marathon_qt::qmap(&request)))
            .ok();
        rx.recv()
            .await
            .map_err(|e| fdo::Error::Failed(format!("the shell is stopping: {e}")))
    }
}

#[interface(name = "org.freedesktop.impl.portal.FileChooser")]
impl Chooser {
    #[zbus(property, name = "version")]
    fn version(&self) -> u32 {
        4
    }

    async fn open_file(
        &self,
        handle: ObjectPath<'_>,
        app_id: String,
        parent_window: String,
        title: String,
        options: Options,
    ) -> fdo::Result<Answer> {
        self.request(Mode::Open, handle, app_id, parent_window, title, options)
            .await
    }

    async fn save_file(
        &self,
        handle: ObjectPath<'_>,
        app_id: String,
        parent_window: String,
        title: String,
        options: Options,
    ) -> fdo::Result<Answer> {
        self.request(Mode::Save, handle, app_id, parent_window, title, options)
            .await
    }

    async fn save_files(
        &self,
        handle: ObjectPath<'_>,
        app_id: String,
        parent_window: String,
        title: String,
        options: Options,
    ) -> fdo::Result<Answer> {
        self.request(
            Mode::SaveMany,
            handle,
            app_id,
            parent_window,
            title,
            options,
        )
        .await
    }
}

fn file_uri(path: &str) -> String {
    url::Url::from_file_path(path).map_or_else(|()| format!("file://{path}"), String::from)
}

#[derive(Default)]
pub struct FileChooserRust;

impl cxx_qt::Initialize for FileChooser {
    fn initialize(self: Pin<&mut Self>) {
        QT.set(self.qt_thread()).ok();
        io::spawn(async {
            let served = async {
                let bus = io::session_bus().await?;
                bus.object_server().at(PATH, Settings).await?;
                bus.object_server().at(PATH, Chooser).await?;
                bus.request_name(NAME).await
            };
            if let Err(e) = served.await {
                log::warn("portal", format_args!("cannot serve {NAME}: {e}"));
            }
        });
    }
}

impl FileChooser {
    fn accept(
        &self,
        paths: &QStringList,
        filter_index: i32,
        choices: &QMap<QMapPair_QString_QVariant>,
    ) {
        let paths: Vec<String> = QList::<QString>::from(paths)
            .iter()
            .map(ToString::to_string)
            .collect();
        let (mode, filters, files) = match pending().as_ref() {
            Some(p) => (p.mode, p.filters.clone(), p.files.clone()),
            None => return,
        };
        let uris: Vec<String> = if mode == Mode::SaveMany {
            let folder = paths.first().cloned().unwrap_or_default();
            files
                .iter()
                .map(|f| file_uri(&format!("{}/{f}", folder.trim_end_matches('/'))))
                .collect()
        } else {
            paths.iter().map(|p| file_uri(p)).collect()
        };
        let mut results = HashMap::from([("uris".to_owned(), owned(Value::from(uris)))]);
        if let Some(f) = usize::try_from(filter_index)
            .ok()
            .and_then(|i| filters.get(i))
        {
            results.insert("current_filter".into(), owned(Value::from(f.clone())));
        }
        let chosen: Vec<(String, String)> = choices
            .iter()
            .map(|(k, v)| {
                (
                    k.to_string(),
                    v.value::<QString>()
                        .map(|s| s.to_string())
                        .unwrap_or_default(),
                )
            })
            .collect();
        if !chosen.is_empty() {
            results.insert("choices".into(), owned(Value::from(chosen)));
        }
        if mode != Mode::Open {
            results.insert("writable".into(), owned(Value::from(true)));
        }
        finish(0, results);
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn cancel(&self) {
        finish(1, HashMap::new());
    }
}
