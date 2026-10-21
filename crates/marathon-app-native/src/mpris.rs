#![allow(clippy::struct_excessive_bools, reason = "MPRIS Player state flags")]
//! The Music app's player on the session bus as `org.mpris.MediaPlayer2.music`
//! while `active`, so the shell's media controls and background-audio
//! observer see it (QML `MarathonOS.Music`'s `MprisPlayer`), and its album
//! art (`Artwork`). Positions and lengths are milliseconds here and
//! microseconds on the bus.

use std::collections::HashMap;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, PoisonError};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use lofty::prelude::*;
use zbus::zvariant::{ObjectPath, OwnedObjectPath, Value};

use marathon_rt::{io, log};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, active, READ, WRITE, NOTIFY)]
        #[qproperty(bool, registered, READ, NOTIFY)]
        #[qproperty(bool, playing, READ, WRITE, NOTIFY = status_changed)]
        #[qproperty(bool, shuffle, READ, WRITE, NOTIFY = status_changed)]
        #[qproperty(QString, repeat_mode, cxx_name = "repeatMode", READ, WRITE, NOTIFY = status_changed)]
        #[qproperty(bool, can_go_next, cxx_name = "canGoNext", READ, WRITE, NOTIFY = status_changed)]
        #[qproperty(bool, can_go_previous, cxx_name = "canGoPrevious", READ, WRITE, NOTIFY = status_changed)]
        #[qproperty(i32, track_id, cxx_name = "trackId", READ, WRITE, NOTIFY = metadata_changed)]
        #[qproperty(QString, title, READ, WRITE, NOTIFY = metadata_changed)]
        #[qproperty(QString, artist, READ, WRITE, NOTIFY = metadata_changed)]
        #[qproperty(QString, album, READ, WRITE, NOTIFY = metadata_changed)]
        #[qproperty(QString, art_url, cxx_name = "artUrl", READ, WRITE, NOTIFY = metadata_changed)]
        #[qproperty(i64, length, READ, WRITE, NOTIFY = metadata_changed)]
        #[qproperty(i64, position, READ, WRITE, NOTIFY)]
        type MprisPlayer = super::MprisPlayerRust;

        #[qsignal]
        #[cxx_name = "statusChanged"]
        fn status_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "metadataChanged"]
        fn metadata_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "raiseRequested"]
        fn raise_requested(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "playRequested"]
        fn play_requested(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "pauseRequested"]
        fn pause_requested(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "playPauseRequested"]
        fn play_pause_requested(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "stopRequested"]
        fn stop_requested(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "nextRequested"]
        fn next_requested(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "previousRequested"]
        fn previous_requested(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "seekRequested"]
        fn seek_requested(self: Pin<&mut Self>, position: i64);
        #[qsignal]
        #[cxx_name = "shuffleRequested"]
        fn shuffle_requested(self: Pin<&mut Self>, shuffle: bool);
        #[qsignal]
        #[cxx_name = "repeatModeRequested"]
        fn repeat_mode_requested(self: Pin<&mut Self>, mode: &QString);
    }

    extern "RustQt" {
        #[qobject]
        type Artwork = super::ArtworkRust;

        /// The track's album art: its embedded picture, saved to the cache,
        /// else a cover image beside it; "" for none.
        #[qinvokable]
        fn art(self: &Artwork, track: &QString) -> QString;
    }

    impl cxx_qt::Threading for MprisPlayer {}
    impl cxx_qt::Initialize for MprisPlayer {}
}

use qobject::MprisPlayer;

const SERVICE: &str = "org.mpris.MediaPlayer2.music";
const PATH: &str = "/org/mpris/MediaPlayer2";

type Qt = cxx_qt::CxxQtThread<MprisPlayer>;

/// What the bus reads, copied from the properties as they change.
#[derive(Clone, Default)]
struct State {
    playing: bool,
    shuffle: bool,
    repeat_mode: String,
    can_go_next: bool,
    can_go_previous: bool,
    track_id: i32,
    title: String,
    artist: String,
    album: String,
    art_url: String,
    length: i64,
    position: i64,
}

