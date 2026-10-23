//! The `UnifiedPush` distributor (spec v2, unifiedpush.org/developers/spec/dbus)
//! on the session bus, with ntfy as its push server: a registration is an ntfy
//! topic, its endpoint `https://<server>/<topic>`, and one WebSocket per topic
//! hands its messages to the app's `org.unifiedpush.Connector2`. The server is
//! ntfy.sh unless `MARATHON_NTFY_SERVER` names another.

use std::collections::HashMap;
use std::io::Read;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use async_channel::{Receiver, Sender};
use async_io::Timer;
use async_tungstenite::tungstenite::Message;
use futures_lite::{future, StreamExt};
use serde::{Deserialize, Serialize};
use zbus::fdo::{RequestNameFlags, RequestNameReply};
use zbus::zvariant::{OwnedValue, Value};
use zbus::Connection;

use crate::notifications::NotificationsProxy;
use crate::{io, log, stored};

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::push"]
    extern "Rust" {
        /// Takes the distributor's name, unless another distributor has it.
        fn serve();
        /// Each message also posts "New push notification" for its app.
        fn set_fallback_notifications(on: bool);
    }
}

const NAME: &str = "org.unifiedpush.Distributor.marathon";
const PATH: &str = "/org/unifiedpush/Distributor";
const BACKOFF_MAX: Duration = Duration::from_mins(1);
const SILENCE: Duration = Duration::from_mins(2);

static FALLBACK: AtomicBool = AtomicBool::new(false);

fn set_fallback_notifications(on: bool) {
    FALLBACK.store(on, Ordering::Relaxed);
}

fn serve() {
    io::spawn(async {
        if let Err(e) = start().await {
            log::warn("push", format_args!("no distributor: {e}"));
        }
    });
}

