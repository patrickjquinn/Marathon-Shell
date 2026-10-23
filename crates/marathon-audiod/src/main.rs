//! Marathon's audio service: `org.marathonos.Audio` on the session bus.
//!
//! A `PipeWire` client for the levels and defaults the shell shows: the
//! media volume and mute (the Multimedia role's under `WirePlumber`'s
//! role policy, else the default sink's), the default source's, the sinks
//! and sources to choose from, per-app playback streams, and the in-call
//! speakerphone choice. Policy (which device, which profile, call routing)
//! is `WirePlumber`'s; this service only writes what its policy reads:
//! node and device route props, the `default` metadata and `sm-settings`.

mod graph;
mod pw;

use std::process::ExitCode;
use std::sync::{mpsc, Arc, Mutex, MutexGuard};
use std::thread;

use zbus::{fdo, interface};

use graph::{Direction, Op, Port, Snapshot};
use pw::Request;

const BUS_NAME: &str = "org.marathonos.Audio";
const PATH: &str = "/org/marathonos/Audio";

#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn log(message: &str) {
    eprintln!("marathon-audiod: {message}");
}

fn lock(snapshot: &Mutex<Snapshot>) -> MutexGuard<'_, Snapshot> {
    snapshot.lock().unwrap_or_else(|_| std::process::abort())
}

fn ports(ports: &[Port]) -> Vec<(String, String)> {
    ports
        .iter()
        .map(|p| (p.name.clone(), p.description.clone()))
        .collect()
}

fn level(value: f64) -> fdo::Result<f64> {
    if value.is_finite() {
        Ok(value.clamp(0.0, 1.0))
    } else {
        Err(fdo::Error::InvalidArgs("volume is not a number".into()))
    }
}

struct Audio {
    requests: ::pipewire::channel::Sender<Request>,
    snapshot: Arc<Mutex<Snapshot>>,
}

impl Audio {
    async fn request(&self, op: Op) -> fdo::Result<()> {
        let (done, finished) = async_channel::bounded(1);
        self.requests
            .send(Request { op, done })
            .map_err(|_request| fdo::Error::Failed("PipeWire is gone".into()))?;
        finished
            .recv()
            .await
            .map_err(|e| fdo::Error::Failed(e.to_string()))
    }
}

#[interface(name = "org.marathonos.Audio1")]
impl Audio {
    #[zbus(property)]
    fn volume(&self) -> f64 {
        lock(&self.snapshot).volume
    }

    #[zbus(property)]
    fn muted(&self) -> bool {
        lock(&self.snapshot).muted
    }

    #[zbus(property)]
    fn input_volume(&self) -> f64 {
        lock(&self.snapshot).input_volume
    }

    #[zbus(property)]
    fn input_muted(&self) -> bool {
        lock(&self.snapshot).input_muted
    }

    #[zbus(property)]
    fn default_sink(&self) -> String {
        lock(&self.snapshot).default_sink.clone()
    }

    #[zbus(property)]
    fn default_source(&self) -> String {
        lock(&self.snapshot).default_source.clone()
    }

    /// `(node name, description)` of every sink.
    #[zbus(property)]
    fn sinks(&self) -> Vec<(String, String)> {
        ports(&lock(&self.snapshot).sinks)
    }

    #[zbus(property)]
    fn sources(&self) -> Vec<(String, String)> {
        ports(&lock(&self.snapshot).sources)
    }

    /// `(id, name, volume, muted)` of every playback stream.
    #[zbus(property)]
    fn streams(&self) -> Vec<(u32, String, f64, bool)> {
        lock(&self.snapshot)
            .streams
            .iter()
            .map(|s| (s.id, s.name.clone(), s.volume, s.muted))
            .collect()
    }

    #[zbus(property)]
    fn speakerphone(&self) -> bool {
        lock(&self.snapshot).speakerphone
    }

    async fn set_volume(&self, volume: f64) -> fdo::Result<()> {
        self.request(Op::Volume(Direction::Output, level(volume)?))
            .await
    }

    async fn set_muted(&self, muted: bool) -> fdo::Result<()> {
        self.request(Op::Muted(Direction::Output, muted)).await
    }

    async fn set_input_volume(&self, volume: f64) -> fdo::Result<()> {
        self.request(Op::Volume(Direction::Input, level(volume)?))
            .await
    }

