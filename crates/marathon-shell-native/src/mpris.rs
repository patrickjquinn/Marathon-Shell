//! `Mpris`: the media player the shell's controls drive, the first MPRIS
//! player on the session bus. Players are read on the I/O thread with a
//! timeout and driven without waiting: one can be blocked on the compositor
//! (a GTK client's roundtrip before its first map).

use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;

use async_channel::{Receiver, Sender};
use async_io::Timer;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_lite::{stream, StreamExt};
use zbus::fdo::DBusProxy;
use zbus::message::Type as MessageType;
use zbus::{DynamicType, OwnedObjectPath, OwnedVariant as OwnedValue, Variant as Value};
use zbus::{MatchRule, MessageStream};

use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, has_active_player, cxx_name = "hasActivePlayer", READ, NOTIFY = active_player_changed)]
        #[qproperty(QString, player_name, cxx_name = "playerName", READ, NOTIFY = active_player_changed)]
        #[qproperty(QString, desktop_entry, cxx_name = "desktopEntry", READ, NOTIFY = active_player_changed)]
        #[qproperty(QString, bus_name, cxx_name = "currentBusName", READ, NOTIFY = active_player_changed)]
        #[qproperty(QString, playback_status, cxx_name = "playbackStatus", READ, NOTIFY = playback_status_changed)]
        #[qproperty(bool, is_playing, cxx_name = "isPlaying", READ, NOTIFY = playback_status_changed)]
        #[qproperty(bool, is_paused, cxx_name = "isPaused", READ, NOTIFY = playback_status_changed)]
        #[qproperty(QString, track_title, cxx_name = "trackTitle", READ, NOTIFY = metadata_changed)]
        #[qproperty(QString, track_artist, cxx_name = "trackArtist", READ, NOTIFY = metadata_changed)]
        #[qproperty(QString, track_album, cxx_name = "trackAlbum", READ, NOTIFY = metadata_changed)]
        #[qproperty(QString, album_art_url, cxx_name = "albumArtUrl", READ, NOTIFY = metadata_changed)]
        /// Microseconds, as MPRIS has them.
        #[qproperty(i64, track_length, cxx_name = "trackLength", READ, NOTIFY = metadata_changed)]
        #[qproperty(i64, position, READ, NOTIFY)]
        #[qproperty(bool, can_play, cxx_name = "canPlay", READ, NOTIFY = capabilities_changed)]
        #[qproperty(bool, can_pause, cxx_name = "canPause", READ, NOTIFY = capabilities_changed)]
        #[qproperty(bool, can_go_next, cxx_name = "canGoNext", READ, NOTIFY = capabilities_changed)]
        #[qproperty(bool, can_go_previous, cxx_name = "canGoPrevious", READ, NOTIFY = capabilities_changed)]
        #[qproperty(bool, can_seek, cxx_name = "canSeek", READ, NOTIFY = capabilities_changed)]
        type Mpris = super::MprisRust;

        #[qsignal]
        #[cxx_name = "activePlayerChanged"]
        fn active_player_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "playbackStatusChanged"]
        fn playback_status_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "metadataChanged"]
        fn metadata_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "capabilitiesChanged"]
        fn capabilities_changed(self: Pin<&mut Self>);

        #[qinvokable]
        fn play(self: &Mpris);
        #[qinvokable]
        fn pause(self: &Mpris);
        #[qinvokable]
        #[cxx_name = "playPause"]
        fn play_pause(self: &Mpris);
        #[qinvokable]
        fn stop(self: &Mpris);
        /// The next track, or 30 s on in a podcast-length one.
        #[qinvokable]
        fn next(self: &Mpris);
        /// The previous track, or 10 s back in a podcast-length one.
        #[qinvokable]
        fn previous(self: &Mpris);
        #[qinvokable]
        fn seek(self: &Mpris, offset: i64);
        #[qinvokable]
        #[cxx_name = "setPosition"]
        fn set_position(self: &Mpris, position: i64);
    }

    impl cxx_qt::Threading for Mpris {}
    impl cxx_qt::Initialize for Mpris {}
}

use qobject::Mpris;

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct MprisRust {
    has_active_player: bool,
    player_name: QString,
    desktop_entry: QString,
    bus_name: QString,
    playback_status: QString,
    is_playing: bool,
    is_paused: bool,
    track_title: QString,
    track_artist: QString,
    track_album: QString,
    album_art_url: QString,
    track_length: i64,
    position: i64,
    can_play: bool,
    can_pause: bool,
    can_go_next: bool,
    can_go_previous: bool,
    can_seek: bool,
    actor: Option<Sender<Command>>,
}

