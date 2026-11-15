//! `Pilot` (QML `MarathonOS.Pilot`): the Pilot app's client of pilotd
//! (`org.shipwright.Pilot1`, crates/pilotd).
//!
//! Turns (`ask`, `confirm`) run on a worker thread and come back through
//! `turnFinished(json)`; `busy` is true meanwhile. Settings, the egress log,
//! export and wipe are quick local D-Bus calls and return at once. A watcher
//! thread follows pilotd's `Offline` and `LastResponse` properties, and
//! hands over why pilotd started the app as one of the request signals.

pub mod client;
mod photo;

#[cxx_qt::bridge(namespace = "marathon::pilot")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, connected, READ, NOTIFY)]
        #[qproperty(bool, offline, READ, NOTIFY)]
        #[qproperty(bool, busy, READ, NOTIFY)]
        #[qproperty(QString, last_response, cxx_name = "lastResponse", READ, NOTIFY)]
        #[qproperty(QString, error, READ, NOTIFY)]
        #[qproperty(bool, voice_available, cxx_name = "voiceAvailable", READ, NOTIFY)]
        #[qproperty(QString, model_state, cxx_name = "modelState", READ, NOTIFY)]
        type Pilot = super::PilotRust;

        /// A typed (or transcribed) turn; the result arrives as
        /// `turnFinished`.
        #[qinvokable]
        fn ask(self: Pin<&mut Pilot>, text: &QString, spoken: bool);
        /// Answers a confirmation card; the result arrives as `turnFinished`.
        #[qinvokable]
        fn confirm(self: Pin<&mut Pilot>, id: &QString, approved: bool);
        /// The `TurnResult` JSON of apps/pilot/README.md, or `{"error": ...}`.
        #[qsignal]
        #[cxx_name = "turnFinished"]
        fn turn_finished(self: Pin<&mut Pilot>, json: QString);

        /// Settings JSON, or `{"error": ...}`.
        #[qinvokable]
        fn settings(self: &Pilot) -> QString;
        /// Returns an error message, empty on success.
        #[qinvokable]
        #[cxx_name = "setConsent"]
        fn set_consent(self: &Pilot, name: &QString, on: bool) -> QString;
        /// Stops using the app Pilot was opened over as context.
        #[qinvokable]
        #[cxx_name = "clearOnScreen"]
        fn clear_on_screen(self: &Pilot);
        /// Opens a card's web address (a source chip) in the browser,
        /// through pilotd: the sandboxed app cannot itself.
        #[qinvokable]
        #[cxx_name = "openUrl"]
        fn open_url(self: &Pilot, url: &QString);
        /// Starts a new conversation: earlier questions stop being context.
        #[qinvokable]
        #[cxx_name = "clearConversation"]
        fn clear_conversation(self: &Pilot);
        /// What Pilot can do in the person's apps, as JSON
        /// `[{"app", "name", "actions": [{"title", "description", "asks"}]}]`;
        /// `[]` on error.
        #[qinvokable]
        fn capabilities(self: &Pilot) -> QString;
        /// What Pilot remembers, as JSON `[{"id", "ts_ms", "fact"}]`; `[]` on error.
        #[qinvokable]
        fn memories(self: &Pilot) -> QString;
        /// Forgets one remembered fact; whether it was there.
        #[qinvokable]
        fn forget(self: &Pilot, id: i64) -> bool;
        /// A step of the getting-started guide tried (or "hidden"); "" or
        /// an error.
        #[qinvokable]
        #[cxx_name = "setGuide"]
        fn set_guide(self: &Pilot, step: &QString, done: bool) -> QString;
        /// What Pilot calls the person on its home; "" or an error.
        #[qinvokable]
        #[cxx_name = "setName"]
        fn set_name(self: &Pilot, name: &QString) -> QString;
        /// Newest first, as JSON; `[]` on error.
        #[qinvokable]
        #[cxx_name = "egressLog"]
        fn egress_log(self: &Pilot, limit: i32) -> QString;
        /// Writes pilotd's export to `path` (0600). Error message or empty.
        #[qinvokable]
        #[cxx_name = "exportTo"]
        fn export_to(self: &Pilot, path: &QString) -> QString;
        /// `~/Downloads/pilot-export-<unix time>.json`.
        #[qinvokable]
        #[cxx_name = "defaultExportPath"]
        fn default_export_path(self: &Pilot) -> QString;
        /// Error message or empty; emits `wiped` on success.
        #[qinvokable]
        fn wipe(self: Pin<&mut Pilot>) -> QString;
        /// pilotd's records were deleted: clear the conversation too.
        #[qsignal]
        fn wiped(self: Pin<&mut Pilot>);
        /// Bytes of the speech models pilot-voice downloaded; -1 when
        /// pilotd cannot be asked.
        #[qinvokable]
        #[cxx_name = "voiceModelsBytes"]
        fn voice_models_bytes(self: &Pilot) -> i64;
        /// Deletes them: error message or empty.
        #[qinvokable]
        #[cxx_name = "removeVoiceModels"]
        fn remove_voice_models(self: &Pilot) -> QString;
        /// Downloads the models on the phone, on mobile data too when
        /// `allowMetered`; `modelState` follows.
        #[qinvokable]
        #[cxx_name = "downloadModels"]
        fn download_models(self: Pin<&mut Pilot>, allow_metered: bool);
        /// Proactive triage results, JSON array.
        #[qinvokable]
        fn triage(self: &Pilot) -> QString;
        /// A push-to-talk turn through pilot-voice; the result (with
        /// `transcript`) arrives as `turnFinished`.
        #[qinvokable]
        fn listen(self: Pin<&mut Pilot>);
        /// A camera turn: the photo at `path` (deleted afterwards) and the
        /// question; the result arrives as `turnFinished`.
        #[qinvokable]
        fn look(self: Pin<&mut Pilot>, question: &QString, path: &QString);
        /// Where the viewfinder saves the photo: the app's private cache.
        #[qinvokable]
        #[cxx_name = "photoPath"]
        fn photo_path(self: &Pilot) -> QString;
        /// Pilot's events entry asked for the events page, or started the
        /// app for it.
        #[qsignal]
        #[cxx_name = "eventsRequested"]
        fn events_requested(self: Pin<&mut Pilot>);
        /// The system-wide gesture asked for the sheet, or started the app
        /// for it.
        #[qsignal]
        #[cxx_name = "sheetRequested"]
        fn sheet_requested(self: Pin<&mut Pilot>);
        /// The shell's assistant key asked for the sheet, listening, or
        /// started the app for it.
        #[qsignal]
        #[cxx_name = "listenRequested"]
        fn listen_requested(self: Pin<&mut Pilot>);

        /// Reads the home (`Now` on D-Bus); the JSON arrives as `nowChanged`.
        #[qinvokable]
        #[cxx_name = "refreshNow"]
        fn refresh_now(self: Pin<&mut Pilot>);
        #[qsignal]
        #[cxx_name = "nowChanged"]
        fn now_changed(self: Pin<&mut Pilot>, json: QString);

        /// Cancels a timer, alarm or reminder, then refreshes the home.
        #[qinvokable]
        #[cxx_name = "cancelClock"]
        fn cancel_clock(self: Pin<&mut Pilot>, cookie: i32);
        /// `seconds` more on a running timer; its new card arrives as
        /// `timerExtended(oldCookie, json)`.
        #[qinvokable]
        #[cxx_name = "extendTimer"]
        fn extend_timer(self: Pin<&mut Pilot>, cookie: i32, seconds: i32);
        #[qsignal]
        #[cxx_name = "timerExtended"]
        fn timer_extended(self: Pin<&mut Pilot>, old_cookie: i32, json: QString);
        #[qsignal]
        #[cxx_name = "clockCancelled"]
        fn clock_cancelled(self: Pin<&mut Pilot>, cookie: i32);

        /// A turn's stage: `{"turn", "stage", "detail"}`.
        #[qsignal]
        #[cxx_name = "turnProgress"]
        fn turn_progress(self: Pin<&mut Pilot>, json: QString);
    }

    impl cxx_qt::Threading for Pilot {}
    impl cxx_qt::Initialize for Pilot {}
}

