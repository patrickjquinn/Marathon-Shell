// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! `org.shipwright.Pilot` on the session bus: interface
//! `org.shipwright.Pilot1` at `/org/shipwright/Pilot`.
//!
//! Structured values cross the bus as JSON strings, which QML parses with
//! `JSON.parse` and which keep the interface stable while card types grow.
//! Calls are reachable from sandboxed apps only with the `ShoalPilot`
//! Sailjail permission (`sailjail/ShoalPilot.permission`); on Marathon only
//! from the Pilot app and the shell ([`crate::callers`]).
//!
//! | Member | Signature | Meaning |
//! | --- | --- | --- |
//! | `Ask(text, spoken)` | `sb -> s` | One turn; returns the `TurnResult` JSON |
//! | `Confirm(id, approved)` | `sb -> s` | Answer a confirmation card |
//! | `Stop()` | | Ends the turn in flight; its `Ask` returns "Stopped." |
//! | `Listen()` | `-> s` | A push-to-talk turn through pilot-voice |
//! | `Look(question, jpeg)` | `say -> s` | A camera turn: the photo the person took |
//! | `Triage(limit)` | `u -> s` | Triaged events, newest first, 0 = all |
//! | `OpenEvents()` | | The Events view entry was tapped: mark seen, open the app's events page |
//! | `EventsSummary()` | `-> s` | What needs the person: `{"summary", "titles"}`, or `{}` |
//! | `ShowSheet()` | | The system-wide gesture (shoal-pilot-gesture-patch): bring up the app's sheet |
//! | `Settings()` | `-> s` | Consent, backend, available backends |
//! | `SetConsent(name, on)` | `sb` | Per-capability cloud consent |
//! | `SetBackend(name)` | `s` | "standard" or "lighthouse" |
//! | `EgressLog(limit)` | `u -> s` | Newest first, 0 = all |
//! | `Export()` | `-> s` | Egress and decision logs as one JSON document |
//! | `Wipe()` | | Deletes both logs and the last response |
//! | `VoiceModels()` | `-> t` | Bytes of the speech models pilot-voice downloaded (`voice_models`) |
//! | `RemoveVoiceModels()` | `-> t` | Deletes them; the bytes freed |
//! | `Offline` | property `b` | Privacy switch engaged |
//! | `VoiceAvailable` | property `b` | pilot-voice is installed; read it, no change signal |
//! | `ModelState` | property `s` | The models on the phone: `{"state", "bytes", "total", "error"}` (`models::Status`) |
//! | `DownloadModels(allow_metered)` | `b` → `s` | Starts their download (unmetered network, room for them); `ModelState` after |
//! | `LastResponse` | property `s` | Headline of the last turn (cover) |
//! | `EventsRequested` | property `u` | Counts `OpenEvents` calls; a running app shows its events page on change |
//! | `SheetRequested` | property `u` | Counts `ShowSheet` calls; a running app opens its sheet on change |
//! | `TurnFinished(json)` | signal `s` | Every turn and confirmation result |
//! | `TriageAdded(json)` | signal `s` | One newly triaged event |
//! | `Memories()` | `s` | What Pilot remembers: `[{"id", "ts_ms", "fact"}]` |
//! | `Forget(id)` | `x` → `b` | Forgets one remembered fact |
//! | `SetGuide(step, done)` | `sb` | The app's getting-started guide: a step tried, or "hidden" |
//! | `Capabilities()` | `s` | What Pilot can do in the person's apps: `[{"app", "name", "actions": [{"title", "description", "asks"}]}]` |
//! | `SetName(name)` | `s` | What Pilot calls the person on its home; empty for none |
//! | `ShowSheetFor(pid)` | `u` → `s` | As `ShowSheet`, from Lipstick's gesture with the process id of the window on top: that app's screen (its `KeelContext`, through keel-mcp) is the context of the next questions for three minutes; returns the app's name |
//! | `ListenFor(pid)` | `u` → `s` | As `ShowSheetFor`, with Pilot listening: the shell's assistant key |
//! | `ListenRequested` | property `u` | Counts `ListenFor` calls; a running app opens its sheet and listens on change |
//! | `TakeLaunchRequest()` | `s` | "sheet", "listen" or "events" when `ShowSheet`/`ListenFor`/`OpenEvents` started the app in the last 10 s, taken once |
//! | `ClearOnScreen()` | | Stops using that app's screen as context |
//! | `OpenUrl(url)` | `s` → `b` | Opens an http(s) address from a card in Pacific (or the browser): the sandboxed app cannot |
//! | `ClearConversation()` | | Starts a new conversation: earlier questions are no longer context |
//! | `Now()` | `s` | The home: running timers, alarms, reminders, the next events, triage that needs the person, suggestions (JSON, `now::Now`) |
//! | `CancelClock(cookie)` | `u` → `b` | Cancels a timer, alarm or reminder |
//! | `ExtendTimer(cookie, seconds)` | `uu` → `s` | Adds `seconds` to a running timer; the new timer card (JSON) |
//! | `TurnProgress(json)` | signal `s` | A turn's stage: `{"turn", "stage", "detail"}`, stage thinking, searching, reading or writing |

