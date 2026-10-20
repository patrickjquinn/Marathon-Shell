//! `Audio`: the shell's Audio1, volume, sound profiles, the system sounds,
//! and each app's playback stream as a list model.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray, QList, QMap, QMapPair_QString_QVariant, QModelIndex, QString, QVariant};

use crate::shell::{get, mirror, Service, Update};
use crate::variant;

// In the global namespace: cxx-qt 0.10 would put the base class in a
// bridge's namespace too.
#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++Qt" {
        include!(<QtCore/QAbstractListModel>);
        #[qobject]
        type QAbstractListModel;
    }

    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qmodelindex.h");
        type QModelIndex = cxx_qt_lib::QModelIndex;
        include!("cxx-qt-lib/qhash.h");
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY = state_changed)]
        #[qproperty(f64, volume, READ, NOTIFY = state_changed)]
        #[qproperty(bool, muted, READ, NOTIFY = state_changed)]
        #[qproperty(bool, per_app_volume_supported, cxx_name = "perAppVolumeSupported", READ, NOTIFY = state_changed)]
        #[qproperty(QString, audio_profile, cxx_name = "audioProfile", READ, NOTIFY = state_changed)]
        /// The playback streams, an `AudioStreams` the runner hands it.
        #[qproperty(*mut AudioStreams, streams, READ, CONSTANT)]
        type Audio = super::AudioRust;

        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Self>);

        /// Before QML reads `streams`.
        #[cxx_name = "setStreams"]
        unsafe fn set_streams(self: Pin<&mut Audio>, streams: *mut AudioStreams);
        #[qinvokable]
        #[cxx_name = "setVolume"]
        fn set_volume(self: &Audio, volume: f64);
        #[qinvokable]
        #[cxx_name = "setMuted"]
        fn set_muted(self: &Audio, muted: bool);
        #[qinvokable]
        #[cxx_name = "setStreamVolume"]
        fn set_stream_volume(self: &Audio, stream_id: i32, volume: f64);
        #[qinvokable]
        #[cxx_name = "setStreamMuted"]
        fn set_stream_muted(self: &Audio, stream_id: i32, muted: bool);
        #[qinvokable]
        #[cxx_name = "refreshStreams"]
        fn refresh_streams(self: &Audio);
        #[qinvokable]
        #[cxx_name = "setDoNotDisturb"]
        fn set_do_not_disturb(self: &Audio, enabled: bool);
        #[qinvokable]
        #[cxx_name = "setAudioProfile"]
        fn set_audio_profile(self: &Audio, profile: &QString);
        #[qinvokable]
        #[cxx_name = "playRingtone"]
        fn play_ringtone(self: &Audio);
        #[qinvokable]
        #[cxx_name = "stopRingtone"]
        fn stop_ringtone(self: &Audio);
        #[qinvokable]
        #[cxx_name = "playNotificationSound"]
        fn play_notification_sound(self: &Audio);
        #[qinvokable]
        #[cxx_name = "playAlarmSound"]
        fn play_alarm_sound(self: &Audio);
        #[qinvokable]
        #[cxx_name = "stopAlarmSound"]
        fn stop_alarm_sound(self: &Audio);
        #[qinvokable]
        #[cxx_name = "previewSound"]
        fn preview_sound(self: &Audio, sound_path: &QString);
        #[qinvokable]
        #[cxx_name = "vibratePattern"]
        fn vibrate_pattern(self: &Audio, pattern: &QList_QVariant);
    }

    unsafe extern "RustQt" {
        /// Roles `streamId`, `name`, `appName`, `volume`, `muted` and
        /// `mediaClass`.
        #[qobject]
        #[base = QAbstractListModel]
        type AudioStreams = super::AudioStreamsRust;

        #[inherit]
        #[cxx_name = "beginResetModel"]
        fn begin_reset_model(self: Pin<&mut AudioStreams>);
        #[inherit]
        #[cxx_name = "endResetModel"]
        fn end_reset_model(self: Pin<&mut AudioStreams>);
        #[cxx_override]
        #[cxx_name = "rowCount"]
        fn row_count(self: &AudioStreams, parent: &QModelIndex) -> i32;
        #[cxx_override]
        fn data(self: &AudioStreams, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_override]
        #[cxx_name = "roleNames"]
        fn role_names(self: &AudioStreams) -> QHash_i32_QByteArray;
    }

    impl cxx_qt::Threading for Audio {}
    impl cxx_qt::Initialize for Audio {}
    impl cxx_qt::Threading for AudioStreams {}
    impl cxx_qt::Initialize for AudioStreams {}
}

