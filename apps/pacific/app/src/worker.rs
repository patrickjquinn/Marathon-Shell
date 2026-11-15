// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The core thread: owns the profile databases, the session store, the
//! filter lists and the compiled filter engine, and runs jobs queued from
//! the GUI thread one after another. Nothing here ever runs on the GUI
//! thread; results go back through each `QObject`'s `CxxQtThread::queue`.

use std::path::{Path, PathBuf};
use std::sync::mpsc;
use std::sync::OnceLock;

use pacific_core::blocker::lists::ListStore;
use pacific_core::blocker::Blocker;
use pacific_core::session::SessionStore;
use pacific_core::Profile;

/// Where things live. Sailjail gives the app these private directories
/// from OrganizationName/ApplicationName (org.shipwright/pacific).
#[derive(Debug, Clone)]
pub struct Dirs {
    pub data: PathBuf,
    pub cache: PathBuf,
    pub downloads: PathBuf,
    /// The package's read-only data: bundled filter lists, autoconsent.
    pub share: PathBuf,
}

fn home() -> PathBuf {
    std::env::var_os("HOME").map_or_else(|| PathBuf::from("/tmp"), PathBuf::from)
}

fn env_dir(name: &str) -> Option<PathBuf> {
    std::env::var_os(name)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
}

impl Dirs {
    /// From the environment: `PACIFIC_DATA`, `PACIFIC_CACHE`,
    /// `PACIFIC_DOWNLOADS`, `PACIFIC_SHARE` override the defaults.
    pub fn from_env() -> Self {
        let data = env_dir("PACIFIC_DATA").unwrap_or_else(|| {
            env_dir("XDG_DATA_HOME")
                .unwrap_or_else(|| home().join(".local/share"))
                .join("org.shipwright/pacific")
        });
        let cache = env_dir("PACIFIC_CACHE").unwrap_or_else(|| {
            env_dir("XDG_CACHE_HOME")
                .unwrap_or_else(|| home().join(".cache"))
                .join("org.shipwright/pacific")
        });
        let downloads = env_dir("PACIFIC_DOWNLOADS").unwrap_or_else(|| home().join("Downloads"));
        let share = env_dir("PACIFIC_SHARE")
            .unwrap_or_else(|| PathBuf::from("/usr/share/shipwright-pacific"));
        Self {
            data,
            cache,
            downloads,
            share,
        }
    }

    pub fn adblock(&self) -> PathBuf {
        self.cache.join("adblock")
    }

    pub fn lists(&self) -> PathBuf {
        self.data.join("filter-lists")
    }

    pub fn reader(&self) -> PathBuf {
        self.cache.join("reader")
    }

    pub fn favicons(&self) -> PathBuf {
        self.cache.join("favicons")
    }

    /// The cached icon of `icon_url` as a `file://` URL, or "" when not
    /// fetched (yet).
    pub fn favicon_url(&self, icon_url: &str) -> String {
        if icon_url.is_empty() {
            return String::new();
        }
        let f = pacific_core::favicons::file_for(&self.favicons(), icon_url);
        if f.exists() {
            file_url(&f)
        } else {
            String::new()
        }
    }

    pub fn thumbnails(&self) -> PathBuf {
        self.cache.join("thumbnails")
    }
}

/// Everything the core thread owns.
pub struct Core {
    pub dirs: Dirs,
    pub profile: Profile,
    /// The private session's profile: in memory, gone at exit.
    pub private: Profile,
    pub sessions: SessionStore,
    pub lists: ListStore,
    pub blocker: Option<Blocker>,
    /// Why the profile on disk could not be opened (then `profile` is in
    /// memory and nothing is kept).
    pub open_error: Option<String>,
}

