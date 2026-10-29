//! `WeatherClient`: marathon-weatherd's forecast, as the Hub shows it.

use crate::i18n::fl;
use std::pin::Pin;
use std::time::Duration;

use async_io::Timer;
use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString};
use futures_lite::{future, StreamExt};
use zbus::fdo::PropertiesProxy;
use zbus::names::InterfaceName;
use zbus::Variant as Value;

use crate::{io, log, variant};

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        /// The service's Forecast, parsed; empty until the first one.
        #[qproperty(QMap_QString_QVariant, forecast, READ, NOTIFY)]
        /// "idle", "updating", "offline", "no-location" or "error: …".
        #[qproperty(QString, state, READ, NOTIFY)]
        /// °F and mph for the US locale, mph for the UK, metric otherwise.
        #[qproperty(bool, fahrenheit, READ, CONSTANT)]
        #[qproperty(bool, miles_per_hour, cxx_name = "milesPerHour", READ, CONSTANT)]
        type WeatherClient = super::WeatherClientRust;

        /// Reads the current values, then asks for newer ones; starts the service.
        #[qinvokable]
        fn refresh(self: &WeatherClient);
        /// Answers with searchFinished.
        #[qinvokable]
        fn search(self: &WeatherClient, query: &QString);
        /// A place from search(): {name, region, latitude, longitude}.
        #[qinvokable]
        #[cxx_name = "setLocation"]
        fn set_location(self: &WeatherClient, place: &QMap_QString_QVariant);
        #[qinvokable]
        #[cxx_name = "setAutomatic"]
        fn set_automatic(self: &WeatherClient);

        #[qsignal]
        #[cxx_name = "searchFinished"]
        fn search_finished(self: Pin<&mut Self>, places: &QList_QVariant, error: &QString);
    }

    impl cxx_qt::Threading for WeatherClient {}
    impl cxx_qt::Initialize for WeatherClient {}
}

use qobject::WeatherClient;

type Qt = CxxQtThread<WeatherClient>;

const SERVICE: &str = "org.marathonos.Weather";
const PATH: &str = "/org/marathonos/Weather";
const INTERFACE: InterfaceName<'static> =
    InterfaceName::from_static_str_unchecked("org.marathonos.Weather1");

#[zbus::proxy(
    interface = "org.marathonos.Weather1",
    default_service = "org.marathonos.Weather",
    default_path = "/org/marathonos/Weather"
)]
trait Weather {
    fn refresh(&self) -> zbus::Result<()>;
    fn search(&self, query: &str) -> zbus::Result<String>;
    fn set_location(
        &self,
        name: &str,
        region: &str,
        latitude: f64,
        longitude: f64,
    ) -> zbus::Result<()>;
    fn set_automatic(&self) -> zbus::Result<()>;
}

pub struct WeatherClientRust {
    forecast: QMap<QMapPair_QString_QVariant>,
    forecast_json: String,
    state: QString,
    fahrenheit: bool,
    miles_per_hour: bool,
}

impl Default for WeatherClientRust {
    fn default() -> Self {
        let territory = territory();
        let fahrenheit = matches!(territory.as_str(), "US" | "LR" | "MM");
        Self {
            forecast: QMap::default(),
            forecast_json: String::new(),
            state: QString::default(),
            fahrenheit,
            miles_per_hour: fahrenheit || territory == "GB",
        }
    }
}

/// The locale's territory, as `QLocale` reads it from the environment.
fn territory() -> String {
    ["LC_ALL", "LC_MEASUREMENT", "LANG"]
        .iter()
        .find_map(|key| std::env::var(key).ok().filter(|v| !v.is_empty()))
        .and_then(|locale| {
            Some(
                locale
                    .split(['.', '@'])
                    .next()?
                    .split_once('_')?
                    .1
                    .to_owned(),
            )
        })
        .unwrap_or_default()
}

impl cxx_qt::Initialize for WeatherClient {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            if let Err(e) = watch(&qt).await {
                log::warn("weather", e);
            }
        });
    }
}

