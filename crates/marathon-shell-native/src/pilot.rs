//! `PilotClient`: Shipwright Pilot's session service, `org.shipwright.Pilot`
//! (pilotd).

use std::pin::Pin;
use std::time::Duration;

use async_channel::Sender;
use async_io::Timer;
use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use futures_lite::{future, StreamExt};
use zbus::fdo::DBusProxy;
use zbus::names::BusName;

use cxx_qt_lib::QString;

use crate::{io, log};

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        /// Pilot can be asked: its service is activatable or on the bus.
        #[qproperty(bool, available, READ, NOTIFY)]
        /// Re-check availability every 30 s while true (unlocked).
        #[qproperty(bool, watching, READ, WRITE = set_watching, NOTIFY)]
        type PilotClient = super::PilotClientRust;

        #[cxx_name = "setWatching"]
        fn set_watching(self: Pin<&mut PilotClient>, watching: bool);
        /// The sheet over the app whose process is `pid` (0: the home
        /// screen); an older pilotd without ShowSheetFor gets ShowSheet.
        #[qinvokable]
        #[cxx_name = "showSheetFor"]
        fn show_sheet_for(self: &PilotClient, pid: u32);
        /// Asks Pilot `question`; `answered` follows.
        #[qinvokable]
        fn ask(self: &PilotClient, question: &QString);
        /// The answer's text, empty when Pilot had none.
        #[qsignal]
        fn answered(self: Pin<&mut PilotClient>, question: QString, text: QString);
    }

    impl cxx_qt::Threading for PilotClient {}
    impl cxx_qt::Initialize for PilotClient {}
}

use qobject::PilotClient;

const NAME: &str = "org.shipwright.Pilot";

#[zbus::proxy(
    interface = "org.shipwright.Pilot1",
    default_service = "org.shipwright.Pilot",
    default_path = "/org/shipwright/Pilot"
)]
trait Pilot {
    fn show_sheet_for(&self, pid: u32) -> zbus::Result<()>;
    fn show_sheet(&self) -> zbus::Result<()>;
    fn ask(&self, question: &str, spoken: bool) -> zbus::Result<String>;
}

#[derive(Default)]
pub struct PilotClientRust {
    available: bool,
    watching: bool,
    actor: Option<Sender<bool>>,
}

impl cxx_qt::Initialize for PilotClient {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, watching) = async_channel::unbounded();
        let qt = self.qt_thread();
        io::spawn(async move {
            let dbus = match async { DBusProxy::new(&io::session_bus().await?).await }.await {
                Ok(dbus) => dbus,
                Err(e) => return log::warn("pilot", e),
            };
            let mut owners = dbus
                .receive_name_owner_changed_with_args(&[(0, NAME)])
                .await
                .ok();
            let mut watch = false;
            loop {
                publish(&qt, available(&dbus).await);
                let poll = async {
                    if watch {
                        Timer::after(Duration::from_secs(30)).await;
                    } else {
                        future::pending::<()>().await;
                    }
                    Some(watch)
                };
                let owner = async {
                    match &mut owners {
                        Some(owners) => owners.next().await.map(|_| watch),
                        None => future::pending().await,
                    }
                };
                match future::or(future::or(poll, owner), async {
                    watching.recv().await.ok()
                })
                .await
                {
                    Some(now) => watch = now,
                    None => return,
                }
            }
        });
        self.as_mut().rust_mut().actor = Some(tx);
    }
}

/// Activatable, or running without a service file (a developer's pilotd).
async fn available(dbus: &DBusProxy<'_>) -> bool {
    if dbus
        .list_activatable_names()
        .await
        .is_ok_and(|names| names.iter().any(|n| n.as_str() == NAME))
    {
        return true;
    }
    match BusName::try_from(NAME) {
        Ok(name) => dbus.name_has_owner(name).await.unwrap_or(false),
        Err(_) => false,
    }
}

fn publish(qt: &CxxQtThread<PilotClient>, available: bool) {
    qt.queue(move |mut obj| set!(obj, available, available_changed, available))
        .ok();
}

impl PilotClient {
    fn set_watching(mut self: Pin<&mut Self>, watching: bool) {
        if watching != self.watching {
            if let Some(actor) = &self.actor {
                actor.try_send(watching).ok();
            }
            set!(self, watching, watching_changed, watching);
        }
    }

    #[allow(clippy::unused_self, reason = "an invokable")]
    fn show_sheet_for(&self, pid: u32) {
        io::spawn(async move {
            let shown = async {
                let pilot = PilotProxy::new(&io::session_bus().await?).await?;
                match pilot.show_sheet_for(pid).await {
                    Err(zbus::Error::MethodError(name, ..))
                        if name.as_str() == "org.freedesktop.DBus.Error.UnknownMethod" =>
                    {
                        pilot.show_sheet().await
                    }
                    shown => shown,
                }
            };
            if let Err(e) = shown.await {
                log::warn("pilot", format_args!("ShowSheetFor: {e}"));
            }
        });
    }

    fn ask(&self, question: &QString) {
        let question = question.to_string();
        let qt = self.qt_thread();
        io::spawn(async move {
            let reply = async {
                let pilot = PilotProxy::new(&io::session_bus().await?).await?;
                pilot.ask(&question, false).await
            };
            let text = match reply.await {
                Ok(json) => answer_text(&json),
                Err(e) => {
                    log::warn("pilot", format_args!("Ask: {e}"));
                    String::new()
                }
            };
            qt.queue(move |obj| {
                obj.answered(QString::from(&question), QString::from(&text));
            })
            .ok();
        });
    }
}

/// The text of the reply's cards (an answer, a set timer's line), one per line.
fn answer_text(json: &str) -> String {
    let reply: serde_json::Value = serde_json::from_str(json).unwrap_or_default();
    reply["cards"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|card| card["text"].as_str().or_else(|| card["title"].as_str()))
        .filter(|text| !text.trim().is_empty())
        .collect::<Vec<_>>()
        .join("\n")
}
