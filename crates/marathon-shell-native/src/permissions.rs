//! `Permissions`: what each app may do, and the prompt that asks the user.
//!
//! An app holds only what it declared: its read-only manifest for a system
//! app, the install receipt for any other. A restricted permission goes only
//! to a protected system app, which holds the rest without asking. Decisions
//! live in `~/.config/marathon/app-permissions.json`. Requests that arrive
//! together become one prompt per app. Apps whose grants another system keeps
//! (Android's, for deckardd) get a "foreign" prompt that stores nothing.

use crate::i18n::fl;
use std::collections::{BTreeMap, HashMap, VecDeque};
use std::fs;
use std::path::PathBuf;
use std::pin::Pin;
use std::sync::{LazyLock, Mutex, MutexGuard, OnceLock};
use std::time::Duration;

use async_channel::Sender;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QStringList, QVariant};
use futures_lite::{future, StreamExt};
use zbus::fdo;
use zbus::message::Header;
use zbus::names::BusName;

use crate::ipc::{self, value, State};
use crate::{app_ids, gate, io, log};

#[cxx_qt::bridge(namespace = "marathon")]
mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, prompt_active, cxx_name = "promptActive", READ, NOTIFY)]
        #[qproperty(QString, current_app_id, cxx_name = "currentAppId", READ, NOTIFY = current_request_changed)]
        #[qproperty(QString, current_permission, cxx_name = "currentPermission", READ, NOTIFY = current_request_changed)]
        #[qproperty(QStringList, current_permissions, cxx_name = "currentPermissions", READ, NOTIFY = current_request_changed)]
        #[qproperty(QStringList, current_refused, cxx_name = "currentRefused", READ, NOTIFY = current_request_changed)]
        #[qproperty(QMap_QString_QVariant, current_options, cxx_name = "currentOptions", READ, NOTIFY = current_request_changed)]
        type Permissions = super::PermissionsRust;

        #[qsignal]
        #[cxx_name = "currentRequestChanged"]
        fn current_request_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "permissionGranted"]
        fn permission_granted(self: Pin<&mut Self>, app_id: &QString, permission: &QString);
        #[qsignal]
        #[cxx_name = "permissionDenied"]
        fn permission_denied(self: Pin<&mut Self>, app_id: &QString, permission: &QString);
        #[qsignal]
        #[cxx_name = "permissionRevoked"]
        fn permission_revoked(self: Pin<&mut Self>, app_id: &QString, permission: &QString);
        #[qsignal]
        #[cxx_name = "permissionsRequested"]
        fn permissions_requested(self: Pin<&mut Self>, app_id: &QString, permissions: &QStringList);

        #[qinvokable]
        #[cxx_name = "hasPermission"]
        fn has_permission(self: &Permissions, app_id: &QString, permission: &QString) -> bool;
        /// 0 not asked, 1 granted, 2 denied.
        #[qinvokable]
        #[cxx_name = "getPermissionStatus"]
        fn permission_status(self: &Permissions, app_id: &QString, permission: &QString) -> i32;
        #[qinvokable]
        #[cxx_name = "requestPermission"]
        fn request_permission(self: Pin<&mut Permissions>, app_id: &QString, permission: &QString);
        #[qinvokable]
        #[cxx_name = "requestPermissions"]
        fn request_permissions(
            self: Pin<&mut Permissions>,
            app_id: &QString,
            permissions: &QStringList,
        );
        /// Every permission the app declared that is not decided yet: at launch.
        #[cxx_name = "requestDeclaredPermissions"]
        fn request_declared_permissions(self: Pin<&mut Permissions>, app_id: &QString);
        #[qinvokable]
        fn respond(self: Pin<&mut Permissions>, granted: bool);
        /// With a foreign prompt's choices: only this time, precise.
        #[qinvokable]
        #[cxx_name = "respondWith"]
        fn respond_with(self: Pin<&mut Permissions>, granted: bool, once: bool, precise: bool);
        /// Back: deny a Marathon prompt, cancel a foreign one.
        #[qinvokable]
        #[cxx_name = "respondToBack"]
        fn respond_to_back(self: Pin<&mut Permissions>);
        #[qinvokable]
        #[cxx_name = "setPermission"]
        fn set_permission(
            self: Pin<&mut Permissions>,
            app_id: &QString,
            permission: &QString,
            granted: bool,
            remember: bool,
        );
        #[qinvokable]
        #[cxx_name = "setPermissions"]
        fn set_permissions(
            self: Pin<&mut Permissions>,
            app_id: &QString,
            permissions: &QStringList,
            granted: bool,
            remember: bool,
        );
        #[qinvokable]
        #[cxx_name = "revokePermission"]
        fn revoke_permission(self: Pin<&mut Permissions>, app_id: &QString, permission: &QString);
        #[qinvokable]
        #[cxx_name = "dismissAll"]
        fn dismiss_all(self: Pin<&mut Permissions>);
        /// Drops the app's prompts: it exited.
        #[qinvokable]
        #[cxx_name = "dismissForApp"]
        fn dismiss_for_app(self: Pin<&mut Permissions>, app_id: &QString);
        #[qinvokable]
        #[cxx_name = "getAppPermissions"]
        fn app_permissions(self: &Permissions, app_id: &QString) -> QStringList;
        #[qinvokable]
        #[cxx_name = "getAvailablePermissions"]
        fn available_permissions(self: &Permissions) -> QStringList;
        #[qinvokable]
        #[cxx_name = "getPermissionLabel"]
        fn permission_label(self: &Permissions, permission: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "getPermissionDescription"]
        fn permission_description(self: &Permissions, permission: &QString) -> QString;
    }

    impl cxx_qt::Threading for Permissions {}
    impl cxx_qt::Initialize for Permissions {}
}

