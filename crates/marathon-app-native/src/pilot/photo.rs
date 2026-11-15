//! A camera photo for Pilot (pilotd's `photo.rs`): read with its EXIF
//! orientation applied, scaled down and written as a plain JPEG, which
//! carries none of the source's metadata. Qt's image readers do the work.

use std::path::Path;

use cxx_qt_lib::QString;

#[cxx_qt::bridge(namespace = "marathon::pilot")]
mod ffi {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "C++" {
        include!("marathon-app-native/cpp/pilotphoto.h");
        #[cxx_name = "preparePhoto"]
        fn prepare_photo(src: &QString, dst: &QString, max_side: i32) -> bool;
    }
}

/// `src` at most `max_side` pixels on its long side, re-encoded to `dst`;
/// false if either fails.
pub fn prepare(src: &Path, dst: &Path, max_side: i32) -> bool {
    ffi::prepare_photo(
        &QString::from(src.to_string_lossy().as_ref()),
        &QString::from(dst.to_string_lossy().as_ref()),
        max_side,
    )
}
