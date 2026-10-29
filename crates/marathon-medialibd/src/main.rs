//! Marathon's photo and video library: `org.marathonos.MediaLibrary` on the
//! session bus, serving `MediaLibrary1` where the shell served it. Scans
//! and thumbnails run off the bus's thread; Pictures is watched for new
//! files. The shell admits each caller (`Permissions1.Admit`).

mod library;

use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use async_io::Timer;
use futures_lite::future;
use marathon_rt::daemon::{admit, shell_cache, shell_data, Shared};
use marathon_rt::{io, log};
use zbus::message::Header;
use zbus::object_server::SignalEmitter;
use zbus::{fdo, interface, Connection};
use zbus::{ObjectPath, Variant as Value};

use library::Library;

const BUS_NAME: &str = "org.marathonos.MediaLibrary";
const PATH: &str = "/org/marathonos/Shell/MediaLibrary";

#[derive(Default)]
struct Progress {
    scanning: bool,
    percent: i32,
}

#[derive(Clone)]
struct Core {
    bus: Connection,
    library: Shared<Library>,
    progress: Shared<Progress>,
}

fn pictures() -> Option<PathBuf> {
    dirs::picture_dir().or_else(|| dirs::home_dir().map(|h| h.join("Pictures")))
}

fn roots() -> Vec<PathBuf> {
    let mut roots: Vec<PathBuf> = pictures().into_iter().collect();
    for dir in &roots {
        std::fs::create_dir_all(dir).ok();
    }
    roots.extend(
        dirs::home_dir()
            .map(|h| h.join("DCIM"))
            .filter(|d| d.is_dir()),
    );
    roots
}

impl Core {
    fn emitter(&self) -> SignalEmitter<'static> {
        SignalEmitter::from_parts(
            self.bus.clone(),
            ObjectPath::from_static_str_unchecked(PATH),
        )
    }

    async fn show(&self, scanning: Option<bool>, percent: i32) {
        self.progress
            .with(move |p| {
                p.scanning = scanning.unwrap_or(p.scanning);
                p.percent = percent;
            })
            .await;
        let e = self.emitter();
        if let Some(scanning) = scanning {
            MediaLibrary::scanning_changed(&e, scanning).await.ok();
        }
        MediaLibrary::scan_progress_changed(&e, percent).await.ok();
    }

    /// Adds what is new under Pictures and DCIM, with thumbnails, and drops
    /// what went.
    async fn scan(&self) {
        if self
            .progress
            .with(|p| std::mem::replace(&mut p.scanning, true))
            .await
        {
            return;
        }
        self.show(Some(true), 0).await;
        let found = blocking::unblock(|| library::walk(&roots())).await;
        let todo = self
            .library
            .with(move |l| l.reconcile(found))
            .await
            .unwrap_or_else(|e| {
                log::warn("MediaLibrary", format_args!("cannot read the library: {e}"));
                Vec::new()
            });
        let total = todo.len();
        let e = self.emitter();
        for (done, file) in todo.into_iter().enumerate() {
            let (file, path) = self.library.with(move |l| (l.add(&file), file)).await;
            match file {
                Ok(true) => {
                    MediaLibrary::new_media_added(&e, path.path()).await.ok();
                }
                Ok(false) => {}
                Err(err) => log::warn(
                    "MediaLibrary",
                    format_args!("cannot add {}: {err}", path.path()),
                ),
            }
            if done % 25 == 24 {
                self.show(None, i32::try_from(done * 100 / total).unwrap_or(100))
                    .await;
            }
        }
        let (photos, videos) = self
            .library
            .with(|l| (l.count("photo"), l.count("video")))
            .await;
        MediaLibrary::albums_changed(&e).await.ok();
        MediaLibrary::scan_complete(&e, photos, videos).await.ok();
        MediaLibrary::library_changed(&e).await.ok();
        self.show(Some(false), 100).await;
    }
}

struct MediaLibrary(Core);

impl MediaLibrary {
    async fn admit(&self, h: &Header<'_>) -> fdo::Result<()> {
        admit(&self.0.bus, h, "MediaLibrary", &["storage"]).await
    }

    async fn rows(
        &self,
        h: &Header<'_>,
        kind: &'static str,
        album: Option<String>,
    ) -> fdo::Result<Vec<Value<'static>>> {
        self.admit(h).await?;
        let rows = self
            .0
            .library
            .with(move |l| l.items(kind, album.as_deref()))
            .await
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        Ok(rows.into_iter().map(Value::from).collect())
    }

    fn start_scan(&self) {
        let core = self.0.clone();
        io::spawn(async move { core.scan().await });
    }
}

#[interface(name = "org.marathonos.Shell.MediaLibrary1")]
impl MediaLibrary {
    async fn albums(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<Vec<Value<'static>>> {
        self.admit(&h).await?;
        let rows = self
            .0
            .library
            .with(|l| l.albums())
            .await
            .map_err(|e| fdo::Error::Failed(e.to_string()))?;
        Ok(rows.into_iter().map(Value::from).collect())
    }