use qobject::Permissions;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Status {
    NotRequested = 0,
    Granted = 1,
    Denied = 2,
}

#[derive(Clone, Debug, Default, PartialEq)]
struct ForeignOptions {
    kind: String,
    once: bool,
    accuracy: String,
    precise_default: bool,
}

#[derive(Clone, Debug, PartialEq)]
struct Prompt {
    app: String,
    asked: Vec<String>,
    refused: Vec<String>,
    // A foreign prompt's key and choices.
    foreign: Option<(String, ForeignOptions)>,
}

struct Foreign {
    key: String,
    app: String,
    permission: String,
    options: ForeignOptions,
}

struct Facts {
    declared: Vec<String>,
    protected: bool,
}

#[derive(Debug, PartialEq)]
enum Event {
    Granted(String, String),
    Denied(String, String),
    Revoked(String, String),
    Requested(String, Vec<String>),
    Answered(String, &'static str, bool),
    PromptChanged,
    // Look at the queue again, after this long.
    Recheck(u64),
}

fn canonical(permission: &str) -> String {
    marathon_permissions::canonical(permission).map_or_else(|| permission.to_owned(), str::to_owned)
}

#[derive(Default)]
struct Core {
    path: Option<PathBuf>,
    stored: BTreeMap<String, BTreeMap<String, bool>>,
    apps: HashMap<String, Facts>,
    pending: Vec<(String, String)>,
    prompt: Option<Prompt>,
    foreign: VecDeque<Foreign>,
}

impl Core {
    fn load(path: PathBuf) -> Self {
        let json: serde_json::Value = fs::read(&path)
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or_default();
        let stored = json
            .as_object()
            .into_iter()
            .flatten()
            .map(|(app, grants)| {
                let grants = grants
                    .as_object()
                    .into_iter()
                    .flatten()
                    .map(|(p, g)| (canonical(p), g.as_bool().unwrap_or(false)))
                    .collect();
                (app.clone(), grants)
            })
            .collect();
        Self {
            path: Some(path),
            stored,
            ..Self::default()
        }
    }

    fn save(&self) {
        let Some(path) = &self.path else { return };
        let written = path
            .parent()
            .map(fs::create_dir_all)
            .transpose()
            .and_then(|_| {
                fs::write(
                    path,
                    serde_json::to_vec_pretty(&self.stored).unwrap_or_default(),
                )
            });
        if let Err(e) = written {
            log::warn(
                "permissions",
                format_args!("saving {}: {e}", path.display()),
            );
        }
    }

    fn declares(&self, app: &str, permission: &str) -> bool {
        self.apps
            .get(app)
            .is_none_or(|f| f.declared.iter().any(|d| canonical(d) == permission))
    }

    // Restricted permissions are held only by protected system apps.
    fn refused(&self, app: &str, permission: &str) -> bool {
        marathon_permissions::describe(permission).is_some_and(|p| p.restricted)
            && !self.apps.get(app).is_some_and(|f| f.protected)
    }

    fn decided(&self, app: &str, permission: &str) -> bool {
        self.stored
            .get(app)
            .is_some_and(|g| g.contains_key(permission))
    }

    fn status(&self, app: &str, permission: &str) -> Status {
        let permission = canonical(permission);
        if !self.declares(app, &permission) || self.refused(app, &permission) {
            return Status::Denied;
        }
        match self.stored.get(app).and_then(|g| g.get(&permission)) {
            Some(true) => Status::Granted,
            Some(false) => Status::Denied,
            None if self.apps.get(app).is_some_and(|f| f.protected) => Status::Granted,
            None => Status::NotRequested,
        }
    }

    fn has(&self, app: &str, permission: &str) -> bool {
        self.status(app, permission) == Status::Granted
    }

    /// Asks for `permission` in the next prompt, or answers at once.
    fn request(&mut self, app: &str, permission: &str, out: &mut Vec<Event>) {
        let permission = canonical(permission);
        if !self.declares(app, &permission) {
            log::warn(
                "permissions",
                format_args!("SECURITY: undeclared permission requested: {app} {permission}"),
            );
            return out.push(Event::Denied(app.to_owned(), permission));
        }
        // A refusal the user has not been shown yet goes to the prompt.
        let untold = self.refused(app, &permission) && !self.decided(app, &permission);
        match self.status(app, &permission) {
            Status::Granted => out.push(Event::Granted(app.to_owned(), permission)),
            Status::Denied if !untold => out.push(Event::Denied(app.to_owned(), permission)),
            _ => {
                self.pending.push((app.to_owned(), permission));
                out.push(Event::Recheck(150));
            }
        }
    }

    fn ask_if_undecided(
        &mut self,
        app: &str,
        permissions: &[String],
        out: &mut Vec<Event>,
    ) -> Option<String> {
        self.apps.get(app)?;
        let permission = permissions
            .iter()
            .map(|p| canonical(p))
            .find(|p| self.status(app, p) == Status::NotRequested)?;
        self.request(app, &permission, out);
        Some(permission)
    }