use core::pin::Pin;
use std::path::PathBuf;
use std::sync::Arc;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use marathon_rt::log;

use client::{Change, Client};

#[derive(Default)]
#[allow(
    clippy::struct_excessive_bools,
    reason = "each is a QML property of its own, not a state"
)]
pub struct PilotRust {
    connected: bool,
    offline: bool,
    busy: bool,
    last_response: QString,
    error: QString,
    voice_available: bool,
    model_state: QString,
    client: Option<Arc<Client>>,
}

fn q(s: &str) -> QString {
    QString::from(s)
}

/// The app's locale from its environment (`LC_ALL`, `LC_MESSAGES`, `LANG`,
/// as `QLocale` reads it), without the encoding: `de_DE`. None for the C
/// locale.
fn app_locale() -> Option<String> {
    ["LC_ALL", "LC_MESSAGES", "LANG"]
        .iter()
        .filter_map(|v| std::env::var(v).ok())
        .map(|v| v.split(['.', '@']).next().unwrap_or("").to_owned())
        .find(|v| !v.is_empty() && v != "C" && v != "POSIX")
}

fn err_json(msg: &str) -> QString {
    q(&serde_json::json!({ "error": msg }).to_string())
}


impl cxx_qt::Initialize for qobject::Pilot {
    fn initialize(self: Pin<&mut Self>) {
        // The session bus connection and the first contact, which
        // activates pilotd, are made on a worker, not before the app's
        // first frame. Until the connection is handed over, calls answer
        // "Pilot is not available".
        let thread = self.qt_thread();
        let spawned = std::thread::Builder::new()
            .name("pilot-watch".into())
            .spawn(move || {
                let client = match Client::connect() {
                    Ok(c) => Arc::new(c),
                    Err(e) => {
                        thread
                            .queue(move |mut o| {
                                set!(o, error, error_changed, q(&format!("No session bus: {e}")));
                            })
                            .ok();
                        return;
                    }
                };
                {
                    let client = Arc::clone(&client);
                    if thread
                        .queue(move |mut o| o.as_mut().rust_mut().client = Some(client))
                        .is_err()
                    {
                        return;
                    }
                }
                // A turn's stages, for the line that says what Pilot is doing.
                {
                    let client = Arc::clone(&client);
                    let thread = thread.clone();
                    let progress = std::thread::Builder::new()
                        .name("pilot-progress".into())
                        .spawn(move || loop {
                            let watched = client.watch_progress(|stage| {
                                thread
                                    .queue(move |mut o| o.as_mut().turn_progress(q(&stage)))
                                    .is_ok()
                            });
                            // pilotd not running yet: try again shortly.
                            if watched.is_ok() {
                                return;
                            }
                            std::thread::sleep(std::time::Duration::from_secs(2));
                        });
                    if let Err(e) = progress {
                        log::warn("pilot", format_args!("no progress thread: {e}"));
                    }
                }
                watch_pilotd(&client, &thread);
            });
        if let Err(e) = spawned {
            log::warn("pilot", format_args!("no watcher thread: {e}"));
        }
    }
}

