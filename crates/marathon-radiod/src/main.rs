//! Marathon's FM radio: `org.marathonos.Radio` on the session bus. Powers
//! the receiver while it plays, tunes, seeks and scans, and plays its audio
//! through PipeWire. While it plays it is an MPRIS player, so the shell's
//! media controls show it; a phone call stops it. The wired headset is the
//! antenna.

mod fm;
mod route;

use std::collections::HashMap;
use std::path::Path;
use std::process::ExitCode;

use futures_lite::{future, StreamExt};
use marathon_rt::daemon::Shared;
use marathon_rt::{io, log};
use zbus::object_server::SignalEmitter;

use zbus::{fdo, interface, Connection, MatchRule, MessageStream, ObjectPath};
use zbus::{OwnedVariant as OwnedValue, Variant};

use fm::Fm;
use route::Route;

const BUS_NAME: &str = "org.marathonos.Radio";
const PATH: &str = "/org/marathonos/Radio";
const MPRIS_NAME: &str = "org.mpris.MediaPlayer2.radio";
const MPRIS_PATH: &str = "/org/mpris/MediaPlayer2";
const ART: &str = "file:///usr/share/marathon-apps/radio/assets/icon.svg";
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

/// "100.3 FM".
fn title(freq: u16) -> String {
    format!("{}.{} FM", freq / 100, freq % 100 / 10)
}

fn channel(frequency_khz: i32) -> fdo::Result<u16> {
    u16::try_from(frequency_khz / 10)
        .ok()
        .filter(|f| (fm::LOWEST..=fm::HIGHEST).contains(f))
        .ok_or_else(|| {
            fdo::Error::InvalidArgs(format!("{frequency_khz} kHz is outside the FM band"))
        })
}

fn put<K: std::hash::Hash + Eq>(map: &mut HashMap<K, OwnedValue>, key: K, value: Variant<'_>) {
    if let Ok(v) = OwnedValue::try_from(value) {
        map.insert(key, v);
    }
}

impl Radio {
    fn state(&self) -> HashMap<&'static str, OwnedValue> {
        let mut s = HashMap::new();
        put(&mut s, "available", Path::new("/dev/fm").exists().into());
        put(&mut s, "playing", self.on.is_some().into());
        put(&mut s, "frequency", khz(self.frequency).into());
        let stations: Vec<i32> = self.stations.iter().copied().map(khz).collect();
        put(&mut s, "stations", stations.into());
        if let Some(t) = &self.on {
            put(&mut s, "signal", t.fm.rssi().unwrap_or(0).into());
            put(&mut s, "stereo", t.fm.stereo().unwrap_or(false).into());
        }
        s
    }

    fn metadata(&self) -> HashMap<String, OwnedValue> {
        let mut m = HashMap::new();
        if let Ok(id) = ObjectPath::try_from(format!("{PATH}/{}", khz(self.frequency))) {
            put(&mut m, "mpris:trackid".into(), id.into());
        }
        put(&mut m, "xesam:title".into(), title(self.frequency).into());
        put(&mut m, "xesam:artist".into(), vec!["Radio"].into());
        put(&mut m, "mpris:artUrl".into(), ART.into());
        m
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
    fn with_receiver<R>(
        &mut self,
        work: impl FnOnce(&Fm) -> std::io::Result<R>,
    ) -> std::io::Result<R> {
        if let Some(t) = &self.on {
            return work(&t.fm);
        }
        let fm = Fm::open()?;
        fm.power_up(self.frequency)?;
        let r = work(&fm);
        fm.power_down().ok();
        r
    }

    fn seek(&mut self, up: bool) -> std::io::Result<()> {
        let from = self.frequency;
        self.frequency = self.with_receiver(|fm| fm.seek(from, up))?;
        Ok(())
    }
}

#[derive(Clone)]
struct Core {
    radio: Shared<Radio>,
    bus: Connection,
}

impl Core {
    /// Runs `work`, then tells both interfaces' listeners what changed.
    async fn act(
        &self,
        work: impl FnOnce(&mut Radio) -> std::io::Result<()> + Send + 'static,
    ) -> fdo::Result<()> {
        let r = self.radio.with(work).await;
        self.changed().await;
        r.map_err(|e| fdo::Error::Failed(e.to_string()))
    }

    async fn changed(&self) {
        let (state, playing) = self.radio.with(|r| (r.state(), r.on.is_some())).await;
        if let Ok(emitter) = SignalEmitter::new(&self.bus, PATH) {
            Service::state_changed(&emitter, state).await.ok();
        }
        // Only a playing radio is a player: the shell follows the newest.
        if playing {
            self.bus.request_name(MPRIS_NAME).await.ok();
        } else {
            self.bus.release_name(MPRIS_NAME).await.ok();
        }
        if let Ok(player) = self
            .bus
            .object_server()
            .interface::<_, Player>(MPRIS_PATH)
            .await
        {
            let emitter = player.signal_emitter();
            let p = player.get().await;
            p.playback_status_changed(emitter).await.ok();
            p.metadata_changed(emitter).await.ok();
        }
    }
}

