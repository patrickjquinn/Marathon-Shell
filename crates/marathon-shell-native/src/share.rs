//! `Share` (QML `ShareService`): the share sheet's service, org.sailfishos.share
//! on the session bus, as Keel's `ShareAction` calls it. A request opens the
//! sheet with the apps whose manifest's shareMethods take its type, and the
//! clipboard for text; the chosen app is brought to the front and handed the
//! request on its org.marathonos.<id> name at /share/<method>. Android's
//! activities join the sheet through deckardd.

use std::collections::HashMap;
use std::fs::File;
use std::os::fd::OwnedFd;
use std::os::unix::fs::{MetadataExt as _, OpenOptionsExt as _};
use std::path::{Component, Path, PathBuf};
use std::pin::Pin;
use std::sync::{Mutex, OnceLock, PoisonError};
use std::time::Duration;

use cxx_qt::Threading;
use cxx_qt_lib::QString;
use zbus::message::Header;
use zbus::zvariant::{Fd, OwnedValue, Value};
use zbus::{fdo, interface};

use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    unsafe extern "RustQt" {
        #[qobject]
        type Share = super::ShareRust;

        /// title, mimeType, text, image (a local URL), count, targets:
        /// [{id, name, icon, action, glyph}]
        #[qsignal]
        fn requested(self: Pin<&mut Share>, request: &QMap_QString_QVariant);
        /// Android's targets (deckardd), after the request: [{id, name, icon}]
        #[qsignal]
        #[cxx_name = "targetsAdded"]
        fn targets_added(self: Pin<&mut Share>, targets: &QList_QVariant);
        #[qsignal]
        fn delivered(self: Pin<&mut Share>, target_id: &QString);
        #[qsignal]
        fn failed(self: Pin<&mut Share>, target_id: &QString, reason: &QString);
        /// The text for the clipboard (main.cpp sets it).
        #[qsignal]
        #[cxx_name = "copyRequested"]
        fn copy_requested(self: Pin<&mut Share>, text: &QString);

        #[qinvokable]
        fn choose(self: &Share, target_id: &QString);
        #[qinvokable]
        fn cancel(self: &Share);
    }

    impl cxx_qt::Threading for Share {}
    impl cxx_qt::Initialize for Share {}
}

use qobject::Share;

const MAX_RESOURCES: usize = 32;
const MAX_TEXT: usize = 64 * 1024;
const TRIES: u32 = 50;
const DECKARD: &str = "org.marathonos.Deckard";

type Props = HashMap<String, OwnedValue>;

struct Item {
    name: String,
    text: String,
    host_path: String,
    mime: String,
    file: Option<OwnedFd>,
}

#[derive(Clone)]
enum Target {
    Clipboard,
    App { app_id: String, method: String },
    Android { activity: String },
}

#[derive(Default)]
struct Request {
    serial: u64,
    title: String,
    mime: String,
    items: Vec<Item>,
    targets: Vec<(String, Target)>,
}

static REQUEST: Mutex<Option<Request>> = Mutex::new(None);
static QT: OnceLock<cxx_qt::CxxQtThread<Share>> = OnceLock::new();

fn request() -> std::sync::MutexGuard<'static, Option<Request>> {
    REQUEST.lock().unwrap_or_else(PoisonError::into_inner)
}

fn emit(f: impl FnOnce(Pin<&mut Share>) + Send + 'static) {
    if let Some(qt) = QT.get() {
        qt.queue(f).ok();
    }
}

fn owned(v: Value<'_>) -> OwnedValue {
    OwnedValue::try_from(v).unwrap_or_else(|_| OwnedValue::from(false))
}

/// A variant's own value, however deep the variants go.
fn bare<'a>(v: &'a Value<'a>) -> &'a Value<'a> {
    match v {
        Value::Value(inner) => bare(inner),
        v => v,
    }
}

