// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Wiring: configuration, store, adapters, backends and the pipeline, then
//! the D-Bus service and the privacy-switch watcher.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::adapters::{self, Adapters, Missing};
use crate::config::{Config, JevConfig};
use crate::dbus::{BackendFactory, PilotService, BUS_NAME, PATH};
use crate::jev::{HttpJev, JevClient, ScoreJev};
use crate::llm::{LlmClient, OpenAiClient};
use crate::localtime::{self, LocalNow};
use crate::pipeline::{Backends, Pipeline, PipelineParts, TurnResult};
use crate::privacy::{self, Offline, OfflineControl, PrivacySwitch};
use crate::redact::Redactor;
use crate::relay_auth::{LicenceSource, ReefHandoff, RelayAuth};
use crate::remote::{Credential, Remote};
use crate::settings::{Settings, SettingsFile};
use crate::store::{EgressSink, Store, StoreError};
use crate::system_tools::{self, SystemTools};
use crate::tools::Registry;
use crate::triage::{Incoming, Triage};

#[derive(Debug, thiserror::Error)]
pub enum StartError {
    #[error("{0}")]
    Store(#[from] StoreError),
    #[error("HTTP client: {0}")]
    Http(#[from] reqwest::Error),
    #[error("session bus: {0}")]
    Bus(#[from] zbus::Error),
    #[error("backend {0} is not configured")]
    Backend(String),
}

/// Inputs to [`build`].
pub struct Options {
    pub config: Config,
    /// `None`: in-memory store and settings (`--ask`, tests).
    pub data_dir: Option<PathBuf>,
    pub session: Option<zbus::Connection>,
    pub system: Option<zbus::Connection>,
    /// Replaces the Sailfish adapters (tests).
    pub adapters: Option<Adapters>,
    /// Replaces the HTTP credential (tests use none).
    pub credential: Option<Credential>,
    /// Replaces Reef's licence hand-off (tests).
    pub licence: Option<Arc<dyn LicenceSource>>,
    pub now: fn() -> LocalNow,
}

pub struct Daemon {
    pub pipeline: Arc<Pipeline>,
    pub store: Arc<Store>,
    pub settings: Arc<Mutex<SettingsFile>>,
    pub live: Arc<Mutex<Settings>>,
    pub offline_ctl: Arc<OfflineControl>,
    pub offline: Offline,
    pub factory: BackendFactory,
    pub backend_names: Vec<String>,
    pub adapters: Arc<Adapters>,
    pub triage: Arc<Triage>,
    pub events: Arc<crate::events::EventsEntry>,
    pub events_requested: Arc<std::sync::atomic::AtomicU32>,
    pub open_events: Vec<String>,
    pub sheet_requested: Arc<std::sync::atomic::AtomicU32>,
    /// What the last `ShowSheet` or `OpenEvents` asked for ("sheet",
    /// "events") and when, for an app just started to take.
    pub launch_request: Arc<std::sync::Mutex<Option<(String, std::time::Instant)>>>,
    pub open_sheet: Vec<String>,
}

fn sailfish_adapters(
    cfg: &Config,
    session: Option<&zbus::Connection>,
    system: Option<&zbus::Connection>,
) -> Adapters {
    if let Some(c) = session.filter(|c| adapters::marathon::present(c)) {
        log::info!("Marathon shell found: using its clock, calendar, contacts, phone and radios");
        return marathon_adapters(cfg, c);
    }
    // While the privileged group is held back the databases are the
    // account's own, never paths from the configuration (privilege.rs).
    let held = crate::privilege::held_back();
    let calendar: Box<dyn adapters::Calendar> = match cfg
        .adapters
        .calendar_db
        .clone()
        .filter(|_| !held)
        .or_else(adapters::calendar::default_path)
    {
        Some(path) => Box::new(adapters::calendar::Mkcal {
            path,
            utc_offset: || localtime::now().utc_offset,
        }),
        None => Box::new(Missing("the calendar")),
    };
    let contacts: Arc<dyn adapters::Contacts> = match cfg
        .adapters
        .contacts_db
        .clone()
        .filter(|_| !held)
        .or_else(adapters::contacts::default_path)
    {
        Some(path) => Arc::new(adapters::contacts::SqliteContacts::new(path)),
        None => Arc::new(Missing("the address book")),
    };
    Adapters {
        clock: match system {
            Some(c) => Box::new(adapters::clock::TimedClock { system: c.clone() }),
            None => Box::new(Missing("the clock service")),
        },
        media: match session {
            Some(c) => Box::new(adapters::media::Mpris { session: c.clone() }),
            None => Box::new(Missing("media control")),
        },
        calendar,
        contacts,
        telephony: match system {
            Some(c) => Box::new(adapters::telephony::Ofono { system: c.clone() }),
            None => Box::new(Missing("telephony")),
        },
        toggles: match system {
            Some(c) => Box::new(adapters::connman::ConnMan { system: c.clone() }),
            None => Box::new(Missing("device settings")),
        },
        voice: match session {
            Some(c) => Box::new(adapters::voice::SystemdVoice {
                session: c.clone(),
                unit: cfg.adapters.voice_unit.clone(),
            }),
            None => Box::new(Missing("voice")),
        },
        speech: match adapters::voice::TtsSocket::default_path() {
            Some(path) => Box::new(adapters::voice::TtsSocket::new(path)),
            None => Box::new(Missing("speech")),
        },
        notifier: match session {
            Some(c) => Box::new(adapters::FdoNotifier { session: c.clone() }),
            None => Box::new(Missing("notifications")),
        },
        stock: match session {
            Some(c) => Box::new(adapters::stock::JollaApps { session: c.clone() }),
            None => Box::new(Missing("the phone's apps")),
        },
    }
}

/// Marathon OS: the shell's services (`adapters::marathon`); media,
/// notifications and speech as on Sailfish.
fn marathon_adapters(cfg: &Config, session: &zbus::Connection) -> Adapters {
    use adapters::marathon::{
        ShellCalendar, ShellClock, ShellContacts, ShellTelephony, ShellToggles,
    };
    Adapters {
        clock: Box::new(ShellClock::new(session.clone())),
        media: Box::new(adapters::media::Mpris {
            session: session.clone(),
        }),
        calendar: Box::new(ShellCalendar {
            session: session.clone(),
        }),
        contacts: Arc::new(ShellContacts::new(session.clone())),
        telephony: Box::new(ShellTelephony {
            session: session.clone(),
        }),
        toggles: Box::new(ShellToggles {
            session: session.clone(),
        }),
        voice: Box::new(adapters::voice::SystemdVoice {
            session: session.clone(),
            unit: cfg.adapters.voice_unit.clone(),
        }),
        speech: match adapters::voice::TtsSocket::default_path() {
            Some(path) => Box::new(adapters::voice::TtsSocket::new(path)),
            None => Box::new(Missing("speech")),
        },
        notifier: Box::new(adapters::FdoNotifier {
            session: session.clone(),
        }),
        stock: Box::new(Missing("the phone's apps")),
    }
}

/// Builds the named backend pair from configuration.
pub fn make_backends(cfg: &Config, name: &str, remote: &Remote) -> Option<Backends> {
    let b = cfg.backends.get(name)?;
    let jev: Arc<dyn JevClient> = match &b.jev {
        JevConfig::Jev {
            url,
            model,
            provider,
        } => Arc::new(HttpJev {
            remote: remote.clone(),
            url: url.clone(),
            model: model.clone(),
            provider: provider.clone(),
        }),
        JevConfig::Score {
            url,
            model,
            provider,
            labels,
            yes,
            no,
        } => Arc::new(ScoreJev {
            remote: remote.clone(),
            url: url.clone(),
            model: model.clone(),
            provider: provider.clone(),
            labels: labels.clone(),
            yes: yes.clone(),
            no: no.clone(),
        }),
    };
    let llm: Arc<dyn LlmClient> = Arc::new(OpenAiClient {
        remote: remote.clone(),
        url: b.llm.url.clone(),
        model: b.llm.model.clone(),
        provider: b.llm.provider.clone(),
        region_header: b.llm.region_header.to_ascii_lowercase(),
        allowed_regions: b.llm.allowed_regions.clone(),
        effort: (&b.llm.effort).into(),
        max_completion_tokens: b.llm.max_completion_tokens,
    });
    Some(Backends {
        name: name.to_owned(),
        jev,
        llm,
    })
}

/// Triage (spec section 5.3) and its Events view entry.
fn proactive(
    pipeline: &Arc<Pipeline>,
    store: &Arc<Store>,
    live: &Arc<Mutex<Settings>>,
    offline: &Offline,
    adapters: &Arc<Adapters>,
    cfg: &Config,
    now: fn() -> LocalNow,
) -> (Arc<Triage>, Arc<crate::events::EventsEntry>) {
    let triage = Arc::new(Triage::new(
        pipeline.clone(),
        store.clone(),
        live.clone(),
        offline.clone(),
        adapters.clone(),
        cfg.triage.clone(),
        now,
    ));
    let events = Arc::new(crate::events::EventsEntry::new(
        cfg.events.notification,
        store.clone(),
        adapters.clone(),
        live.clone(),
        offline.clone(),
    ));
    (triage, events)
}

pub fn build(opts: Options) -> Result<Daemon, StartError> {
    let Options {
        config,
        data_dir,
        session,
        system,
        adapters: injected,
        credential,
        licence,
        now,
    } = opts;
    let store = Arc::new(match &data_dir {
        Some(d) => Store::open(&d.join("pilot.db"))?,
        None => Store::memory()?,
    });
    let settings_file = SettingsFile::load(data_dir.as_ref().map(|d| d.join("settings.json")));
    let live = Arc::new(Mutex::new(settings_file.current.clone()));
    let (ctl, offline) = privacy::offline_state(false);
    let egress: Arc<dyn EgressSink> = store.clone();
    let http = crate::remote::http_client()?;
    let credential = credential.unwrap_or_else(|| {
        let token_file = config
            .token_file
            .clone()
            .or_else(|| data_dir.as_ref().map(|d| d.join("device-token")))
            .unwrap_or_else(|| PathBuf::from("/nonexistent/device-token"));
        if config.token_exchange_url.is_empty() {
            return Credential::TokenFile(token_file);
        }
        let device_file = token_file.with_file_name("device-id");
        Credential::Relay(Arc::new(RelayAuth::new(
            token_file,
            device_file,
            config.token_exchange_url.clone(),
            licence.unwrap_or_else(|| Arc::new(ReefHandoff)),
            http.clone(),
            egress.clone(),
            offline.clone(),
            Duration::from_secs(config.timeout_secs),
        )))
    });
    let remote = Remote::new(
        http,
        credential,
        egress,
        offline.clone(),
        Duration::from_secs(config.timeout_secs),
    );
    let adapters = Arc::new(
        injected.unwrap_or_else(|| sailfish_adapters(&config, session.as_ref(), system.as_ref())),
    );
    let tools = Arc::new(SystemTools {
        adapters: adapters.clone(),
        now,
        local_at: localtime::at,
    });
    let mut registry = Registry::new();
    system_tools::register(&mut registry, &tools);
    crate::web::register(&mut registry, remote.clone(), &config.web_search_url);
    crate::weather::register(&mut registry, remote.clone(), Some(store.clone()));
    crate::memory::register(&mut registry, store.clone());

    let chosen = settings_file.current.backend.clone();
    let cfg = Arc::new(config);
    let factory: BackendFactory = {
        let cfg = cfg.clone();
        let remote = remote.clone();
        Arc::new(move |name: &str| make_backends(&cfg, name, &remote))
    };
    let backends = factory(&chosen)
        .or_else(|| factory("standard"))
        .ok_or_else(|| StartError::Backend(chosen.clone()))?;
    let pipeline = Arc::new(Pipeline::new(PipelineParts {
        redactor: Redactor::new(Box::new(adapters::NamesFrom(adapters.contacts.clone()))),
        backends,
        registry,
        store: store.clone(),
        thresholds: cfg.thresholds,
        settings: live.clone(),
        offline: offline.clone(),
        max_rounds: cfg.max_tool_rounds.max(1),
        now,
    }));
    let (triage, events) = proactive(&pipeline, &store, &live, &offline, &adapters, &cfg, now);
    Ok(Daemon {
        events,
        events_requested: Arc::default(),
        open_events: cfg.events.open_command.clone(),
        sheet_requested: Arc::default(),
        launch_request: Arc::default(),
        open_sheet: cfg.sheet.open_command.clone(),
        triage,
        pipeline,
        store,
        settings: Arc::new(Mutex::new(settings_file)),
        live,
        offline_ctl: Arc::new(ctl),
        offline,
        factory,
        backend_names: cfg.backends.keys().cloned().collect(),
        adapters,
    })
}

impl Daemon {
    /// The D-Bus object for this daemon. Call from within the Tokio runtime.
    pub fn service(&self) -> PilotService {
        PilotService {
            pipeline: self.pipeline.clone(),
            settings: self.settings.clone(),
            live: self.live.clone(),
            store: self.store.clone(),
            offline: self.offline.clone(),
            backends: self.backend_names.clone(),
            factory: self.factory.clone(),
            adapters: self.adapters.clone(),
            triage: self.triage.clone(),
            events: self.events.clone(),
            events_requested: self.events_requested.clone(),
            open_events: self.open_events.clone(),
            sheet_requested: self.sheet_requested.clone(),
            launch_request: self.launch_request.clone(),
            open_sheet: self.open_sheet.clone(),
            runtime: tokio::runtime::Handle::current(),
            card_owners: Arc::default(),
        }
    }

    /// Applies a privacy-switch state: offline flag, pending requests
    /// dropped, `pilot-voice` stopped, `Offline` property signalled.
    pub async fn apply_privacy(&self, engaged: bool, conn: Option<&zbus::Connection>) {
        if !self.offline_ctl.set(engaged) {
            return;
        }
        if engaged {
            log::info!("privacy switch engaged: offline, voice stopped, pending dropped");
            self.pipeline.drop_pending();
            self.adapters.speech.stop();
            if let Err(e) = self.adapters.voice.stop().await {
                log::warn!("stopping pilot-voice: {e}");
            }
        } else {
            log::info!("privacy switch released: online");
        }
        // The Events view entry goes while offline and comes back after.
        self.events.refresh().await;
        if let Some(conn) = conn {
            if let Ok(iface) = conn
                .object_server()
                .interface::<_, PilotService>(PATH)
                .await
            {
                let _ = iface
                    .get()
                    .await
                    .offline_changed(iface.signal_emitter())
                    .await;
            }
        }
    }

    /// Reads the switch once, then follows it. Unknown state is treated as
    /// engaged (fail closed).
    pub async fn follow_switch(
        self: Arc<Self>,
        switch: Arc<dyn PrivacySwitch>,
        conn: Option<zbus::Connection>,
    ) {
        let initial = switch.current().await.unwrap_or_else(|e| {
            log::warn!("privacy switch state unknown ({e}); staying offline");
            true
        });
        self.apply_privacy(initial, conn.as_ref()).await;
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        let watcher = {
            let switch = switch.clone();
            tokio::spawn(async move {
                switch
                    .watch(Box::new(move |v| {
                        let _ = tx.send(v);
                    }))
                    .await;
            })
        };
        while let Some(v) = rx.recv().await {
            self.apply_privacy(v, conn.as_ref()).await;
        }
        watcher.abort();
    }
}

impl Daemon {
    /// Runs a spoken turn whenever `pilot-voice`'s wake-word hook fires.
    pub async fn follow_wake(self: Arc<Self>, conn: zbus::Connection) {
        use futures_util::StreamExt as _;
        let Ok(p) = zbus::Proxy::new(
            &conn,
            adapters::voice::VOICE_BUS_NAME,
            adapters::voice::VOICE_PATH,
            adapters::voice::VOICE_INTERFACE,
        )
        .await
        else {
            return;
        };
        let Ok(mut wakes) = p.receive_signal("WakeWord").await else {
            return;
        };
        while wakes.next().await.is_some() {
            let r = listen_turn(&self.pipeline, &self.adapters, &self.offline).await;
            if let Ok(iface) = conn
                .object_server()
                .interface::<_, PilotService>(PATH)
                .await
            {
                let json = serde_json::to_string(&r).unwrap_or_default();
                let _ = PilotService::turn_finished(iface.signal_emitter(), &json).await;
                let _ = iface
                    .get()
                    .await
                    .last_response_changed(iface.signal_emitter())
                    .await;
            }
        }
    }
}

impl Daemon {
    /// Triages each incoming event (spec section 5.3) and announces the
    /// result with `TriageAdded` on `conn`.
    pub async fn run_triage(
        self: Arc<Self>,
        mut rx: tokio::sync::mpsc::Receiver<Incoming>,
        conn: Option<zbus::Connection>,
    ) {
        while let Some(ev) = rx.recv().await {
            let Ok(item) = self.triage.handle(&ev).await else {
                continue;
            };
            self.events.refresh().await;
            let Some(conn) = &conn else { continue };
            if let Ok(iface) = conn
                .object_server()
                .interface::<_, PilotService>(PATH)
                .await
            {
                let json = serde_json::to_string(&item).unwrap_or_default();
                let _ = PilotService::triage_added(iface.signal_emitter(), &json).await;
            }
        }
    }

    /// Starts the feeders: the notification monitor (on `monitor`, a
    /// connection of its own) and the calendar poll.
    pub fn start_triage(
        self: &Arc<Self>,
        monitor: Option<zbus::Connection>,
        conn: Option<zbus::Connection>,
    ) {
        let (tx, rx) = tokio::sync::mpsc::channel(64);
        if let Some(m) = monitor {
            let tx = tx.clone();
            tokio::spawn(async move {
                if let Err(e) = crate::triage::watch_notifications(m, tx).await {
                    log::warn!("notification triage unavailable: {e}");
                }
            });
        }
        tokio::spawn(crate::triage::watch_calendar(
            self.adapters.clone(),
            self.triage.clone(),
            tx,
        ));
        tokio::spawn(self.clone().run_triage(rx, conn));
    }
}

/// Registers the service on `conn` (already owning or about to own
/// [`BUS_NAME`]).
pub async fn serve_on(d: &Daemon, conn: &zbus::Connection) -> zbus::Result<()> {
    conn.object_server().at(PATH, d.service()).await?;
    conn.request_name(BUS_NAME).await?;
    // A turn's stages, as TurnProgress signals.
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();
    d.pipeline.set_progress(tx);
    let conn = conn.clone();
    tokio::spawn(async move {
        while let Some(stage) = rx.recv().await {
            if let Ok(iface) = conn
                .object_server()
                .interface::<_, PilotService>(PATH)
                .await
            {
                let _ = PilotService::turn_progress(iface.signal_emitter(), &stage).await;
            }
        }
    });
    Ok(())
}

/// A push-to-talk turn: `pilot-voice` hears it, the pipeline handles the
/// transcript as a spoken turn, and `pilot-tts` speaks the headline.
pub async fn listen_turn(
    pipeline: &Pipeline,
    adapters: &Adapters,
    offline: &Offline,
) -> TurnResult {
    use crate::pipeline::Card;
    if offline.is_offline() {
        return pipeline.record(TurnResult::single(
            pipeline.turn_id(),
            "offline",
            Card::Offline {
                text: "The microphone is closed while the privacy switch is on.".into(),
            },
            true,
        ));
    }
    // Pressing the microphone while Pilot speaks interrupts it, as it
    // would a person: the new question matters more than the old answer.
    adapters.speech.stop();
    let heard = adapters
        .voice
        .listen_reporting(&|stage, level| pipeline.progress(stage, level))
        .await;
    let result = match heard {
        // A processor whisper.cpp was not built for (pilot-voice NO_CPU).
        Err(crate::adapters::AdapterError::Failed(m)) if m.starts_with("NoCpu") => pipeline
            .record(TurnResult::single(
                pipeline.turn_id(),
                "voice-cpu",
                Card::Error {
                    text: "Speaking to Pilot needs a newer phone processor than this one has. Typing works as usual.".into(),
                },
                true,
            )),
        // pilot-voice has no model yet and has started fetching one.
        Err(crate::adapters::AdapterError::Failed(m)) if m.starts_with("NoModel") => {
            pipeline.record(TurnResult::single(
                pipeline.turn_id(),
                "voice-model",
                Card::Clarify {
                    text: "Getting speech recognition ready: a one-time download of about 78 MB. Try the microphone again in a minute.".into(),
                    intent: "open_ended".into(),
                },
                true,
            ))
        }
        Err(e) => pipeline.record(TurnResult::single(
            pipeline.turn_id(),
            "voice-error",
            Card::Error {
                text: format!("Voice: {e}"),
            },
            true,
        )),
        Ok(t) if t.trim().is_empty() => pipeline.record(TurnResult::single(
            pipeline.turn_id(),
            "no-speech",
            Card::Clarify {
                text: "I didn't hear anything.".into(),
                intent: "open_ended".into(),
            },
            true,
        )),
        Ok(t) => pipeline.ask(&t, true).await,
    };
    let say = result.headline();
    if !say.is_empty() && !offline.is_offline() {
        adapters.speech.say(&say);
    }
    result
}