    fn check_queue(&self, out: &mut Vec<Event>) {
        if self.prompt.is_none() && (!self.pending.is_empty() || !self.foreign.is_empty()) {
            out.push(Event::Recheck(50));
        }
    }

    /// The next prompt: a foreign one first, else every request of the
    /// first app waiting, re-checked against what was decided meanwhile.
    fn process(&mut self, out: &mut Vec<Event>) {
        if self.prompt.is_some() {
            return;
        }
        if let Some(f) = self.foreign.front() {
            self.prompt = Some(Prompt {
                app: f.app.clone(),
                asked: vec![f.permission.clone()],
                refused: Vec::new(),
                foreign: Some((f.key.clone(), f.options.clone())),
            });
            return out.push(Event::PromptChanged);
        }
        let Some((app, _)) = self.pending.first().cloned() else {
            return;
        };
        let (mine, rest): (Vec<_>, Vec<_>) = std::mem::take(&mut self.pending)
            .into_iter()
            .partition(|(a, _)| *a == app);
        self.pending = rest;
        let (mut asked, mut refused) = (Vec::new(), Vec::new());
        for (_, permission) in mine {
            let list = if self.refused(&app, &permission) && !self.decided(&app, &permission) {
                &mut refused
            } else {
                match self.status(&app, &permission) {
                    Status::Granted => {
                        out.push(Event::Granted(app.clone(), permission));
                        continue;
                    }
                    Status::Denied => {
                        out.push(Event::Denied(app.clone(), permission));
                        continue;
                    }
                    Status::NotRequested => &mut asked,
                }
            };
            if !list.contains(&permission) {
                list.push(permission);
            }
        }
        if asked.is_empty() && refused.is_empty() {
            return self.check_queue(out);
        }
        out.push(Event::Requested(app.clone(), asked.clone()));
        self.prompt = Some(Prompt {
            app,
            asked,
            refused,
            foreign: None,
        });
        out.push(Event::PromptChanged);
    }

    fn close(&mut self, out: &mut Vec<Event>) {
        self.prompt = None;
        out.push(Event::PromptChanged);
    }

    fn finish_foreign(
        &mut self,
        key: &str,
        answer: &'static str,
        precise: bool,
        out: &mut Vec<Event>,
    ) {
        let Some(i) = self.foreign.iter().position(|f| f.key == key) else {
            return;
        };
        self.foreign.remove(i);
        if self
            .prompt
            .as_ref()
            .and_then(|p| p.foreign.as_ref())
            .is_some_and(|(k, _)| k == key)
        {
            self.close(out);
            self.check_queue(out);
        }
        out.push(Event::Answered(key.to_owned(), answer, precise));
    }

    fn respond(&mut self, granted: bool, once: bool, precise: Option<bool>, out: &mut Vec<Event>) {
        let Some(prompt) = self.prompt.clone() else {
            return;
        };
        if let Some((key, options)) = prompt.foreign {
            let answer = if !granted {
                "deny"
            } else if once && options.once {
                "once"
            } else {
                "allow"
            };
            let exact = match precise {
                Some(p) if options.accuracy == "choice" => p,
                _ => options.precise_default,
            };
            return self.finish_foreign(&key, answer, granted && exact, out);
        }
        // Stored as denied: the user has been told, so it is not shown again.
        let grants = self.stored.entry(prompt.app.clone()).or_default();
        for permission in &prompt.refused {
            grants.insert(permission.clone(), false);
        }
        if let Some(p) = &mut self.prompt {
            p.refused.clear();
        }
        if prompt.asked.is_empty() {
            self.save();
            self.close(out);
            self.check_queue(out);
        } else {
            self.set(&prompt.app, &prompt.asked, granted, true, out);
        }
        out.extend(
            prompt
                .refused
                .into_iter()
                .map(|p| Event::Denied(prompt.app.clone(), p)),
        );
    }

    fn set(
        &mut self,
        app: &str,
        permissions: &[String],
        granted: bool,
        remember: bool,
        out: &mut Vec<Event>,
    ) {
        let permissions: Vec<String> = permissions.iter().map(|p| canonical(p)).collect();
        let grants = self.stored.entry(app.to_owned()).or_default();
        for permission in &permissions {
            grants.insert(permission.clone(), granted);
        }
        if remember {
            self.save();
        }
        // Answers only what it decides: a grant for another app must not
        // close this prompt and lose its requests.
        if let Some(p) = self
            .prompt
            .as_mut()
            .filter(|p| p.foreign.is_none() && p.app == app)
        {
            p.asked.retain(|a| !permissions.contains(a));
            if p.asked.is_empty() && p.refused.is_empty() {
                self.close(out);
            } else {
                out.push(Event::PromptChanged);
            }
        }
        for permission in permissions {
            out.push(if self.has(app, &permission) {
                Event::Granted(app.to_owned(), permission)
            } else {
                Event::Denied(app.to_owned(), permission)
            });
        }
        self.check_queue(out);
    }

