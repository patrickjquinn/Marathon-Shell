//! `marathon::Audio`: the default sink's volume and mute, the playback
//! streams and the call controls, through marathon-audiod's
//! `org.marathonos.Audio1` on the I/O thread.

use std::collections::HashMap;
use std::pin::Pin;

use async_channel::{Receiver, Sender};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use futures_lite::{stream, StreamExt};
use zbus::fdo::DBusProxy;
use zbus::zvariant::{DynamicType, OwnedValue};

use crate::{io, log};

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY)]
        #[qproperty(bool, available, cxx_name = "perAppVolumeSupported", READ = per_app_volume_supported, NOTIFY = available_changed)]
        #[qproperty(f64, volume, READ, NOTIFY)]
        #[qproperty(bool, muted, READ, NOTIFY)]
        #[qproperty(bool, is_playing, cxx_name = "isPlaying", READ, NOTIFY)]
        /// Each stream a map of streamId, name, appName, volume, muted and
        /// mediaClass.
        #[qproperty(QList_QVariant, streams, READ, NOTIFY)]
        type Audio = super::AudioRust;

        /// A sink the shell knew changed its level: not a first report,
        /// not one of the shell's own writes.
        #[qsignal]
        #[cxx_name = "levelChanged"]
        fn level_changed(self: Pin<&mut Self>);

        #[cxx_name = "perAppVolumeSupported"]
        fn per_app_volume_supported(self: &Audio) -> bool;

        #[qinvokable]
        #[cxx_name = "setVolume"]
        fn set_volume(self: Pin<&mut Audio>, volume: f64);
        #[qinvokable]
        #[cxx_name = "setMuted"]
        fn set_muted(self: Pin<&mut Audio>, muted: bool);
        #[qinvokable]
        #[cxx_name = "setStreamVolume"]
        fn set_stream_volume(self: &Audio, stream_id: i32, volume: f64);
        #[qinvokable]
        #[cxx_name = "setStreamMuted"]
        fn set_stream_muted(self: &Audio, stream_id: i32, muted: bool);
        /// Reads everything again; the service pushes changes otherwise.
        #[qinvokable]
        #[cxx_name = "refreshStreams"]
        fn refresh_streams(self: &Audio);
    }

    impl cxx_qt::Threading for Audio {}
    impl cxx_qt::Initialize for Audio {}
}

use qobject::Audio;

#[derive(Default)]
pub struct AudioRust {
    available: bool,
    volume: f64,
    muted: bool,
    is_playing: bool,
    streams: QList<QVariant>,
    sink: Sink,
    actor: Option<Sender<Command>>,
}

/// Volume and mute of whichever sink is the default now. A report that
/// crosses a write of ours in flight is stale for that field.
#[derive(Debug)]
#[allow(clippy::struct_excessive_bools, reason = "a field and its pending write each")]
struct Sink {
    name: String,
    volume: f64,
    muted: bool,
    volume_pending: bool,
    mute_pending: bool,
    volume_writes: u32,
    mute_writes: u32,
    reported: bool,
}

impl Default for Sink {
    fn default() -> Self {
        Self { name: String::new(), volume: 0.6, muted: false, volume_pending: false, mute_pending: false, volume_writes: 0, mute_writes: 0, reported: false }
    }
}

impl Sink {
    fn set_volume(&mut self, volume: f64) -> Option<f64> {
        self.volume = volume.clamp(0.0, 1.0);
        self.volume_pending = true;
        self.write_volume()
    }

    fn set_muted(&mut self, muted: bool) -> Option<bool> {
        self.muted = muted;
        self.mute_pending = true;
        self.write_muted()
    }

    /// Set before a default sink exists (at boot): applied to the first one.
    fn set_default(&mut self, name: &str) -> (Option<f64>, Option<bool>) {
        self.reported &= name == self.name;
        name.clone_into(&mut self.name);
        (self.write_volume(), self.write_muted())
    }

