//! The Maps app's routing and voice guidance (QML `import MarathonOS.Maps`).
//! `Routing` asks Valhalla (valhalla1.openstreetmap.de: free, OSM-derived,
//! spoken instructions included) for a route; `Voice` speaks a cue with
//! Piper when its voice is installed, else flite, and plays it with paplay.

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use serde_json::{json, Value};

use marathon_rt::log;

#[cxx_qt::bridge(namespace = "marathon::maps")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, routing, READ, NOTIFY)]
        #[qproperty(QString, last_error, cxx_name = "lastError", READ, NOTIFY)]
        #[qproperty(QMap_QString_QVariant, current_route, cxx_name = "currentRoute", READ, NOTIFY = route_ready)]
        type Routing = super::RoutingRust;

        /// `mode`: Valhalla's costing, "auto", "pedestrian" or "bicycle".
        #[qinvokable]
        #[cxx_name = "requestRoute"]
        fn request_route(
            self: Pin<&mut Routing>,
            start_lat: f64,
            start_lon: f64,
            end_lat: f64,
            end_lon: f64,
            mode: &QString,
        );
        #[qinvokable]
        #[cxx_name = "clearRoute"]
        fn clear_route(self: Pin<&mut Routing>);

        /// `geojson` is a FeatureCollection of the route's LineString, for
        /// MapLibre's route source; `maneuvers` the banner's and list's
        /// steps; distance in metres.
        #[qsignal]
        #[cxx_name = "routeReady"]
        fn route_ready(
            self: Pin<&mut Routing>,
            geojson: &QString,
            maneuvers: &QList_QVariant,
            duration_sec: f64,
            distance_meters: f64,
            summary: &QMap_QString_QVariant,
        );
        #[qsignal]
        #[cxx_name = "routeFailed"]
        fn route_failed(self: Pin<&mut Routing>, error: &QString);
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(bool, available, READ, CONSTANT)]
        #[qproperty(bool, speaking, READ, NOTIFY)]
        #[qproperty(QString, backend, READ, CONSTANT)]
        #[qproperty(bool, muted, READ, WRITE = set_muted, NOTIFY)]
        type Voice = super::VoiceRust;

        #[qinvokable]
        fn speak(self: Pin<&mut Voice>, text: &QString);
        #[qinvokable]
        fn stop(self: Pin<&mut Voice>);
        #[cxx_name = "setMuted"]
        fn set_muted(self: Pin<&mut Voice>, muted: bool);
    }

    impl cxx_qt::Threading for Routing {}
    impl cxx_qt::Threading for Voice {}
}

use qobject::{Routing, Voice};

const VALHALLA: &str = "https://valhalla1.openstreetmap.de/route";

#[derive(Default)]
pub struct RoutingRust {
    routing: bool,
    last_error: QString,
    current_route: QMap<QMapPair_QString_QVariant>,
}

fn text(s: &str) -> QVariant {
    QVariant::from(&QString::from(s))
}

/// A JSON value as QML sees it.
fn variant(value: &Value) -> QVariant {
    match value {
        Value::Bool(b) => QVariant::from(b),
        Value::Number(n) => n.as_i64().and_then(|i| i32::try_from(i).ok()).map_or_else(
            || QVariant::from(&n.as_f64().unwrap_or(0.0)),
            |i| QVariant::from(&i),
        ),
        Value::String(s) => text(s),
        Value::Array(items) => {
            let mut list = QList::<QVariant>::default();
            for item in items {
                list.append(variant(item));
            }
            QVariant::from(&list)
        }
        Value::Object(fields) => {
            let mut map = QMap::<QMapPair_QString_QVariant>::default();
            for (key, item) in fields {
                map.insert(QString::from(key), variant(item));
            }
            QVariant::from(&map)
        }
        Value::Null => QVariant::default(),
    }
}

fn map(value: &Value) -> QMap<QMapPair_QString_QVariant> {
    variant(value)
        .value::<QMap<QMapPair_QString_QVariant>>()
        .unwrap_or_default()
}