use std::sync::{Arc, Mutex};

use zbus::object_server::SignalEmitter;
use zbus::{fdo, interface};

use crate::callers::Caller;
use crate::pipeline::{Pipeline, TurnResult};
use crate::settings::{Consent, SettingsFile};
use crate::store::Store;

pub const BUS_NAME: &str = "org.shipwright.Pilot";
pub const PATH: &str = "/org/shipwright/Pilot";

/// Builds the backends named in settings; injected so tests can swap them.
pub type BackendFactory = Arc<dyn Fn(&str) -> Option<crate::pipeline::Backends> + Send + Sync>;

pub struct PilotService {
    pub pipeline: Arc<Pipeline>,
    pub settings: Arc<Mutex<SettingsFile>>,
    pub live: Arc<Mutex<crate::settings::Settings>>,
    pub store: Arc<Store>,
    pub offline: crate::privacy::Offline,
    pub backends: Vec<String>,
    pub factory: BackendFactory,
    pub adapters: Arc<crate::adapters::Adapters>,
    pub triage: Arc<crate::triage::Triage>,
    pub events: Arc<crate::events::EventsEntry>,
    pub events_requested: Arc<std::sync::atomic::AtomicU32>,
    /// `[events] open_command`.
    pub open_events: Vec<String>,
    pub sheet_requested: Arc<std::sync::atomic::AtomicU32>,
    pub listen_requested: Arc<std::sync::atomic::AtomicU32>,
    pub launch_request: Arc<Mutex<Option<(String, std::time::Instant)>>>,
    /// `[sheet] open_command`.
    pub open_sheet: Vec<String>,
    /// zbus runs interface methods on its own executor; the pipeline's
    /// HTTP client needs Tokio, so turns are spawned onto this runtime.
    pub runtime: tokio::runtime::Handle,
    /// Each confirmation card's id and the bus connection whose turn made
    /// it: only that connection (the Pilot app that shows the card) may
    /// answer it. Turns are broadcast in `TurnFinished`, card ids included,
    /// so without this any process of the person's could watch for a card
    /// and say yes to a text or a call itself.
    pub card_owners: Arc<Mutex<std::collections::HashMap<String, String>>>,
    /// `Daemon::warm`.
    pub warm: Vec<String>,
    pub http: reqwest::Client,
    pub callers: Arc<crate::callers::Callers>,
    /// The connection this object is served on.
    pub session: zbus::Connection,
    pub models: Arc<crate::models::Models>,
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Starts `command` (program and arguments), not waiting for it.
fn spawn(command: &[String], what: &str) {
    if let Some((prog, args)) = command.split_first() {
        match crate::privilege::unprivileged(&mut std::process::Command::new(prog))
            .args(args)
            .spawn()
        {
            // Reaped on its own thread: the app may run for hours.
            Ok(mut child) => {
                std::thread::Builder::new()
                    .name("pilot-reap".into())
                    .spawn(move || child.wait())
                    .ok();
            }
            Err(e) => log::warn!("{what}: {e}"),
        }
    }
}

fn to_json(r: &TurnResult) -> String {
    serde_json::to_string(r).unwrap_or_else(|_| "{}".into())
}

impl PilotService {
    async fn admit(&self, header: &zbus::message::Header<'_>) -> fdo::Result<Caller> {
        let sender = header.sender().map(ToString::to_string);
        self.callers.admit(&self.session, sender.as_deref()).await
    }

