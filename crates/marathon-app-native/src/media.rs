//! `MediaLibrary`: the shell's `MediaLibrary1`, the photos and videos.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QString, QVariant};
use futures_lite::StreamExt;
use zbus::zvariant::OwnedValue;

use crate::shell::{allowed, answers, relay, Service};
use crate::variant;
use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QList_QVariant, albums, READ, NOTIFY)]
        #[qproperty(bool, is_scanning, cxx_name = "isScanning", READ, NOTIFY = scanning_changed)]
        #[qproperty(i32, photo_count, cxx_name = "photoCount", READ, NOTIFY = library_changed)]
        #[qproperty(i32, video_count, cxx_name = "videoCount", READ, NOTIFY = library_changed)]
        #[qproperty(i32, scan_progress, cxx_name = "scanProgress", READ, NOTIFY = scan_progress_changed)]
        type MediaLibrary = super::MediaLibraryRust;

        #[qsignal]
        #[cxx_name = "scanningChanged"]
        fn scanning_changed(self: Pin<&mut Self>, scanning: bool);
        #[qsignal]
        #[cxx_name = "scanComplete"]
        fn scan_complete(self: Pin<&mut Self>, photo_count: i32, video_count: i32);
        #[qsignal]
        #[cxx_name = "newMediaAdded"]
        fn new_media_added(self: Pin<&mut Self>, path: &QString);
        #[qsignal]
        #[cxx_name = "libraryChanged"]
        fn library_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "scanProgressChanged"]
        fn scan_progress_changed(self: Pin<&mut Self>, progress: i32);

        #[qinvokable]
        fn refresh(self: &MediaLibrary);
        #[qinvokable]
        #[cxx_name = "scanLibrary"]
        fn scan_library(self: &MediaLibrary);
        #[qinvokable]
        #[cxx_name = "scanLibraryAsync"]
        fn scan_library_async(self: &MediaLibrary);
        #[qinvokable]
        #[cxx_name = "getPhotos"]
        fn get_photos(self: &MediaLibrary, album_id: &QString) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "getAllPhotos"]
        fn get_all_photos(self: &MediaLibrary) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "getVideos"]
        fn get_videos(self: &MediaLibrary) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "generateThumbnail"]
        fn generate_thumbnail(self: &MediaLibrary, file_path: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "deleteMedia"]
        fn delete_media(self: &MediaLibrary, media_id: i32);
    }

    impl cxx_qt::Threading for MediaLibrary {}
    impl cxx_qt::Initialize for MediaLibrary {}
}

use qobject::MediaLibrary;

const MEDIA: Service = Service("MediaLibrary");

#[derive(Default)]
pub struct MediaLibraryRust {
    albums: QList<QVariant>,
    is_scanning: bool,
    photo_count: i32,
    video_count: i32,
    scan_progress: i32,
}

type Qt = cxx_qt::CxxQtThread<MediaLibrary>;

enum Event {
    Albums,
    Library,
}

impl cxx_qt::Initialize for MediaLibrary {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), MEDIA, "ScanComplete", |obj, (p, v): (i32, i32)| obj.scan_complete(p, v));
        relay(qt.clone(), MEDIA, "NewMediaAdded", |obj, (path,): (String,)| obj.new_media_added(&QString::from(&path)));
        relay(qt.clone(), MEDIA, "ScanningChanged", |obj, (scanning,): (bool,)| show_scanning(obj, scanning));
        relay(qt.clone(), MEDIA, "ScanProgressChanged", |obj, (p,): (i32,)| show_progress(obj, p));
        io::spawn(async move {
            let mut asked = false;
            read(&qt, &mut asked).await;
            let (Ok(albums), Ok(library), Ok(grants)) = (
                MEDIA.signals::<()>("AlbumsChanged").await,
                MEDIA.signals::<()>("LibraryChanged").await,
                answers("PermissionGranted", "storage").await,
            ) else {
                return;
            };
            let events = albums.map(|()| Event::Albums).or(library.map(|()| Event::Library)).or(grants.map(|()| Event::Albums));
            let mut events = std::pin::pin!(events);
            while let Some(event) = events.next().await {
                match event {
                    Event::Albums => read(&qt, &mut asked).await,
                    Event::Library => counts(&qt).await,
                }
            }
        });
    }
}

fn show_scanning(mut obj: Pin<&mut MediaLibrary>, scanning: bool) {
    if obj.is_scanning != scanning {
        obj.as_mut().rust_mut().is_scanning = scanning;
        obj.scanning_changed(scanning);
    }
}

fn show_progress(mut obj: Pin<&mut MediaLibrary>, progress: i32) {
    if obj.scan_progress != progress {
        obj.as_mut().rust_mut().scan_progress = progress;
        obj.scan_progress_changed(progress);
    }
}

async fn read(qt: &Qt, asked: &mut bool) {
    if !allowed("storage", asked).await.unwrap_or(false) {
        return;
    }
    let Ok(albums) = MEDIA.ask::<_, Vec<OwnedValue>>("Albums", &()).await else { return };
    let scanning = MEDIA.ask::<_, bool>("IsScanning", &()).await;
    let progress = MEDIA.ask::<_, i32>("ScanProgress", &()).await;
    qt.queue(move |mut obj| {
        obj.as_mut().rust_mut().albums = variant::qlist(&albums);
        obj.as_mut().albums_changed();
        if let Ok(scanning) = scanning {
            show_scanning(obj.as_mut(), scanning);
        }
        if let Ok(progress) = progress {
            show_progress(obj, progress);
        }
    })
    .ok();
    counts(qt).await;
}

async fn counts(qt: &Qt) {
    let photos = MEDIA.ask::<_, i32>("PhotoCount", &()).await;
    let videos = MEDIA.ask::<_, i32>("VideoCount", &()).await;
    qt.queue(move |mut obj| {
        let mut m = obj.as_mut().rust_mut();
        if let Ok(photos) = photos {
            m.photo_count = photos;
        }
        if let Ok(videos) = videos {
            m.video_count = videos;
        }
        obj.library_changed();
    })
    .ok();
}

impl MediaLibrary {
    crate::shell::calls! { MEDIA;
        scan_library() => "ScanLibrary";
        scan_library_async() => "ScanLibraryAsync";
        delete_media(media_id: i32) => "DeleteMedia";
    }
    crate::shell::asks! { MEDIA;
        get_photos(album_id: &QString) -> QList<QVariant> => "GetPhotos";
        get_all_photos() -> QList<QVariant> => "GetAllPhotos";
        get_videos() -> QList<QVariant> => "GetVideos";
        generate_thumbnail(file_path: &QString) -> QString => "GenerateThumbnail";
    }

    fn refresh(&self) {
        let qt = self.qt_thread();
        io::spawn(async move { read(&qt, &mut false).await });
    }
}