    fn dismiss_for(&mut self, app: Option<&str>, out: &mut Vec<Event>) {
        let keys: Vec<String> = self
            .foreign
            .iter()
            .filter(|f| app.is_none_or(|a| f.app == a))
            .map(|f| f.key.clone())
            .collect();
        for key in keys {
            self.finish_foreign(&key, "cancel", false, out);
        }
        self.pending
            .retain(|(a, _)| app.is_some_and(|app| a != app));
        if self
            .prompt
            .as_ref()
            .is_some_and(|p| app.is_none_or(|a| p.app == a))
        {
            self.close(out);
            self.check_queue(out);
        }
    }
}

#[derive(Default)]
pub struct PermissionsRust {
    prompt_active: bool,
    current_app_id: QString,
    current_permission: QString,
    current_permissions: QStringList,
    current_refused: QStringList,
    current_options: QMap<QMapPair_QString_QVariant>,
    // Bumped by each timer, so only the latest one processes.
    generation: u64,
}

// The I/O thread's gate reads the decisions as the GUI thread's prompt
// changes them; held only while one call runs.
static CORE: LazyLock<Mutex<Core>> = LazyLock::new(|| {
    Mutex::new(Core::load(
        marathon_rt::dirs::config().join("marathon/app-permissions.json"),
    ))
});
static QT: OnceLock<cxx_qt::CxxQtThread<Permissions>> = OnceLock::new();
type Answer = (String, bool);
// Permissions1.PromptAndroid's callers, by prompt key.
static WAITING: LazyLock<Mutex<HashMap<String, Sender<Answer>>>> = LazyLock::new(Mutex::default);

fn core() -> MutexGuard<'static, Core> {
    CORE.lock().unwrap_or_else(|_| std::process::abort())
}

/// Whether the app holds `permission`, from any thread.
pub(crate) fn has(app: &str, permission: &str) -> bool {
    core().has(app, permission)
}

/// As `Permissions::askIfUndecided`, from any thread: the prompt shows on
/// the GUI thread.
pub(crate) fn ask_if_undecided(app: &str, permissions: &[String]) -> Option<String> {
    let mut events = Vec::new();
    let asked = core().ask_if_undecided(app, permissions, &mut events);
    if let Some(qt) = QT.get() {
        qt.queue(move |obj| obj.apply(events)).ok();
    }
    asked
}

/// What an app declared, from its manifest or install receipt.
pub(crate) fn declare(app_id: &str, declared: Vec<String>, system: bool) {
    core().apps.insert(
        app_id.to_owned(),
        Facts {
            declared,
            protected: system,
        },
    );
}

pub(crate) fn undeclare(app_id: &str) {
    core().apps.remove(app_id);
}

/// Runs `f` on the permissions, on the GUI thread.
pub(crate) fn with(f: impl FnOnce(Pin<&mut Permissions>) + Send + 'static) {
    if let Some(qt) = QT.get() {
        qt.queue(f).ok();
    }
}

fn strings(list: &QStringList) -> Vec<String> {
    QList::<QString>::from(list)
        .iter()
        .map(ToString::to_string)
        .collect()
}

fn list(items: &[String]) -> QStringList {
    items.iter().map(QString::from).collect()
}

impl cxx_qt::Initialize for Permissions {
    fn initialize(self: Pin<&mut Self>) {
        QT.set(self.qt_thread()).ok();
        ipc::export(
            "Permissions",
            Permissions1 {
                qt: self.qt_thread(),
            },
        );
    }
}

#[allow(
    clippy::unused_self,
    reason = "invokables are the QObject's methods, whatever of it they read"
)]
impl Permissions {
    fn apply(mut self: Pin<&mut Self>, events: Vec<Event>) {
        for event in events {
            match event {
                Event::Granted(a, p) => {
                    self.as_mut()
                        .permission_granted(&QString::from(&a), &QString::from(&p));
                    ipc::signal("Permissions", "PermissionGranted", (a, p));
                }
                Event::Denied(a, p) => {
                    self.as_mut()
                        .permission_denied(&QString::from(&a), &QString::from(&p));
                    ipc::signal("Permissions", "PermissionDenied", (a, p));
                }
                Event::Revoked(a, p) => self
                    .as_mut()
                    .permission_revoked(&QString::from(&a), &QString::from(&p)),
                Event::Requested(a, ps) => self
                    .as_mut()
                    .permissions_requested(&QString::from(&a), &list(&ps)),
                Event::Answered(k, a, precise) => {
                    if let Some(waiter) = WAITING
                        .lock()
                        .unwrap_or_else(|_| std::process::abort())
                        .remove(&k)
                    {
                        waiter.try_send((a.to_owned(), precise)).ok();
                    }
                }
                Event::PromptChanged => self.as_mut().show_prompt(),
                Event::Recheck(ms) => self.as_mut().recheck(ms),
            }
        }
    }

    fn show_prompt(mut self: Pin<&mut Self>) {
        let prompt = core().prompt.clone();
        let mut options = QMap::<QMapPair_QString_QVariant>::default();
        if let Some((_, o)) = prompt.as_ref().and_then(|p| p.foreign.as_ref()) {
            options.insert(
                QString::from("kind"),
                QVariant::from(&QString::from(&o.kind)),
            );
            options.insert(QString::from("once"), QVariant::from(&o.once));
            options.insert(
                QString::from("accuracy"),
                QVariant::from(&QString::from(&o.accuracy)),
            );
            options.insert(
                QString::from("preciseDefault"),
                QVariant::from(&o.precise_default),
            );
        }
        let mut rust = self.as_mut().rust_mut();
        let p = prompt.as_ref();
        rust.current_app_id = QString::from(p.map_or("", |p| p.app.as_str()));
        rust.current_permissions = list(p.map_or(&[][..], |p| &p.asked));
        rust.current_permission =
            QString::from(p.and_then(|p| p.asked.first()).map_or("", String::as_str));
        rust.current_refused = list(p.map_or(&[][..], |p| &p.refused));
        rust.current_options = options;
        let active = prompt.is_some();
        set!(self, prompt_active, prompt_active_changed, active);
        self.current_request_changed();
    }