    /// Records `sender` as the owner of the turn's confirmation cards.
    fn on_marathon(&self) -> bool {
        self.callers.policy == crate::callers::Policy::Marathon
    }

    fn own_cards(&self, r: &TurnResult, sender: Option<String>) {
        let Some(sender) = sender else { return };
        let mut owners = lock(&self.card_owners);
        // A card waits at most a few minutes (PENDING_TTL); a bound on the
        // map all the same.
        if owners.len() > 256 {
            owners.clear();
        }
        for c in &r.cards {
            if let crate::pipeline::Card::Confirm { id, .. } = c {
                owners.insert(id.clone(), sender.clone());
            }
        }
    }

    fn save(&self, f: impl FnOnce(&mut crate::settings::Settings)) -> fdo::Result<()> {
        let mut file = lock(&self.settings);
        f(&mut file.current);
        *lock(&self.live) = file.current.clone();
        file.save().map_err(|e| {
            log::error!("saving settings: {e}");
            fdo::Error::Failed("could not save settings".into())
        })
    }

    /// The app on top (`pid`, 0 for none) becomes the context of the next
    /// questions: what it shows is read before Pilot comes to the front.
    /// Its name, empty when it is not a Keel app.
    async fn capture_for(&self, pid: u32, session: &zbus::Connection) -> String {
        let app = match crate::adapters::marathon::app_for_pid(session, pid).await {
            Some(app) => Some(app),
            None => crate::onscreen::app_for_pid(pid),
        }
        // Pilot itself: its Sailfish id, or the shell's for it.
        .filter(|a| {
            a.id != "org.shipwright.shoal-pilot"
                && a.id.strip_prefix("org.marathonos.") != Some(crate::callers::PILOT_APP)
        });
        if let Some(app) = app {
            let pipeline = Arc::clone(&self.pipeline);
            let (id, name) = (app.id.clone(), app.name.clone());
            self.runtime
                .spawn(async move { pipeline.capture_on_screen(&id, &name).await })
                .await
                .ok();
            app.name
        } else {
            self.pipeline.clear_on_screen();
            String::new()
        }
    }

