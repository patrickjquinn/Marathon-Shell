//! `MusicLibrary`: the songs under Music, by their tags; a song without
//! them is named by its folders, `<artist>/<album>/<title>`. A scan only
//! walks the folder, so it is the store; each song's id is a hash of its
//! path, the same from one scan to the next.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::Mutex;
use std::time::SystemTime;

use lofty::prelude::{Accessor as _, AudioFile as _, TaggedFileExt as _};

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
    /// Seconds.
    duration: i32,
    /// On its album.
    number: i32,
}

/// What a song's tags say; empty or 0 where they say nothing.
#[derive(Clone, Default)]
struct Tags {
    title: String,
    artist: String,
    album: String,
    duration: i32,
    track_number: i32,
}

/// Tags by path, kept while the file's modification time stays: the
/// library scans again on every change under Music.
static TAGS: Mutex<Option<HashMap<PathBuf, (SystemTime, Tags)>>> = Mutex::new(None);

fn read_tags(path: &Path) -> Tags {
    let Ok(tagged) = lofty::read_from_path(path) else {
        return Tags::default();
    };
    let millis = tagged.properties().duration().as_millis();
    let duration = i32::try_from((millis + 500) / 1000).unwrap_or(0);
    let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) else {
        return Tags {
            duration,
            ..Tags::default()
        };
    };
    let text = |v: Option<std::borrow::Cow<'_, str>>| v.map_or_default(|v| v.trim().to_owned());
    Tags {
        title: text(tag.title()),
        artist: text(tag.artist()),
        album: text(tag.album()),
        duration,
        track_number: tag.track().and_then(|n| i32::try_from(n).ok()).unwrap_or(0),
    }
}

fn tags(path: &Path) -> Tags {
    let modified = std::fs::metadata(path).and_then(|m| m.modified()).ok();
    let mut cache = TAGS
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let cache = cache.get_or_insert_with(HashMap::new);
    if let (Some(modified), Some((at, tags))) = (modified, cache.get(path)) {
        if *at == modified {
            return tags.clone();
        }
    }
    let read = read_tags(path);
    if let Some(modified) = modified {
        cache.insert(path.to_owned(), (modified, read.clone()));
    }
    read
}

fn or(tag: String, fallback: impl FnOnce() -> String) -> String {
    if tag.is_empty() {
        fallback()
    } else {
        tag
    }
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
            // Only folders inside Music name a song: one loose in Music
            // is not by its owner.
            let mut folders = e
                .path()
                .strip_prefix(root)
                .ok()
                .and_then(Path::parent)
                .into_iter()
                .flat_map(Path::components)
                .map(|c| c.as_os_str().to_string_lossy().into_owned())
                .collect::<Vec<_>>();
            let album_dir = folders.pop();
            let artist_dir = folders.pop();
            let tags = tags(e.path());
            Track {
                id: i32::try_from(hash >> 1).unwrap_or_default().max(1),
                title: or(tags.title, || {
                    e.path()
                        .file_stem()
                        .map_or_default(|s| s.to_string_lossy().into_owned())
                }),
                artist: or(tags.artist, || {
                    artist_dir.unwrap_or_else(|| "Unknown Artist".into())
                }),
                album: or(tags.album, || {
                    album_dir.unwrap_or_else(|| "Unknown Album".into())
                }),
                duration: tags.duration,
                number: tags.track_number,
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
                        ("duration", QVariant::from(&t.duration)),
                        ("trackNumber", QVariant::from(&t.number)),
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

    #[test]
    fn a_song_loose_in_music_is_not_by_its_owner() {
        let dir = tempfile::tempdir().unwrap();
        touch(dir.path(), "tone.opus");
        touch(dir.path(), "Ava/Blue.mp3");
        let tracks = scan(dir.path());
        let named: Vec<(&str, &str, &str)> = tracks
            .iter()
            .map(|t| (t.artist.as_str(), t.album.as_str(), t.title.as_str()))
            .collect();
        assert_eq!(
            named,
            [
                ("Unknown Artist", "Ava", "Blue"),
                ("Unknown Artist", "Unknown Album", "tone")
            ]
        );
    }

    #[test]
    fn tags_name_the_song() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("x/y/take.wav");
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        let ringtone = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../shell/resources/sounds/phone/bbpro1.wav"
        );
        std::fs::copy(ringtone, &file).unwrap();
        let tracks = scan(dir.path());
        // Tags over folders; 0.53 s rounds to a second.
        let t = &tracks[0];
        assert_eq!(
            (t.title.as_str(), t.artist.as_str(), t.duration),
            ("BB Pro 1", "phone", 1)
        );
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