async fn start() -> zbus::Result<()> {
    let conn = io::session_bus().await?;
    let registrations = load();
    let distributor = Distributor {
        registrations: registrations.clone(),
        subscriptions: HashMap::new(),
    };
    conn.object_server().at(PATH, distributor).await?;
    let reply = conn
        .request_name_with_flags(NAME, RequestNameFlags::DoNotQueue.into())
        .await?;
    if !matches!(
        reply,
        RequestNameReply::PrimaryOwner | RequestNameReply::AlreadyOwner
    ) {
        log::warn(
            "push",
            format_args!("another distributor has {NAME}; yielding"),
        );
        conn.object_server().remove::<Distributor, _>(PATH).await?;
        return Ok(());
    }
    // Subscriptions resume without waiting for apps to register again.
    let iface = conn
        .object_server()
        .interface::<_, Distributor>(PATH)
        .await?;
    let mut distributor = iface.get_mut().await;
    for (token, registration) in &registrations {
        distributor.subscribe(&conn, token, &registration.endpoint);
    }
    Ok(())
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
struct Registration {
    /// The app's well-known name.
    service: String,
    description: String,
    /// The last endpoint the app was given; "" until the topic is subscribed.
    endpoint: String,
}

struct Distributor {
    registrations: HashMap<String, Registration>,
    // Dropping a token's sender closes its socket.
    subscriptions: HashMap<String, Sender<()>>,
}

type Reply = HashMap<&'static str, Value<'static>>;

#[zbus::interface(name = "org.unifiedpush.Distributor2")]
impl Distributor {
    /// `service`, `token`, optional `description` and `vapid`; answers
    /// `success`: "OK" or why not, and `reason`.
    fn register(
        &mut self,
        mut args: HashMap<String, OwnedValue>,
        #[zbus(connection)] conn: &Connection,
    ) -> Reply {
        let (service, token, description) = (
            take(&mut args, "service"),
            take(&mut args, "token"),
            take(&mut args, "description"),
        );
        if service.is_empty() || token.is_empty() {
            return Reply::from([
                ("success", "INVALID_ARGUMENTS".into()),
                ("reason", "service and token are required".into()),
            ]);
        }
        let mut registrations = self.registrations.clone();
        let registration = registrations.entry(token.clone()).or_default();
        registration.service = service;
        registration.description = description;
        let registration = registration.clone();
        if let Err(error) = save(&registrations) {
            log::warn("push", format_args!("saving registration: {error}"));
            return Reply::from([
                ("success", "INTERNAL_ERROR".into()),
                ("reason", error.to_string().into()),
            ]);
        }
        self.registrations = registrations;
        self.subscribe(conn, &token, &registration.endpoint);
        if !registration.endpoint.is_empty() {
            connector(
                conn,
                &registration.service,
                "NewEndpoint",
                [
                    ("token", token.into()),
                    ("endpoint", registration.endpoint.into()),
                ],
            );
        }
        Reply::from([("success", "OK".into())])
    }

    fn unregister(
        &mut self,
        mut args: HashMap<String, OwnedValue>,
        #[zbus(connection)] conn: &Connection,
    ) -> Reply {
        let token = take(&mut args, "token");
        let mut registrations = self.registrations.clone();
        if let Some(registration) = registrations.remove(&token) {
            if let Err(error) = save(&registrations) {
                log::warn("push", format_args!("removing registration: {error}"));
                return Reply::from([
                    ("success", "INTERNAL_ERROR".into()),
                    ("reason", error.to_string().into()),
                ]);
            }
            self.registrations = registrations;
            self.subscriptions.remove(&token);
            connector(
                conn,
                &registration.service,
                "Unregistered",
                [("token", token.into())],
            );
        }
        Reply::new()
    }
}

impl Distributor {
    fn subscribe(&mut self, conn: &Connection, token: &str, endpoint: &str) {
        if self.subscriptions.contains_key(token) {
            return;
        }
        let topic = if endpoint.is_empty() {
            mint_topic()
        } else {
            topic_of(endpoint).to_owned()
        };
        if topic.is_empty() {
            return log::warn("push", format_args!("no topic for {token}"));
        }
        let (stop, stopped) = async_channel::bounded(1);
        self.subscriptions.insert(token.to_owned(), stop);
        io::spawn(listen(
            conn.clone(),
            token.to_owned(),
            topic,
            endpoint.is_empty(),
            stopped,
        ));
    }
}

fn take(args: &mut HashMap<String, OwnedValue>, key: &str) -> String {
    args.remove(key)
        .and_then(|v| String::try_from(v).ok())
        .unwrap_or_default()
}

/// Calls the app's connector without waiting for it.
fn connector<const N: usize>(
    conn: &Connection,
    service: &str,
    method: &'static str,
    args: [(&'static str, Value<'static>); N],
) {
    let (conn, service) = (conn.clone(), service.to_owned());
    io::spawn(async move {
        let args: HashMap<_, _> = args.into_iter().collect();
        let called = conn
            .call_method(
                Some(service.as_str()),
                "/org/unifiedpush/Connector",
                Some("org.unifiedpush.Connector2"),
                method,
                &(args,),
            )
            .await;
        if let Err(e) = called {
            log::warn("push", format_args!("{service} {method}: {e}"));
        }
    });
}

fn server() -> String {
    std::env::var("MARATHON_NTFY_SERVER")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "https://ntfy.sh".to_owned())
}

/// Whether the server takes TLS, and its host and port.
fn host(server: &str) -> (bool, &str) {
    let (tls, rest) = match server.strip_prefix("http://") {
        Some(rest) => (false, rest),
        None => (true, server.strip_prefix("https://").unwrap_or(server)),
    };
    (tls, rest.split('/').next().unwrap_or_default())
}

fn endpoint_for(server: &str, topic: &str) -> String {
    format!("https://{}/{topic}", host(server).1)
}

fn topic_of(endpoint: &str) -> &str {
    endpoint
        .split_once("://")
        .map_or(endpoint, |(_, rest)| rest)
        .split_once('/')
        .map_or("", |(_, path)| path)
}