fn text_of(v: Option<&Value<'_>>) -> String {
    v.map(bare).and_then(|v| <&str>::try_from(v).ok()).unwrap_or_default().to_owned()
}

fn capped(s: &str, n: usize) -> String {
    s.chars().take(n).collect()
}

fn mime_of(path: &Path) -> String {
    mime_guess::from_path(path).first_or_octet_stream().essence_str().to_owned()
}

/// Whether a target's accepted type takes the shared one, either a wildcard.
fn mime_matches(accepted: &str, mime: &str) -> bool {
    accepted == mime
        || accepted == "*/*"
        || accepted.strip_suffix('*').is_some_and(|p| p.ends_with('/') && mime.starts_with(p))
        || mime.strip_suffix('*').is_some_and(|p| p.ends_with('/') && accepted.starts_with(p))
}

/// A path without `..` or `.`, absolute.
fn clean(path: &str) -> Option<PathBuf> {
    let p = Path::new(path);
    (p.is_absolute() && p.components().all(|c| matches!(c, Component::RootDir | Component::Normal(_)))).then(|| p.to_path_buf())
}

/// The file at `path` as process `pid` sees it, only if it is a regular file
/// in one of the shared folders on the host as well: its descriptor and
/// host path.
fn open_shared(pid: u32, path: &str, shared: &[PathBuf]) -> Option<(OwnedFd, String)> {
    let clean = clean(path)?;
    let canonical = std::fs::canonicalize(&clean).ok()?;
    let seen = shared.iter().any(|f| clean.starts_with(f) && clean != *f);
    let on_host = shared.iter().filter_map(|f| std::fs::canonicalize(f).ok()).any(|root| canonical.starts_with(&root) && canonical != root);
    if !seen || !on_host {
        return None;
    }
    let theirs = File::options()
        .read(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(format!("/proc/{pid}/root{}", clean.display()))
        .ok()?;
    let (t, o) = (theirs.metadata().ok()?, std::fs::metadata(&canonical).ok()?);
    (t.is_file() && t.dev() == o.dev() && t.ino() == o.ino()).then(|| (OwnedFd::from(theirs), canonical.to_string_lossy().into_owned()))
}

/// The apps whose manifest's shareMethods take `mime`: (id, Target, its
/// sheet entry).
fn app_targets(mime: &str, left_out: &[String]) -> Vec<(String, Target, Props)> {
    let mut out = Vec::new();
    for app in crate::apps::all() {
        if left_out.contains(&app.id) {
            continue;
        }
        let Some(manifest) = crate::apps::manifest(&app.id) else { continue };
        let json: serde_json::Value = std::fs::read(manifest.path.join("manifest.json")).ok().and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default();
        for method in json["shareMethods"].as_array().into_iter().flatten() {
            let takes = method["mimeTypes"].as_array().into_iter().flatten().filter_map(serde_json::Value::as_str).any(|a| mime_matches(a, mime));
            let name = method["name"].as_str().unwrap_or_default();
            if !takes || name.is_empty() {
                continue;
            }
            let id = format!("{}/{name}", app.id);
            let entry = Props::from([
                ("id".to_owned(), owned(Value::from(id.clone()))),
                ("name".to_owned(), owned(Value::from(app.name.clone()))),
                ("action".to_owned(), owned(Value::from(method["title"].as_str().unwrap_or_default().to_owned()))),
                ("icon".to_owned(), owned(Value::from(app.icon.clone()))),
            ]);
            out.push((id, Target::App { app_id: app.id.clone(), method: name.to_owned() }, entry));
        }
    }
    out
}

struct ShareIface;

#[interface(name = "org.sailfishos.share")]
impl ShareIface {
    #[zbus(name = "share")]
    async fn share(&self, configuration: HashMap<String, Value<'_>>, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        let get = |k: &str| configuration.get(k).map(bare);
        let resources: Vec<&Value<'_>> = match get("resources") {
            Some(Value::Array(a)) => a.iter().map(bare).collect(),
            Some(v) => vec![v],
            None => Vec::new(),
        };
        if resources.is_empty() || resources.len() > MAX_RESOURCES {
            return Err(fdo::Error::InvalidArgs("1 to 32 resources".into()));
        }
        let mime_asked = capped(&text_of(get("mimeType")), 128);
        let title = capped(&text_of(get("title")), 256);
        let pid = match h.sender() {
            Some(s) => fdo::DBusProxy::new(&io::session_bus().await?).await?.get_connection_unix_process_id(s.clone().into()).await.ok(),
            None => None,
        };
        let from = crate::gate::caller(pid).unwrap_or_default();
        // A session service (deckardd) may name the app that shares; an app
        // may not name another.
        let from_app = !from.is_empty() && !from.starts_with("service:");
        let source = if from_app { String::new() } else { capped(&text_of(get("source")), 256) };
        let shared: Vec<PathBuf> = crate::sandbox::shared_paths();

        let mut items = Vec::new();
        for r in resources {
            if let Ok(path) = <&str>::try_from(r) {
                let found = pid.filter(|_| !from.is_empty()).and_then(|p| open_shared(p, path, &shared));
                let Some((fd, host)) = found else { return Err(fdo::Error::AccessDenied("Not a shared file".into())) };
                let host_path = PathBuf::from(&host);
                items.push(Item { name: host_path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(), mime: mime_of(&host_path), text: String::new(), host_path: host, file: Some(fd) });
                continue;
            }
            let map: HashMap<String, Value<'_>> = match r {
                Value::Dict(d) => d.try_clone().ok().and_then(|d| HashMap::try_from(d).ok()).unwrap_or_default(),
                _ => HashMap::new(),
            };
            let field = |k: &str| map.get(k).map(bare);
            if let Some(Value::Fd(fd)) = field("fileDescriptor") {
                // A descriptor is its own proof of access, whoever sends it.
                let owned_fd = std::os::fd::AsFd::as_fd(fd).try_clone_to_owned().map_err(|e| fdo::Error::InvalidArgs(format!("Not a regular file: {e}")))?;
                let file = File::from(owned_fd.try_clone().map_err(|e| fdo::Error::Failed(e.to_string()))?);
                if !file.metadata().is_ok_and(|m| m.is_file()) {
                    return Err(fdo::Error::InvalidArgs("Not a regular file".into()));
                }
                let name = capped(Path::new(&text_of(field("name"))).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default().as_str(), 256);
                let name = if name.is_empty() || name == ".." { "file".to_owned() } else { name };
                items.push(Item { mime: mime_of(Path::new(&name)), name, text: String::new(), host_path: String::new(), file: Some(owned_fd) });
                continue;
            }
            let text = text_of(field(if map.contains_key("data") { "data" } else { "status" }));
            if text.is_empty() || text.len() > MAX_TEXT {
                return Err(fdo::Error::InvalidArgs("Text of 1 to 65536 characters".into()));
            }
            let name = capped(&text_of(field("name").or_else(|| field("linkTitle"))), 256);
            items.push(Item { name, text, host_path: String::new(), mime: String::new(), file: None });
        }

        let files = items.iter().filter(|i| i.file.is_some()).count();
        let text_only = files == 0;
        let mime = if !mime_asked.is_empty() {
            mime_asked
        } else if text_only {
            "text/plain".to_owned()
        } else {
            items.iter().find(|i| i.file.is_some()).map(|i| i.mime.clone()).unwrap_or_default()
        };
        let mut targets = Vec::new();
        let mut shown: Vec<Value<'_>> = Vec::new();
        for (id, target, entry) in app_targets(&mime, &[from, source.clone()]) {
            targets.push((id, target));
            shown.push(Value::from(entry));
        }
        if text_only {
            targets.push(("clipboard".into(), Target::Clipboard));
            shown.push(Value::from(HashMap::from([("id", "clipboard"), ("name", "Copy"), ("glyph", "copy")])));
        }
        let mut sheet = Props::from([
            ("title".into(), owned(Value::from(title.clone()))),
            ("mimeType".into(), owned(Value::from(mime.clone()))),
            ("count".into(), owned(Value::from(i32::try_from(items.len()).unwrap_or(0)))),
            ("targets".into(), owned(Value::from(shown))),
        ]);
        if let Some(t) = items.iter().find(|i| !i.text.is_empty()) {
            sheet.insert("text".into(), owned(Value::from(capped(&t.text, 500))));
        }
        if let Some(i) = items.iter().find(|i| i.file.is_some() && i.mime.starts_with("image/")) {
            let image = if i.host_path.is_empty() { None } else { url::Url::from_file_path(&i.host_path).ok().map(String::from) };
            if let Some(image) = image {
                sheet.insert("image".into(), owned(Value::from(image)));
            }
        }
        let serial = {
            let mut r = request();
            let serial = r.as_ref().map_or(1, |r| r.serial + 1);
            *r = Some(Request { serial, title, mime: mime.clone(), items, targets });
            serial
        };
        emit(move |obj| obj.requested(&marathon_qt::qmap(&sheet)));
        ask_android(serial, if text_only { "text/plain".into() } else { mime }, source, files);
        Ok(())
    }
}