/// First contact with pilotd (which activates it) and why it started the
/// app, then its changes, for as long as the app runs.
fn watch_pilotd(client: &Arc<Client>, thread: &cxx_qt::CxxQtThread<qobject::Pilot>) {
    let mut first = true;
    loop {
        // pilotd is D-Bus activated on a phone; until it answers
        // (first start, a restart, a test bus being set up), retry.
        let initial = client
            .offline()
            .and_then(|off| client.last_response().map(|last| (off, last)));
        let ok = initial.is_ok();
        let mut request = String::new();
        let (voice, models) = if ok {
            (client.voice_available(), client.model_state())
        } else {
            (false, String::new())
        };
        if ok {
            // pilotd answers in the app's language. An older pilotd
            // without SetLocale keeps its own.
            if let Some(locale) = app_locale() {
                client.set_locale(&locale).ok();
            }
            if first {
                request = client.take_launch_request().unwrap_or_default();
                first = false;
            }
        }
        let alive = thread
            .queue(move |mut o| {
                match initial {
                    Ok((off, last)) => {
                        set!(o, connected, connected_changed, true);
                        set!(o, offline, offline_changed, off);
                        set!(o, last_response, last_response_changed, q(&last));
                        set!(o, error, error_changed, QString::default());
                        set!(o, voice_available, voice_available_changed, voice);
                        set!(o, model_state, model_state_changed, q(&models));
                    }
                    Err(e) => {
                        set!(o, connected, connected_changed, false);
                        set!(
                            o,
                            error,
                            error_changed,
                            q(&format!("Pilot is not running: {e}"))
                        );
                    }
                }
                match request.as_str() {
                    "events" => o.as_mut().events_requested(),
                    "sheet" => o.as_mut().sheet_requested(),
                    "listen" => o.as_mut().listen_requested(),
                    _ => {}
                }
            })
            .is_ok();
        if !alive {
            return;
        }
        if !ok {
            std::thread::sleep(std::time::Duration::from_secs(2));
            continue;
        }
        let watched = client.watch(|change| {
            thread
                .queue(move |mut o| match change {
                    Change::Offline(v) => set!(o, offline, offline_changed, v),
                    Change::LastResponse(s) => {
                        set!(o, last_response, last_response_changed, q(&s));
                    }
                    Change::EventsRequested => o.as_mut().events_requested(),
                    Change::SheetRequested => o.as_mut().sheet_requested(),
                    Change::ListenRequested => o.as_mut().listen_requested(),
                    Change::ModelState(s) => set!(o, model_state, model_state_changed, q(&s)),
                })
                .is_ok()
        });
        if let Err(e) = watched {
            log::warn("pilot", format_args!("watching pilotd: {e}"));
        }
        return;
    }
}

