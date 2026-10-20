//! Polls the iio ambient light and proximity channels off the GUI thread:
//! on vcnl4000-class parts each read starts a synchronous I2C measurement.
//! Reports only changes; polls only while something asked for a channel,
//! every 200 ms while proximity is wanted (calls), else every second.

use std::path::PathBuf;
use std::pin::Pin;
use std::time::Duration;

use async_channel::{Receiver, Sender};
use async_io::Timer;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_lite::future;

use crate::io;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        type IioPoller = super::IioRust;

        #[qsignal]
        #[cxx_name = "lightRead"]
        fn light_read(self: Pin<&mut Self>, lux: i32);
        #[qsignal]
        #[cxx_name = "proximityRead"]
        fn proximity_read(self: Pin<&mut Self>, near: bool);

        /// The raw sysfs channels; an empty path is a channel there isn't.
        #[qinvokable]
        #[cxx_name = "setChannels"]
        fn set_channels(self: Pin<&mut IioPoller>, light: &QString, lux_scale: f64, proximity: &QString, near_level: i32);
        #[qinvokable]
        #[cxx_name = "setActive"]
        fn set_active(self: &IioPoller, light: bool, proximity: bool);
    }

    impl cxx_qt::Threading for IioPoller {}
}

use qobject::IioPoller;

#[derive(Default)]
pub struct IioRust {
    actor: Option<Sender<(bool, bool)>>,
}

struct Channels {
    light: Option<PathBuf>,
    lux_scale: f64,
    proximity: Option<PathBuf>,
    near_level: i32,
}

impl IioPoller {
    fn set_channels(mut self: Pin<&mut Self>, light: &QString, lux_scale: f64, proximity: &QString, near_level: i32) {
        let path = |p: &QString| Some(PathBuf::from(p.to_string())).filter(|p| !p.as_os_str().is_empty());
        let channels = Channels { light: path(light), lux_scale, proximity: path(proximity), near_level };
        let (tx, rx) = async_channel::bounded(8);
        io::spawn(run(self.qt_thread(), channels, rx));
        self.as_mut().rust_mut().actor = Some(tx);
    }

    fn set_active(&self, light: bool, proximity: bool) {
        if let Some(actor) = &self.actor {
            actor.try_send((light, proximity)).ok();
        }
    }
}

async fn run(qt: cxx_qt::CxxQtThread<IioPoller>, channels: Channels, wanted: Receiver<(bool, bool)>) {
    let (mut light, mut proximity) = (false, false);
    let (mut last_lux, mut last_near) = (None, None);
    loop {
        let next = if light || proximity {
            let every = Duration::from_millis(if proximity { 200 } else { 1000 });
            future::or(async { Some(wanted.recv().await.ok()) }, async {
                Timer::after(every).await;
                None
            })
            .await
        } else {
            Some(wanted.recv().await.ok())
        };
        match next {
            Some(None) => return,
            // A channel just asked for is read at once.
            Some(Some((l, p))) => (light, proximity) = (l, p),
            None => {}
        }
        if let (true, Some(path)) = (light, channels.light.clone()) {
            if let Some(raw) = read(path).await {
                #[allow(clippy::cast_possible_truncation, reason = "lux fits an i32")]
                let lux = (f64::from(raw) * channels.lux_scale).round() as i32;
                if last_lux != Some(lux) {
                    last_lux = Some(lux);
                    qt.queue(move |obj| obj.light_read(lux)).ok();
                }
            }
        }
        if let (true, Some(path)) = (proximity, channels.proximity.clone()) {
            let near = read(path).await.unwrap_or(0) >= channels.near_level;
            if last_near != Some(near) {
                last_near = Some(near);
                qt.queue(move |obj| obj.proximity_read(near)).ok();
            }
        }
    }
}

// On the blocking pool: the driver measures while the read waits.
async fn read(path: PathBuf) -> Option<i32> {
    blocking::unblock(move || std::fs::read_to_string(path).ok()?.trim().parse().ok()).await
}
