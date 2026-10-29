//! marathon-audiod against a private `PipeWire`, `WirePlumber` and session
//! bus, checked with `wpctl` from the same session. Every process gets its
//! own runtime, config, state and home directories and no system bus, so
//! the user's own audio session is never touched. Skipped when the
//! programs are not installed.

#![allow(
    clippy::unwrap_used,
    clippy::unwrap_in_result,
    clippy::expect_used,
    clippy::panic,
    clippy::print_stderr,
    reason = "tests"
)]

use std::cell::RefCell;
use std::fs;
use std::io::{BufRead, BufReader};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::thread::sleep;
use std::time::{Duration, Instant};

use zbus::{Connection, Proxy};

mod fake_device;

const TIMEOUT: Duration = Duration::from_secs(15);

fn on_path(program: &str) -> bool {
    std::env::var_os("PATH")
        .is_some_and(|p| std::env::split_paths(&p).any(|d| d.join(program).is_file()))
}

fn eventually(what: &str, mut ok: impl FnMut() -> bool) {
    let start = Instant::now();
    while !ok() {
        assert!(start.elapsed() < TIMEOUT, "timed out waiting for {what}");
        sleep(Duration::from_millis(50));
    }
}

struct Session {
    dir: PathBuf,
    env: Vec<(String, String)>,
    children: RefCell<Vec<Child>>,
    bus: Connection,
}

impl Drop for Session {
    fn drop(&mut self) {
        for child in self.children.get_mut().iter_mut().rev() {
            child.kill().ok();
            child.wait().ok();
        }
        if std::thread::panicking() {
            for log in fs::read_dir(self.dir.join("logs"))
                .into_iter()
                .flatten()
                .flatten()
            {
                let text = fs::read_to_string(log.path()).unwrap_or_default();
                eprintln!("--- {}\n{text}", log.path().display());
            }
        }
        fs::remove_dir_all(&self.dir).ok();
    }
}

impl Session {
    fn command(&self, program: &str) -> Command {
        let mut c = Command::new(program);
        c.env_clear()
            .envs(self.env.iter().map(|(k, v)| (k, v)))
            .stdin(Stdio::null());
        c
    }

    fn spawn(&self, program: &str, args: &[&str]) {
        let name = Path::new(program).file_name().unwrap().to_string_lossy();
        let log = fs::File::create(self.dir.join(format!("logs/{name}.log"))).unwrap();
        let child = self
            .command(program)
            .args(args)
            .stdout(Stdio::null())
            .stderr(log)
            .spawn()
            .unwrap();
        self.children.borrow_mut().push(child);
    }

    fn output(&self, program: &str, args: &[&str]) -> Option<String> {
        let out = self.command(program).args(args).output().ok()?;
        out.status
            .success()
            .then(|| String::from_utf8_lossy(&out.stdout).into_owned())
    }

    fn start(name: &str) -> Option<Session> {
        Self::start_with(name, false)
    }

    /// With Marathon's media roles installed as well.
    fn start_with_roles(name: &str) -> Option<Session> {
        Self::start_with(name, true)
    }

    fn tools_installed() -> bool {
        let programs = [
            "pipewire",
            "wireplumber",
            "dbus-daemon",
            "wpctl",
            "pw-cat",
            "pw-dump",
        ];
        let Some(missing) = programs.iter().find(|p| !on_path(p)) else {
            return true;
        };
        assert!(
            std::env::var_os("MARATHON_TEST_STRICT").is_none(),
            "MARATHON_TEST_STRICT: {missing} is not installed"
        );
        eprintln!("skipped: {missing} is not installed");
        false
    }

