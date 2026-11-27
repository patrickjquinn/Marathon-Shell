//! `Privacy`: who has the camera or the microphone open, from the kernel's
//! own open and close events on their device nodes (inotify), so no app,
//! sandboxed or not, uses them unseen. A thread blocks on the events; nothing
//! polls. Holders are named by app id where the gate knows them, else by
//! process; one the shell may not look into (root's call audio) still counts.
//! The camera's holders are all the user's, so /proc alone answers for it:
//! inotify merges back-to-back closes, which left its count stuck above zero.
//! PipeWire holds the microphone for its clients: marathon-audiod names them.
//!
//! Also the side privacy switch (`SW_MUTE_DEVICE`), where a device has one:
//! on, it cuts what Settings has it cover. Microphones and cameras are cut
//! at their device nodes by a root helper, and PipeWire's input is muted for
//! a stream already running; location is cut at `GeoClue`'s agent. Its other
//! mode is a silent switch.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::OnceLock;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QString, QStringList};
use inotify::{EventMask, Inotify, WatchDescriptor, WatchMask};

use crate::{gate, io, log, security};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, camera, READ, NOTIFY = changed)]
        #[qproperty(bool, microphone, READ, NOTIFY = changed)]
        /// Who: app ids, else process names; empty for one the shell may
        /// not look into.
        #[qproperty(QStringList, camera_users, cxx_name = "cameraUsers", READ, NOTIFY = changed)]
        #[qproperty(QStringList, microphone_users, cxx_name = "microphoneUsers", READ, NOTIFY = changed)]
        /// The privacy switch: whether the device has one, and its position.
        #[qproperty(bool, switch_available, cxx_name = "switchAvailable", READ, NOTIFY = switch_changed)]
        #[qproperty(bool, switched, READ, NOTIFY = switch_changed)]
        /// What the switch does: "silent", else the comma list of what it
        /// cuts ("microphone", "camera", "location"); the setting.
        #[qproperty(QString, covers, READ, WRITE = set_covers, NOTIFY = switch_changed)]
        /// What the switch cuts now.
        #[qproperty(QStringList, blocked, READ, NOTIFY = switch_changed)]
        type Privacy = super::PrivacyRust;

        #[qsignal]
        fn changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "switchChanged"]
        fn switch_changed(self: Pin<&mut Self>);

        #[cxx_name = "setCovers"]
        fn set_covers(self: Pin<&mut Privacy>, covers: &QString);
    }

    impl cxx_qt::Threading for Privacy {}
    impl cxx_qt::Initialize for Privacy {}
}

use qobject::Privacy;

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "each is a QML property")]
pub struct PrivacyRust {
    camera: bool,
    microphone: bool,
    camera_users: QStringList,
    microphone_users: QStringList,
    /// The capture devices' holders, PipeWire among them.
    holding: Vec<String>,
    /// PipeWire's recording clients.
    recording: Vec<String>,
    switch_available: bool,
    switched: bool,
    covers: QString,
    blocked: QStringList,
}

static PRIVACY: OnceLock<cxx_qt::CxxQtThread<Privacy>> = OnceLock::new();
/// The switch cuts the microphone: the call's mute keeps the input muted.
static MICROPHONE_BLOCKED: AtomicBool = AtomicBool::new(false);
static CAMERA_BLOCKED: AtomicBool = AtomicBool::new(false);
/// Cuts for the root helper, the latest first.
static CUTS: OnceLock<async_channel::Sender<String>> = OnceLock::new();
const HELPER: &str = "/usr/libexec/marathon-privacy";

/// The switch's last position, 0 before it is read: the key thread can
/// read it before this object exists.
static POSITION: AtomicU8 = AtomicU8::new(0);

/// The privacy switch moved, or was read at start.
pub fn switched(on: bool) {
    POSITION.store(1 + u8::from(on), Ordering::Relaxed);
    let Some(qt) = PRIVACY.get() else { return };
    qt.queue(move |mut obj| {
        // The first reading runs the helper: it gives back a cut from before a restart.
        let first = !obj.switch_available;
        let mut rust = obj.as_mut().rust_mut();
        rust.switch_available = true;
        rust.switched = on;
        obj.as_mut().apply(first);
        if obj.covers == QString::from("silent") {
            crate::settings::with(move |s| s.set_dnd_enabled(on));
        }
    })
    .ok();
}