    async fn is_scanning(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        self.admit(&h).await?;
        Ok(self.0.progress.with(|p| p.scanning).await)
    }

    async fn scan_progress(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<i32> {
        self.admit(&h).await?;
        Ok(self.0.progress.with(|p| p.percent).await)
    }

    async fn photo_count(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<i32> {
        self.admit(&h).await?;
        Ok(self.0.library.with(|l| l.count("photo")).await)
    }

    async fn video_count(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<i32> {
        self.admit(&h).await?;
        Ok(self.0.library.with(|l| l.count("video")).await)
    }

    async fn scan_library(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        self.admit(&h).await?;
        self.start_scan();
        Ok(())
    }

    async fn scan_library_async(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        self.admit(&h).await?;
        self.start_scan();
        Ok(())
    }

    async fn get_photos(
        &self,
        #[zbus(header)] h: Header<'_>,
        album_id: String,
    ) -> fdo::Result<Vec<Value<'static>>> {
        self.rows(&h, "photo", Some(album_id)).await
    }

    async fn get_all_photos(
        &self,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<Vec<Value<'static>>> {
        self.rows(&h, "photo", None).await
    }

    async fn get_videos(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<Vec<Value<'static>>> {
        self.rows(&h, "video", None).await
    }

    async fn generate_thumbnail(
        &self,
        #[zbus(header)] h: Header<'_>,
        file_path: String,
    ) -> fdo::Result<String> {
        self.admit(&h).await?;
        let path = file_path
            .strip_prefix("file://")
            .unwrap_or(&file_path)
            .to_owned();
        Ok(self
            .0
            .library
            .with(move |l| library::thumbnail(&path, &l.thumbnails, l.size))
            .await
            .unwrap_or_default())
    }

    async fn delete_media(&self, #[zbus(header)] h: Header<'_>, media_id: i32) -> fdo::Result<()> {
        self.admit(&h).await?;
        if self
            .0
            .library
            .with(move |l| l.delete(media_id))
            .await
            .map_err(|e| fdo::Error::Failed(e.to_string()))?
        {
            let e = self.0.emitter();
            Self::albums_changed(&e).await?;
            Self::library_changed(&e).await?;
        }
        Ok(())
    }

    #[zbus(signal)]
    async fn albums_changed(e: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn scanning_changed(e: &SignalEmitter<'_>, scanning: bool) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn scan_complete(
        e: &SignalEmitter<'_>,
        photo_count: i32,
        video_count: i32,
    ) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn new_media_added(e: &SignalEmitter<'_>, path: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn library_changed(e: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn scan_progress_changed(e: &SignalEmitter<'_>, progress: i32) -> zbus::Result<()>;
}

/// Scans two seconds after Pictures last changed.
async fn watch(core: Core) {
    let Some(pictures) = pictures() else { return };
    std::fs::create_dir_all(&pictures).ok();
    let (tx, rx) = async_channel::bounded::<()>(1);
    let follow = move || -> std::io::Result<()> {
        use inotify::{Inotify, WatchMask};
        let mut inotify = Inotify::init()?;
        let mask = WatchMask::CREATE
            | WatchMask::DELETE
            | WatchMask::MOVED_FROM
            | WatchMask::MOVED_TO
            | WatchMask::CLOSE_WRITE;
        inotify.watches().add(&pictures, mask)?;
        let mut buffer = [0; 4096];
        loop {
            inotify.read_events_blocking(&mut buffer)?;
            tx.try_send(()).ok();
        }
    };
    let watcher = std::thread::Builder::new()
        .name("pictures-watch".into())
        .spawn(move || {
            if let Err(e) = follow() {
                log::warn(
                    "MediaLibrary",
                    format_args!("stopped watching Pictures: {e}"),
                );
            }
        });
    if let Err(e) = watcher {
        return log::warn("MediaLibrary", format_args!("cannot watch Pictures: {e}"));
    }
    while rx.recv().await.is_ok() {
        loop {
            let quiet = future::or(async { rx.recv().await.is_err() }, async {
                Timer::after(Duration::from_secs(2)).await;
                true
            })
            .await;
            if quiet {
                break;
            }
        }
        core.scan().await;
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let size = std::env::var("MARATHON_THUMBNAIL_SIZE")
        .ok()
        .and_then(|s| s.parse().ok())
        .filter(|s| *s > 0)
        .unwrap_or(768);
    let library = Library::open(
        &shell_data().join("marathon/medialibrary.db"),
        shell_cache().join("marathon/thumbnails"),
        size,
    )?;
    let bus = io::session_bus().await?;
    let core = Core {
        bus: bus.clone(),
        library: Shared::new(library),
        progress: Shared::new(Progress::default()),
    };
    bus.object_server()
        .at(PATH, MediaLibrary(core.clone()))
        .await?;
    bus.request_name(BUS_NAME).await?;
    watch(core).await;
    future::pending().await
}

fn main() -> ExitCode {
    match async_io::block_on(run()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            log::warn("marathon-medialibd", e);
            ExitCode::FAILURE
        }
    }
}