impl qobject::Pilot {
    fn client(&self) -> Option<Arc<Client>> {
        self.rust().client.clone()
    }

    /// Runs `work` on a worker and emits its JSON as `turnFinished`.
    fn turn(
        mut self: Pin<&mut Self>,
        work: impl FnOnce(&Client) -> Result<String, String> + Send + 'static,
    ) {
        let Some(client) = self.client() else {
            self.as_mut()
                .turn_finished(err_json("Pilot is not available"));
            return;
        };
        set!(self, busy, busy_changed, true);
        let thread = self.qt_thread();
        let spawned = std::thread::Builder::new()
            .name("pilot-turn".into())
            .spawn(move || {
                let json = match work(&client) {
                    Ok(j) => q(&j),
                    Err(e) => err_json(&e),
                };
                thread
                    .queue(move |mut o| {
                        set!(o, busy, busy_changed, false);
                        set!(o, connected, connected_changed, true);
                        o.as_mut().turn_finished(json);
                    })
                    .ok();
            });
        if spawned.is_err() {
            set!(self, busy, busy_changed, false);
            self.as_mut()
                .turn_finished(err_json("could not start a worker"));
        }
    }

    pub fn ask(self: Pin<&mut Self>, text: &QString, spoken: bool) {
        let text = text.to_string();
        self.turn(move |c| c.ask(&text, spoken));
    }

    pub fn confirm(self: Pin<&mut Self>, id: &QString, approved: bool) {
        let id = id.to_string();
        self.turn(move |c| c.confirm(&id, approved));
    }