pub fn microphone_blocked() -> bool {
    MICROPHONE_BLOCKED.load(Ordering::Relaxed)
}

/// For apps: the camera app says why it has no camera.
pub fn camera_blocked() -> bool {
    CAMERA_BLOCKED.load(Ordering::Relaxed)
}

/// What a switch in `covers` cuts while on.
fn cuts(covers: &str) -> Vec<&'static str> {
    ["microphone", "camera", "location"]
        .into_iter()
        .filter(|k| covers.split(',').any(|c| c.trim() == *k))
        .collect()
}

/// Hands the device cuts to the root helper, one run at a time.
fn cut_devices(blocked: &[&str]) {
    let devices: Vec<&str> = blocked
        .iter()
        .copied()
        .filter(|k| *k != "location")
        .collect();
    let command = format!("block {}", devices.join(" "));
    let tx = CUTS.get_or_init(|| {
        let (tx, rx) = async_channel::unbounded::<String>();
        io::spawn(async move {
            while let Ok(mut command) = rx.recv().await {
                while let Ok(newer) = rx.try_recv() {
                    command = newer;
                }
                if security::run_helper(HELPER, command.trim_end(), "").await != Some(0) {
                    log::warn("privacy", format_args!("{command} failed"));
                }
            }
        });
        tx
    });
    tx.try_send(command).ok();
}

/// PipeWire's recording streams, `(client pid, app)`, from marathon-audiod.
pub fn recording(streams: &[(u32, String)]) {
    let Some(qt) = PRIVACY.get() else { return };
    let mut names: Vec<String> = streams
        .iter()
        .map(|(pid, app)| {
            (*pid != 0)
                .then(|| gate::resolve(*pid))
                .flatten()
                .unwrap_or_else(|| app.clone())
        })
        .collect();
    names.sort();
    names.dedup();
    qt.queue(move |mut obj| {
        obj.as_mut().rust_mut().recording = names;
        obj.as_mut().publish();
    })
    .ok();
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Kind {
    Camera,
    Microphone,
}

/// The device nodes behind each: video, media and sensor sub-devices; the
/// capture PCMs.
fn nodes() -> Vec<(Kind, PathBuf)> {
    let list = |dir: &str, keep: &dyn Fn(&str) -> bool| -> Vec<PathBuf> {
        fs::read_dir(dir)
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.file_name().to_str().is_some_and(keep))
            .map(|e| e.path())
            .collect()
    };
    let camera = |n: &str| {
        ["video", "media", "v4l-subdev"]
            .iter()
            .any(|p| n.starts_with(p) && n[p.len()..].chars().all(|c| c.is_ascii_digit()))
    };
    let capture = |n: &str| n.starts_with("pcmC") && n.ends_with('c');
    let mut nodes: Vec<(Kind, PathBuf)> = list("/dev", &camera)
        .into_iter()
        .map(|p| (Kind::Camera, p))
        .collect();
    nodes.extend(
        list("/dev/snd", &capture)
            .into_iter()
            .map(|p| (Kind::Microphone, p)),
    );
    nodes
}

/// The processes holding any of `paths` open, as far as /proc shows them.
fn holders(paths: &[&Path]) -> Vec<(u32, PathBuf)> {
    let mut found = Vec::new();
    for entry in fs::read_dir("/proc").into_iter().flatten().flatten() {
        let Some(pid) = entry
            .file_name()
            .to_str()
            .and_then(|n| n.parse::<u32>().ok())
        else {
            continue;
        };
        let Ok(fds) = fs::read_dir(entry.path().join("fd")) else {
            continue;
        };
        for fd in fds.flatten() {
            if let Ok(target) = fs::read_link(fd.path()) {
                if paths.iter().any(|p| *p == target) {
                    found.push((pid, target));
                }
            }
        }
    }
    found
}