    fn recheck(mut self: Pin<&mut Self>, ms: u64) {
        self.as_mut().rust_mut().generation += 1;
        let generation = self.generation;
        let qt = self.qt_thread();
        io::spawn(async move {
            async_io::Timer::after(Duration::from_millis(ms)).await;
            qt.queue(move |obj| {
                if obj.generation == generation {
                    let mut events = Vec::new();
                    core().process(&mut events);
                    obj.apply(events);
                }
            })
            .ok();
        });
    }

    // The lock is let go before the events run, as they read the core again.
    fn with(self: Pin<&mut Self>, f: impl FnOnce(&mut Core, &mut Vec<Event>)) {
        let mut events = Vec::new();
        f(&mut core(), &mut events);
        self.apply(events);
    }

    fn has_permission(&self, app_id: &QString, permission: &QString) -> bool {
        has(&app_id.to_string(), &permission.to_string())
    }

    fn permission_status(&self, app_id: &QString, permission: &QString) -> i32 {
        core().status(&app_id.to_string(), &permission.to_string()) as i32
    }

    fn request_permission(self: Pin<&mut Self>, app_id: &QString, permission: &QString) {
        self.with(|core, out| core.request(&app_id.to_string(), &permission.to_string(), out));
    }

    fn request_permissions(self: Pin<&mut Self>, app_id: &QString, permissions: &QStringList) {
        self.with(|core, out| {
            for permission in strings(permissions) {
                core.request(&app_id.to_string(), &permission, out);
            }
        });
    }

    pub(crate) fn request_declared_permissions(self: Pin<&mut Self>, app_id: &QString) {
        let app = app_id.to_string();
        self.with(|core, out| {
            for permission in core
                .apps
                .get(&app)
                .map(|f| f.declared.clone())
                .unwrap_or_default()
            {
                core.request(&app, &permission, out);
            }
        });
    }

    fn foreign(self: Pin<&mut Self>, foreign: Foreign) {
        self.with(|core, out| {
            core.foreign.push_back(foreign);
            core.process(out);
        });
    }

    fn cancel_foreign(self: Pin<&mut Self>, key: &str) {
        self.with(|core, out| core.finish_foreign(key, "cancel", false, out));
    }

    fn respond(self: Pin<&mut Self>, granted: bool) {
        self.with(|core, out| core.respond(granted, false, None, out));
    }

    fn respond_with(self: Pin<&mut Self>, granted: bool, once: bool, precise: bool) {
        self.with(|core, out| core.respond(granted, once, Some(precise), out));
    }

    fn respond_to_back(self: Pin<&mut Self>) {
        self.with(
            |core, out| match core.prompt.as_ref().and_then(|p| p.foreign.clone()) {
                Some((key, _)) => core.finish_foreign(&key, "cancel", false, out),
                None => core.respond(false, false, None, out),
            },
        );
    }

    fn set_permission(
        self: Pin<&mut Self>,
        app_id: &QString,
        permission: &QString,
        granted: bool,
        remember: bool,
    ) {
        self.with(|core, out| {
            core.set(
                &app_id.to_string(),
                &[permission.to_string()],
                granted,
                remember,
                out,
            );
        });
    }

    fn set_permissions(
        self: Pin<&mut Self>,
        app_id: &QString,
        permissions: &QStringList,
        granted: bool,
        remember: bool,
    ) {
        self.with(|core, out| {
            core.set(
                &app_id.to_string(),
                &strings(permissions),
                granted,
                remember,
                out,
            );
        });
    }

    fn revoke_permission(self: Pin<&mut Self>, app_id: &QString, permission: &QString) {
        let (app, permission) = (app_id.to_string(), canonical(&permission.to_string()));
        self.with(|core, out| {
            if let Some(grants) = core.stored.get_mut(&app) {
                grants.remove(&permission);
                core.save();
                out.push(Event::Revoked(app, permission));
            }
        });
    }

    fn dismiss_all(self: Pin<&mut Self>) {
        self.with(|core, out| core.dismiss_for(None, out));
    }

    pub(crate) fn dismiss_for_app(self: Pin<&mut Self>, app_id: &QString) {
        let app = app_id.to_string();
        if !app.is_empty() {
            self.with(|core, out| core.dismiss_for(Some(&app), out));
        }
    }

    /// Every decision, as when it is uninstalled.
    pub(crate) fn forget_app(self: Pin<&mut Self>, app_id: &QString) {
        let app = app_id.to_string();
        self.with(|core, out| {
            core.dismiss_for(Some(&app), out);
            if core.stored.remove(&app).is_some() {
                core.save();
            }
        });
    }

    fn app_permissions(&self, app_id: &QString) -> QStringList {
        let app = app_id.to_string();
        let core = core();
        marathon_permissions::permissions()
            .keys()
            .filter(|p| core.has(&app, p))
            .map(QString::from)
            .collect()
    }

    fn available_permissions(&self) -> QStringList {
        marathon_permissions::permissions()
            .keys()
            .map(QString::from)
            .collect()
    }

    fn permission_label(&self, permission: &QString) -> QString {
        let p = permission.to_string();
        marathon_permissions::describe(&p)
            .map_or_else(|| permission.clone(), |d| QString::from(&d.label))
    }