/// The route Valhalla answers, as QML takes it: the line, the steps and the
/// summary; or why there is none.
fn route(from: (f64, f64), to: (f64, f64), mode: &str) -> Result<(String, Value, Value), String> {
    let body = json!({
        "locations": [{"lat": from.0, "lon": from.1}, {"lat": to.0, "lon": to.1}],
        "costing": if mode.is_empty() { "auto" } else { mode },
        "units": "kilometers",
        "directions_options": {"language": "en-US", "units": "kilometers"},
    });
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .user_agent("MarathonOS/1.0 (Maps app routing)")
        .timeout_global(Some(Duration::from_secs(15)))
        .http_status_as_error(false)
        .build()
        .into();
    let mut reply = agent
        .post(VALHALLA)
        .header("Content-Type", "application/json")
        .send(body.to_string())
        .map_err(|e| match e {
            ureq::Error::Timeout(_) => "Timed out".to_owned(),
            e => e.to_string(),
        })?;
    let ok = reply.status().is_success();
    let reply: Value = serde_json::from_str(
        &reply
            .body_mut()
            .read_to_string()
            .map_err(|e| e.to_string())?,
    )
    .map_err(|e| format!("Parse error: {e}"))?;
    if !ok {
        // Valhalla answers "no route" as an HTTP error with a reason.
        return Err(reply["error"]
            .as_str()
            .unwrap_or("Valhalla refused the route")
            .to_owned());
    }
    let leg = &reply["trip"]["legs"][0];
    if leg.is_null() {
        return Err("Valhalla returned an empty trip".into());
    }
    let line = polyline::decode_polyline(leg["shape"].as_str().unwrap_or_default(), 6)
        .map_err(|e| format!("Bad route shape: {e}"))?;
    let coordinates: Vec<[f64; 2]> = line.coords().map(|c| [c.x, c.y]).collect();
    let geojson = json!({"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {}, "geometry": {"type": "LineString", "coordinates": coordinates}}]});
    let maneuvers: Vec<Value> = leg["maneuvers"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|m| {
            json!({
                "instruction": m["instruction"].as_str().unwrap_or_default(),
                "type": m["type"].as_i64().unwrap_or(0),
                "length": m["length"].as_f64().unwrap_or(0.0),
                "time": m["time"].as_f64().unwrap_or(0.0),
                "verbalPre": m["verbal_pre_transition_instruction"].as_str().unwrap_or_default(),
                "verbalPost": m["verbal_post_transition_instruction"].as_str().unwrap_or_default(),
                "streetNames": m["street_names"],
                "beginShapeIndex": m["begin_shape_index"].as_i64().unwrap_or(0),
                "endShapeIndex": m["end_shape_index"].as_i64().unwrap_or(0),
            })
        })
        .collect();
    let s = &leg["summary"];
    let summary = json!({
        "time": s["time"].as_f64().unwrap_or(0.0),
        "distance": s["length"].as_f64().unwrap_or(0.0),
        "minLat": s["min_lat"].as_f64().unwrap_or(0.0),
        "minLon": s["min_lon"].as_f64().unwrap_or(0.0),
        "maxLat": s["max_lat"].as_f64().unwrap_or(0.0),
        "maxLon": s["max_lon"].as_f64().unwrap_or(0.0),
    });
    Ok((geojson.to_string(), Value::Array(maneuvers), summary))
}

impl Routing {
    fn request_route(
        mut self: Pin<&mut Self>,
        start_lat: f64,
        start_lon: f64,
        end_lat: f64,
        end_lon: f64,
        mode: &QString,
    ) {
        if self.routing {
            return;
        }
        self.as_mut().routing_now(true);
        let (qt, mode) = (self.qt_thread(), mode.to_string());
        std::thread::spawn(move || {
            let answer = route((start_lat, start_lon), (end_lat, end_lon), &mode);
            qt.queue(move |mut obj| {
                obj.as_mut().routing_now(false);
                match answer {
                    Ok((geojson, maneuvers, summary)) => {
                        let (time, km) = (
                            summary["time"].as_f64().unwrap_or(0.0),
                            summary["distance"].as_f64().unwrap_or(0.0),
                        );
                        let steps = variant(&maneuvers)
                            .value::<QList<QVariant>>()
                            .unwrap_or_default();
                        let summary = map(&summary);
                        let mut current = QMap::<QMapPair_QString_QVariant>::default();
                        current.insert(QString::from("geojson"), text(&geojson));
                        current.insert(QString::from("maneuvers"), QVariant::from(&steps));
                        current.insert(QString::from("duration"), QVariant::from(&time));
                        current.insert(QString::from("distance"), QVariant::from(&(km * 1000.0)));
                        current.insert(QString::from("summary"), QVariant::from(&summary));
                        obj.as_mut().rust_mut().current_route = current;
                        obj.as_mut().route_ready(
                            &QString::from(&geojson),
                            &steps,
                            time,
                            km * 1000.0,
                            &summary,
                        );
                    }
                    Err(e) => {
                        obj.as_mut().error_now(&e);
                        obj.as_mut().route_failed(&QString::from(&e));
                    }
                }
            })
            .ok();
        });
    }

    fn routing_now(mut self: Pin<&mut Self>, routing: bool) {
        self.as_mut().rust_mut().routing = routing;
        self.routing_changed();
    }

    fn error_now(mut self: Pin<&mut Self>, error: &str) {
        self.as_mut().rust_mut().last_error = QString::from(error);
        self.last_error_changed();
    }

    fn clear_route(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().current_route = QMap::default();
        self.as_mut().error_now("");
        self.route_ready(
            &QString::default(),
            &QList::default(),
            0.0,
            0.0,
            &QMap::default(),
        );
    }
}

/// How cues are spoken on this phone.
#[derive(Clone)]
enum Engine {
    Piper { bin: PathBuf, model: PathBuf },
    Flite(PathBuf),
}

fn engine() -> Option<Engine> {
    let home = dirs::home_dir().unwrap_or_default();
    let first = |paths: Vec<PathBuf>| paths.into_iter().find(|p| p.exists());
    let piper = first(vec![
        "/usr/bin/piper".into(),
        "/usr/local/bin/piper".into(),
        home.join(".local/bin/piper"),
    ]);
    let model = first(vec![
        "/usr/share/marathon/voice/en_US-amy-low.onnx".into(),
        "/usr/share/piper-voices/en_US-amy-low.onnx".into(),
        home.join(".local/share/marathon-apps/maps/voice/en_US-amy-low.onnx"),
    ]);
    match (piper, model) {
        (Some(bin), Some(model)) => Some(Engine::Piper { bin, model }),
        _ => first(vec!["/usr/bin/flite".into()]).map(Engine::Flite),
    }
}

pub struct VoiceRust {
    available: bool,
    speaking: bool,
    backend: QString,
    muted: bool,
    engine: Option<Engine>,
    /// Bumped by every cue and stop: a cue finishing after a newer one
    /// began does not end "speaking".
    turn: Arc<AtomicU64>,
    /// The cue's synthesis or playback process.
    child: Arc<Mutex<Option<Child>>>,
}

impl Default for VoiceRust {
    fn default() -> Self {
        let engine = engine();
        let backend = match &engine {
            Some(Engine::Piper { .. }) => "piper",
            Some(Engine::Flite(_)) => "flite",
            None => "none",
        };
        Self {
            available: engine.is_some(),
            speaking: false,
            backend: QString::from(backend),
            muted: false,
            engine,
            turn: Arc::default(),
            child: Arc::default(),
        }
    }
}

/// Runs `command` as the cue's current process, until it exits or is
/// stopped; whether it succeeded.
fn run(slot: &Mutex<Option<Child>>, command: &mut Command, input: Option<&str>) -> bool {
    let Ok(mut child) = command
        .stdin(if input.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::null())
        .spawn()
    else {
        return false;
    };
    if let (Some(text), Some(mut stdin)) = (input, child.stdin.take()) {
        use std::io::Write as _;
        stdin.write_all(text.as_bytes()).ok();
    }
    let pid = child.id();
    *slot.lock().unwrap_or_else(|_| std::process::abort()) = Some(child);
    loop {
        let mut guard = slot.lock().unwrap_or_else(|_| std::process::abort());
        match guard.as_mut() {
            Some(c) if c.id() == pid => match c.try_wait() {
                Ok(Some(status)) => {
                    *guard = None;
                    return status.success();
                }
                Ok(None) => {}
                Err(_) => return false,
            },
            // Stopped, or replaced by a newer cue.
            _ => return false,
        }
        drop(guard);
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn say(engine: &Engine, text: &str, wav: &Path, slot: &Mutex<Option<Child>>) -> bool {
    let synthesised = match engine {
        Engine::Piper { bin, model } => run(
            slot,
            Command::new(bin)
                .arg("--model")
                .arg(model)
                .arg("--output_file")
                .arg(wav),
            Some(text),
        ),
        Engine::Flite(bin) => run(
            slot,
            Command::new(bin).arg("-t").arg(text).arg("-o").arg(wav),
            None,
        ),
    };
    let played = synthesised && run(slot, Command::new("paplay").arg(wav), None);
    std::fs::remove_file(wav).ok();
    played
}

impl Voice {
    fn speak(mut self: Pin<&mut Self>, text: &QString) {
        let Some(engine) = self
            .engine
            .clone()
            .filter(|_| !self.muted && !text.is_empty())
        else {
            return;
        };
        // The latest maneuver wins: rerouting, or turns in quick succession.
        self.as_mut().stop();
        let turn = self.turn.fetch_add(1, Ordering::SeqCst) + 1;
        self.as_mut().speaking_now(true);
        let (qt, child, turns, text) = (
            self.qt_thread(),
            Arc::clone(&self.child),
            Arc::clone(&self.turn),
            text.to_string(),
        );
        std::thread::spawn(move || {
            let wav = std::env::temp_dir()
                .join(format!("marathon-nav-{}-{turn}.wav", std::process::id()));
            if !say(&engine, &text, &wav, &child) && turns.load(Ordering::SeqCst) == turn {
                log::warn("maps", "a voice cue failed to play");
            }
            qt.queue(move |obj| {
                if obj.turn.load(Ordering::SeqCst) == turn {
                    obj.speaking_now(false);
                }
            })
            .ok();
        });
    }

    fn stop(mut self: Pin<&mut Self>) {
        self.turn.fetch_add(1, Ordering::SeqCst);
        if let Some(mut child) = self
            .child
            .lock()
            .unwrap_or_else(|_| std::process::abort())
            .take()
        {
            child.kill().ok();
            child.wait().ok();
        }
        self.as_mut().speaking_now(false);
    }

    fn speaking_now(mut self: Pin<&mut Self>, speaking: bool) {
        if speaking != self.speaking {
            self.as_mut().rust_mut().speaking = speaking;
            self.speaking_changed();
        }
    }

    fn set_muted(mut self: Pin<&mut Self>, muted: bool) {
        if muted == self.muted {
            return;
        }
        self.as_mut().rust_mut().muted = muted;
        if muted {
            self.as_mut().stop();
        }
        self.muted_changed();
    }
}
