//! `Captures` (QML `MarathonOS.Services`): the Camera app's photos and
//! videos on disk. The newest one and an image of it (the photo itself, a
//! video's poster frame), where the next one goes, and deleting it.
//! Capturing stays in the app's Qt Multimedia controller.

use std::fs;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::time::{SystemTime, UNIX_EPOCH};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QString, QUrl};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        /// The newest capture's file:// URL, "" for none.
        #[qproperty(QString, latest, READ, NOTIFY = changed)]
        /// An image of it, "" when a video has no poster.
        #[qproperty(QString, preview, READ, NOTIFY = changed)]
        type Captures = super::CapturesRust;

        #[qsignal]
        fn changed(self: Pin<&mut Self>);

        /// Where the next photo (`kind` "photo") or video goes.
        #[qinvokable]
        #[cxx_name = "nextPath"]
        fn next_path(self: &Captures, kind: &QString) -> QString;
        /// Where a video's poster frame goes.
        #[qinvokable]
        #[cxx_name = "posterPath"]
        fn poster_path_of(self: &Captures, video: &QString) -> QString;
        /// A capture the controller saved, as a URL or a path.
        #[qinvokable]
        fn add(self: Pin<&mut Captures>, capture: &QString);
        #[qinvokable]
        #[cxx_name = "deleteLatest"]
        fn delete_latest(self: Pin<&mut Captures>);
    }

    impl cxx_qt::Threading for Captures {}
    impl cxx_qt::Initialize for Captures {}
}

use qobject::Captures;

#[derive(Default)]
pub struct CapturesRust {
    latest: QString,
    preview: QString,
}

const KINDS: [&str; 4] = ["jpg", "jpeg", "png", "mp4"];

fn folder() -> PathBuf {
    dirs::picture_dir().unwrap_or_else(|| marathon_rt::dirs::home().join("Pictures")).join("Marathon")
}

fn poster_path(video: &Path) -> PathBuf {
    let name = video.file_stem().map_or_else(Default::default, |s| s.to_string_lossy().into_owned());
    dirs::cache_dir().unwrap_or_else(|| marathon_rt::dirs::home().join(".cache")).join("posters").join(format!("{name}.jpg"))
}

fn is_video(path: &Path) -> bool {
    path.extension().is_some_and(|e| e.eq_ignore_ascii_case("mp4"))
}

/// A photo is its own preview; a video, its poster if it has one.
fn preview_of(file: &Path) -> Option<PathBuf> {
    if !is_video(file) {
        return Some(file.to_owned());
    }
    Some(poster_path(file)).filter(|p| p.exists())
}

fn url(path: &Path) -> QString {
    QUrl::from_local_file(&QString::from(&*path.to_string_lossy())).to_qstring()
}

/// A URL or a plain path, as a path.
fn local(capture: &QString) -> PathBuf {
    let text = capture.to_string();
    if text.starts_with("file:") {
        PathBuf::from(QUrl::from(capture).to_local_file().map(|p| p.to_string()).unwrap_or_default())
    } else {
        PathBuf::from(text)
    }
}

/// The folder's newest capture, by modification time.
fn newest(dir: &Path) -> Option<PathBuf> {
    fs::read_dir(dir)
        .ok()?
        .flatten()
        .filter(|e| e.path().extension().is_some_and(|x| KINDS.iter().any(|k| x.eq_ignore_ascii_case(k))))
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .max_by_key(|(time, _)| *time)
        .map(|(_, path)| path)
}

impl cxx_qt::Initialize for Captures {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let Some(found) = newest(&folder()) else { return };
            qt.queue(move |obj| {
                if obj.latest.is_empty() {
                    obj.show(Some(&found));
                }
            })
            .ok();
        });
    }
}

impl Captures {
    fn show(mut self: Pin<&mut Self>, file: Option<&Path>) {
        let mut rust = self.as_mut().rust_mut();
        rust.latest = file.map(url).unwrap_or_default();
        rust.preview = file.and_then(preview_of).as_deref().map(url).unwrap_or_default();
        self.changed();
    }

    fn next_path(&self, kind: &QString) -> QString {
        let dir = folder();
        fs::create_dir_all(&dir).ok();
        let (prefix, extension) = if kind.to_string() == "video" { ("VID", "mp4") } else { ("IMG", "jpg") };
        let ms = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis());
        QString::from(&*dir.join(format!("{prefix}_{ms}.{extension}")).to_string_lossy())
    }

    fn poster_path_of(&self, video: &QString) -> QString {
        let path = poster_path(&local(video));
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir).ok();
        }
        QString::from(&*path.to_string_lossy())
    }

    fn add(self: Pin<&mut Self>, capture: &QString) {
        let file = local(capture);
        if file.exists() {
            self.show(Some(&file));
        }
    }

    fn delete_latest(self: Pin<&mut Self>) {
        let file = local(&self.latest);
        if file.as_os_str().is_empty() {
            return;
        }
        fs::remove_file(&file).ok();
        if is_video(&file) {
            fs::remove_file(poster_path(&file)).ok();
        }
        let next = newest(&folder());
        self.show(next.as_deref());
    }
}