    /// Whether the level of a sink already reported changed.
    fn report(&mut self, name: &str, volume: f64, muted: bool) -> bool {
        if name != self.name {
            return false;
        }
        let (before, was_muted) = (self.volume, self.muted);
        if self.volume_writes == 0 {
            self.volume = volume.clamp(0.0, 1.0);
        }
        if self.mute_writes == 0 {
            self.muted = muted;
        }
        let changed = (self.volume - before).abs() > f64::EPSILON || self.muted != was_muted;
        std::mem::replace(&mut self.reported, true) && changed
    }

    fn write_volume(&mut self) -> Option<f64> {
        if !self.volume_pending || self.name.is_empty() {
            return None;
        }
        self.volume_pending = false;
        self.volume_writes += 1;
        Some(self.volume)
    }

    fn write_muted(&mut self) -> Option<bool> {
        if !self.mute_pending || self.name.is_empty() {
            return None;
        }
        self.mute_pending = false;
        self.mute_writes += 1;
        Some(self.muted)
    }
}

enum Command {
    Volume(f64),
    Muted(bool),
    StreamVolume(u32, f64),
    StreamMuted(u32, bool),
    Refresh,
}

/// A playback stream as marathon-audiod lists it: id, name, volume, muted.
type Stream = (u32, String, f64, bool);

impl cxx_qt::Initialize for Audio {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::bounded(64);
        io::spawn(run(self.qt_thread(), rx));
        let mut rust = self.as_mut().rust_mut();
        rust.volume = rust.sink.volume;
        rust.actor = Some(tx);
    }
}

impl Audio {
    fn send(&self, command: Command) {
        if self.actor.as_ref().is_none_or(|a| a.try_send(command).is_err()) {
            log::warn("audio", "no audio backend");
        }
    }

    fn per_app_volume_supported(&self) -> bool {
        self.available
    }

    fn set_volume(mut self: Pin<&mut Self>, volume: f64) {
        let write = self.as_mut().rust_mut().sink.set_volume(volume);
        self.as_mut().write(write, None);
    }

    fn set_muted(mut self: Pin<&mut Self>, muted: bool) {
        let write = self.as_mut().rust_mut().sink.set_muted(muted);
        self.as_mut().write(None, write);
    }

    fn set_stream_volume(&self, stream_id: i32, volume: f64) {
        if let Ok(id) = u32::try_from(stream_id) {
            self.send(Command::StreamVolume(id, volume.clamp(0.0, 1.0)));
        }
    }

    fn set_stream_muted(&self, stream_id: i32, muted: bool) {
        if let Ok(id) = u32::try_from(stream_id) {
            self.send(Command::StreamMuted(id, muted));
        }
    }

    fn refresh_streams(&self) {
        self.send(Command::Refresh);
    }

    fn write(mut self: Pin<&mut Self>, volume: Option<f64>, muted: Option<bool>) {
        if let Some(v) = volume {
            self.send(Command::Volume(v));
        }
        if let Some(m) = muted {
            self.send(Command::Muted(m));
        }
        self.as_mut().sync();
    }

    fn sync(mut self: Pin<&mut Self>) {
        let (volume, muted) = (self.sink.volume, self.sink.muted);
        if (self.volume - volume).abs() > f64::EPSILON {
            self.as_mut().rust_mut().volume = volume;
            self.as_mut().volume_changed();
        }
        set!(self, muted, muted_changed, muted);
    }

    fn written(mut self: Pin<&mut Self>, volume: bool) {
        let mut rust = self.as_mut().rust_mut();
        let writes = if volume { &mut rust.sink.volume_writes } else { &mut rust.sink.mute_writes };
        *writes = writes.saturating_sub(1);
    }