    fn permission_description(&self, permission: &QString) -> QString {
        QString::from(
            marathon_permissions::describe(&permission.to_string())
                .map_or_else(|| fl!("permission-unknown"), |d| d.description.clone()),
        )
    }
}

/// Who may act on an app's permissions: an app on its own, never granting;
/// Settings on any, asking only for itself.
fn allowed(caller: &str, app: &str, op: Op) -> bool {
    if gate::is_test_caller(caller) {
        return true;
    }
    if caller.is_empty() || app.is_empty() {
        return false;
    }
    if caller == "settings" {
        return caller == app || op != Op::Request;
    }
    caller == app && op != Op::Grant
}

#[derive(PartialEq, Eq, Clone, Copy)]
enum Op {
    Read,
    Request,
    Grant,
    Revoke,
}

fn is_android_app(app: &str) -> bool {
    let segment = |s: &str| {
        s.starts_with(|c: char| c.is_ascii_alphabetic())
            && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    };
    app.len() <= app_ids::ANDROID.len() + 255
        && app_ids::android_package(app).is_some_and(|pkg| pkg.split('.').all(segment))
}

/// A foreign prompt's options, when every known one is valid.
fn foreign_options(options: &State) -> Option<ForeignOptions> {
    let text = |k: &str, default: &str| match options.get(k) {
        None => Some(default.to_owned()),
        Some(v) => v.downcast_ref::<&str>().ok().map(str::to_owned),
    };
    let flag = |k: &str| match options.get(k) {
        None => Some(false),
        Some(v) => v.downcast_ref::<bool>().ok(),
    };
    let (kind, accuracy) = (text("kind", "foreground")?, text("accuracy", "")?);
    if !["foreground", "background", "precise"].contains(&kind.as_str())
        || !["", "choice", "approximate"].contains(&accuracy.as_str())
    {
        return None;
    }
    Some(ForeignOptions {
        kind,
        once: flag("once")?,
        accuracy,
        precise_default: flag("preciseDefault")?,
    })
}

async fn pid_of(name: &str) -> Option<u32> {
    let bus = io::session_bus().await.ok()?;
    let name = BusName::try_from(name).ok()?;
    fdo::DBusProxy::new(&bus)
        .await
        .ok()?
        .get_connection_unix_process_id(name)
        .await
        .ok()
}

async fn caller(h: &Header<'_>) -> String {
    let pid = match h.sender() {
        Some(sender) => pid_of(sender.as_str()).await,
        None => None,
    };
    gate::caller(pid).unwrap_or_default()
}

async fn authorize(h: &Header<'_>, app: &str, op: Op) -> fdo::Result<()> {
    if allowed(&caller(h).await, app, op) {
        Ok(())
    } else {
        Err(fdo::Error::AccessDenied(
            "AppId spoofing or unknown caller".into(),
        ))
    }
}

async fn prompter(h: &Header<'_>) -> fdo::Result<String> {
    let caller = caller(h).await;
    if gate::service_or_test(&caller, "android-permissions") {
        Ok(caller)
    } else {
        Err(fdo::Error::AccessDenied("Not a permission prompter".into()))
    }
}

// Forgets its prompt's caller however the call ends.
struct Waiting(String);

impl Drop for Waiting {
    fn drop(&mut self) {
        WAITING
            .lock()
            .unwrap_or_else(|_| std::process::abort())
            .remove(&self.0);
    }
}

struct Permissions1 {
    qt: cxx_qt::CxxQtThread<Permissions>,
}

#[zbus::interface(name = "org.marathonos.Shell.Permissions1")]
impl Permissions1 {
    async fn has_permission(
        &self,
        app_id: String,
        permission: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<bool> {
        authorize(&h, &app_id, Op::Read).await?;
        Ok(has(&app_id, &permission))
    }

    async fn request_permission(
        &self,
        app_id: String,
        permission: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        authorize(&h, &app_id, Op::Request).await?;
        ipc::on_gui(&self.qt, move |obj| {
            obj.request_permission(&QString::from(&app_id), &QString::from(&permission));
        })
        .await
    }

    async fn set_permission(
        &self,
        app_id: String,
        permission: String,
        granted: bool,
        remember: bool,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        authorize(&h, &app_id, if granted { Op::Grant } else { Op::Revoke }).await?;
        ipc::on_gui(&self.qt, move |obj| {
            obj.set_permission(
                &QString::from(&app_id),
                &QString::from(&permission),
                granted,
                remember,
            );
        })
        .await
    }

    /// deckardd's prompt for an Android app, `deckard.<package>`; options
    /// request (16 hex digits), kind, once, accuracy and preciseDefault.
    /// Answers allow, once, deny or cancel, and precise.
    async fn prompt_android(
        &self,
        app_id: String,
        permission: String,
        options: State,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<State> {
        let caller = prompter(&h).await?;
        let request = options
            .get("request")
            .and_then(|v| v.downcast_ref::<&str>().ok())
            .unwrap_or_default()
            .to_owned();
        let known = marathon_permissions::permissions()
            .get(&permission)
            .is_some_and(|p| !p.restricted);
        let cleaned = foreign_options(&options);
        let hex = request.len() == 16
            && request
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b));
        let (Some(cleaned), true, true, true) = (cleaned, is_android_app(&app_id), known, hex)
        else {
            return Err(fdo::Error::InvalidArgs("Bad prompt".into()));
        };
        let key = format!("{caller} {request}");
        let (tx, rx) = async_channel::bounded(1);
        {
            let mut waiting = WAITING.lock().unwrap_or_else(|_| std::process::abort());
            if waiting.contains_key(&key) || waiting.len() >= 16 {
                return Err(fdo::Error::LimitsExceeded("Too many prompts".into()));
            }
            waiting.insert(key.clone(), tx);
        }
        let _waiting = Waiting(key.clone());
        let sender = h.sender().map(ToString::to_string).unwrap_or_default();
        let bus = io::session_bus().await?;
        let mut gone = fdo::DBusProxy::new(&bus)
            .await?
            .receive_name_owner_changed_with_args(&[(0, sender.as_str()), (2, "")])
            .await?;
        let foreign = Foreign {
            key: key.clone(),
            app: app_id,
            permission,
            options: cleaned,
        };
        ipc::on_gui(&self.qt, move |obj| obj.foreign(foreign)).await?;
        // A prompter that leaves the bus takes its prompts with it.
        let answered = future::or(async { rx.recv().await.ok() }, async {
            gone.next().await;
            None
        })
        .await;
        let Some((answer, precise)) = answered else {
            ipc::on_gui(&self.qt, move |obj| obj.cancel_foreign(&key)).await?;
            return Err(fdo::Error::Failed("The prompter left".into()));
        };
        Ok(State::from([
            ("answer".to_owned(), value(answer)),
            ("precise".to_owned(), value(precise)),
        ]))
    }

