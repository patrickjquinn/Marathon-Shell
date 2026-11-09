//! `Privacy`: who has the camera or the microphone open, from the kernel's
//! own open and close events on their device nodes (inotify), so no app,
//! sandboxed or not, uses them unseen. A thread blocks on the events; nothing
//! polls. Holders are named by app id where the gate knows them, else by
//! process; one the shell may not look into (root's call audio) still counts.
//! PipeWire holds the microphone for its clients: marathon-audiod names them.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::OnceLock;
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QString, QStringList};
use inotify::{EventMask, Inotify, WatchDescriptor, WatchMask};

use crate::{gate, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
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
        type Privacy = super::PrivacyRust;

        #[qsignal]
        fn changed(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Privacy {}
    impl cxx_qt::Initialize for Privacy {}
}

use qobject::Privacy;

#[derive(Default)]
pub struct PrivacyRust {
    camera: bool,
    microphone: bool,
    camera_users: QStringList,
    microphone_users: QStringList,
    /// The capture devices' holders, PipeWire among them.
    holding: Vec<String>,
    /// PipeWire's recording clients.
    recording: Vec<String>,
}

static PRIVACY: OnceLock<cxx_qt::CxxQtThread<Privacy>> = OnceLock::new();

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
        fs::read_to_string(format!("/proc/{pid}/comm"))
            .map(|c| c.trim().to_owned())
            .unwrap_or_default()
    })
}

struct Seen {
    camera: bool,
    microphone: bool,
    camera_users: Vec<String>,
    microphone_users: Vec<String>,
}

/// The state from the open counts and the holders /proc shows.
fn see(nodes: &[(Kind, PathBuf)], open: &HashMap<PathBuf, u32>) -> Seen {
    let paths: Vec<&Path> = nodes.iter().map(|(_, p)| p.as_path()).collect();
    let held = holders(&paths);
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
            .any(|(k, p)| *k == kind && open.get(p).copied().unwrap_or(0) > 0)
    };
    Seen {
        camera: !camera_users.is_empty() || counted(Kind::Camera),
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