    async fn set_input_muted(&self, muted: bool) -> fdo::Result<()> {
        self.request(Op::Muted(Direction::Input, muted)).await
    }

    async fn set_default_sink(&self, name: String) -> fdo::Result<()> {
        self.request(Op::Default(Direction::Output, name)).await
    }

    async fn set_default_source(&self, name: String) -> fdo::Result<()> {
        self.request(Op::Default(Direction::Input, name)).await
    }

    async fn set_stream_volume(&self, id: u32, volume: f64) -> fdo::Result<()> {
        self.request(Op::StreamVolume(id, level(volume)?)).await
    }

    async fn set_stream_muted(&self, id: u32, muted: bool) -> fdo::Result<()> {
        self.request(Op::StreamMuted(id, muted)).await
    }

    async fn set_speakerphone(&self, on: bool) -> fdo::Result<()> {
        self.request(Op::Speakerphone(on)).await
    }
}

/// Emits `PropertiesChanged` for what differs between two snapshots.
fn emit(conn: &zbus::blocking::Connection, old: &Snapshot, new: &Snapshot) -> zbus::Result<()> {
    let iface = conn.object_server().interface::<_, Audio>(PATH)?;
    let audio = iface.get();
    let e = iface.signal_emitter();
    if old.volume.to_bits() != new.volume.to_bits() {
        zbus::block_on(audio.volume_changed(e))?;
    }
    if old.muted != new.muted {
        zbus::block_on(audio.muted_changed(e))?;
    }
    if old.input_volume.to_bits() != new.input_volume.to_bits() {
        zbus::block_on(audio.input_volume_changed(e))?;
    }
    if old.input_muted != new.input_muted {
        zbus::block_on(audio.input_muted_changed(e))?;
    }
    if old.default_sink != new.default_sink {
        zbus::block_on(audio.default_sink_changed(e))?;
    }
    if old.default_source != new.default_source {
        zbus::block_on(audio.default_source_changed(e))?;
    }
    if old.sinks != new.sinks {
        zbus::block_on(audio.sinks_changed(e))?;
    }
    if old.sources != new.sources {
        zbus::block_on(audio.sources_changed(e))?;
    }
    if old.streams != new.streams {
        zbus::block_on(audio.streams_changed(e))?;
    }
    if old.speakerphone != new.speakerphone {
        zbus::block_on(audio.speakerphone_changed(e))?;
    }
    Ok(())
}

/// Publishes the latest snapshot of each burst.
fn publisher(
    conn: &zbus::blocking::Connection,
    shared: &Mutex<Snapshot>,
    snapshots: &mpsc::Receiver<Snapshot>,
) {
    while let Ok(first) = snapshots.recv() {
        let new = snapshots.try_iter().last().unwrap_or(first);
        let old = std::mem::replace(&mut *lock(shared), new.clone());
        if let Err(e) = emit(conn, &old, &new) {
            log(&format!("emitting PropertiesChanged: {e}"));
        }
    }
}

fn main() -> ExitCode {
    ::pipewire::init();
    let (requests, incoming) = ::pipewire::channel::channel();
    let snapshot = Arc::new(Mutex::new(Snapshot::default()));
    let audio = Audio {
        requests,
        snapshot: Arc::clone(&snapshot),
    };
    let conn = match zbus::blocking::connection::Builder::session()
        .and_then(|b| b.serve_at(PATH, audio))
        .and_then(zbus::blocking::connection::Builder::build)
    {
        Ok(conn) => conn,
        Err(e) => {
            log(&format!("cannot serve {PATH}: {e}"));
            return ExitCode::FAILURE;
        }
    };

    let (snapshots, published) = mpsc::channel();
    {
        let conn = conn.clone();
        thread::spawn(move || publisher(&conn, &snapshot, &published));
    }

    // The name is taken once the graph is known, so the first GetAll after
    // activation sees the real levels.
    let result = pw::run(
        incoming,
        move |s| {
            snapshots.send(s).ok();
        },
        move || {
            if let Err(e) = conn.request_name(BUS_NAME) {
                log(&format!("cannot own {BUS_NAME}: {e}"));
                std::process::exit(1);
            }
        },
    );
    match result {
        // The connection to PipeWire went away; systemd restarts us.
        Ok(()) => ExitCode::FAILURE,
        Err(e) => {
            log(&format!("PipeWire: {e}"));
            ExitCode::FAILURE
        }
    }
}