use qobject::{Audio, AudioStreams};

const AUDIO: Service = Service("Audio");

pub struct AudioRust {
    available: bool,
    volume: f64,
    muted: bool,
    per_app_volume_supported: bool,
    audio_profile: QString,
    streams: *mut AudioStreams,
}

impl Default for AudioRust {
    fn default() -> Self {
        Self {
            available: false,
            volume: 0.0,
            muted: false,
            per_app_volume_supported: false,
            audio_profile: QString::default(),
            streams: std::ptr::null_mut(),
        }
    }
}

impl cxx_qt::Initialize for Audio {
    fn initialize(self: Pin<&mut Self>) {
        mirror(self.qt_thread(), AUDIO, "system", |mut obj, update| {
            let Update::State(s) = update else { return };
            let mut a = obj.as_mut().rust_mut();
            a.available = get(&s, "available");
            a.volume = get(&s, "volume");
            a.muted = get(&s, "muted");
            a.per_app_volume_supported = get(&s, "perAppVolumeSupported");
            a.audio_profile = get(&s, "audioProfile");
            obj.state_changed();
        });
    }
}

impl Audio {
    crate::shell::calls! { AUDIO;
        set_volume(volume: f64) => "SetVolume";
        set_muted(muted: bool) => "SetMuted";
        set_stream_volume(stream_id: i32, volume: f64) => "SetStreamVolume";
        set_stream_muted(stream_id: i32, muted: bool) => "SetStreamMuted";
        refresh_streams() => "RefreshStreams";
        set_do_not_disturb(enabled: bool) => "SetDoNotDisturb";
        set_audio_profile(profile: &QString) => "SetAudioProfile";
        play_ringtone() => "PlayRingtone";
        stop_ringtone() => "StopRingtone";
        play_notification_sound() => "PlayNotificationSound";
        play_alarm_sound() => "PlayAlarmSound";
        stop_alarm_sound() => "StopAlarmSound";
        preview_sound(sound_path: &QString) => "PreviewSound";
    }

    /// # Safety
    ///
    /// `streams` outlives this object; the runner parents both to the app.
    unsafe fn set_streams(self: Pin<&mut Self>, streams: *mut AudioStreams) {
        self.rust_mut().streams = streams;
    }

    fn vibrate_pattern(&self, pattern: &QList<QVariant>) {
        AUDIO.call("VibratePattern", (variant::list(pattern),));
    }
}

#[derive(Default)]
pub struct AudioStreamsRust {
    streams: Vec<QMap<QMapPair_QString_QVariant>>,
}

const ROLES: [&str; 6] = ["streamId", "name", "appName", "volume", "muted", "mediaClass"];
const FIRST_ROLE: i32 = 0x0100 + 1; // Qt::UserRole + 1

impl cxx_qt::Initialize for AudioStreams {
    fn initialize(self: Pin<&mut Self>) {
        mirror(self.qt_thread(), AUDIO, "system", |mut model, update| {
            let Update::State(state) = update else { return };
            let streams: QList<QVariant> = get(&state, "streams");
            model.as_mut().begin_reset_model();
            model.as_mut().rust_mut().streams = streams.iter().filter_map(QVariant::value).collect();
            model.end_reset_model();
        });
    }
}

impl AudioStreams {
    fn row_count(&self, parent: &QModelIndex) -> i32 {
        if parent.is_valid() { 0 } else { i32::try_from(self.streams.len()).unwrap_or(i32::MAX) }
    }

    fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
        let stream = usize::try_from(index.row()).ok().and_then(|row| self.streams.get(row));
        let key = usize::try_from(role - FIRST_ROLE).ok().and_then(|i| ROLES.get(i));
        stream.zip(key).and_then(|(s, key)| s.get(&QString::from(*key))).unwrap_or_default()
    }

    fn role_names(&self) -> QHash<QHashPair_i32_QByteArray> {
        let mut roles = QHash::<QHashPair_i32_QByteArray>::default();
        for (role, name) in (FIRST_ROLE..).zip(ROLES) {
            roles.insert(role, QByteArray::from(name));
        }
        roles
    }
}