    fn start_with(name: &str, roles: bool) -> Option<Session> {
        if !Self::tools_installed() {
            return None;
        }
        let data = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/session");
        // Short: the PipeWire socket path must fit in sun_path.
        let dir = std::env::temp_dir().join(format!("audiod-{}-{name}", std::process::id()));
        fs::remove_dir_all(&dir).ok();
        for sub in ["run", "config/wireplumber", "state", "home", "data", "logs"] {
            fs::create_dir_all(dir.join(sub)).unwrap();
        }
        fs::set_permissions(dir.join("run"), fs::Permissions::from_mode(0o700)).unwrap();
        let confd = dir.join("config/wireplumber/wireplumber.conf.d");
        fs::create_dir_all(&confd).unwrap();
        fs::copy(
            data.join("wireplumber.conf.d/90-marathon-test.conf"),
            confd.join("90-marathon-test.conf"),
        )
        .unwrap();
        // Marathon's shipped call policy, as installed.
        let shipped = Path::new(env!("CARGO_MANIFEST_DIR")).join("data/wireplumber");
        fs::copy(
            shipped.join("wireplumber.conf.d/60-marathon-call.conf"),
            confd.join("60-marathon-call.conf"),
        )
        .unwrap();
        let scripts = dir.join("data/wireplumber/scripts/marathon");
        fs::create_dir_all(&scripts).unwrap();
        fs::copy(
            shipped.join("scripts/marathon/call-routing.lua"),
            scripts.join("call-routing.lua"),
        )
        .unwrap();
        if roles {
            fs::copy(
                shipped.join("wireplumber.conf.d/61-marathon-media-roles.conf"),
                confd.join("61-marathon-media-roles.conf"),
            )
            .unwrap();
            fs::copy(
                shipped.join("scripts/marathon/role-default-target.lua"),
                scripts.join("role-default-target.lua"),
            )
            .unwrap();
        }

        let mut bus_daemon = Command::new("dbus-daemon")
            .arg(format!("--config-file={}", data.join("bus.conf").display()))
            .args(["--nofork", "--print-address=1"])
            .env_clear()
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let mut address = String::new();
        BufReader::new(bus_daemon.stdout.take().unwrap())
            .read_line(&mut address)
            .unwrap();
        let address = address.trim().to_owned();

        let path = |sub: &str| dir.join(sub).display().to_string();
        let env = vec![
            ("PATH".into(), std::env::var("PATH").unwrap_or_default()),
            ("XDG_RUNTIME_DIR".into(), path("run")),
            ("PIPEWIRE_RUNTIME_DIR".into(), path("run")),
            ("XDG_CONFIG_HOME".into(), path("config")),
            ("XDG_STATE_HOME".into(), path("state")),
            ("XDG_DATA_HOME".into(), path("data")),
            ("HOME".into(), path("home")),
            ("DBUS_SESSION_BUS_ADDRESS".into(), address.clone()),
            // WirePlumber's ModemManager watch finds no modem here.
            ("DBUS_SYSTEM_BUS_ADDRESS".into(), address.clone()),
            ("WIREPLUMBER_DEBUG".into(), "3".into()),
        ];
        let bus =
            zbus::block_on(zbus::connection::Builder::address(address.as_str()).build()).unwrap();
        let s = Session {
            dir: dir.clone(),
            env,
            children: RefCell::new(vec![bus_daemon]),
            bus,
        };

        s.spawn(
            "pipewire",
            &["-c", &data.join("pipewire.conf").display().to_string()],
        );
        eventually("pipewire's socket", || dir.join("run/pipewire-0").exists());
        s.spawn("wireplumber", &["-p", "marathon-test"]);
        eventually("WirePlumber's default sink", || {
            s.output("wpctl", &["inspect", "@DEFAULT_AUDIO_SINK@"])
                .is_some()
        });
        s.spawn(env!("CARGO_BIN_EXE_marathon-audiod"), &[]);
        Some(s)
    }