    fn apply(mut self: Pin<&mut Self>, report: Report) {
        let mut writes = (None, None);
        if let Some(name) = report.default.filter(|n| *n != self.sink.name) {
            writes = self.as_mut().rust_mut().sink.set_default(&name);
        }
        let mut level = false;
        if let Some((volume, muted)) = report.level {
            let mut rust = self.as_mut().rust_mut();
            let name = rust.sink.name.clone();
            level = rust.sink.report(&name, volume, muted);
        }
        self.as_mut().write(writes.0, writes.1);
        if level {
            self.as_mut().level_changed();
        }
        if let Some(streams) = report.streams {
            let mut list = QList::<QVariant>::default();
            for (id, name, volume, muted) in &streams {
                let mut map = QMap::<QMapPair_QString_QVariant>::default();
                let name = QVariant::from(&QString::from(name.as_str()));
                map.insert(QString::from("streamId"), QVariant::from(&i32::try_from(*id).unwrap_or(i32::MAX)));
                map.insert(QString::from("name"), name.clone());
                map.insert(QString::from("appName"), name);
                map.insert(QString::from("volume"), QVariant::from(volume));
                map.insert(QString::from("muted"), QVariant::from(muted));
                map.insert(QString::from("mediaClass"), QVariant::from(&QString::from("Stream/Output/Audio")));
                list.append(QVariant::from(&map));
            }
            self.as_mut().rust_mut().streams = list;
            self.as_mut().streams_changed();
            set!(self, is_playing, is_playing_changed, !streams.is_empty());
        }
        set!(self, available, available_changed, report.available);
    }
}

const SERVICE: &str = "org.marathonos.Audio";
const PATH: &str = "/org/marathonos/Audio";
const INTERFACE: &str = "org.marathonos.Audio1";

type Qt = cxx_qt::CxxQtThread<Audio>;

/// What changed: the default sink, its level, and the streams.
struct Report {
    available: bool,
    default: Option<String>,
    level: Option<(f64, bool)>,
    streams: Option<Vec<Stream>>,
}

enum Event {
    Command(Command),
    Closed,
    Changed(HashMap<String, OwnedValue>),
    Owner(bool),
}

#[derive(Default)]
struct Cache {
    volume: f64,
    muted: bool,
}

impl Cache {
    /// The properties as a report, if any of them is one we show.
    fn apply(&mut self, props: &HashMap<String, OwnedValue>) -> Report {
        let default = props.get("DefaultSink").and_then(|v| v.downcast_ref::<&str>().ok()).map(str::to_owned);
        let volume = props.get("Volume").and_then(|v| v.downcast_ref::<f64>().ok());
        let muted = props.get("Muted").and_then(|v| v.downcast_ref::<bool>().ok());
        let level = (default.is_some() || volume.is_some() || muted.is_some()).then(|| {
            self.volume = volume.unwrap_or(self.volume);
            self.muted = muted.unwrap_or(self.muted);
            (self.volume, self.muted)
        });
        let streams = props.get("Streams").and_then(|v| Vec::<Stream>::try_from(v.try_clone().ok()?).ok());
        Report { available: true, default, level, streams }
    }
}