/// deckardd lists the Android activities that take the type; they join the
/// sheet when it answers, leaving out the sharing app and, for several
/// files, those that take only one.
fn ask_android(serial: u64, mime: String, source: String, files: usize) {
    io::spawn(async move {
        let Ok(bus) = io::session_bus().await else { return };
        let args = (mime,);
        let call = bus.call_method(Some(DECKARD), "/org/marathonos/Deckard", Some("org.marathonos.Deckard1.Share"), "ShareTargets", &args);
        let Ok(Ok(reply)) = futures_lite::future::or(async { Ok(call.await) }, async {
            async_io::Timer::after(Duration::from_secs(5)).await;
            Err(())
        })
        .await
        else {
            return;
        };
        let Ok(found) = reply.body().deserialize::<Vec<HashMap<String, OwnedValue>>>() else { return };
        let skipped = source.strip_prefix("waydroid.").unwrap_or_default().to_owned();
        let s = |m: &HashMap<String, OwnedValue>, k: &str| m.get(k).and_then(|v| <&str>::try_from(&**v).ok()).unwrap_or_default().to_owned();
        let mut added = Vec::new();
        let mut targets = Vec::new();
        for t in &found {
            let activity = s(t, "id");
            let multiple = t.get("multiple").and_then(|v| bool::try_from(&**v).ok()).unwrap_or(false);
            if activity.is_empty() || activity.len() > 256 || s(t, "pkg") == skipped || (files > 1 && !multiple) {
                continue;
            }
            let id = format!("android:{activity}");
            targets.push((id.clone(), Target::Android { activity }));
            added.push(owned(Value::from(HashMap::from([("id", Value::from(id)), ("name", Value::from(capped(&s(t, "label"), 64))), ("icon", Value::from(s(t, "icon")))]))));
        }
        {
            let mut r = request();
            match r.as_mut().filter(|r| r.serial == serial) {
                Some(r) => r.targets.extend(targets),
                None => return,
            }
        }
        if !added.is_empty() {
            emit(move |obj| obj.targets_added(&marathon_qt::qlist(&added)));
        }
    });
}