#[derive(Clone, Copy)]
enum Command {
    Call(&'static str),
    Next,
    Previous,
    Seek(i64),
    SetPosition(i64),
}

/// The player as the shell shows it.
#[derive(Clone, Debug, Default, PartialEq)]
#[allow(clippy::struct_excessive_bools, reason = "MPRIS's capabilities")]
struct Player {
    bus_name: String,
    name: String,
    desktop_entry: String,
    /// Its properties have been read.
    active: bool,
    status: String,
    track: Track,
    position: i64,
    can_play: bool,
    can_pause: bool,
    can_go_next: bool,
    can_go_previous: bool,
    can_seek: bool,
}

#[derive(Clone, Debug, Default, PartialEq)]
struct Track {
    id: String,
    title: String,
    artist: String,
    album: String,
    art_url: String,
    length: i64,
}

impl cxx_qt::Initialize for Mpris {
    fn initialize(mut self: Pin<&mut Self>) {
        let (tx, rx) = async_channel::bounded(16);
        io::spawn(run(self.qt_thread(), rx));
        let mut rust = self.as_mut().rust_mut();
        rust.playback_status = QString::from("Stopped");
        rust.actor = Some(tx);
    }
}

impl Mpris {
    fn send(&self, command: Command) {
        if let Some(actor) = &self.actor {
            actor.try_send(command).ok();
        }
    }

    fn play(&self) {
        if self.can_play {
            self.send(Command::Call("Play"));
        }
    }

    fn pause(&self) {
        if self.can_pause {
            self.send(Command::Call("Pause"));
        }
    }

    fn play_pause(&self) {
        self.send(Command::Call("PlayPause"));
    }

    fn stop(&self) {
        self.send(Command::Call("Stop"));
    }

    fn next(&self) {
        self.send(Command::Next);
    }

    fn previous(&self) {
        self.send(Command::Previous);
    }

    fn seek(&self, offset: i64) {
        self.send(Command::Seek(offset));
    }

    fn set_position(&self, position: i64) {
        self.send(Command::SetPosition(position));
    }

    fn apply(mut self: Pin<&mut Self>, p: &Player) {
        let text = |s: &str| QString::from(s);
        let active = p.active && !p.bus_name.is_empty();
        let status = if active { p.status.as_str() } else { "Stopped" };
        let changed_player = self.has_active_player != active
            || self.player_name != text(&p.name)
            || self.desktop_entry != text(&p.desktop_entry)
            || self.bus_name != text(&p.bus_name);
        let changed_status = self.playback_status != text(status);
        if changed_player {
            let mut rust = self.as_mut().rust_mut();
            rust.has_active_player = active;
            rust.player_name = text(&p.name);
            rust.desktop_entry = text(&p.desktop_entry);
            rust.bus_name = text(&p.bus_name);
            self.as_mut().active_player_changed();
        }
        if changed_status {
            let mut rust = self.as_mut().rust_mut();
            rust.playback_status = text(status);
            rust.is_playing = status == "Playing";
            rust.is_paused = status == "Paused";
            self.as_mut().playback_status_changed();
        }
        if changed_player || changed_status {
            crate::tasks::playback_changed(
                p.bus_name.clone(),
                p.desktop_entry.clone(),
                active && status == "Playing",
            );
        }
        let t = &p.track;
        if self.track_title != text(&t.title)
            || self.track_artist != text(&t.artist)
            || self.track_album != text(&t.album)
            || self.album_art_url != text(&t.art_url)
            || self.track_length != t.length
        {
            let mut rust = self.as_mut().rust_mut();
            rust.track_title = text(&t.title);
            rust.track_artist = text(&t.artist);
            rust.track_album = text(&t.album);
            rust.album_art_url = text(&t.art_url);
            rust.track_length = t.length;
            self.as_mut().metadata_changed();
        }
        let caps = [
            p.can_play,
            p.can_pause,
            p.can_go_next,
            p.can_go_previous,
            p.can_seek,
        ];
        if [
            self.can_play,
            self.can_pause,
            self.can_go_next,
            self.can_go_previous,
            self.can_seek,
        ] != caps
        {
            let mut rust = self.as_mut().rust_mut();
            [
                rust.can_play,
                rust.can_pause,
                rust.can_go_next,
                rust.can_go_previous,
                rust.can_seek,
            ] = caps;
            self.as_mut().capabilities_changed();
        }
        set!(self, position, position_changed, p.position);
    }
}

impl Player {
    fn new(bus_name: &str) -> Self {
        let short = bus_name.strip_prefix(PREFIX).unwrap_or(bus_name);
        let short = short.split('.').next().unwrap_or(short);
        let mut chars = short.chars();
        let name = chars
            .next()
            .map(|c| c.to_uppercase().chain(chars).collect())
            .unwrap_or_default();
        Self {
            bus_name: bus_name.to_owned(),
            name,
            desktop_entry: short.to_lowercase(),
            status: "Stopped".to_owned(),
            ..Self::default()
        }
    }

