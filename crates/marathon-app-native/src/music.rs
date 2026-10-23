//! `MusicLibrary`: the songs under Music, by folder: `<artist>/<album>/<title>`.
//! A scan only walks the folder, so it is the store; each song's id is a
//! hash of its path, the same from one scan to the next.

use std::path::{Path, PathBuf};
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};

use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QList_QVariant, artists, READ, NOTIFY = library_changed)]
        #[qproperty(i32, track_count, cxx_name = "trackCount", READ, NOTIFY = library_changed)]
        #[qproperty(bool, is_scanning, cxx_name = "isScanning", READ, NOTIFY = scanning_changed)]
        #[qproperty(i32, scan_progress, cxx_name = "scanProgress", READ, NOTIFY = scan_progress_changed)]
        type MusicLibrary = super::MusicLibraryRust;

        #[qsignal]
        #[cxx_name = "libraryChanged"]
        fn library_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "scanningChanged"]
        fn scanning_changed(self: Pin<&mut Self>, scanning: bool);
        #[qsignal]
        #[cxx_name = "scanComplete"]
        fn scan_complete(self: Pin<&mut Self>, track_count: i32);
        #[qsignal]
        #[cxx_name = "scanProgressChanged"]
        fn scan_progress_changed(self: Pin<&mut Self>, progress: i32);
        #[qsignal]
        #[cxx_name = "tracksLoaded"]
        fn tracks_loaded(self: Pin<&mut Self>, tracks: &QList_QVariant);

        #[qinvokable]
        #[cxx_name = "scanLibraryAsync"]
        fn scan_library_async(self: Pin<&mut MusicLibrary>);
        #[qinvokable]
        #[cxx_name = "loadTracksAsync"]
        fn load_tracks_async(self: &MusicLibrary);
    }

    impl cxx_qt::Threading for MusicLibrary {}
}

use qobject::MusicLibrary;

const AUDIO: &[&str] = &["mp3", "m4a", "flac", "ogg", "opus", "wav", "aac", "wma"];

#[derive(Default)]
pub struct MusicLibraryRust {
    artists: QList<QVariant>,
    track_count: i32,
    is_scanning: bool,
    scan_progress: i32,
    watching: bool,
}

#[derive(Debug, PartialEq)]
struct Track {
    id: i32,
    path: String,
    title: String,
    artist: String,
    album: String,
}

fn name(path: Option<&Path>) -> Option<String> {
    path?.file_name().map(|n| n.to_string_lossy().into_owned())
}

/// The songs under `root`, by artist, then album, then file.
fn scan(root: &Path) -> Vec<Track> {
    let mut tracks: Vec<Track> = walkdir::WalkDir::new(root)
        .into_iter()
        .flatten()
        .filter(|e| {
            e.file_type().is_file()
                && e.path().extension().is_some_and(|x| {
                    AUDIO.contains(&x.to_string_lossy().to_ascii_lowercase().as_str())
                })
        })
        .map(|e| {
            let path = e.path().to_string_lossy().into_owned();
            let hash = path.bytes().fold(0x811c_9dc5_u32, |h, b| {
                (h ^ u32::from(b)).wrapping_mul(0x0100_0193)
            });
            let album = e.path().parent();
            Track {
                id: i32::try_from(hash >> 1).unwrap_or_default().max(1),
                title: e
                    .path()
                    .file_stem()
                    .map(|s| s.to_string_lossy().into_owned())
                    .unwrap_or_default(),
                album: name(album).unwrap_or_else(|| "Unknown Album".into()),
                artist: name(album.and_then(Path::parent))
                    .unwrap_or_else(|| "Unknown Artist".into()),
                path,
            }
        })
        .collect();
    tracks.sort_by(|a, b| (&a.artist, &a.album, &a.path).cmp(&(&b.artist, &b.album, &b.path)));
    tracks
}

/// Scans again two seconds after songs come or go under Music, at any depth.
fn watch(qt: cxx_qt::CxxQtThread<MusicLibrary>) {
    use inotify::{Inotify, WatchMask};
    std::thread::spawn(move || -> std::io::Result<()> {
        let mut inotify = Inotify::init()?;
        let mask = WatchMask::CREATE
            | WatchMask::DELETE
            | WatchMask::MOVED_FROM
            | WatchMask::MOVED_TO
            | WatchMask::CLOSE_WRITE;
        let mut buffer = [0; 4096];
        loop {
            for dir in walkdir::WalkDir::new(music_dir())
                .into_iter()
                .flatten()
                .filter(|e| e.file_type().is_dir())
            {
                inotify.watches().add(dir.path(), mask).ok();
            }
            inotify.read_events_blocking(&mut buffer)?;
            std::thread::sleep(std::time::Duration::from_secs(2));
            qt.queue(MusicLibrary::scan_library_async).ok();
        }
    });
}