    /// Brings up the app's sheet, listening when `listen`: a running app
    /// follows `SheetRequested` or `ListenRequested`, a started one its launch
    /// request.
    async fn request_sheet(&self, emitter: &SignalEmitter<'_>, listen: bool) {
        let what = if listen { "listen" } else { "sheet" };
        *lock(&self.launch_request) = Some((what.into(), std::time::Instant::now()));
        // A frozen app reads nothing until it is thawed: the shell wakes a
        // running Pilot (or starts it, behind the app on screen) first.
        let marathon = self.on_marathon();
        if marathon {
            match crate::adapters::marathon::start_in_background(
                &self.session,
                crate::callers::PILOT_APP,
            )
            .await
            {
                Ok(true) => {}
                Ok(false) => log::warn!("the shell did not start Pilot"),
                Err(e) => log::warn!("waking Pilot: {e}"),
            }
        }
        if listen {
            self.listen_requested
                .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            self.listen_requested_changed(emitter).await.ok();
        } else {
            self.sheet_requested
                .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            self.sheet_requested_changed(emitter).await.ok();
        }
        // Starting a running app again would make invoker raise its main
        // window, over the app the person was in.
        let app = self.open_sheet.iter().rev().find(|a| a.starts_with('/'));
        if !marathon && !app.is_some_and(|a| crate::onscreen::process_running(a)) {
            spawn(&self.open_sheet, "opening the sheet");
        }
    }
}

/// Whether Lipstick's home screen has Pilot's gesture (the gesture patch is
/// applied: its call to `ShowSheetFor` is in Lipstick's compositor).
fn gesture_installed() -> bool {
    std::fs::read_to_string("/usr/share/lipstick-jolla-home-qt5/compositor.qml")
        .is_ok_and(|q| q.contains("\"ShowSheetFor\""))
}

#[interface(name = "org.shipwright.Pilot1")]
#[allow(
    clippy::needless_pass_by_value,
    reason = "zbus deserializes each D-Bus argument into an owned value"
)]
impl PilotService {
    async fn ask(
        &self,
        text: String,
        spoken: bool,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        if text.chars().count() > 4000 {
            return Err(fdo::Error::InvalidArgs(
                "text longer than 4000 characters".into(),
            ));
        }
        let pipeline = Arc::clone(&self.pipeline);
        // Stop ends the turn where it is: the model's request goes with it,
        // and a model on the phone stops writing when its stream closes.
        let stopped = self.pipeline.stop.notified();
        let turn = self
            .runtime
            .spawn(async move { pipeline.ask(&text, spoken).await });
        let abort = turn.abort_handle();
        let r = tokio::select! {
            r = turn => r.map_err(|e| fdo::Error::Failed(format!("turn aborted: {e}")))?,
            () = stopped => {
                abort.abort();
                self.pipeline.stopped()
            }
        };
        self.own_cards(&r, header.sender().map(ToString::to_string));
        let json = to_json(&r);
        Self::turn_finished(&emitter, &json).await.ok();
        self.last_response_changed(&emitter).await.ok();
        Ok(json)
    }

    async fn confirm(
        &self,
        id: String,
        approved: bool,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let sender = header.sender().map(ToString::to_string);
        let owner = lock(&self.card_owners).get(&id).cloned();
        if owner.is_none() || owner != sender {
            log::warn!("a confirmation from a connection that did not get the card was refused");
            return Err(fdo::Error::AccessDenied(
                "only the app that showed this card can answer it".into(),
            ));
        }
        lock(&self.card_owners).remove(&id);
        let pipeline = Arc::clone(&self.pipeline);
        let r = self
            .runtime
            .spawn(async move { pipeline.confirm(&id, approved).await })
            .await
            .map_err(|e| fdo::Error::Failed(format!("confirmation aborted: {e}")))?;
        self.own_cards(&r, sender);
        let json = to_json(&r);
        Self::turn_finished(&emitter, &json).await.ok();
        self.last_response_changed(&emitter).await.ok();
        Ok(json)
    }

    /// A push-to-talk turn through `pilot-voice`; the result includes
    /// `transcript`.
    async fn listen(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let (pipeline, adapters, offline) = (
            Arc::clone(&self.pipeline),
            Arc::clone(&self.adapters),
            self.offline.clone(),
        );
        let r = self
            .runtime
            .spawn(async move { crate::daemon::listen_turn(&pipeline, &adapters, &offline).await })
            .await
            .map_err(|e| fdo::Error::Failed(format!("turn aborted: {e}")))?;
        self.own_cards(&r, header.sender().map(ToString::to_string));
        let json = to_json(&r);
        Self::turn_finished(&emitter, &json).await.ok();
        self.last_response_changed(&emitter).await.ok();
        Ok(json)
    }

    /// A camera turn: `jpeg` is the photo the person just took, already
    /// downscaled by the app; pilotd checks it and strips its metadata.
    async fn look(
        &self,
        question: String,
        jpeg: Vec<u8>,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        if question.chars().count() > 4000 {
            return Err(fdo::Error::InvalidArgs(
                "question longer than 4000 characters".into(),
            ));
        }
        let pipeline = Arc::clone(&self.pipeline);
        let r = self
            .runtime
            .spawn(async move { pipeline.look(&question, &jpeg).await })
            .await
            .map_err(|e| fdo::Error::Failed(format!("turn aborted: {e}")))?;
        self.own_cards(&r, header.sender().map(ToString::to_string));
        let json = to_json(&r);
        Self::turn_finished(&emitter, &json).await.ok();
        self.last_response_changed(&emitter).await.ok();
        Ok(json)
    }

