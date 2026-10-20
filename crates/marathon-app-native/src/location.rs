//! `Location`: the shell's Location1, the position `GeoClue` gives it.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use futures_lite::StreamExt;

use crate::shell::{answers, get, Service, State};
use marathon_rt::{io, log};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY)]
        #[qproperty(bool, active, READ, NOTIFY)]
        #[qproperty(f64, latitude, READ, NOTIFY = location_changed)]
        #[qproperty(f64, longitude, READ, NOTIFY = location_changed)]
        #[qproperty(f64, accuracy, READ, NOTIFY = location_changed)]
        #[qproperty(f64, altitude, READ, NOTIFY = location_changed)]
        #[qproperty(f64, speed, READ, NOTIFY = location_changed)]
        #[qproperty(f64, heading, READ, NOTIFY = location_changed)]
        #[qproperty(i64, timestamp, READ, NOTIFY = location_changed)]
        type Location = super::LocationRust;

        #[qsignal]
        #[cxx_name = "locationChanged"]
        fn location_changed(self: Pin<&mut Self>);

        #[qinvokable]
        fn start(self: &Location);
        #[qinvokable]
        fn stop(self: &Location);
    }

    impl cxx_qt::Threading for Location {}
    impl cxx_qt::Initialize for Location {}
}

use qobject::Location;

const LOCATION: Service = Service::shell("Location");

#[derive(Default)]
pub struct LocationRust {
    available: bool,
    active: bool,
    latitude: f64,
    longitude: f64,
    accuracy: f64,
    altitude: f64,
    speed: f64,
    heading: f64,
    timestamp: i64,
}

type Qt = cxx_qt::CxxQtThread<Location>;

impl cxx_qt::Initialize for Location {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            enum Event {
                Fix(State),
                Active(bool),
                Granted,
            }
            let (Ok(fixes), Ok(active), Ok(grants)) = (
                LOCATION.signals::<State>("LocationChanged").await,
                LOCATION.signals::<bool>("activeChanged").await,
                answers("PermissionGranted", "location").await,
            ) else {
                return log::warn("Location", "no session bus");
            };
            refresh(&qt).await;
            let events = fixes.map(Event::Fix).or(active.map(Event::Active)).or(grants.map(|()| Event::Granted));
            let mut events = std::pin::pin!(events);
            while let Some(event) = events.next().await {
                match event {
                    Event::Fix(fix) => show(&qt, fix),
                    Event::Granted => refresh(&qt).await,
                    Event::Active(active) => {
                        qt.queue(move |mut obj| set!(obj, active, active_changed, active)).ok();
                    }
                }
            }
        });
    }
}

impl Location {
    crate::shell::calls! { LOCATION;
        stop() => "Stop";
    }
    fn start(&self) {
        let qt = self.qt_thread();
        // A fresh fix shows at once, not at GeoClue's next heartbeat.
        io::spawn(async move {
            if let Err(e) = LOCATION.ask::<_, ()>("Start", &()).await {
                log::warn("Location", format_args!("Start: {e}"));
            }
            refresh(&qt).await;
        });
    }

}

async fn refresh(qt: &Qt) {
    let available = LOCATION.ask::<_, bool>("IsAvailable", &()).await.unwrap_or(false);
    let active = LOCATION.ask::<_, bool>("IsActive", &()).await.unwrap_or(false);
    qt.queue(move |mut obj| {
        set!(obj, available, available_changed, available);
        set!(obj, active, active_changed, active);
    })
    .ok();
    if let Ok(fix) = LOCATION.ask::<_, State>("GetLocation", &()).await {
        show(qt, fix);
    }
}

fn show(qt: &Qt, fix: State) {
    if fix.is_empty() {
        return;
    }
    qt.queue(move |mut obj| {
        let mut l = obj.as_mut().rust_mut();
        l.latitude = get(&fix, "latitude");
        l.longitude = get(&fix, "longitude");
        l.accuracy = get(&fix, "accuracy");
        l.altitude = get(&fix, "altitude");
        l.speed = get(&fix, "speed");
        l.heading = get(&fix, "heading");
        l.timestamp = get(&fix, "timestamp");
        obj.location_changed();
    })
    .ok();
}