    fn set(&mut self, key: &str, value: &Value<'_>) {
        let text = || {
            value
                .downcast_ref::<&str>()
                .map(str::to_owned)
                .unwrap_or_default()
        };
        let flag = || value.downcast_ref::<bool>().unwrap_or(false);
        match key {
            "Identity" | "DesktopEntry" => {
                let field = if key == "Identity" {
                    &mut self.name
                } else {
                    &mut self.desktop_entry
                };
                if let Some(v) = Some(text()).filter(|v| !v.is_empty()) {
                    *field = v;
                }
            }
            "PlaybackStatus" => {
                self.status = Some(text())
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| self.status.clone());
            }
            "CanPlay" => self.can_play = flag(),
            "CanPause" => self.can_pause = flag(),
            "CanGoNext" => self.can_go_next = flag(),
            "CanGoPrevious" => self.can_go_previous = flag(),
            "CanSeek" => self.can_seek = flag(),
            "Position" => self.position = int(value),
            "Metadata" => {
                if let Value::Dict(dict) = value {
                    self.track = Track::default();
                    for (k, v) in dict.iter() {
                        let v = if let Value::Variant(inner) = v {
                            inner
                        } else {
                            v
                        };
                        if let Value::Str(k) = k {
                            self.track.set(k, v);
                        }
                    }
                }
            }
            _ => {}
        }
    }

    /// Podcast-length tracks skip within themselves.
    fn skip(&self, forward: bool) -> Option<(&'static str, i64)> {
        const PODCAST: i64 = 20 * 60 * 1_000_000;
        if self.can_seek && self.track.length > PODCAST {
            Some(("Seek", if forward { 30_000_000 } else { -10_000_000 }))
        } else if forward && self.can_go_next {
            Some(("Next", 0))
        } else if !forward && self.can_go_previous {
            Some(("Previous", 0))
        } else {
            None
        }
    }
}

impl Track {
    fn set(&mut self, key: &str, value: &Value<'_>) {
        let text = || match value {
            Value::Str(s) => s.to_string(),
            Value::ObjectPath(p) => p.to_string(),
            // xesam:artist is a list; some players send one string.
            Value::Array(a) => a
                .iter()
                .next()
                .and_then(|v| v.downcast_ref::<&str>().ok())
                .unwrap_or_default()
                .to_owned(),
            _ => String::new(),
        };
        match key {
            "mpris:trackid" => self.id = text(),
            "xesam:title" => self.title = text(),
            "xesam:artist" => self.artist = text(),
            "xesam:album" => self.album = text(),
            "mpris:artUrl" => self.art_url = text(),
            "mpris:length" => self.length = int(value),
            _ => {}
        }
    }
}

fn int(value: &Value<'_>) -> i64 {
    match *value {
        Value::I64(v) => v,
        Value::U64(v) => i64::try_from(v).unwrap_or(i64::MAX),
        Value::I32(v) => v.into(),
        Value::U32(v) => v.into(),
        _ => 0,
    }
}

const PREFIX: &str = "org.mpris.MediaPlayer2.";
const PATH: &str = "/org/mpris/MediaPlayer2";
const ROOT: &str = "org.mpris.MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";
const PROPERTIES: &str = "org.freedesktop.DBus.Properties";

type Qt = cxx_qt::CxxQtThread<Mpris>;

enum Event {
    Command(Command),
    Closed,
    Changed {
        sender: String,
        interface: String,
        changed: HashMap<String, OwnedValue>,
    },
    Owner {
        name: String,
        owner: Option<String>,
    },
    Tick,
}

struct Actor {
    qt: Qt,
    bus: zbus::Connection,
    player: Player,
    owner: Option<String>,
}