    /// Stops the turn in flight, if any: its `Ask` returns "Stopped.".
    async fn stop(&self, #[zbus(header)] header: zbus::message::Header<'_>) -> fdo::Result<()> {
        self.admit(&header).await?;
        self.pipeline.stop.notify_waiters();
        Ok(())
    }

    /// The home, read on the phone. The app reads it as it opens, which
    /// also starts the models loading.
    async fn now(&self, #[zbus(header)] header: zbus::message::Header<'_>) -> fdo::Result<String> {
        self.admit(&header).await?;
        // Not downloaded: nothing to load, and asking would only start a
        // server that is not there.
        let warm = if self.models.present() {
            self.warm.clone()
        } else {
            Vec::new()
        };
        for url in warm.clone() {
            let http = self.http.clone();
            self.runtime.spawn(async move {
                let wake = http.get(url).timeout(std::time::Duration::from_secs(2));
                wake.send().await.ok();
            });
        }
        // Only a router on the phone: an empty question never leaves it.
        if !warm.is_empty() {
            let (pipeline, models) = (Arc::clone(&self.pipeline), Arc::clone(&self.models));
            self.runtime.spawn(async move {
                models.set_loading(true);
                pipeline.warm().await;
                models.set_loading(false);
                pipeline.warm_routes().await;
            });
        }
        let adapters = Arc::clone(&self.adapters);
        let store = Arc::clone(&self.store);
        let offline = self.offline.is_offline();
        let name = lock(&self.live).name.clone();
        let now = self
            .runtime
            .spawn(async move {
                crate::now::snapshot(&adapters, &store, &crate::localtime::now(), offline, &name)
                    .await
            })
            .await;
        let on_screen = self.pipeline.on_screen().map(|(_, name)| name);
        Ok(now
            .ok()
            .map(|mut n| {
                n.on_screen = on_screen;
                n
            })
            .and_then(|n| serde_json::to_string(&n).ok())
            .unwrap_or_else(|| "{}".into()))
    }

    async fn cancel_clock(
        &self,
        cookie: u32,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<bool> {
        self.admit(&header).await?;
        let adapters = Arc::clone(&self.adapters);
        self.runtime
            .spawn(async move { adapters.clock.cancel(cookie).await })
            .await
            .map_err(|e| fdo::Error::Failed(e.to_string()))?
            .map_err(|e| fdo::Error::Failed(e.to_string()))
    }

    /// A running timer `seconds` longer: a new timer for what was left
    /// plus `seconds`, the old one cancelled.
    async fn extend_timer(
        &self,
        cookie: u32,
        seconds: u32,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let adapters = Arc::clone(&self.adapters);
        let card = self
            .runtime
            .spawn(async move {
                let now = crate::localtime::now().epoch;
                let items = adapters.clock.upcoming().await?;
                let Some(t) = items
                    .iter()
                    .find(|i| i.cookie == cookie && i.kind == "timer")
                else {
                    return Err(crate::adapters::AdapterError::Failed(
                        "that timer has ended".into(),
                    ));
                };
                let left = u32::try_from((t.at - now).max(0)).unwrap_or(0);
                let total = left.saturating_add(seconds);
                let label =
                    Some(t.title.as_str()).filter(|l| !l.is_empty() && !l.ends_with(" timer"));
                let new = adapters.clock.set_timer(total, label).await?;
                adapters.clock.cancel(cookie).await?;
                Ok(crate::pipeline::Card::Timer {
                    text: format!(
                        "Timer: {} left.",
                        crate::system_tools::describe_duration(total)
                    ),
                    cookie: new,
                    seconds: t.seconds.unwrap_or(total).saturating_add(seconds),
                    ends_at: now + i64::from(total),
                    label: label.map(str::to_owned),
                })
            })
            .await
            .map_err(|e| fdo::Error::Failed(e.to_string()))?
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        Ok(serde_json::to_string(&card).unwrap_or_default())
    }

    /// Triaged events for the Events view, newest first.
    async fn triage(
        &self,
        limit: u32,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let rows = self
            .store
            .triage(limit)
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        Ok(serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into()))
    }