async fn properties() -> zbus::Result<PropertiesProxy<'static>> {
    PropertiesProxy::builder(&io::session_bus().await?)
        .destination(SERVICE)
        .path(PATH)
        .build()
        .await
}

async fn weather() -> zbus::Result<WeatherProxy<'static>> {
    WeatherProxy::new(&io::session_bus().await?).await
}

async fn watch(qt: &Qt) -> zbus::Result<()> {
    let mut signals = properties().await?.receive_properties_changed().await?;
    while let Some(signal) = signals.next().await {
        let args = signal.args()?;
        if args.interface_name == INTERFACE {
            let changed = args.changed_properties();
            publish(
                qt,
                text(changed.get("Forecast")),
                text(changed.get("State")),
            );
        }
    }
    Ok(())
}

fn text(value: Option<&Value<'_>>) -> Option<String> {
    value?.downcast_ref::<String>().ok()
}

fn publish(qt: &Qt, forecast: Option<String>, state: Option<String>) {
    qt.queue(move |mut obj| {
        if let Some(json) = forecast.filter(|json| *json != obj.forecast_json) {
            let parsed = serde_json::from_str(&json).unwrap_or_default();
            let mut rust = obj.as_mut().rust_mut();
            rust.forecast = variant::map(&parsed);
            rust.forecast_json = json;
            obj.as_mut().forecast_changed();
        }
        if let Some(state) = state {
            set!(obj, state, state_changed, QString::from(&state));
        }
    })
    .ok();
}

fn call<F: future::Future<Output = zbus::Result<()>> + Send>(
    method: &'static str,
    done: impl FnOnce(WeatherProxy<'static>) -> F + Send + 'static,
) {
    io::spawn(async move {
        let result = async { done(weather().await?).await }.await;
        if let Err(e) = result {
            log::warn("weather", format_args!("{method}: {e}"));
        }
    });
}

impl WeatherClient {
    fn refresh(&self) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let done = async {
                let all = properties().await?.get_all(INTERFACE).await?;
                let get = |name| text(all.get(name).map(|v| &**v));
                publish(&qt, get("Forecast"), get("State"));
                weather().await?.refresh().await
            };
            if let Err(e) = done.await {
                log::warn("weather", format_args!("refresh: {e}"));
            }
        });
    }

    fn search(&self, query: &QString) {
        let qt = self.qt_thread();
        let query = query.to_string();
        io::spawn(async move {
            let found = future::or(
                async {
                    async { weather().await?.search(&query).await }
                        .await
                        .map_err(|e| e.to_string())
                },
                async {
                    Timer::after(Duration::from_secs(15)).await;
                    Err(fl!("weather-timed-out"))
                },
            );
            let found: Result<String, String> = found.await;
            let (json, error) = match found {
                Ok(json) => (
                    serde_json::from_str(&json).unwrap_or_default(),
                    String::new(),
                ),
                Err(e) => (serde_json::Value::Null, e),
            };
            qt.queue(move |obj| {
                let places = json
                    .as_array()
                    .map(|items| variant::list(items))
                    .unwrap_or_default();
                obj.search_finished(&places, &QString::from(&error));
            })
            .ok();
        });
    }

    #[allow(clippy::unused_self, reason = "an invokable")]
    fn set_location(&self, place: &QMap<QMapPair_QString_QVariant>) {
        let text = |key| {
            place
                .get(&QString::from(key))
                .and_then(|v| v.value::<QString>())
                .map(|s| s.to_string())
                .unwrap_or_default()
        };
        let number = |key| {
            place
                .get(&QString::from(key))
                .and_then(|v| v.value::<f64>())
                .unwrap_or_default()
        };
        let (name, region, latitude, longitude) = (
            text("name"),
            text("region"),
            number("latitude"),
            number("longitude"),
        );
        call("SetLocation", move |w| async move {
            w.set_location(&name, &region, latitude, longitude).await
        });
    }

    #[allow(clippy::unused_self, reason = "an invokable")]
    fn set_automatic(&self) {
        call("SetAutomatic", |w| async move { w.set_automatic().await });
    }
}