async fn run(qt: Qt, commands: Receiver<Command>) {
    let bus = match io::session_bus().await {
        Ok(bus) => bus,
        Err(e) => return log::warn("audio", format_args!("no session bus: {e}")),
    };
    let mut events = stream::empty().boxed();
    if let Ok(props) = zbus::fdo::PropertiesProxy::builder(&bus).destination(SERVICE).and_then(|b| b.path(PATH)) {
        if let Ok(props) = props.cache_properties(zbus::proxy::CacheProperties::No).build().await {
            if let Ok(changes) = props.receive_properties_changed().await {
                let changes = changes.filter_map(|s| {
                    let args = s.args().ok()?;
                    (args.interface_name().as_str() == INTERFACE).then(|| {
                        Event::Changed(args.changed_properties().iter().filter_map(|(k, v)| Some(((*k).to_owned(), v.try_to_owned().ok()?))).collect())
                    })
                });
                events = events.or(changes).boxed();
            }
        }
    }
    if let Ok(dbus) = DBusProxy::new(&bus).await {
        if let Ok(owners) = dbus.receive_name_owner_changed_with_args(&[(0, SERVICE)]).await {
            events = events.or(owners.filter_map(|s| Some(Event::Owner(s.args().ok()?.new_owner().is_some())))).boxed();
        }
    }
    let events = stream::once(Event::Command(Command::Refresh)).chain(commands.map(Event::Command)).chain(stream::once(Event::Closed)).or(events);
    let mut events = std::pin::pin!(events);
    let mut cache = Cache::default();
    while let Some(event) = events.next().await {
        let result = match event {
            Event::Closed => break,
            Event::Changed(changed) => {
                let report = cache.apply(&changed);
                qt.queue(move |obj| obj.apply(report)).ok();
                Ok(())
            }
            // A restarted service starts from PipeWire's state, not ours.
            Event::Owner(true) | Event::Command(Command::Refresh) => {
                let all = bus.call_method(Some(SERVICE), PATH, Some("org.freedesktop.DBus.Properties"), "GetAll", &(INTERFACE,)).await;
                let report = match all.and_then(|m| m.body().deserialize::<HashMap<String, OwnedValue>>()) {
                    Ok(props) => cache.apply(&props),
                    Err(e) => {
                        log::warn("audio", format_args!("marathon-audiod: {e}"));
                        gone(&mut cache)
                    }
                };
                qt.queue(move |obj| obj.apply(report)).ok();
                Ok(())
            }
            Event::Owner(false) => {
                let report = gone(&mut cache);
                qt.queue(move |obj| obj.apply(report)).ok();
                Ok(())
            }
            Event::Command(Command::Volume(v)) => {
                let result = call(&bus, "SetVolume", &(v,)).await;
                qt.queue(|obj| obj.written(true)).ok();
                result
            }
            Event::Command(Command::Muted(m)) => {
                let result = call(&bus, "SetMuted", &(m,)).await;
                qt.queue(|obj| obj.written(false)).ok();
                result
            }
            Event::Command(Command::StreamVolume(id, v)) => call(&bus, "SetStreamVolume", &(id, v)).await,
            Event::Command(Command::StreamMuted(id, m)) => call(&bus, "SetStreamMuted", &(id, m)).await,
        };
        if let Err(e) = result {
            log::warn("audio", e);
        }
    }
}

/// Answered once `PipeWire` has it.
pub async fn call<B: serde::Serialize + DynamicType>(bus: &zbus::Connection, method: &str, body: &B) -> zbus::Result<()> {
    bus.call_method(Some(SERVICE), PATH, Some(INTERFACE), method, body).await.map(|_| ())
}

/// The service is gone: no sink, no streams.
fn gone(cache: &mut Cache) -> Report {
    *cache = Cache::default();
    Report { available: false, default: Some(String::new()), level: None, streams: Some(Vec::new()) }
}

#[cfg(test)]
mod tests {
    use super::Sink;

    fn sink(name: &str) -> Sink {
        let mut s = Sink::default();
        s.set_default(name);
        s
    }

    #[test]
    fn a_volume_set_before_any_sink_goes_to_the_first() {
        let mut s = Sink::default();
        assert_eq!(s.set_volume(1.4), None);
        assert_eq!(s.set_default("speaker"), (Some(1.0), None));
    }

    #[test]
    fn stale_reports_during_a_drag_are_ignored() {
        let mut s = sink("speaker");
        s.set_volume(0.3);
        s.set_volume(0.4);
        s.report("speaker", 0.3, false);
        assert!((s.volume - 0.4).abs() < 1e-9);
        s.volume_writes = 0;
        s.report("speaker", 0.7, true);
        assert!((s.volume - 0.7).abs() < 1e-9 && s.muted);
    }

    #[test]
    fn only_a_known_sinks_change_is_a_level_change() {
        let mut s = sink("speaker");
        assert!(!s.report("speaker", 0.5, false));
        assert!(s.report("speaker", 0.6, false));
        assert!(!s.report("speaker", 0.6, false));
        s.set_default("headset");
        assert!(!s.report("headset", 0.2, false));
    }

    #[test]
    fn fields_are_independent_and_other_sinks_ignored() {
        let mut s = sink("speaker");
        s.set_muted(true);
        s.report("speaker", 0.2, false);
        assert!(s.muted && (s.volume - 0.2).abs() < 1e-9);
        s.report("headset", 0.9, false);
        assert!((s.volume - 0.2).abs() < 1e-9);
    }
}