/// The resources as the chosen app takes them: text, or a descriptor.
fn configuration(r: &Request) -> HashMap<&'static str, Value<'static>> {
    let resources: Vec<Value<'static>> = r
        .items
        .iter()
        .filter_map(|i| match &i.file {
            Some(fd) => Some(Value::from(HashMap::from([("name", Value::from(i.name.clone())), ("fileDescriptor", Value::from(Fd::from(fd.try_clone().ok()?)))]))),
            None => Some(Value::from(HashMap::from([("name", Value::from(i.name.clone())), ("data", Value::from(i.text.clone()))]))),
        })
        .collect();
    HashMap::from([("mimeType", Value::from(r.mime.clone())), ("title", Value::from(r.title.clone())), ("resources", Value::from(resources))])
}

impl Share {
    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn choose(&self, target_id: &QString) {
        let id = target_id.to_string();
        let Some(r) = request().take() else { return };
        let Some(target) = r.targets.iter().find(|t| t.0 == id).map(|t| t.1.clone()) else { return };
        match target {
            Target::Clipboard => {
                let text = r.items.iter().map(|i| i.text.as_str()).collect::<Vec<_>>().join("\n");
                emit(move |mut obj| {
                    obj.as_mut().copy_requested(&QString::from(&text));
                    obj.delivered(&QString::from("clipboard"));
                });
            }
            // deckardd brings the Android app's window forward itself.
            Target::Android { activity } => {
                let config = configuration(&r);
                io::spawn(async move {
                    let sent = async {
                        let bus = io::session_bus().await?;
                        bus.call_method(Some(DECKARD), "/org/marathonos/Deckard", Some("org.marathonos.Deckard1.Share"), "Share", &(activity, config)).await
                    };
                    let result = sent.await;
                    emit(move |mut obj| match result {
                        Ok(_) => obj.delivered(&QString::from(&id)),
                        Err(e) => obj.as_mut().failed(&QString::from(&id), &QString::from(&e.to_string())),
                    });
                });
            }
            Target::App { app_id, method } => {
                let app = QString::from(&app_id);
                crate::tasks::with(move |t| {
                    t.launch_app(&app);
                });
                io::spawn(deliver(id, app_id, method, configuration(&r)));
            }
        }
    }

    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn cancel(&self) {
        request().take();
    }
}

