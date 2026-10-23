//! `WorldClock`: the time in an IANA zone, DST-correct, which QML's
//! `Date.toLocaleString` cannot give (it ignores `timeZone`).

use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString, QVariant};
use jiff::tz::TimeZone;
use jiff::Timestamp;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        type WorldClock = super::WorldClockRust;

        /// `time` ("3:05 PM"), `weekday` ("WED") and `offsetLabel`
        /// ("Local", "+5h") for `zone`.
        #[qinvokable]
        #[cxx_name = "timeIn"]
        fn time_in(self: &WorldClock, zone: &QString) -> QMap_QString_QVariant;
    }
}

#[derive(Default)]
pub struct WorldClockRust;

impl qobject::WorldClock {
    fn time_in(&self, zone: &QString) -> QMap<QMapPair_QString_QVariant> {
        let mut out = QMap::<QMapPair_QString_QVariant>::default();
        let mut put =
            |k: &str, v: &str| out.insert(QString::from(k), QVariant::from(&QString::from(v)));
        let Ok(tz) = TimeZone::get(&zone.to_string()) else {
            put("time", "—:—");
            put("weekday", "");
            put("offsetLabel", &zone.to_string());
            return out;
        };
        let now = Timestamp::now();
        let there = now.to_zoned(tz.clone());
        put("time", &there.strftime("%-I:%M %p").to_string());
        put("weekday", &there.strftime("%a").to_string().to_uppercase());
        let hours =
            (tz.to_offset(now).seconds() - TimeZone::system().to_offset(now).seconds()) / 3600;
        put(
            "offsetLabel",
            &if hours == 0 {
                "Local".to_owned()
            } else {
                format!("{hours:+}h")
            },
        );
        out
    }
}