fn random<const N: usize>() -> [u8; N] {
    let mut bytes = [0; N];
    if let Err(e) = std::fs::File::open("/dev/urandom").and_then(|mut f| f.read_exact(&mut bytes)) {
        log::warn("push", format_args!("/dev/urandom: {e}"));
    }
    bytes
}

/// 16 lowercase letters and digits: ntfy's topics are global, and the
/// topic is all it takes to read one.
fn mint_topic() -> String {
    const ALPHABET: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789";
    random::<16>()
        .iter()
        .map(|b| char::from(ALPHABET[usize::from(*b) % ALPHABET.len()]))
        .collect()
}

fn message_id() -> String {
    let hex = format!("{:032x}", u128::from_be_bytes(random()));
    format!(
        "{}-{}-{}-{}-{}",
        &hex[..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..]
    )
}

/// The topic's socket, reopened with a backoff from 1 s to a minute, until
/// the registration goes.
async fn listen(
    conn: Connection,
    token: String,
    topic: String,
    mut fresh: bool,
    stopped: Receiver<()>,
) {
    let server = server();
    let (tls, host) = host(&server);
    let url = format!("{}://{host}/{topic}/ws", if tls { "wss" } else { "ws" });
    let mut retry = Duration::from_secs(1);
    loop {
        let session = async {
            let (mut socket, _) = async_tungstenite::smol::connect_async(url.as_str()).await?;
            retry = Duration::from_secs(1);
            if fresh {
                deliver_endpoint(&conn, &token, endpoint_for(&server, &topic)).await;
                fresh = false;
            }
            // ntfy sends a keepalive every 45 s; a socket silent for longer
            // lost its connection without a close.
            loop {
                let frame = future::or(async { socket.next().await }, async {
                    Timer::after(SILENCE).await;
                    Some(Err(
                        std::io::Error::from(std::io::ErrorKind::TimedOut).into()
                    ))
                });
                let Some(frame) = frame.await else { break };
                if let Message::Text(json) = frame? {
                    deliver_message(&conn, &token, json.as_str()).await;
                }
            }
            Ok::<_, async_tungstenite::tungstenite::Error>(())
        };
        match future::or(async { Some(Box::pin(session).await) }, async {
            stopped.recv().await.ok();
            None
        })
        .await
        {
            None => return,
            Some(Err(e)) => log::warn("push", format_args!("{url}: {e}")),
            Some(Ok(())) => {}
        }
        let stop = future::or(
            async {
                Timer::after(retry).await;
                false
            },
            async { stopped.recv().await.is_err() },
        );
        if stop.await {
            return;
        }
        retry = (retry * 2).min(BACKOFF_MAX);
    }
}

async fn deliver_endpoint(conn: &Connection, token: &str, endpoint: String) {
    let Ok(iface) = conn.object_server().interface::<_, Distributor>(PATH).await else {
        return;
    };
    let mut distributor = iface.get_mut().await;
    let mut registrations = distributor.registrations.clone();
    let Some(registration) = registrations.get_mut(token) else {
        return;
    };
    registration.endpoint.clone_from(&endpoint);
    let service = registration.service.clone();
    if let Err(error) = save(&registrations) {
        return log::warn("push", format_args!("saving endpoint: {error}"));
    }
    distributor.registrations = registrations;
    connector(
        conn,
        &service,
        "NewEndpoint",
        [
            ("token", token.to_owned().into()),
            ("endpoint", endpoint.into()),
        ],
    );
}