impl State {
    fn playback_status(&self) -> &'static str {
        match (self.title.is_empty(), self.playing) {
            (true, _) => "Stopped",
            (false, true) => "Playing",
            (false, false) => "Paused",
        }
    }

    fn loop_status(&self) -> &'static str {
        match self.repeat_mode.as_str() {
            "one" => "Track",
            "all" => "Playlist",
            _ => "None",
        }
    }

    fn track_path(&self) -> OwnedObjectPath {
        let path = if self.track_id >= 0 { format!("/org/marathonos/music/track/{}", self.track_id) } else { "/org/mpris/MediaPlayer2/TrackList/NoTrack".into() };
        ObjectPath::try_from(path).map_or_else(|_| OwnedObjectPath::default(), OwnedObjectPath::from)
    }

    fn metadata(&self) -> HashMap<String, Value<'static>> {
        let mut map = HashMap::new();
        if self.title.is_empty() {
            return map;
        }
        map.insert("mpris:trackid".into(), Value::from(self.track_path()));
        map.insert("mpris:length".into(), Value::from(self.length * 1000));
        map.insert("xesam:title".into(), Value::from(self.title.clone()));
        map.insert("xesam:artist".into(), Value::from(vec![self.artist.clone()]));
        map.insert("xesam:album".into(), Value::from(self.album.clone()));
        if !self.art_url.is_empty() {
            map.insert("mpris:artUrl".into(), Value::from(self.art_url.clone()));
        }
        map
    }
}

type Shared = Arc<Mutex<State>>;

fn read(state: &Shared) -> State {
    state.lock().unwrap_or_else(PoisonError::into_inner).clone()
}

pub struct MprisPlayerRust {
    active: bool,
    registered: bool,
    playing: bool,
    shuffle: bool,
    repeat_mode: QString,
    can_go_next: bool,
    can_go_previous: bool,
    track_id: i32,
    title: QString,
    artist: QString,
    album: QString,
    art_url: QString,
    length: i64,
    position: i64,
    state: Shared,
    /// A `PropertiesChanged` is on its way.
    pending: Arc<AtomicBool>,
}

impl Default for MprisPlayerRust {
    fn default() -> Self {
        Self {
            active: false,
            registered: false,
            playing: false,
            shuffle: false,
            repeat_mode: QString::from("off"),
            can_go_next: false,
            can_go_previous: false,
            track_id: -1,
            title: QString::default(),
            artist: QString::default(),
            album: QString::default(),
            art_url: QString::default(),
            length: 0,
            position: 0,
            state: Shared::default(),
            pending: Arc::default(),
        }
    }
}

impl cxx_qt::Initialize for MprisPlayer {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().snapshot();
        self.as_mut().on_active_changed(Self::publish).release();
        self.as_mut()
            .on_status_changed(|mut obj| {
                obj.as_mut().snapshot();
                obj.announce();
            })
            .release();
        self.as_mut()
            .on_metadata_changed(|mut obj| {
                obj.as_mut().snapshot();
                obj.announce();
            })
            .release();
        self.on_position_changed(|mut obj| obj.as_mut().snapshot()).release();
    }
}

impl MprisPlayer {
    fn snapshot(self: Pin<&mut Self>) {
        let s = State {
            playing: self.playing,
            shuffle: self.shuffle,
            repeat_mode: self.repeat_mode.to_string(),
            can_go_next: self.can_go_next,
            can_go_previous: self.can_go_previous,
            track_id: self.track_id,
            title: self.title.to_string(),
            artist: self.artist.to_string(),
            album: self.album.to_string(),
            art_url: self.art_url.to_string(),
            length: self.length,
            position: self.position,
        };
        *self.state.lock().unwrap_or_else(PoisonError::into_inner) = s;
    }