/// An app id, else the process's name.
pub fn name(pid: u32) -> String {
    gate::resolve(pid).unwrap_or_else(|| {
        fs::read_to_string(format!("/proc/{pid}/comm")).map_or_default(|c| c.trim().to_owned())
    })
}

struct Seen {
    camera: bool,
    microphone: bool,
    camera_users: Vec<String>,
    microphone_users: Vec<String>,
}

/// Whether `pid` is the FM radio's capture: its tuner's audio comes in
/// through a capture PCM, and is no microphone.
fn tuner(pid: u32) -> bool {
    let parent = fs::read_to_string(format!("/proc/{pid}/stat"))
        .ok()
        .and_then(|stat| {
            stat.rsplit(')')
                .next()?
                .split_whitespace()
                .nth(1)?
                .parse::<u32>()
                .ok()
        });
    parent
        .and_then(|p| fs::read_link(format!("/proc/{p}/exe")).ok())
        .is_some_and(|exe| exe.ends_with("marathon-radiod"))
}

/// The state from the open counts and the holders /proc shows.
fn see(nodes: &[(Kind, PathBuf)], open: &HashMap<PathBuf, u32>) -> Seen {
    let paths: Vec<&Path> = nodes.iter().map(|(_, p)| p.as_path()).collect();
    let (radio, held): (Vec<_>, Vec<_>) = holders(&paths)
        .into_iter()
        .partition(|(pid, _)| tuner(*pid));
    let kind_of = |path: &Path| nodes.iter().find(|(_, p)| p == path).map(|(k, _)| *k);
    let users = |kind: Kind| {
        let mut names: Vec<String> = held
            .iter()
            .filter(|(_, p)| kind_of(p) == Some(kind))
            .map(|(pid, _)| name(*pid))
            .filter(|n| !n.is_empty())
            .collect();
        names.sort();
        names.dedup();
        names
    };
    let camera_users = users(Kind::Camera);
    let microphone_users = users(Kind::Microphone);
    let counted = |kind: Kind| {
        nodes
            .iter()
            .filter(|(_, p)| !radio.iter().any(|(_, r)| r == p))
            .any(|(k, p)| *k == kind && open.get(p).copied().unwrap_or(0) > 0)
    };
    Seen {
        camera: !camera_users.is_empty(),
        microphone: !microphone_users.is_empty() || counted(Kind::Microphone),
        camera_users,
        microphone_users,
    }
}

fn list(names: &[String]) -> QStringList {
    let mut list = QStringList::default();
    for n in names {
        list.append(QString::from(n.as_str()));
    }
    list
}