    /// Lipstick calls this when Pilot's Events view entry is tapped.
    async fn open_events(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.admit(&header).await?;
        let events = Arc::clone(&self.events);
        self.runtime
            .spawn(async move { events.opened().await })
            .await
            .ok();
        *lock(&self.launch_request) = Some(("events".into(), std::time::Instant::now()));
        self.events_requested
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        self.events_requested_changed(&emitter).await.ok();
        spawn(&self.open_events, "opening the events page");
        Ok(())
    }

    /// The system-wide bottom-edge gesture (shoal/pilot/lipstick/patch)
    /// calls this from Lipstick: Pilot comes up over the app on screen
    /// (the app's overlay), started for it when it does not run.
    async fn show_sheet(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.admit(&header).await?;
        self.request_sheet(&emitter, false).await;
        Ok(())
    }

    /// Lipstick's gesture, with the process id of the window on top
    /// (0: none): Pilot comes up, and that app's screen is the context of
    /// the next questions. Returns the app's name, empty when it is not
    /// a Keel app.
    async fn show_sheet_for(
        &self,
        pid: u32,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        #[zbus(connection)] session: &zbus::Connection,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let name = self.capture_for(pid, session).await;
        self.request_sheet(&emitter, false).await;
        Ok(name)
    }

    /// As `ShowSheetFor`, with Pilot listening when it comes up: the
    /// shell's assistant key, held.
    async fn listen_for(
        &self,
        pid: u32,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        #[zbus(connection)] session: &zbus::Connection,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let name = self.capture_for(pid, session).await;
        self.request_sheet(&emitter, true).await;
        Ok(name)
    }

    #[zbus(property)]
    fn listen_requested(&self) -> u32 {
        self.listen_requested
            .load(std::sync::atomic::Ordering::SeqCst)
    }

    /// For the app at start: "sheet", "listen" or "events" when
    /// `ShowSheet`, `ListenFor` or `OpenEvents` started it in the last ten
    /// seconds, else empty. Taken once.
    async fn take_launch_request(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        Ok(lock(&self.launch_request)
            .take()
            .filter(|(_, at)| at.elapsed() < std::time::Duration::from_secs(10))
            .map_or_default(|(what, _)| what))
    }

    /// Stops using the app Pilot was opened over as context.
    async fn clear_on_screen(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<()> {
        self.admit(&header).await?;
        self.pipeline.clear_on_screen();
        Ok(())
    }

    /// Opens a web address from a card (a source chip) in Pacific, or the
    /// phone's browser without it. The app is sandboxed: its own attempt
    /// (`Qt.openUrlExternally`) did nothing when a chip was tapped. Only
    /// http and https; true when handed on.
    async fn open_url(
        &self,
        url: String,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(connection)] session: &zbus::Connection,
    ) -> fdo::Result<bool> {
        self.admit(&header).await?;
        let Some(url) = crate::onscreen::web_url(&url) else {
            return Ok(false);
        };
        Ok(crate::onscreen::open_url(session, &url).await)
    }