    /// Runs `work` on a worker and hands its result to `done` on the Qt
    /// thread.
    fn background<T: Send + 'static>(
        &self,
        work: impl FnOnce(&Client) -> Result<T, String> + Send + 'static,
        done: impl FnOnce(Pin<&mut Self>, Result<T, String>) + Send + 'static,
    ) {
        let Some(client) = self.client() else { return };
        let thread = self.qt_thread();
        let spawned = std::thread::Builder::new()
            .name("pilot-call".into())
            .spawn(move || {
                let r = work(&client);
                thread.queue(move |o| done(o, r)).ok();
            });
        if let Err(e) = spawned {
            log::warn("pilot", format_args!("no worker: {e}"));
        }
    }

    pub fn download_models(self: Pin<&mut Self>, allow_metered: bool) {
        self.background(
            move |client| client.download_models(allow_metered),
            |mut o, r| match r {
                Ok(json) => set!(o, model_state, model_state_changed, q(&json)),
                Err(e) => log::warn("pilot", format_args!("DownloadModels: {e}")),
            },
        );
    }

    pub fn refresh_now(self: Pin<&mut Self>) {
        self.background(Client::now, |o, r| {
            if let Ok(json) = r {
                o.now_changed(q(&json));
            }
        });
    }

    pub fn cancel_clock(self: Pin<&mut Self>, cookie: i32) {
        let Ok(c) = u32::try_from(cookie) else { return };
        self.background(
            move |client| client.cancel_clock(c),
            move |mut o, r| {
                if r.is_ok() {
                    o.as_mut().clock_cancelled(cookie);
                }
                o.refresh_now();
            },
        );
    }

    pub fn extend_timer(self: Pin<&mut Self>, cookie: i32, seconds: i32) {
        let (Ok(c), Ok(s)) = (u32::try_from(cookie), u32::try_from(seconds)) else {
            return;
        };
        self.background(
            move |client| client.extend_timer(c, s),
            move |mut o, r| {
                if let Ok(json) = r {
                    o.as_mut().timer_extended(cookie, q(&json));
                }
                o.refresh_now();
            },
        );
    }

    fn with<T>(&self, f: impl FnOnce(&Client) -> Result<T, String>) -> Result<T, String> {
        match self.client() {
            Some(c) => f(&c),
            None => Err("Pilot is not available".into()),
        }
    }

    fn status(r: Result<(), String>) -> QString {
        r.err().map_or_else(QString::default, |e| q(&e))
    }

    pub fn settings(&self) -> QString {
        self.with(Client::settings)
            .map_or_else(|e| err_json(&e), |s| q(&s))
    }

    pub fn set_consent(&self, name: &QString, on: bool) -> QString {
        let name = name.to_string();
        Self::status(self.with(|c| c.set_consent(&name, on)))
    }

    pub fn open_url(&self, url: &QString) {
        let url = url.to_string();
        self.with(|c| c.open_url(&url)).ok();
    }

    pub fn clear_conversation(&self) {
        self.with(Client::clear_conversation).ok();
    }

    pub fn clear_on_screen(&self) {
        self.with(Client::clear_on_screen).ok();
    }

    pub fn capabilities(&self) -> QString {
        q(&self
            .with(Client::capabilities)
            .unwrap_or_else(|_| "[]".into()))
    }

    pub fn memories(&self) -> QString {
        q(&self.with(Client::memories).unwrap_or_else(|_| "[]".into()))
    }

    pub fn forget(&self, id: i64) -> bool {
        self.with(|c| c.forget(id)).unwrap_or(false)
    }

    pub fn set_guide(&self, step: &QString, done: bool) -> QString {
        let step = step.to_string();
        Self::status(self.with(|c| c.set_guide(&step, done)))
    }

    pub fn set_name(&self, name: &QString) -> QString {
        let name = name.to_string();
        Self::status(self.with(|c| c.set_name(&name)))
    }

    pub fn egress_log(&self, limit: i32) -> QString {
        let limit = u32::try_from(limit).unwrap_or(0);
        self.with(|c| c.egress_log(limit))
            .map_or_else(|_| q("[]"), |s| q(&s))
    }

    pub fn export_to(&self, path: &QString) -> QString {
        let path = PathBuf::from(path.to_string());
        Self::status(self.with(|c| {
            let data = c.export()?;
            write_private(&path, data.as_bytes()).map_err(|e| format!("{}: {e}", path.display()))
        }))
    }

    pub fn default_export_path(&self) -> QString {
        q(&default_export_path().to_string_lossy())
    }

    pub fn wipe(mut self: Pin<&mut Self>) -> QString {
        let r = self.with(Client::wipe);
        if r.is_ok() {
            self.as_mut().wiped();
        }
        Self::status(r)
    }

    pub fn voice_models_bytes(&self) -> i64 {
        self.with(Client::voice_models)
            .map_or(-1, |b| i64::try_from(b).unwrap_or(i64::MAX))
    }

    pub fn remove_voice_models(&self) -> QString {
        Self::status(self.with(Client::remove_voice_models).map(|_| ()))
    }

    pub fn triage(&self) -> QString {
        self.with(|c| Ok(c.triage()))
            .map_or_else(|_| q("[]"), |s| q(&s))
    }

    pub fn listen(self: Pin<&mut Self>) {
        self.turn(Client::listen);
    }

    pub fn look(self: Pin<&mut Self>, question: &QString, path: &QString) {
        let question = question.to_string();
        let path = PathBuf::from(path.to_string());
        self.turn(move |c| {
            let small = path.with_extension("pilot.jpg");
            let bytes = if photo::prepare(&path, &small, PHOTO_SIDE) {
                std::fs::read(&small).map_err(|e| e.to_string())
            } else {
                Err("the photo could not be read".into())
            };
            // Nothing of the photo stays behind on the app's side.
            std::fs::remove_file(&path).ok();
            std::fs::remove_file(&small).ok();
            c.look(&question, &bytes?)
        });
    }

    pub fn photo_path(&self) -> QString {
        let dir = photo_dir();
        if let Err(e) = std::fs::create_dir_all(&dir) {
            log::warn("pilot", format_args!("{}: {e}", dir.display()));
        }
        q(&dir.join("pilot-look.jpg").to_string_lossy())
    }
}

/// `$XDG_CACHE_HOME/shoal-pilot`, or `~/.cache/shoal-pilot`.
fn photo_dir() -> PathBuf {
    std::env::var_os("XDG_CACHE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .unwrap_or_else(std::env::temp_dir)
        .join("shoal-pilot")
}

/// Long side of the photo sent to Pilot; pilotd accepts up to 1600.
const PHOTO_SIDE: i32 = 1280;

/// `$SHOAL_PILOT_DOWNLOADS` (tests) or `~/Downloads`, with a timestamped name.
pub fn default_export_path() -> PathBuf {
    let dir = std::env::var_os("SHOAL_PILOT_DOWNLOADS")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join("Downloads")))
        .unwrap_or_else(|| PathBuf::from("."));
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    dir.join(format!("pilot-export-{secs}.json"))
}

fn write_private(path: &std::path::Path, bytes: &[u8]) -> std::io::Result<()> {
    use std::io::Write as _;
    use std::os::unix::fs::OpenOptionsExt as _;
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)?;
    f.write_all(bytes)
}
