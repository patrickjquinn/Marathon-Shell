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

use zbus::blocking::{Connection, Proxy};

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

    fn start() -> Option<Session> {
        let programs = ["pipewire", "wireplumber", "dbus-daemon", "wpctl", "pw-cat"];
        if let Some(missing) = programs.iter().find(|p| !on_path(p)) {
            eprintln!("skipped: {missing} is not installed");
            return None;
        }
        let data = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/session");
        // Short: the PipeWire socket path must fit in sun_path.
        let dir = std::env::temp_dir().join(format!("audiod-{}", std::process::id()));
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
        ];
        let bus = zbus::blocking::connection::Builder::address(address.as_str())
            .unwrap()
            .build()
            .unwrap();
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
        let dbus = zbus::blocking::fdo::DBusProxy::new(&self.bus).unwrap();
        eventually("org.marathonos.Audio", || {
            dbus.name_has_owner("org.marathonos.Audio".try_into().unwrap())
                .unwrap_or(false)
        });
        Proxy::new(
            &self.bus,
            "org.marathonos.Audio",
            "/org/marathonos/Audio",
            "org.marathonos.Audio1",
        )
        .unwrap()
    }

    fn wpctl_volume(&self, node: &str) -> String {
        self.output("wpctl", &["get-volume", node])
            .unwrap_or_default()
            .trim()
            .to_owned()
    }
}

fn property<T>(audio: &Proxy<'_>, name: &str) -> T
where
    T: TryFrom<zbus::zvariant::OwnedValue>,
    T::Error: Into<zbus::Error>,
{
    audio.get_property::<T>(name).unwrap()
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
    let Some(session) = Session::start() else {
        return;
    };
    let audio = session.audio();

    // The initial graph, as WirePlumber chose it.
    assert_eq!(property::<String>(&audio, "DefaultSink"), "test-sink-a");
    let sinks: Vec<(String, String)> = property(&audio, "Sinks");
    assert!(sinks.contains(&("test-sink-b".into(), "Test Sink B".into())));
    assert!((property::<f64>(&audio, "Volume") - 1.0).abs() < 1e-3);

    // Volume is the level wpctl shows, and PropertiesChanged carries it.
    audio.call_method("SetVolume", &(0.5f64)).unwrap();
    assert_eq!(session.wpctl_volume("@DEFAULT_AUDIO_SINK@"), "Volume: 0.50");
    eventually("Volume to follow", || {
        (property::<f64>(&audio, "Volume") - 0.5).abs() < 1e-3
    });

    audio.call_method("SetMuted", &(true)).unwrap();
    assert_eq!(
        session.wpctl_volume("@DEFAULT_AUDIO_SINK@"),
        "Volume: 0.50 [MUTED]"
    );
    eventually("Muted to follow", || property::<bool>(&audio, "Muted"));

    // A new default is WirePlumber's to apply; the levels follow it.
    audio
        .call_method("SetDefaultSink", &("test-sink-b"))
        .unwrap();
    eventually("the default sink to move", || {
        property::<String>(&audio, "DefaultSink") == "test-sink-b"
    });
    assert!(!property::<bool>(&audio, "Muted"));
    assert!(audio
        .call_method("SetDefaultSink", &("no-such-sink"))
        .is_ok());
    assert_eq!(property::<String>(&audio, "DefaultSink"), "test-sink-b");

    // Microphone mute, for calls.
    eventually("a default source", || {
        property::<String>(&audio, "DefaultSource") == "test-mic"
    });
    audio.call_method("SetInputMuted", &(true)).unwrap();
    assert_eq!(
        session.wpctl_volume("@DEFAULT_AUDIO_SOURCE@"),
        "Volume: 1.00 [MUTED]"
    );
    eventually("InputMuted to follow", || {
        property::<bool>(&audio, "InputMuted")
    });

    // The speakerphone choice is a WirePlumber setting for its call policy.
    audio.call_method("SetSpeakerphone", &(true)).unwrap();
    eventually("Speakerphone to follow", || {
        property::<bool>(&audio, "Speakerphone")
    });

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
    audio.call_method("SetStreamVolume", &(id, 0.5f64)).unwrap();
    assert_eq!(session.wpctl_volume(&id.to_string()), "Volume: 0.50");
    eventually("the stream's volume to follow", || {
        let s: Vec<(u32, String, f64, bool)> = property(&audio, "Streams");
        s.iter()
            .any(|(i, _, v, _)| *i == id && (v - 0.5).abs() < 1e-3)
    });
}