    /// Starts a new conversation (the app's "Clear conversation").
    async fn clear_conversation(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<()> {
        self.admit(&header).await?;
        self.pipeline.clear_history();
        Ok(())
    }

    /// For the Pilot widget in Lipstick's Events view.
    async fn events_summary(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        Ok(match self.events.current() {
            Some((summary, titles)) => {
                serde_json::json!({"summary": summary, "titles": titles}).to_string()
            }
            None => "{}".into(),
        })
    }

    #[zbus(property)]
    fn sheet_requested(&self) -> u32 {
        self.sheet_requested
            .load(std::sync::atomic::Ordering::SeqCst)
    }

    #[zbus(property)]
    fn events_requested(&self) -> u32 {
        self.events_requested
            .load(std::sync::atomic::Ordering::SeqCst)
    }

    async fn settings(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let s = lock(&self.live).clone();
        Ok(serde_json::json!({
            "consent": s.consent,
            "capabilities": Consent::NAMES,
            "backend": s.backend,
            "backends": self.backends,
            "onboarded": s.onboarded,
            "name": s.name,
            "guide": s.guide,
            // Marathon's shell has the gesture built in.
            "gesture": self.on_marathon() || gesture_installed(),
            "offline": self.offline.is_offline(),
        })
        .to_string())
    }

    async fn set_consent(
        &self,
        name: String,
        on: bool,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<()> {
        self.admit(&header).await?;
        let mut known = true;
        self.save(|s| {
            known = s.consent.set(&name, on);
            s.onboarded = true;
        })?;
        // Turned off: what was kept goes now, not in 30 days.
        if name == "history" && !on {
            self.store
                .clear_conversation()
                .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        }
        if name == "triage" {
            let events = Arc::clone(&self.events);
            self.runtime
                .spawn(async move { events.refresh().await })
                .await
                .ok();
        }
        if known {
            Ok(())
        } else {
            Err(fdo::Error::InvalidArgs(format!(
                "unknown capability {name}"
            )))
        }
    }

    /// What Pilot can do in the person's apps (their Keel Actions), for
    /// the app's "What Pilot can do": by app name, each action with its
    /// title, what it does, and whether Pilot asks before it runs.
    async fn capabilities(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let registry = self.pipeline.registry();
        let mut apps: std::collections::BTreeMap<String, (String, Vec<serde_json::Value>)> =
            std::collections::BTreeMap::new();
        for e in registry.entries().filter(|e| e.available) {
            let Some((app, _)) = e.spec.name.split_once('/') else {
                continue;
            };
            if app == "keel" {
                continue;
            }
            let name = crate::onscreen::app_name(app).unwrap_or_else(|| app.to_owned());
            apps.entry(name)
                .or_insert_with(|| (app.to_owned(), Vec::new()))
                .1
                .push(serde_json::json!({
                    "title": e.spec.title,
                    "description": e.spec.description,
                    "asks": e.spec.needs_confirmation(&serde_json::json!({})),
                }));
        }
        let list: Vec<serde_json::Value> = apps
            .into_iter()
            .map(|(name, (app, actions))| serde_json::json!({"app": app, "name": name, "actions": actions}))
            .collect();
        Ok(serde_json::Value::Array(list).to_string())
    }

    /// What Pilot remembers, oldest first (JSON).
    async fn memories(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let m = self
            .store
            .memories()
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        Ok(serde_json::to_string(&m).unwrap_or_else(|_| "[]".into()))
    }

    async fn forget(
        &self,
        id: i64,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<bool> {
        self.admit(&header).await?;
        self.store
            .forget(id)
            .map_err(|e| fdo::Error::Failed(e.to_string()))
    }

    /// What Pilot calls the person; empty for no name.
    async fn set_name(
        &self,
        name: String,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<()> {
        self.admit(&header).await?;
        let name: String = name.trim().chars().take(40).collect();
        self.save(|s| s.name = name)
    }

    /// The person's locale as the app has it (`de_DE`, from Settings >
    /// Language): the language Pilot answers in, the weather's units and
    /// the language of dates and place names. `pilotd`'s own environment
    /// until the app says.
    async fn set_locale(
        &self,
        name: String,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<()> {
        self.admit(&header).await?;
        if crate::lang::set(&name) {
            Ok(())
        } else {
            Err(fdo::Error::InvalidArgs(format!("not a locale: {name:?}")))
        }
    }

    /// Marks a step of the app's getting-started guide done (or, with
    /// `done` false, not done); "hidden" puts the guide away.
    async fn set_guide(
        &self,
        step: String,
        done: bool,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<()> {
        self.admit(&header).await?;
        let step: String = step.trim().chars().take(24).collect();
        self.save(|s| {
            s.guide.retain(|g| *g != step);
            if done && !step.is_empty() {
                s.guide.push(step);
            }
        })
    }

    async fn set_backend(
        &self,
        name: String,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<()> {
        self.admit(&header).await?;
        let b = (self.factory)(&name)
            .ok_or_else(|| fdo::Error::InvalidArgs(format!("no backend {name}")))?;
        self.pipeline.set_backends(b);
        self.save(|s| s.backend = name)
    }

    async fn egress_log(
        &self,
        limit: u32,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let rows = self
            .store
            .egress(limit)
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        Ok(serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into()))
    }

    async fn export(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let v = self
            .store
            .export()
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        Ok(v.to_string())
    }

    async fn wipe(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.admit(&header).await?;
        self.store
            .wipe()
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        self.pipeline.drop_pending();
        self.pipeline.clear_last();
        self.pipeline.clear_history();
        let events = Arc::clone(&self.events);
        self.runtime
            .spawn(async move { events.refresh().await })
            .await
            .ok();
        self.last_response_changed(&emitter).await.ok();
        Ok(())
    }

    async fn voice_models(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<u64> {
        self.admit(&header).await?;
        Ok(crate::voice_models::dir().map_or(0, |d| crate::voice_models::bytes(&d)))
    }

    async fn remove_voice_models(
        &self,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<u64> {
        self.admit(&header).await?;
        let Some(dir) = crate::voice_models::dir() else {
            return Ok(0);
        };
        crate::voice_models::remove(&dir).map_err(|e| fdo::Error::Failed(e.to_string()))
    }

    /// The models on the phone, JSON (`models::Status`): `state` none,
    /// absent, downloading, loading, ready or failed, `bytes` of `total`,
    /// and `error` (offline, metered, no-space, download) when a download
    /// did not start or finish. Signalled as it changes, every second while
    /// downloading.
    #[zbus(property)]
    fn model_state(&self) -> String {
        serde_json::to_string(&self.models.status()).unwrap_or_else(|_| "{}".into())
    }

    /// Downloads the models on the phone, which a question never does: on
    /// a network that is not metered unless `allow_metered`, and with room
    /// for them. The state after (`ModelState`); `error` says why it did
    /// not start.
    async fn download_models(
        &self,
        allow_metered: bool,
        #[zbus(header)] header: zbus::message::Header<'_>,
    ) -> fdo::Result<String> {
        self.admit(&header).await?;
        let models = Arc::clone(&self.models);
        let status = self
            .runtime
            .spawn(async move { models.download(allow_metered).await })
            .await
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        Ok(serde_json::to_string(&status).unwrap_or_else(|_| "{}".into()))
    }

    /// Speech recognition (pilot-voice) is installed: without it the UI
    /// hides the microphone, and `Listen` fails at once with
    /// voice-unavailable.
    #[zbus(property(emits_changed_signal = "false"))]
    async fn voice_available(&self) -> bool {
        self.adapters.voice.available().await
    }

    #[zbus(property)]
    fn offline(&self) -> bool {
        self.offline.is_offline()
    }

    #[zbus(property)]
    async fn last_response(
        &self,
        #[zbus(header)] header: Option<zbus::message::Header<'_>>,
    ) -> fdo::Result<String> {
        // None: the value PropertiesChanged carries.
        if let Some(header) = header {
            self.admit(&header).await?;
        }
        Ok(self.pipeline.last().map_or_default(|r| r.headline()))
    }

    #[zbus(signal)]
    pub async fn turn_finished(emitter: &SignalEmitter<'_>, result: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    pub async fn turn_progress(emitter: &SignalEmitter<'_>, stage: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    pub async fn triage_added(emitter: &SignalEmitter<'_>, item: &str) -> zbus::Result<()>;
}
