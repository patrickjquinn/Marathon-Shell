//! Marathon's FM radio: `org.marathonos.Radio` on the session bus. Powers
//! the receiver while it plays, tunes, seeks and scans, and routes its audio
//! to the phone's output. The wired headset is the antenna.

mod fm;
mod route;

use std::collections::HashMap;
use std::path::Path;
use std::process::ExitCode;

use futures_lite::future;
use marathon_rt::daemon::Shared;
use marathon_rt::{io, log};
use zbus::object_server::SignalEmitter;
use zbus::{OwnedVariant as OwnedValue, Variant};
use zbus::{fdo, interface};

use fm::Fm;
use route::Route;

const BUS_NAME: &str = "org.marathonos.Radio";
const PATH: &str = "/org/marathonos/Radio";
/// 98.0 MHz, where a first play starts.
const FIRST: u16 = 9800;

struct Tuner {
    fm: Fm,
    route: Route,
}

struct Radio {
    on: Option<Tuner>,
    /// 10 kHz.
    frequency: u16,
    stations: Vec<u16>,
}

fn khz(freq: u16) -> i32 {
    i32::from(freq) * 10
}

fn channel(frequency_khz: i32) -> fdo::Result<u16> {
    u16::try_from(frequency_khz / 10)
        .ok()
        .filter(|f| (fm::LOWEST..=fm::HIGHEST).contains(f))
        .ok_or_else(|| fdo::Error::InvalidArgs(format!("{frequency_khz} kHz is outside the FM band")))
}

fn failed(e: impl std::fmt::Display) -> fdo::Error {
    fdo::Error::Failed(e.to_string())
}

impl Radio {
    fn state(&self) -> HashMap<&'static str, OwnedValue> {
        let mut s = HashMap::new();
        let mut put = |k, v: Variant<'_>| {
            if let Ok(v) = v.try_to_owned() {
                s.insert(k, v);
            }
        };
        put("available", Path::new("/dev/fm").exists().into());
        put("playing", self.on.is_some().into());
        put("frequency", khz(self.frequency).into());
        let stations: Vec<i32> = self.stations.iter().copied().map(khz).collect();
        put("stations", stations.into());
        if let Some(t) = &self.on {
            put("signal", t.fm.rssi().unwrap_or(0).into());
            put("stereo", t.fm.stereo().unwrap_or(false).into());
        }
        s
    }

    fn play(&mut self, freq: u16) -> std::io::Result<()> {
        if let Some(t) = &self.on {
            self.frequency = t.fm.tune(freq)?;
            return Ok(());
        }
        let fm = Fm::open()?;
        self.frequency = fm.power_up(freq)?;
        match Route::start() {
            Ok(route) => {
                self.on = Some(Tuner { fm, route });
                Ok(())
            }
            Err(e) => {
                fm.power_down().ok();
                Err(e)
            }
        }
    }

    fn stop(&mut self) {
        if let Some(Tuner { fm, route }) = self.on.take() {
            drop(route);
            fm.power_down().ok();
        }
    }

    /// Runs `work` on the receiver, powering it up for the call if it is off.
    fn with_receiver<R>(&mut self, work: impl FnOnce(&Fm) -> std::io::Result<R>) -> std::io::Result<R> {
        if let Some(t) = &self.on {
            return work(&t.fm);
        }
        let fm = Fm::open()?;
        fm.power_up(self.frequency)?;
        let r = work(&fm);
        fm.power_down().ok();
        r
    }
}

struct Service(Shared<Radio>);

impl Service {
    async fn changed(&self, emitter: &SignalEmitter<'_>) {
        let state = self.0.with(|r| r.state()).await;
        Self::state_changed(emitter, state).await.ok();
    }

    async fn run(
        &self,
        emitter: &SignalEmitter<'_>,
        work: impl FnOnce(&mut Radio) -> std::io::Result<()> + Send + 'static,
    ) -> fdo::Result<()> {
        let r = self.0.with(work).await;
        self.changed(emitter).await;
        r.map_err(failed)
    }
}

#[interface(name = "org.marathonos.Radio1")]
impl Service {
    async fn get_state(&self) -> HashMap<&'static str, OwnedValue> {
        self.0.with(|r| r.state()).await
    }

    /// Plays `frequency` (kHz), or the last station when 0.
    async fn play(
        &self,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        frequency: i32,
    ) -> fdo::Result<()> {
        let freq = if frequency == 0 { None } else { Some(channel(frequency)?) };
        self.run(&emitter, move |r| r.play(freq.unwrap_or(r.frequency))).await
    }

    async fn stop(&self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) -> fdo::Result<()> {
        self.run(&emitter, |r| {
            r.stop();
            Ok(())
        })
        .await
    }

    /// The next station up or down; tunes to it.
    async fn seek(
        &self,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        up: bool,
    ) -> fdo::Result<()> {
        self.run(&emitter, move |r| {
            let from = r.frequency;
            r.frequency = r.with_receiver(|fm| fm.seek(from, up))?;
            Ok(())
        })
        .await
    }

    /// The band's stations, kept for the list.
    async fn scan(&self, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) -> fdo::Result<()> {
        self.run(&emitter, |r| {
            let found = r.with_receiver(Fm::scan)?;
            r.stations = found;
            if let Some(t) = &r.on {
                r.frequency = t.fm.tune(r.frequency)?;
            }
            Ok(())
        })
        .await
    }

    #[zbus(signal)]
    async fn state_changed(
        emitter: &SignalEmitter<'_>,
        state: HashMap<&'static str, OwnedValue>,
    ) -> zbus::Result<()>;
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let radio = Radio {
        on: None,
        frequency: FIRST,
        stations: Vec::new(),
    };
    let bus = io::session_bus().await?;
    bus.object_server().at(PATH, Service(Shared::new(radio))).await?;
    bus.request_name(BUS_NAME).await?;
    future::pending().await
}

fn main() -> ExitCode {
    match async_io::block_on(run()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            log::warn("marathon-radiod", e);
            ExitCode::FAILURE
        }
    }
}