    async fn cancel_android_prompt(
        &self,
        request: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        let key = format!("{} {request}", prompter(&h).await?);
        ipc::on_gui(&self.qt, move |obj| obj.cancel_foreign(&key)).await
    }

    /// A session daemon's gate for a caller of its own, as the shell's own
    /// services answer that caller.
    async fn admit(
        &self,
        sender: String,
        area: String,
        permissions: Vec<String>,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        if !gate::service_or_test(&caller(&h).await, "admit-callers") {
            return Err(fdo::Error::AccessDenied("Not a session daemon".into()));
        }
        let pid = pid_of(&sender).await;
        if pid != Some(std::process::id()) {
            gate::admit(pid, &sender, &area, &permissions)?;
        }
        Ok(())
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn core() -> Core {
        Core::default()
    }

    fn app(core: &mut Core, id: &str, declared: &[&str], protected: bool) {
        core.apps.insert(
            id.to_owned(),
            Facts {
                declared: declared.iter().map(|s| (*s).to_owned()).collect(),
                protected,
            },
        );
    }

    fn run(core: &mut Core, f: impl FnOnce(&mut Core, &mut Vec<Event>)) -> Vec<Event> {
        let mut out = Vec::new();
        f(core, &mut out);
        out
    }

    #[test]
    fn decisions_are_kept_per_app_and_survive_a_restart() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("p.json");
        let mut c = Core::load(path.clone());
        run(&mut c, |c, o| {
            c.set("notes", &["storage".into()], true, true, o);
        });
        run(&mut c, |c, o| {
            c.set("notes", &["network".into()], false, true, o);
        });
        run(&mut c, |c, o| {
            c.set("notes", &["camera".into()], true, false, o);
        });
        assert!(
            c.has("notes", "camera"),
            "a grant not remembered still holds this session"
        );
        let c = Core::load(path);
        assert_eq!(c.status("notes", "storage"), Status::Granted);
        assert_eq!(c.status("notes", "network"), Status::Denied);
        assert_eq!(c.status("other", "storage"), Status::NotRequested);
    }