fn music_dir() -> PathBuf {
    let dir = dirs::audio_dir()
        .or_else(|| dirs::home_dir().map(|h| h.join("Music")))
        .unwrap_or_default();
    std::fs::create_dir_all(&dir).ok();
    dir
}

fn map(entries: &[(&str, QVariant)]) -> QVariant {
    let mut map = QMap::<QMapPair_QString_QVariant>::default();
    for (key, value) in entries {
        map.insert(QString::from(*key), value.clone());
    }
    QVariant::from(&map)
}

fn text(value: &str) -> QVariant {
    QVariant::from(&QString::from(value))
}

fn count(n: usize) -> i32 {
    i32::try_from(n).unwrap_or(i32::MAX)
}

/// `[{name, albumCount, trackCount}]` by artist.
fn artists(tracks: &[Track]) -> QList<QVariant> {
    let mut out = QList::default();
    for group in tracks.chunk_by(|a, b| a.artist == b.artist) {
        let mut albums: Vec<&str> = group.iter().map(|t| t.album.as_str()).collect();
        albums.dedup();
        out.append(map(&[
            ("name", text(&group[0].artist)),
            ("albumCount", QVariant::from(&count(albums.len()))),
            ("trackCount", QVariant::from(&count(group.len()))),
        ]));
    }
    out
}

impl MusicLibrary {
    fn scan_library_async(mut self: Pin<&mut Self>) {
        if self.is_scanning {
            return;
        }
        self.as_mut().rust_mut().is_scanning = true;
        self.as_mut().scanning_changed(true);
        self.as_mut().rust_mut().scan_progress = 0;
        self.as_mut().scan_progress_changed(0);
        let qt = self.qt_thread();
        if !std::mem::replace(&mut self.as_mut().rust_mut().watching, true) {
            watch(qt.clone());
        }
        io::spawn(async move {
            let tracks = blocking::unblock(|| scan(&music_dir())).await;
            qt.queue(move |mut obj| {
                let total = count(tracks.len());
                let mut m = obj.as_mut().rust_mut();
                m.artists = artists(&tracks);
                m.track_count = total;
                m.is_scanning = false;
                m.scan_progress = 100;
                obj.as_mut().scan_progress_changed(100);
                obj.as_mut().scanning_changed(false);
                obj.as_mut().scan_complete(total);
                obj.library_changed();
            })
            .ok();
        });
    }

    fn load_tracks_async(&self) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let tracks = blocking::unblock(|| scan(&music_dir())).await;
            qt.queue(move |obj| {
                let mut list = QList::default();
                for t in &tracks {
                    list.append(map(&[
                        ("id", QVariant::from(&t.id)),
                        ("path", text(&format!("file://{}", t.path))),
                        ("title", text(&t.title)),
                        ("artist", text(&t.artist)),
                        ("album", text(&t.album)),
                        ("duration", QVariant::from(&0_i32)),
                        ("trackNumber", QVariant::from(&0_i32)),
                    ]));
                }
                obj.tracks_loaded(&list);
            })
            .ok();
        });
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn touch(root: &Path, file: &str) {
        let path = root.join(file);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, b"").unwrap();
    }

    #[test]
    fn songs_are_found_by_folder() {
        let dir = tempfile::tempdir().unwrap();
        touch(dir.path(), "Bo/Ice/Cold.flac");
        touch(dir.path(), "Ava/Sky/Blue.mp3");
        touch(dir.path(), "Bo/Ice/notes.txt");
        let tracks = scan(dir.path());
        let titles: Vec<(&str, &str, &str)> = tracks
            .iter()
            .map(|t| (t.artist.as_str(), t.album.as_str(), t.title.as_str()))
            .collect();
        assert_eq!(titles, [("Ava", "Sky", "Blue"), ("Bo", "Ice", "Cold")]);
    }

    // Keel actions and playlists name songs by id between scans.
    #[test]
    fn a_rescan_keeps_ids() {
        let dir = tempfile::tempdir().unwrap();
        touch(dir.path(), "Ava/Sky/Blue.mp3");
        touch(dir.path(), "Bo/Ice/Cold.flac");
        let before = scan(dir.path());
        std::fs::remove_file(dir.path().join("Ava/Sky/Blue.mp3")).unwrap();
        touch(dir.path(), "Cy/Sun/Dawn.ogg");
        let after = scan(dir.path());
        assert_eq!(after.len(), 2);
        assert_eq!(after[0].id, before[1].id);
        assert!(after.iter().all(|t| t.id > 0));
    }
}
