//! `WorldClock`: an IANA zone's UTC offset, DST-correct, which QML's
//! `Date.toLocaleString` cannot give (it ignores `timeZone`).

use cxx_qt_lib::{QString, QVariant};
use jiff::tz::TimeZone;
use jiff::Timestamp;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
    }

    extern "RustQt" {
        #[qobject]
        type WorldClock = super::WorldClockRust;

        /// `zone`'s offset from UTC now, in seconds; undefined for a zone
        /// that does not exist.
        #[qinvokable]
        #[cxx_name = "utcOffset"]
        fn utc_offset(self: &WorldClock, zone: &QString) -> QVariant;

        /// The system zone's IANA name ("Europe/Dublin"), or "".
        #[qinvokable]
        #[cxx_name = "localZone"]
        fn local_zone(self: &WorldClock) -> QString;
    }
}

#[derive(Default)]
pub struct WorldClockRust;

impl qobject::WorldClock {
    fn utc_offset(&self, zone: &QString) -> QVariant {
        TimeZone::get(&zone.to_string()).map_or_else(
            |_| QVariant::default(),
            |tz| QVariant::from(&tz.to_offset(Timestamp::now()).seconds()),
        )
    }

    fn local_zone(&self) -> QString {
        QString::from(TimeZone::system().iana_name().unwrap_or_default())
    }
}
