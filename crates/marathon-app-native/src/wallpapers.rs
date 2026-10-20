//! `Wallpapers`: the shell's wallpapers (`Wallpaper1`), for Settings'
//! ambience page; the current one is the `wallpaperPath` setting.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QVariant};
use zbus::zvariant::OwnedValue;

use crate::shell::Service;
use crate::variant;
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
        #[qproperty(QList_QVariant, wallpapers, READ, NOTIFY = wallpapers_changed)]
        type Wallpapers = super::WallpapersRust;

        #[qsignal]
        #[cxx_name = "wallpapersChanged"]
        fn wallpapers_changed(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Wallpapers {}
    impl cxx_qt::Initialize for Wallpapers {}
}

use qobject::Wallpapers;

#[derive(Default)]
pub struct WallpapersRust {
    wallpapers: QList<QVariant>,
}

impl cxx_qt::Initialize for Wallpapers {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            if let Ok(list) = Service::shell("Wallpaper").ask::<_, Vec<OwnedValue>>("GetWallpapers", &()).await {
                qt.queue(move |mut obj: Pin<&mut Wallpapers>| {
                    obj.as_mut().rust_mut().wallpapers = variant::qlist(&list);
                    obj.wallpapers_changed();
                })
                .ok();
            }
        });
    }
}