impl Core {
    fn open(dirs: Dirs) -> Self {
        for d in [&dirs.data, &dirs.cache] {
            if let Err(e) = std::fs::create_dir_all(d) {
                log::warn!("cannot create {}: {e}", d.display());
            }
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = std::fs::set_permissions(d, std::fs::Permissions::from_mode(0o700));
            }
        }
        // The web view saves thumbnails and reader pages here; it does not
        // create directories.
        for d in [
            dirs.thumbnails(),
            dirs.reader(),
            dirs.adblock(),
            dirs.favicons(),
        ] {
            if let Err(e) = std::fs::create_dir_all(&d) {
                log::warn!("cannot create {}: {e}", d.display());
            }
        }
        let (profile, open_error) = match Profile::open(&dirs.data) {
            Ok(p) => (p, None),
            Err(e) => {
                log::error!("cannot open the profile in {}: {e}", dirs.data.display());
                (memory_profile(), Some(e.to_string()))
            }
        };
        let bundled = dirs.share.join("filter-lists");
        let lists = ListStore::open(&dirs.lists(), bundled.is_dir().then_some(bundled.as_path()));
        Self {
            sessions: SessionStore::new(&dirs.data),
            lists,
            profile,
            private: memory_profile(),
            blocker: None,
            open_error,
            dirs,
        }
    }

    /// The profile for a tab: the private one for private tabs.
    pub fn profile_for(&self, private: bool) -> &Profile {
        if private {
            &self.private
        } else {
            &self.profile
        }
    }
}

/// Opens a core for tests, without the thread.
#[cfg(test)]
pub fn open_core_for_tests(dirs: Dirs) -> Core {
    Core::open(dirs)
}

fn memory_profile() -> Profile {
    // An in-memory SQLite database only fails without memory.
    Profile::in_memory().unwrap_or_else(|e| panic!("cannot create an in-memory profile: {e}"))
}

pub type Job = Box<dyn FnOnce(&mut Core) + Send>;

struct Worker {
    tx: std::sync::Mutex<mpsc::Sender<Job>>,
}

static WORKER: OnceLock<Worker> = OnceLock::new();

fn start(dirs: Dirs) -> Worker {
    let (tx, rx) = mpsc::channel::<Job>();
    let spawned = std::thread::Builder::new()
        .name("pacific-core".into())
        .spawn(move || {
            let mut core = Core::open(dirs);
            while let Ok(job) = rx.recv() {
                // A failing job must not take the profile down with it.
                if std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| job(&mut core)))
                    .is_err()
                {
                    log::error!("a core job panicked");
                }
            }
            let _ = core.profile.checkpoint();
        });
    if let Err(e) = spawned {
        log::error!("cannot start the core thread: {e}");
    }
    Worker {
        tx: std::sync::Mutex::new(tx),
    }
}

/// Starts the core thread with `dirs` (the first call wins).
pub fn init(dirs: Dirs) {
    let _ = WORKER.get_or_init(|| start(dirs));
}

/// Queues `job` on the core thread.
pub fn run(job: impl FnOnce(&mut Core) + Send + 'static) {
    let w = WORKER.get_or_init(|| start(Dirs::from_env()));
    let sent = w.tx.lock().is_ok_and(|tx| tx.send(Box::new(job)).is_ok());
    if !sent {
        log::warn!("the core thread is gone; a request was dropped");
    }
}

/// Runs `job` on the core thread and waits for its answer (start-up and
/// tests only; never from a frame path).
pub fn call<T: Send + 'static>(job: impl FnOnce(&mut Core) -> T + Send + 'static) -> Option<T> {
    let (tx, rx) = mpsc::channel();
    run(move |c| {
        let _ = tx.send(job(c));
    });
    rx.recv().ok()
}

/// `path` as a `file://` URL string.
pub fn file_url(path: &Path) -> String {
    let mut u = String::from("file://");
    for part in path.to_string_lossy().split('/') {
        if !part.is_empty() {
            u.push('/');
            u.extend(url_part(part));
        }
    }
    u
}

fn url_part(s: &str) -> impl Iterator<Item = char> + '_ {
    s.chars().flat_map(|c| {
        let keep =
            c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.' | '~' | '(' | ')' | ' ');
        let out: Vec<char> = if keep {
            if c == ' ' {
                "%20".chars().collect()
            } else {
                vec![c]
            }
        } else {
            let mut b = [0u8; 4];
            c.encode_utf8(&mut b)
                .bytes()
                .flat_map(|x| format!("%{x:02X}").chars().collect::<Vec<_>>())
                .collect()
        };
        out.into_iter()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_urls() {
        assert_eq!(file_url(Path::new("/a b/c.html")), "file:///a%20b/c.html");
        assert_eq!(
            file_url(Path::new("/x/ä#?.html")),
            "file:///x/%C3%A4%23%3F.html"
        );
    }
}