async fn run(qt: Qt, commands: Receiver<Command>) {
    let bus = match io::session_bus().await {
        Ok(bus) => bus,
        Err(e) => return log::warn("mpris", format_args!("no session bus: {e}")),
    };
    let mut actor = Actor {
        qt,
        bus,
        player: Player::default(),
        owner: None,
    };
    let events = commands
        .map(Event::Command)
        .chain(stream::once(Event::Closed))
        .or(actor.signals().await)
        .or(Timer::interval(Duration::from_secs(1)).map(|_| Event::Tick));
    let mut events = std::pin::pin!(events);
    actor.scan().await;
    while let Some(event) = events.next().await {
        match event {
            Event::Command(command) => actor.handle(command).await,
            Event::Closed => break,
            Event::Changed {
                sender,
                interface,
                changed,
            } => {
                if actor.owner.as_ref() == Some(&sender)
                    && (interface == PLAYER || interface == ROOT)
                {
                    for (key, value) in &changed {
                        actor.player.set(key, value);
                    }
                    actor.publish();
                }
            }
            Event::Owner { name, owner } => {
                if name == actor.player.bus_name {
                    actor.player = Player::default();
                    actor.owner = None;
                    actor.publish();
                }
                if actor.player.bus_name.is_empty() {
                    match owner {
                        Some(_) => actor.follow(&name).await,
                        None => actor.scan().await,
                    }
                }
            }
            Event::Tick => {
                if actor.player.active && actor.player.status == "Playing" {
                    actor.read_position().await;
                }
            }
        }
    }
}

impl Actor {
    fn publish(&self) {
        let player = self.player.clone();
        self.qt.queue(move |obj| obj.apply(&player)).ok();
    }