/// ntfy's "message" events; "open", "keepalive" and `poll_request` only
/// keep the socket warm.
async fn deliver_message(conn: &Connection, token: &str, json: &str) {
    let Ok(event) = serde_json::from_str::<serde_json::Value>(json) else {
        return;
    };
    if event["event"] != "message" {
        return;
    }
    let payload = event["message"]
        .as_str()
        .unwrap_or_default()
        .as_bytes()
        .to_vec();
    let Ok(iface) = conn.object_server().interface::<_, Distributor>(PATH).await else {
        return;
    };
    let Some(registration) = iface.get().await.registrations.get(token).cloned() else {
        return;
    };
    connector(
        conn,
        &registration.service,
        "Message",
        [
            ("token", token.to_owned().into()),
            ("message", payload.into()),
            ("id", message_id().into()),
        ],
    );
    if FALLBACK.load(Ordering::Relaxed) {
        // Payloads are opaque, often end-to-end encrypted: the app has the keys.
        let title = if registration.description.is_empty() {
            &registration.service
        } else {
            &registration.description
        };
        let hints = HashMap::from([("category", Value::from("push"))]);
        let posted = async {
            NotificationsProxy::new(conn)
                .await?
                .notify(
                    &registration.service,
                    0,
                    "",
                    title,
                    "New push notification",
                    &[],
                    hints,
                    -1,
                )
                .await
        };
        if let Err(e) = posted.await {
            log::warn("push", format_args!("fallback notification: {e}"));
        }
    }
}

fn load() -> HashMap<String, Registration> {
    stored::load("unifiedpush.json").unwrap_or_else(|| {
        from_qsettings(
            &marathon_rt::dirs::config().join("Marathon OS/Marathon Shell/unifiedpush.ini"),
        )
    })
}

fn save(registrations: &HashMap<String, Registration>) -> Result<(), stored::SaveError> {
    stored::save("unifiedpush.json", registrations)
}

/// The registrations the C++ shell kept, a `QSettings` array.
fn from_qsettings(path: &Path) -> HashMap<String, Registration> {
    let mut rows: HashMap<String, (String, Registration)> = HashMap::new();
    for (key, value) in stored::qsettings(path, "unifiedpush") {
        let mut parts = key.split('\\');
        let (Some("registrations"), Some(row), Some(field)) =
            (parts.next(), parts.next(), parts.next())
        else {
            continue;
        };
        let (token, registration) = rows.entry(row.to_owned()).or_default();
        match field {
            "token" => *token = value,
            "service" => registration.service = value,
            "description" => registration.description = value,
            "endpoint" => registration.endpoint = value,
            _ => {}
        }
    }
    rows.into_values()
        .filter(|(token, _)| !token.is_empty())
        .collect()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn endpoints_and_topics_round_trip() {
        assert_eq!(
            endpoint_for("https://ntfy.sh", "abc"),
            "https://ntfy.sh/abc"
        );
        assert_eq!(
            endpoint_for("http://push.local:8080/", "abc"),
            "https://push.local:8080/abc"
        );
        assert_eq!(host("http://push.local:8080"), (false, "push.local:8080"));
        assert_eq!(topic_of("https://ntfy.sh/abc"), "abc");
        assert_eq!(topic_of("https://ntfy.sh"), "");
        let topic = mint_topic();
        assert_eq!(topic.len(), 16);
        assert!(topic
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit()));
        assert_ne!(topic, mint_topic());
    }

    #[test]
    fn the_qt_settings_carry_over() {
        let dir = tempfile::tempdir().unwrap();
        let ini = dir.path().join("unifiedpush.ini");
        std::fs::write(&ini, "[unifiedpush]\nregistrations\\1\\description=Chat\nregistrations\\1\\endpoint=https://ntfy.sh/abc\nregistrations\\1\\service=org.example.Chat\nregistrations\\1\\token=t1\nregistrations\\2\\service=org.example.Bare\nregistrations\\size=2\n").unwrap();
        let registrations = from_qsettings(&ini);
        assert_eq!(registrations.len(), 1);
        assert_eq!(
            registrations["t1"],
            Registration {
                service: "org.example.Chat".into(),
                description: "Chat".into(),
                endpoint: "https://ntfy.sh/abc".into()
            }
        );
    }
}
