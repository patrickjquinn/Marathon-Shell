//! `Ambience`: the shell's Keel ambience (`Ambience1`), which the Keel host
//! hands its app.

use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant};
use futures_lite::{future, StreamExt};
use zbus::zvariant::OwnedValue;

use crate::shell::{relay, Service};
use crate::variant;
use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QMap_QString_QVariant, ambience, READ, NOTIFY = ambience_changed)]
        type Ambience = super::AmbienceRust;

        #[qsignal]
        #[cxx_name = "ambienceChanged"]
        fn ambience_changed(self: Pin<&mut Self>);

        /// Waits up to a second for the shell, for the moment before Keel
        /// starts: a pool spare's GUI thread is too busy then to answer
        /// Keel's own read in time.
        #[cxx_name = "fetchNow"]
        fn fetch_now(self: Pin<&mut Ambience>) -> bool;
    }

    impl cxx_qt::Threading for Ambience {}
    impl cxx_qt::Initialize for Ambience {}
}

use qobject::Ambience;

const AMBIENCE: Service = Service::session("Ambience");
const SHELL: &str = "org.marathonos.Shell.Session";

type State = HashMap<String, OwnedValue>;

#[derive(Default)]
pub struct AmbienceRust {
    ambience: QMap<QMapPair_QString_QVariant>,
}

fn show(mut obj: Pin<&mut Ambience>, state: &State) {
    let ambience = variant::qmap(state);
    if obj.ambience != ambience {
        obj.as_mut().rust_mut().ambience = ambience;
        obj.ambience_changed();
    }
}

impl cxx_qt::Initialize for Ambience {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), AMBIENCE, "AmbienceChanged", |obj, (state,): (State,)| show(obj, &state));
        // A spare can start before the shell publishes, so read again
        // whenever the shell (re)appears.
        io::spawn(async move {
            let read = || async {
                if let Ok(state) = AMBIENCE.ask::<_, State>("GetAmbience", &()).await {
                    qt.queue(move |obj| show(obj, &state)).ok();
                }
            };
            let Ok(bus) = io::session_bus().await else { return };
            let Ok(dbus) = zbus::fdo::DBusProxy::new(&bus).await else { return };
            let Ok(mut owners) = dbus.receive_name_owner_changed_with_args(&[(0, SHELL)]).await else { return };
            read().await;
            while let Some(change) = owners.next().await {
                if change.args().is_ok_and(|a| a.new_owner().is_some()) {
                    read().await;
                }
            }
        });
    }
}

impl Ambience {
    fn fetch_now(self: Pin<&mut Self>) -> bool {
        let read = async { AMBIENCE.ask::<_, State>("GetAmbience", &()).await.ok() };
        let timeout = async {
            async_io::Timer::after(Duration::from_secs(1)).await;
            None
        };
        match async_io::block_on(future::or(read, timeout)) {
            Some(state) => {
                show(self, &state);
                true
            }
            None => false,
        }
    }
}