    async fn dbus(&self) -> Option<DBusProxy<'static>> {
        DBusProxy::new(&self.bus).await.ok()
    }

    /// The first player already on the bus; later ones arrive by
    /// `NameOwnerChanged`.
    async fn scan(&mut self) {
        let Some(dbus) = self.dbus().await else {
            return;
        };
        let names = dbus.list_names().await.unwrap_or_default();
        if let Some(name) = names.iter().find(|n| n.as_str().starts_with(PREFIX)) {
            self.follow(name.as_str()).await;
        }
    }

    async fn follow(&mut self, name: &str) {
        self.player = Player::new(name);
        self.owner = match (self.dbus().await, zbus::names::BusName::try_from(name)) {
            (Some(dbus), Ok(bus_name)) => dbus
                .get_name_owner(bus_name)
                .await
                .ok()
                .map(|o| o.to_string()),
            _ => None,
        };
        self.read(ROOT).await;
        if self.read(PLAYER).await {
            self.player.active = true;
        }
        self.publish();
    }

    /// Reads an interface's properties into the player; false if it didn't answer.
    async fn read(&mut self, interface: &str) -> bool {
        let reply = self.call(PROPERTIES, "GetAll", &(interface,)).await;
        let Some(props) =
            reply.and_then(|m| m.body().deserialize::<HashMap<String, OwnedValue>>().ok())
        else {
            return false;
        };
        for (key, value) in &props {
            self.player.set(key, value);
        }
        true
    }

    async fn read_position(&mut self) {
        let reply = self.call(PROPERTIES, "Get", &(PLAYER, "Position")).await;
        if let Some(position) = reply.and_then(|m| m.body().deserialize::<OwnedValue>().ok()) {
            self.player.position = int(&position);
            self.publish();
        }
    }

    async fn call<B>(&self, interface: &str, method: &str, body: &B) -> Option<zbus::Message>
    where
        B: serde::Serialize + DynamicType,
    {
        let name = self.player.bus_name.as_str();
        let call = self
            .bus
            .call_method(Some(name), PATH, Some(interface), method, body);
        match io::timeout(Duration::from_secs(2), call).await {
            Some(Ok(reply)) => Some(reply),
            Some(Err(e)) => {
                log::warn("mpris", format_args!("{name} {method}: {e}"));
                None
            }
            None => None,
        }
    }

    /// Sent without waiting on the player, then read back: players that
    /// don't emit `PropertiesChanged` for a command still settle.
    fn send<B>(&self, method: &'static str, body: B)
    where
        B: serde::Serialize + DynamicType + Send + Sync + 'static,
    {
        let (bus, name) = (self.bus.clone(), self.player.bus_name.clone());
        io::spawn(async move {
            if let Err(e) = bus
                .call_method(Some(name.as_str()), PATH, Some(PLAYER), method, &body)
                .await
            {
                log::warn("mpris", format_args!("{name} {method}: {e}"));
            }
        });
    }

    async fn handle(&mut self, command: Command) {
        if !self.player.active {
            return;
        }
        let p = &self.player;
        match command {
            Command::Call(method) => self.send(method, ()),
            Command::Next | Command::Previous => match p.skip(matches!(command, Command::Next)) {
                Some(("Seek", offset)) => self.send("Seek", (offset,)),
                Some((method, _)) => self.send(method, ()),
                None => return,
            },
            Command::Seek(offset) if p.can_seek => self.send("Seek", (offset,)),
            Command::SetPosition(position) if p.can_seek => {
                match OwnedObjectPath::try_from(p.track.id.as_str()) {
                    Ok(track) => self.send("SetPosition", (track, position)),
                    Err(_) => return,
                }
            }
            Command::Seek(_) | Command::SetPosition(_) => return,
        }
        Timer::after(Duration::from_millis(150)).await;
        self.read(PLAYER).await;
        self.publish();
    }

    async fn signals(&self) -> stream::Boxed<Event> {
        let mut merged = stream::empty().boxed();
        let rule = MatchRule::builder()
            .msg_type(MessageType::Signal)
            .path(PATH)
            .interface(PROPERTIES)
            .member("PropertiesChanged")
            .build();
        if let Ok(rule) = rule {
            if let Ok(s) =
                MessageStream::for_match_rule(rule, &self.bus, std::num::NonZeroUsize::new(64))
                    .await
            {
                merged = merged
                    .or(s.filter_map(|m| {
                        let m = m.ok()?;
                        let sender = m.header().sender()?.to_string();
                        let (interface, changed, _): (
                            String,
                            HashMap<String, OwnedValue>,
                            Vec<String>,
                        ) = m.body().deserialize().ok()?;
                        Some(Event::Changed {
                            sender,
                            interface,
                            changed,
                        })
                    }))
                    .boxed();
            }
        }
        if let Some(dbus) = self.dbus().await {
            if let Ok(owners) = dbus.receive_name_owner_changed().await {
                let owners = owners.filter_map(|signal| {
                    let args = signal.args().ok()?;
                    let name = args.name().to_string();
                    name.starts_with(PREFIX).then(|| Event::Owner {
                        name,
                        owner: args.new_owner().as_ref().map(ToString::to_string),
                    })
                });
                merged = merged.or(owners).boxed();
            }
        }
        merged
    }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use zbus::Variant as Value;

    use super::Player;

    fn metadata(artist: Value<'static>, length: i64) -> Value<'static> {
        let mut dict: HashMap<&str, Value<'_>> = HashMap::new();
        dict.insert("xesam:artist", artist);
        dict.insert("xesam:title", Value::from("News"));
        dict.insert("mpris:length", Value::from(length));
        Value::from(dict)
    }

    #[test]
    fn a_player_is_named_from_its_bus_name_until_it_says() {
        let mut p = Player::new("org.mpris.MediaPlayer2.shortwave.instance42");
        assert_eq!(
            (p.name.as_str(), p.desktop_entry.as_str()),
            ("Shortwave", "shortwave")
        );
        p.set("DesktopEntry", &Value::from("de.haeckerfelix.Shortwave"));
        p.set("Identity", &Value::from(""));
        assert_eq!(
            (p.name.as_str(), p.desktop_entry.as_str()),
            ("Shortwave", "de.haeckerfelix.Shortwave")
        );
    }

    #[test]
    fn the_artist_is_the_first_of_a_list_or_a_lone_string() {
        let mut p = Player::new("org.mpris.MediaPlayer2.x");
        p.set(
            "Metadata",
            &metadata(Value::from(vec!["CJME News/Talk 980", "Other"]), 0),
        );
        assert_eq!(
            (p.track.artist.as_str(), p.track.title.as_str()),
            ("CJME News/Talk 980", "News")
        );
        p.set("Metadata", &metadata(Value::from("Solo"), 0));
        assert_eq!(p.track.artist, "Solo");
    }

    #[test]
    fn a_podcast_skips_within_itself() {
        let mut p = Player::new("org.mpris.MediaPlayer2.x");
        p.can_go_next = true;
        p.can_seek = true;
        p.set("Metadata", &metadata(Value::from("a"), 3 * 60 * 1_000_000));
        assert_eq!(p.skip(true), Some(("Next", 0)));
        assert_eq!(p.skip(false), None);
        p.set("Metadata", &metadata(Value::from("a"), 45 * 60 * 1_000_000));
        assert_eq!(p.skip(true), Some(("Seek", 30_000_000)));
        assert_eq!(p.skip(false), Some(("Seek", -10_000_000)));
    }
}