    /// The service follows `active`.
    fn publish(self: Pin<&mut Self>) {
        let (active, qt, state) = (self.active, self.qt_thread(), Arc::clone(&self.state));
        io::spawn(async move {
            let done = async {
                let bus = io::session_bus().await?;
                let server = bus.object_server();
                if active {
                    server.at(PATH, Root { qt: qt.clone() }).await?;
                    server.at(PATH, Player { qt: qt.clone(), state }).await?;
                    bus.request_name(SERVICE).await?;
                } else {
                    bus.release_name(SERVICE).await.ok();
                    server.remove::<Root, _>(PATH).await.ok();
                    server.remove::<Player, _>(PATH).await.ok();
                }
                zbus::Result::Ok(())
            };
            let registered = match done.await {
                Ok(()) => active,
                Err(e) => {
                    log::warn("MprisPlayer", format_args!("cannot publish {SERVICE}: {e}"));
                    false
                }
            };
            qt.queue(move |mut obj| {
                if obj.registered != registered {
                    obj.as_mut().rust_mut().registered = registered;
                    obj.registered_changed();
                }
            })
            .ok();
        });
    }

    /// One `PropertiesChanged` for a run of property writes.
    fn announce(self: Pin<&mut Self>) {
        if !self.registered || self.pending.swap(true, Ordering::AcqRel) {
            return;
        }
        let (state, pending) = (Arc::clone(&self.state), Arc::clone(&self.pending));
        io::spawn(async move {
            pending.store(false, Ordering::Release);
            let s = read(&state);
            let has_track = !s.title.is_empty();
            let changed: HashMap<&str, Value<'_>> = HashMap::from([
                ("PlaybackStatus", Value::from(s.playback_status())),
                ("LoopStatus", Value::from(s.loop_status())),
                ("Shuffle", Value::from(s.shuffle)),
                ("CanGoNext", Value::from(s.can_go_next)),
                ("CanGoPrevious", Value::from(s.can_go_previous)),
                ("Metadata", Value::from(s.metadata())),
                ("CanPlay", Value::from(has_track)),
                ("CanPause", Value::from(has_track)),
                ("CanSeek", Value::from(has_track)),
            ]);
            let Ok(bus) = io::session_bus().await else { return };
            let body = ("org.mpris.MediaPlayer2.Player", changed, Vec::<String>::new());
            if let Err(e) = bus.emit_signal(None::<&str>, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged", &body).await {
                log::warn("MprisPlayer", format_args!("PropertiesChanged: {e}"));
            }
        });
    }
}

struct Root {
    qt: Qt,
}

