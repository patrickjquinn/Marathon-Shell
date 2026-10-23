//! `Sensors`: the shell's Sensor1, the ambient light and proximity.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use futures_lite::StreamExt;

use crate::shell::{answers, Service};
use marathon_rt::{io, log};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, NOTIFY)]
        #[qproperty(bool, proximity_near, cxx_name = "proximityNear", READ, NOTIFY = proximity_changed)]
        #[qproperty(i32, ambient_light, cxx_name = "ambientLight", READ, NOTIFY)]
        type Sensors = super::SensorsRust;

        #[qsignal]
        #[cxx_name = "proximityChanged"]
        fn proximity_changed(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Sensors {}
    impl cxx_qt::Initialize for Sensors {}
}

use qobject::Sensors;

const SENSOR: Service = Service::shell("Sensor");

#[derive(Default)]
pub struct SensorsRust {
    available: bool,
    proximity_near: bool,
    ambient_light: i32,
}

enum Reading {
    Near(bool),
    Lux(i32),
    Granted,
}

type Qt = cxx_qt::CxxQtThread<Sensors>;

impl cxx_qt::Initialize for Sensors {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let (Ok(near), Ok(lux), Ok(grants)) = (
                SENSOR.signals::<bool>("ProximityChanged").await,
                SENSOR.signals::<i32>("AmbientLightChanged").await,
                answers("PermissionGranted", "sensors").await,
            ) else {
                return log::warn("Sensor", "no session bus");
            };
            refresh(&qt).await;
            let readings = near
                .map(Reading::Near)
                .or(lux.map(Reading::Lux))
                .or(grants.map(|()| Reading::Granted));
            let mut readings = std::pin::pin!(readings);
            while let Some(reading) = readings.next().await {
                match reading {
                    Reading::Near(near) => {
                        qt.queue(move |mut obj| set!(obj, proximity_near, proximity_changed, near))
                    }
                    Reading::Lux(lux) => qt
                        .queue(move |mut obj| set!(obj, ambient_light, ambient_light_changed, lux)),
                    Reading::Granted => {
                        refresh(&qt).await;
                        continue;
                    }
                }
                .ok();
            }
        });
    }
}

async fn refresh(qt: &Qt) {
    let read = async {
        Some((
            SENSOR.ask::<_, bool>("IsAvailable", &()).await.ok()?,
            SENSOR.ask::<_, bool>("ProximityNear", &()).await.ok()?,
            SENSOR.ask::<_, i32>("AmbientLight", &()).await.ok()?,
        ))
    };
    if let Some((available, near, lux)) = read.await {
        qt.queue(move |mut obj| {
            set!(obj, available, available_changed, available);
            set!(obj, proximity_near, proximity_changed, near);
            set!(obj, ambient_light, ambient_light_changed, lux);
        })
        .ok();
    }
}