struct Service(Core);

#[interface(name = "org.marathonos.Radio1")]
impl Service {
    async fn get_state(&self) -> HashMap<&'static str, OwnedValue> {
        self.0.radio.with(|r| r.state()).await
    }

    /// Plays `frequency` (kHz), or the last station when 0.
    async fn play(&self, frequency: i32) -> fdo::Result<()> {
        let freq = if frequency == 0 {
            None
        } else {
            Some(channel(frequency)?)
        };
        self.0
            .act(move |r| r.play(freq.unwrap_or(r.frequency)))
            .await
    }

    async fn stop(&self) -> fdo::Result<()> {
        self.0
            .act(|r| {
                r.stop();
                Ok(())
            })
            .await
    }

    /// The next station up or down; tunes to it.
    async fn seek(&self, up: bool) -> fdo::Result<()> {
        self.0.act(move |r| r.seek(up)).await
    }

    /// The band's stations, kept for the list.
    async fn scan(&self) -> fdo::Result<()> {
        self.0
            .act(|r| {
                r.stations = r.with_receiver(Fm::scan)?;
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

struct Root;

#[allow(
    clippy::unused_self,
    reason = "MPRIS properties a radio answers the same way"
)]
#[interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {}

    fn quit(&self) {}

    #[zbus(property)]
    fn can_quit(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn can_raise(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn identity(&self) -> &'static str {
        "Radio"
    }

    #[zbus(property)]
    fn desktop_entry(&self) -> &'static str {
        "radio"
    }

    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<String> {
        Vec::new()
    }

    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<String> {
        Vec::new()
    }
}

struct Player(Core);

#[allow(
    clippy::unused_self,
    reason = "MPRIS properties a radio answers the same way"
)]
#[interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    async fn play(&self) -> fdo::Result<()> {
        self.0.act(|r| r.play(r.frequency)).await
    }

    async fn pause(&self) -> fdo::Result<()> {
        self.stop().await
    }

    async fn stop(&self) -> fdo::Result<()> {
        self.0
            .act(|r| {
                r.stop();
                Ok(())
            })
            .await
    }

    async fn play_pause(&self) -> fdo::Result<()> {
        self.0
            .act(|r| {
                if r.on.is_some() {
                    r.stop();
                    Ok(())
                } else {
                    r.play(r.frequency)
                }
            })
            .await
    }

    async fn next(&self) -> fdo::Result<()> {
        self.0.act(|r| r.seek(true)).await
    }

    async fn previous(&self) -> fdo::Result<()> {
        self.0.act(|r| r.seek(false)).await
    }

    #[zbus(property)]
    async fn playback_status(&self) -> String {
        let playing = self.0.radio.with(|r| r.on.is_some()).await;
        if playing { "Playing" } else { "Stopped" }.to_owned()
    }

    #[zbus(property)]
    async fn metadata(&self) -> HashMap<String, OwnedValue> {
        self.0.radio.with(|r| r.metadata()).await
    }

    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_seek(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn position(&self) -> i64 {
        0
    }

    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn minimum_rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn maximum_rate(&self) -> f64 {
        1.0
    }
}

/// A call takes the capture interface the radio plays from (the modem's
/// speech uses it): any call `ModemManager` reports stops the radio.
async fn stop_on_calls(core: Core) {
    let watch = async {
        let system = io::system_bus().await?;
        let rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .interface("org.freedesktop.ModemManager1.Modem.Voice")
            .member("CallAdded")
            .build()?;
        let mut calls = MessageStream::for_match_rule(rule, &system, None).await?;
        while calls.next().await.is_some() {
            core.act(|r| {
                r.stop();
                Ok(())
            })
            .await
            .ok();
        }
        zbus::Result::Ok(())
    };
    if let Err(e) = watch.await {
        log::warn(
            "marathon-radiod",
            format_args!("not watching for calls: {e}"),
        );
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let radio = Radio {
        on: None,
        frequency: FIRST,
        stations: Vec::new(),
    };
    let bus = io::session_bus().await?;
    let core = Core {
        radio: Shared::new(radio),
        bus: bus.clone(),
    };
    bus.object_server().at(PATH, Service(core.clone())).await?;
    bus.object_server().at(MPRIS_PATH, Root).await?;
    bus.object_server()
        .at(MPRIS_PATH, Player(core.clone()))
        .await?;
    bus.request_name(BUS_NAME).await?;
    io::spawn(stop_on_calls(core));
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