    #[test]
    fn a_corrupted_file_starts_fresh() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("p.json");
        fs::write(&path, "{not json").unwrap();
        assert_eq!(Core::load(path).stored, BTreeMap::new());
    }

    #[test]
    fn an_app_holds_only_what_it_declared_and_restricted_needs_protected() {
        let mut c = core();
        app(&mut c, "notes", &["storage"], false);
        app(&mut c, "settings", &["system", "storage"], true);
        app(&mut c, "rogue", &["system"], false);
        run(&mut c, |c, o| {
            c.set("notes", &["network".into()], true, false, o);
        });
        assert_eq!(c.status("notes", "network"), Status::Denied, "undeclared");
        assert!(
            c.has("settings", "system"),
            "protected apps hold without asking"
        );
        run(&mut c, |c, o| {
            c.set("rogue", &["system".into()], true, false, o);
        });
        assert!(
            !c.has("rogue", "system"),
            "restricted needs a protected app"
        );
        assert_eq!(
            run(&mut c, |c, o| c.request("notes", "network", o)),
            [Event::Denied("notes".into(), "network".into())]
        );
    }

    #[test]
    fn requests_batch_into_one_prompt_per_app() {
        let mut c = core();
        app(&mut c, "mail", &["network", "storage"], false);
        app(&mut c, "maps", &["location"], false);
        run(&mut c, |c, o| {
            c.request("mail", "network", o);
            c.request("maps", "location", o);
            c.request("mail", "storage", o);
        });
        let shown = run(&mut c, Core::process);
        assert_eq!(
            shown[0],
            Event::Requested("mail".into(), vec!["network".into(), "storage".into()])
        );
        // A grant for another app leaves the prompt open.
        run(&mut c, |c, o| {
            c.set("maps", &["location".into()], true, true, o);
        });
        assert_eq!(c.prompt.as_ref().unwrap().app, "mail");
        let answered = run(&mut c, |c, o| c.respond(true, false, None, o));
        assert!(answered.contains(&Event::Granted("mail".into(), "storage".into())));
        assert!(c.prompt.is_none());
        // maps' request was answered meanwhile, so it is not asked again.
        let next = run(&mut c, Core::process);
        assert_eq!(next, [Event::Granted("maps".into(), "location".into())]);
        assert!(c.prompt.is_none());
    }

    #[test]
    fn an_undecided_permission_is_asked_on_first_use() {
        let mut c = core();
        app(&mut c, "camera", &["camera", "storage"], false);
        run(&mut c, |c, o| {
            c.set("camera", &["storage".into()], false, false, o);
        });
        let asked = run(&mut c, |c, o| {
            assert_eq!(
                c.ask_if_undecided("camera", &["storage".into(), "camera".into()], o)
                    .as_deref(),
                Some("camera")
            );
        });
        assert_eq!(asked, [Event::Recheck(150)]);
        assert_eq!(
            run(&mut c, |c, o| assert!(c
                .ask_if_undecided("unknown", &["camera".into()], o)
                .is_none())),
            []
        );
    }

    #[test]
    fn a_refusal_is_shown_once_then_stored() {
        let mut c = core();
        app(&mut c, "rogue", &["system"], false);
        run(&mut c, |c, o| c.request("rogue", "system", o));
        run(&mut c, Core::process);
        assert_eq!(c.prompt.as_ref().unwrap().refused, ["system"]);
        let out = run(&mut c, |c, o| c.respond(true, false, None, o));
        assert!(out.contains(&Event::Denied("rogue".into(), "system".into())));
        assert_eq!(
            run(&mut c, |c, o| c.request("rogue", "system", o)),
            [Event::Denied("rogue".into(), "system".into())]
        );
    }

    #[test]
    fn foreign_prompts_answer_their_choices_and_store_nothing() {
        let mut c = core();
        let ask = |c: &mut Core, key: &str, once: bool, accuracy: &str| {
            c.foreign.push_back(Foreign {
                key: key.into(),
                app: "deckard.org.a".into(),
                permission: "location".into(),
                options: ForeignOptions {
                    kind: "foreground".into(),
                    once,
                    accuracy: accuracy.into(),
                    precise_default: true,
                },
            });
            run(c, Core::process);
        };
        ask(&mut c, "k1", false, "approximate");
        let out = run(&mut c, |c, o| c.respond(true, true, Some(false), o));
        assert!(
            out.contains(&Event::Answered("k1".into(), "allow", true)),
            "{out:?}"
        );
        ask(&mut c, "k2", true, "choice");
        let out = run(&mut c, |c, o| c.respond(true, true, Some(false), o));
        assert!(out.contains(&Event::Answered("k2".into(), "once", false)));
        assert_eq!(c.stored, BTreeMap::new());
        ask(&mut c, "k3", false, "");
        let out = run(&mut c, |c, o| c.dismiss_for(Some("deckard.org.a"), o));
        assert!(out.contains(&Event::Answered("k3".into(), "cancel", false)));
    }

    #[test]
    fn forgetting_an_app_drops_its_decisions_and_prompts() {
        let mut c = core();
        app(&mut c, "x", &["storage", "network"], false);
        run(&mut c, |c, o| {
            c.set("x", &["storage".into()], true, false, o);
        });
        run(&mut c, |c, o| c.request("x", "network", o));
        run(&mut c, |c, o| c.dismiss_for(Some("x"), o));
        c.stored.remove("x");
        assert!(c.pending.is_empty() && c.prompt.is_none());
        assert_eq!(c.status("x", "storage"), Status::NotRequested);
    }

    #[test]
    fn apps_act_on_themselves_settings_on_others_and_only_the_user_grants() {
        use super::{allowed, Op};
        assert!(!allowed("", "notes", Op::Read) && !allowed("settings", "", Op::Read));
        assert!(allowed("notes", "notes", Op::Request) && allowed("notes", "notes", Op::Revoke));
        assert!(!allowed("notes", "notes", Op::Grant) && !allowed("notes", "weather", Op::Read));
        assert!(
            allowed("settings", "weather", Op::Grant)
                && !allowed("settings", "weather", Op::Request)
        );
        assert!(
            !allowed("Settings", "weather", Op::Read)
                && !allowed(" settings", "weather", Op::Grant)
        );
    }

    #[test]
    fn android_prompts_take_only_android_apps_and_known_options() {
        use super::{foreign_options, is_android_app, value, State};
        assert!(is_android_app("deckard.org.fossify.camera"));
        for bad in [
            "deckard.",
            "notes",
            "deckard.bad pkg",
            "deckard.9lives",
            "deckard.a..b",
            &format!("deckard.{}", "a".repeat(256)),
        ] {
            assert!(!is_android_app(bad), "{bad}");
        }
        assert_eq!(foreign_options(&State::new()).unwrap().kind, "foreground");
        let o = State::from([
            ("kind".to_owned(), value("background")),
            ("once".to_owned(), value(true)),
        ]);
        assert!(foreign_options(&o).is_some_and(|o| o.kind == "background" && o.once));
        for (k, v) in [
            ("kind", value("always")),
            ("accuracy", value("fine")),
            ("once", value("yes")),
        ] {
            assert!(
                foreign_options(&State::from([(k.to_owned(), v)])).is_none(),
                "{k}"
            );
        }
    }
}