/// The app may still be starting: its name comes when its actions load, and
/// its share object when its window's QML has.
async fn deliver(target: String, app_id: String, method: String, config: HashMap<&'static str, Value<'static>>) {
    let service = format!("org.marathonos.{app_id}");
    let path = format!("/share/{method}");
    let mut result = Err("The app did not take the share".to_owned());
    for _ in 0..TRIES {
        let Ok(bus) = io::session_bus().await else { break };
        match bus.call_method(Some(service.as_str()), path.as_str(), Some("org.sailfishos.share"), "share", &(&config,)).await {
            Ok(_) => {
                result = Ok(());
                break;
            }
            Err(zbus::Error::MethodError(name, ..)) if !matches!(name.as_str(), "org.freedesktop.DBus.Error.UnknownObject" | "org.freedesktop.DBus.Error.UnknownMethod" | "org.freedesktop.DBus.Error.ServiceUnknown" | "org.freedesktop.DBus.Error.NameHasNoOwner") => {
                result = Err(name.to_string());
                break;
            }
            Err(_) => {
                async_io::Timer::after(Duration::from_millis(200)).await;
            }
        }
    }
    emit(move |mut obj| match result {
        Ok(()) => obj.delivered(&QString::from(&target)),
        Err(e) => obj.as_mut().failed(&QString::from(&target), &QString::from(&e)),
    });
}

#[derive(Default)]
pub struct ShareRust;

impl cxx_qt::Initialize for Share {
    fn initialize(self: Pin<&mut Self>) {
        QT.set(self.qt_thread()).ok();
        io::spawn(async {
            let served = async {
                let bus = io::session_bus().await?;
                bus.object_server().at("/", ShareIface).await?;
                bus.request_name("org.sailfishos.share").await
            };
            if let Err(e) = served.await {
                log::warn("share", format_args!("cannot serve org.sailfishos.share: {e}"));
            }
        });
    }
}
