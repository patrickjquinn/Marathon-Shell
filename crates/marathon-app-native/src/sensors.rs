//! `Sensors`: the shell's Sensor1, the ambient light, proximity and the
//! compass, which the shell reads only while `compassWanted` is set.

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
        #[qproperty(bool, compass_available, cxx_name = "compassAvailable", READ, NOTIFY = compass_changed)]
        #[qproperty(bool, compass_wanted, cxx_name = "compassWanted", READ, WRITE = set_compass_wanted, NOTIFY = compass_changed)]
        /// Degrees clockwise from magnetic north, -1 while unknown.
        #[qproperty(f64, heading, READ, NOTIFY = compass_changed)]
        /// False until the phone has moved enough to learn its magnets.
        #[qproperty(bool, compass_calibrated, cxx_name = "compassCalibrated", READ, NOTIFY = compass_changed)]
        type Sensors = super::SensorsRust;

        #[cxx_name = "setCompassWanted"]
        fn set_compass_wanted(self: Pin<&mut Sensors>, wanted: bool);

        #[qsignal]
        #[cxx_name = "compassChanged"]
        fn compass_changed(self: Pin<&mut Self>);

        #[qsignal]
        #[cxx_name = "proximityChanged"]
        fn proximity_changed(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Sensors {}
    impl cxx_qt::Initialize for Sensors {}
}

use qobject::Sensors;

const SENSOR: Service = Service::shell("Sensor");

#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct SensorsRust {
    available: bool,
    proximity_near: bool,
    ambient_light: i32,
    compass_available: bool,
    compass_wanted: bool,
    heading: f64,
    compass_calibrated: bool,
}

impl Default for SensorsRust {
    fn default() -> Self {
        Self {
            available: false,
            proximity_near: false,
            ambient_light: 0,
            compass_available: false,
            compass_wanted: false,
            heading: -1.0,
            compass_calibrated: false,
        }
    }
}

enum Reading {
    Near(bool),
    Lux(i32),
    Heading(f64, bool),
    Granted,
}

type Qt = cxx_qt::CxxQtThread<Sensors>;

impl cxx_qt::Initialize for Sensors {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let (Ok(near), Ok(lux), Ok(headings), Ok(grants)) = (
                SENSOR.signals::<bool>("ProximityChanged").await,
                SENSOR.signals::<i32>("AmbientLightChanged").await,
                SENSOR.signals::<(f64, bool)>("HeadingChanged").await,
                answers("PermissionGranted", "sensors").await,
            ) else {
                return log::warn("Sensor", "no session bus");
            };
            refresh(&qt).await;
            let readings = near
                .map(Reading::Near)
                .or(lux.map(Reading::Lux))
                .or(headings.map(|(h, c)| Reading::Heading(h, c)))
                .or(grants.map(|()| Reading::Granted));
            let mut readings = std::pin::pin!(readings);
            while let Some(reading) = readings.next().await {
                match reading {
                    Reading::Near(near) => {
                        qt.queue(move |mut obj| set!(obj, proximity_near, proximity_changed, near))
                    }
                    Reading::Lux(lux) => qt
                        .queue(move |mut obj| set!(obj, ambient_light, ambient_light_changed, lux)),
                    Reading::Heading(heading, calibrated) => qt.queue(move |mut obj| {
                        if obj.compass_wanted {
                            obj.as_mut().rust_mut().heading = heading;
                            obj.as_mut().rust_mut().compass_calibrated = calibrated;
                            obj.as_mut().compass_changed();
                        }
                    }),
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
            SENSOR
                .ask::<_, bool>("HasCompass", &())
                .await
                .unwrap_or(false),
        ))
    };
    if let Some((available, near, lux, compass)) = read.await {
        qt.queue(move |mut obj| {
            set!(obj, compass_available, compass_changed, compass);
            set!(obj, available, available_changed, available);
            set!(obj, proximity_near, proximity_changed, near);
            set!(obj, ambient_light, ambient_light_changed, lux);
        })
        .ok();
    }
}

impl Sensors {
    fn set_compass_wanted(mut self: Pin<&mut Self>, wanted: bool) {
        if self.compass_wanted == wanted {
            return;
        }
        let mut rust = self.as_mut().rust_mut();
        rust.compass_wanted = wanted;
        rust.heading = -1.0;
        rust.compass_calibrated = false;
        self.as_mut().compass_changed();
        SENSOR.call(
            if wanted {
                "StartCompass"
            } else {
                "StopCompass"
            },
            (),
        );
    }
}