    /// A proxy whose property cache follows `PropertiesChanged`, made once the
    /// service owns its name.
    fn audio(&self) -> Proxy<'_> {
        let dbus = zbus::block_on(zbus::fdo::DBusProxy::new(&self.bus)).unwrap();
        eventually("org.marathonos.Audio", || {
            zbus::block_on(dbus.name_has_owner("org.marathonos.Audio".try_into().unwrap()))
                .unwrap_or(false)
        });
        zbus::block_on(Proxy::new(
            &self.bus,
            "org.marathonos.Audio",
            "/org/marathonos/Audio",
            "org.marathonos.Audio1",
        ))
        .unwrap()
    }

    fn wpctl_volume(&self, node: &str) -> String {
        self.output("wpctl", &["get-volume", node])
            .unwrap_or_default()
            .trim()
            .to_owned()
    }

    fn dump(&self) -> Vec<serde_json::Value> {
        self.output("pw-dump", &[])
            .and_then(|out| serde_json::from_str(&out).ok())
            .unwrap_or_default()
    }

    fn node_id(&self, name: &str) -> Option<u64> {
        self.dump()
            .iter()
            .find(|o| o["info"]["props"]["node.name"] == name)
            .and_then(|o| o["id"].as_u64())
    }

    /// The level wpctl shows for the node named `name`.
    fn volume_of(&self, name: &str) -> String {
        self.node_id(name)
            .map(|id| self.wpctl_volume(&id.to_string()))
            .unwrap_or_default()
    }

    /// The nodes the node named `name` plays into.
    fn linked_to(&self, name: &str) -> Vec<String> {
        let dump = self.dump();
        let name_of = |id: &serde_json::Value| {
            dump.iter()
                .find(|o| o["id"] == *id)
                .and_then(|o| o["info"]["props"]["node.name"].as_str())
                .unwrap_or_default()
                .to_owned()
        };
        dump.iter()
            .filter(|o| o["type"] == "PipeWire:Interface:Link")
            .filter(|o| name_of(&o["info"]["output-node-id"]) == name)
            .map(|o| name_of(&o["info"]["input-node-id"]))
            .collect()
    }
}