fn watch(qt: &cxx_qt::CxxQtThread<Privacy>) -> std::io::Result<()> {
    let nodes = nodes();
    let mut inotify = Inotify::init()?;
    let mut by_watch: HashMap<WatchDescriptor, PathBuf> = HashMap::new();
    for (_, path) in &nodes {
        match inotify.watches().add(
            path,
            WatchMask::OPEN | WatchMask::CLOSE_WRITE | WatchMask::CLOSE_NOWRITE,
        ) {
            Ok(wd) => {
                by_watch.insert(wd, path.clone());
            }
            Err(e) => log::warn("privacy", format_args!("{}: {e}", path.display())),
        }
    }
    // Opens from before the watch: what /proc shows; root's are unseen until they close.
    let mut open: HashMap<PathBuf, u32> = HashMap::new();
    for (_, path) in holders(&nodes.iter().map(|(_, p)| p.as_path()).collect::<Vec<_>>()) {
        *open.entry(path).or_default() += 1;
    }
    let mut buffer = [0_u8; 4096];
    loop {
        let mut events = inotify.read_events_blocking(&mut buffer)?.peekable();
        loop {
            for event in events {
                let Some(path) = by_watch.get(&event.wd) else {
                    continue;
                };
                let count = open.entry(path.clone()).or_default();
                if event.mask.contains(EventMask::OPEN) {
                    *count += 1;
                } else {
                    *count = count.saturating_sub(1);
                }
            }
            // libcamera opens a dozen nodes at once: one look for the burst.
            std::thread::sleep(Duration::from_millis(100));
            match inotify.read_events(&mut buffer) {
                Ok(more) => {
                    events = more.peekable();
                    if events.peek().is_none() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        let seen = see(&nodes, &open);
        qt.queue(move |mut obj| obj.as_mut().update(seen)).ok();
    }
}

impl Privacy {
    fn set_covers(mut self: Pin<&mut Self>, covers: &QString) {
        if self.covers != *covers {
            self.as_mut().rust_mut().covers = covers.clone();
            self.as_mut().apply(false);
            self.switch_changed();
        }
    }

    /// Cuts what the switch covers while it is on, and gives the rest back.
    fn apply(mut self: Pin<&mut Self>, force: bool) {
        if !self.switch_available {
            return;
        }
        let covers = self.covers.to_string();
        let blocked = if self.switched {
            cuts(&covers)
        } else {
            Vec::new()
        };
        let list = list(&blocked.iter().map(|k| (*k).to_owned()).collect::<Vec<_>>());
        if self.blocked == list && !force {
            self.switch_changed();
            return;
        }
        let microphone = blocked.contains(&"microphone");
        if microphone != MICROPHONE_BLOCKED.swap(microphone, Ordering::Relaxed) {
            crate::modem::reroute_input();
        }
        if blocked.contains(&"camera")
            != CAMERA_BLOCKED.swap(blocked.contains(&"camera"), Ordering::Relaxed)
        {
            crate::power::state_changed();
        }
        cut_devices(&blocked);
        self.as_mut().rust_mut().blocked = list;
        self.switch_changed();
    }

    fn update(mut self: Pin<&mut Self>, seen: Seen) {
        let camera_users = list(&seen.camera_users);
        let changed = self.camera != seen.camera
            || self.microphone != seen.microphone
            || self.camera_users != camera_users;
        let mut rust = self.as_mut().rust_mut();
        rust.camera = seen.camera;
        rust.microphone = seen.microphone;
        rust.camera_users = camera_users;
        rust.holding = seen.microphone_users;
        if !self.as_mut().publish() && changed {
            self.changed();
        }
    }

    /// The microphone's users, PipeWire's clients in its place; whether they changed.
    fn publish(mut self: Pin<&mut Self>) -> bool {
        let mut users: Vec<String> = self
            .holding
            .iter()
            .filter(|n| *n != "pipewire" || self.recording.is_empty())
            .cloned()
            .collect();
        if self.holding.iter().any(|n| n == "pipewire") {
            users.extend(self.recording.iter().cloned());
        }
        users.sort();
        users.dedup();
        let users = list(&users);
        if self.microphone_users == users {
            return false;
        }
        self.as_mut().rust_mut().microphone_users = users;
        self.changed();
        true
    }
}

impl cxx_qt::Initialize for Privacy {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        PRIVACY.set(self.qt_thread()).ok();
        match POSITION.load(Ordering::Relaxed) {
            0 => {}
            p => switched(p == 2),
        }
        std::thread::Builder::new()
            .name("privacy".into())
            .spawn(move || {
                if let Err(e) = watch(&qt) {
                    log::warn("privacy", format_args!("not watching: {e}"));
                }
            })
            .ok();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_switch_cuts_only_what_it_covers() {
        assert_eq!(cuts("location,microphone"), ["microphone", "location"]);
        assert_eq!(
            cuts("microphone,camera,location"),
            ["microphone", "camera", "location"]
        );
        assert_eq!(cuts("silent"), Vec::<&str>::new());
        assert_eq!(cuts(""), Vec::<&str>::new());
    }

    #[test]
    fn a_stale_camera_count_does_not_light_the_dot_but_a_microphone_one_does() {
        let camera = PathBuf::from("/nonexistent/video0");
        let microphone = PathBuf::from("/nonexistent/pcmC0D0c");
        let nodes = [
            (Kind::Camera, camera.clone()),
            (Kind::Microphone, microphone.clone()),
        ];
        let open = HashMap::from([(camera, 1), (microphone, 1)]);
        let seen = see(&nodes, &open);
        assert!(!seen.camera);
        assert!(seen.microphone);
    }
}