#[zbus::interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {
        self.qt.queue(MprisPlayer::raise_requested).ok();
    }

    fn quit(&self) {}

    #[zbus(property)]
    fn can_quit(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn can_raise(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn identity(&self) -> &'static str {
        "Music"
    }

    #[zbus(property)]
    fn desktop_entry(&self) -> &'static str {
        "music"
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

struct Player {
    qt: Qt,
    state: Shared,
}

impl Player {
    fn ask(&self, f: impl FnOnce(Pin<&mut MprisPlayer>) + Send + 'static) {
        self.qt.queue(f).ok();
    }
}

#[zbus::interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    fn next(&self) {
        self.ask(MprisPlayer::next_requested);
    }

    fn previous(&self) {
        self.ask(MprisPlayer::previous_requested);
    }

    fn pause(&self) {
        self.ask(MprisPlayer::pause_requested);
    }

    fn play_pause(&self) {
        self.ask(MprisPlayer::play_pause_requested);
    }

    fn stop(&self) {
        self.ask(MprisPlayer::stop_requested);
    }

    fn play(&self) {
        self.ask(MprisPlayer::play_requested);
    }

    /// Past the end is the next track.
    async fn seek(&self, offset: i64, #[zbus(signal_emitter)] emitter: zbus::object_server::SignalEmitter<'_>) {
        let s = read(&self.state);
        let target = (s.position + offset / 1000).max(0);
        if s.length > 0 && target > s.length {
            return self.ask(MprisPlayer::next_requested);
        }
        self.ask(move |obj| obj.seek_requested(target));
        Self::seeked(&emitter, target * 1000).await.ok();
    }

    async fn set_position(&self, track_id: ObjectPath<'_>, position: i64, #[zbus(signal_emitter)] emitter: zbus::object_server::SignalEmitter<'_>) {
        let s = read(&self.state);
        if *s.track_path() != track_id || position < 0 || (s.length > 0 && position / 1000 > s.length) {
            return;
        }
        self.ask(move |obj| obj.seek_requested(position / 1000));
        Self::seeked(&emitter, position).await.ok();
    }

    fn open_uri(&self, uri: String) {
        drop(uri);
    }

    #[zbus(signal)]
    async fn seeked(emitter: &zbus::object_server::SignalEmitter<'_>, position: i64) -> zbus::Result<()>;

    #[zbus(property)]
    fn playback_status(&self) -> &'static str {
        read(&self.state).playback_status()
    }

    #[zbus(property)]
    fn loop_status(&self) -> &'static str {
        read(&self.state).loop_status()
    }

    #[zbus(property)]
    fn set_loop_status(&self, status: &str) {
        let mode = match status {
            "Track" => "one",
            "Playlist" => "all",
            _ => "off",
        };
        self.ask(move |obj| obj.repeat_mode_requested(&QString::from(mode)));
    }

    #[zbus(property)]
    fn shuffle(&self) -> bool {
        read(&self.state).shuffle
    }

    #[zbus(property)]
    fn set_shuffle(&self, shuffle: bool) {
        self.ask(move |obj| obj.shuffle_requested(shuffle));
    }

    #[zbus(property)]
    fn metadata(&self) -> HashMap<String, Value<'static>> {
        read(&self.state).metadata()
    }

    #[zbus(property)]
    fn position(&self) -> i64 {
        read(&self.state).position * 1000
    }

    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn set_rate(&self, rate: f64) {
        let _ = rate;
    }

    #[zbus(property)]
    fn minimum_rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn maximum_rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn volume(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn set_volume(&self, volume: f64) {
        let _ = volume;
    }

    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        read(&self.state).can_go_next
    }

    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        read(&self.state).can_go_previous
    }

    #[zbus(property)]
    fn can_play(&self) -> bool {
        !read(&self.state).title.is_empty()
    }

    #[zbus(property)]
    fn can_pause(&self) -> bool {
        !read(&self.state).title.is_empty()
    }

    #[zbus(property)]
    fn can_seek(&self) -> bool {
        !read(&self.state).title.is_empty()
    }

    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }
}

#[derive(Default)]
pub struct ArtworkRust;

/// Names a folder's cover image goes by.
const COVERS: &[&str] = &["cover.jpg", "cover.png", "folder.jpg", "folder.png", "front.jpg", "front.png", "Cover.jpg", "Folder.jpg", "AlbumArt.jpg"];

fn local_path(track: &str) -> PathBuf {
    PathBuf::from(track.strip_prefix("file://").unwrap_or(track))
}

/// The embedded picture, written once to the cache (`~/.cache/music/art`).
fn embedded(track: &str, file: &Path) -> Option<PathBuf> {
    let mut hasher = std::hash::DefaultHasher::new();
    track.hash(&mut hasher);
    let cached = dirs::cache_dir()?.join("music/art").join(format!("{:016x}", hasher.finish()));
    if cached.exists() {
        return Some(cached);
    }
    let tagged = lofty::read_from_path(file).ok()?;
    let picture = tagged.primary_tag().or_else(|| tagged.first_tag())?.pictures().first()?.clone();
    std::fs::create_dir_all(cached.parent()?).ok()?;
    std::fs::write(&cached, picture.data()).ok()?;
    Some(cached)
}

impl qobject::Artwork {
    #[allow(clippy::unused_self, reason = "a QML invokable")]
    fn art(&self, track: &QString) -> QString {
        let track = track.to_string();
        let file = local_path(&track);
        let found = embedded(&track, &file).or_else(|| COVERS.iter().map(|c| file.with_file_name(c)).find(|p| p.exists()));
        found.map_or_else(QString::default, |p| QString::from(&format!("file://{}", p.display())))
    }
}