fn property<T>(audio: &Proxy<'_>, name: &str) -> T
where
    T: zbus::export::serde::de::DeserializeOwned + zbus::Type,
{
    zbus::block_on(audio.get_property::<T>(name)).unwrap()
}

/// A WAV header for `seconds` of 8 kHz mono silence.
fn silence(seconds: u32) -> Vec<u8> {
    let len = 8000 * 2 * seconds;
    let mut w = Vec::new();
    w.extend_from_slice(b"RIFF");
    w.extend_from_slice(&(36 + len).to_le_bytes());
    w.extend_from_slice(b"WAVEfmt ");
    w.extend_from_slice(&16u32.to_le_bytes());
    w.extend_from_slice(&1u16.to_le_bytes());
    w.extend_from_slice(&1u16.to_le_bytes());
    w.extend_from_slice(&8000u32.to_le_bytes());
    w.extend_from_slice(&16000u32.to_le_bytes());
    w.extend_from_slice(&2u16.to_le_bytes());
    w.extend_from_slice(&16u16.to_le_bytes());
    w.extend_from_slice(b"data");
    w.extend_from_slice(&len.to_le_bytes());
    w.resize(w.len() + len as usize, 0);
    w
}

#[test]
fn controls_a_private_pipewire_session() {
    let Some(session) = Session::start("graph") else {
        return;
    };
    let audio = session.audio();

    // The initial graph, as WirePlumber chose it.
    assert_eq!(property::<String>(&audio, "DefaultSink"), "test-sink-a");
    let sinks: Vec<(String, String)> = property(&audio, "Sinks");
    assert!(sinks.contains(&("test-sink-b".into(), "Test Sink B".into())));
    assert!((property::<f64>(&audio, "Volume") - 1.0).abs() < 1e-3);

    // Volume is the level wpctl shows, and PropertiesChanged carries it.
    zbus::block_on(audio.call_method("SetVolume", &(0.5f64))).unwrap();
    assert_eq!(session.wpctl_volume("@DEFAULT_AUDIO_SINK@"), "Volume: 0.50");
    eventually("Volume to follow", || {
        (property::<f64>(&audio, "Volume") - 0.5).abs() < 1e-3
    });

    zbus::block_on(audio.call_method("SetMuted", &(true))).unwrap();
    assert_eq!(
        session.wpctl_volume("@DEFAULT_AUDIO_SINK@"),
        "Volume: 0.50 [MUTED]"
    );
    eventually("Muted to follow", || property::<bool>(&audio, "Muted"));

    // A new default is WirePlumber's to apply; the levels follow it.
    zbus::block_on(audio.call_method("SetDefaultSink", &("test-sink-b"))).unwrap();
    eventually("the default sink to move", || {
        property::<String>(&audio, "DefaultSink") == "test-sink-b"
    });
    assert!(!property::<bool>(&audio, "Muted"));
    assert!(zbus::block_on(audio.call_method("SetDefaultSink", &("no-such-sink"))).is_ok());
    assert_eq!(property::<String>(&audio, "DefaultSink"), "test-sink-b");

    // Microphone mute, for calls.
    eventually("a default source", || {
        property::<String>(&audio, "DefaultSource") == "test-mic"
    });
    zbus::block_on(audio.call_method("SetInputMuted", &(true))).unwrap();
    assert_eq!(
        session.wpctl_volume("@DEFAULT_AUDIO_SOURCE@"),
        "Volume: 1.00 [MUTED]"
    );
    eventually("InputMuted to follow", || {
        property::<bool>(&audio, "InputMuted")
    });

    // The speakerphone choice is a WirePlumber setting for its call policy.
    zbus::block_on(audio.call_method("SetSpeakerphone", &(true))).unwrap();
    eventually("Speakerphone to follow", || {
        property::<bool>(&audio, "Speakerphone")
    });
    assert!(session
        .output("wpctl", &["settings", "marathon.call.speakerphone"])
        .is_some_and(|out| out.contains("Value: true")));
    let wp_log = fs::read_to_string(session.dir.join("logs/wireplumber.log")).unwrap();
    assert!(wp_log.contains("enabling plugin 'script:marathon/call-routing.lua'"));

    // Per-app volume.
    let wav = session.dir.join("silence.wav");
    fs::write(&wav, silence(60)).unwrap();
    session.spawn("pw-cat", &["--playback", &wav.display().to_string()]);
    let mut streams: Vec<(u32, String, f64, bool)> = Vec::new();
    eventually("a playback stream", || {
        streams = property(&audio, "Streams");
        !streams.is_empty()
    });
    let id = streams[0].0;
    zbus::block_on(audio.call_method("SetStreamVolume", &(id, 0.5f64))).unwrap();
    assert_eq!(session.wpctl_volume(&id.to_string()), "Volume: 0.50");
    eventually("the stream's volume to follow", || {
        let s: Vec<(u32, String, f64, bool)> = property(&audio, "Streams");
        s.iter()
            .any(|(i, _, v, _)| *i == id && (v - 0.5).abs() < 1e-3)
    });
}

fn close_to(value: f64, level: f64) -> bool {
    (value - level).abs() < 1e-3
}

// A Bluetooth or ALSA card keeps its node's level on the active device
// route, which appears only once WirePlumber has chosen the card's profile.
#[test]
fn controls_a_device_route_sink() {
    let Some(session) = Session::start("route") else {
        return;
    };
    let card = fake_device::start(&session.dir.join("run/pipewire-0"), 0.125);
    let audio = session.audio();
    zbus::block_on(audio.call_method("SetDefaultSink", &(fake_device::NODE_NAME))).unwrap();
    eventually("the card's node to be the default", || {
        property::<String>(&audio, "DefaultSink") == fake_device::NODE_NAME
    });
    assert!(close_to(property(&audio, "Volume"), 1.0));

    // The node's own level is 1.0; the route's, once active, 0.5.
    assert!(session
        .output("wpctl", &["set-profile", &card.to_string(), "1"])
        .is_some());
    eventually("wpctl to read the route", || {
        session.wpctl_volume("@DEFAULT_AUDIO_SINK@") == "Volume: 0.50"
    });
    eventually("Volume to follow the new route", || {
        close_to(property(&audio, "Volume"), 0.5)
    });

    assert!(session
        .output("wpctl", &["set-volume", "@DEFAULT_AUDIO_SINK@", "0.3"])
        .is_some());
    eventually("Volume to follow the route", || {
        close_to(property(&audio, "Volume"), 0.3)
    });

    zbus::block_on(audio.call_method("SetVolume", &(0.6f64))).unwrap();
    eventually("the route's volume to be set", || {
        session.wpctl_volume("@DEFAULT_AUDIO_SINK@") == "Volume: 0.60"
    });
    eventually("Volume to follow", || {
        close_to(property(&audio, "Volume"), 0.6)
    });

    zbus::block_on(audio.call_method("SetMuted", &(true))).unwrap();
    eventually("the route to be muted", || {
        session.wpctl_volume("@DEFAULT_AUDIO_SINK@") == "Volume: 0.60 [MUTED]"
    });
    eventually("Muted to follow", || property::<bool>(&audio, "Muted"));
}

const MEDIA: &str = "input.loopback.sink.role.multimedia";
const ALARM: &str = "input.loopback.sink.role.alarm";

// Marathon's media roles: the media volume is the Multimedia role's and
// the device stays at full level, so an alarm is not scaled by it.
#[test]
fn media_volume_leaves_alarms_alone() {
    let Some(session) = Session::start_with_roles("roles") else {
        return;
    };
    let audio = session.audio();
    eventually("the role loopbacks", || {
        session.volume_of(MEDIA) == "Volume: 1.00"
    });
    assert_eq!(property::<String>(&audio, "DefaultSink"), "test-sink-a");
    let sinks: Vec<(String, String)> = property(&audio, "Sinks");
    assert!(sinks.iter().all(|(name, _)| name.starts_with("test-")));

    // A level the device was given moves into the media volume.
    assert!(session
        .output("wpctl", &["set-volume", "@DEFAULT_AUDIO_SINK@", "0.3"])
        .is_some());
    eventually("the device back at full level", || {
        session.wpctl_volume("@DEFAULT_AUDIO_SINK@") == "Volume: 1.00"
    });
    eventually("the media volume to take it", || {
        session.volume_of(MEDIA) == "Volume: 0.30"
    });
    eventually("Volume to follow", || {
        close_to(property(&audio, "Volume"), 0.3)
    });

    // The shell's volume and mute are the media role's.
    zbus::block_on(audio.call_method("SetVolume", &(0.0f64))).unwrap();
    zbus::block_on(audio.call_method("SetMuted", &(true))).unwrap();
    eventually("media at 0, muted", || {
        session.volume_of(MEDIA) == "Volume: 0.00 [MUTED]"
    });
    assert_eq!(session.wpctl_volume("@DEFAULT_AUDIO_SINK@"), "Volume: 1.00");
    assert_eq!(session.volume_of(ALARM), "Volume: 1.00");

    // Qt names its device's node as the target, the default one included,
    // and does not reconnect; that still goes through the stream's role.
    let wav = session.dir.join("silence.wav");
    fs::write(&wav, silence(60)).unwrap();
    let wav = wav.display().to_string();
    let sink = session.node_id("test-sink-a").unwrap();
    let qt = format!(
        r#"{{ "node.name": "qt-like", "node.target": "{sink}", "node.dont-reconnect": true }}"#
    );
    session.spawn(
        "pw-cat",
        &["--playback", "--media-role", "Music", "-P", &qt, &wav],
    );
    eventually("the default-aimed stream on the media role", || {
        session.linked_to("qt-like").contains(&MEDIA.to_owned())
    });
    let other = r#"{ "node.name": "picked", "node.dont-reconnect": true }"#;
    session.spawn(
        "pw-cat",
        &["--playback", "--target", "test-sink-b", "-P", other, &wav],
    );
    eventually("a stream aimed elsewhere to stay there", || {
        session
            .linked_to("picked")
            .contains(&"test-sink-b".to_owned())
    });
    let alarm = r#"{ "node.name": "alarm-like" }"#;
    session.spawn(
        "pw-cat",
        &["--playback", "--target", ALARM, "-P", alarm, &wav],
    );
    eventually("the alarm on its own role", || {
        session.linked_to("alarm-like").contains(&ALARM.to_owned())
    });
}
