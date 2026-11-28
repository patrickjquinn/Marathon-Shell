//! NFC through neard: the adapter is powered while the NFC setting is on,
//! and polls for tags only while the screen is also on, so its field never
//! runs in a pocket. A tag's first record shows as a notification; a web
//! link on it opens in Pacific when the notification is tapped.

use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use async_io::Timer;

use async_channel::{Receiver, Sender};
use futures_lite::{stream, StreamExt};
use zbus::fdo::{DBusProxy, ObjectManagerProxy};
use zbus::message::Type as MessageType;
use zbus::{MatchRule, MessageStream, OwnedObjectPath, OwnedVariant as OwnedValue};

use crate::i18n::fl;
use crate::notifications::NotificationsProxy;
use crate::{io, log};

const NEARD: &str = "org.neard";
const ADAPTER: &str = "org.neard.Adapter";
const TAG: &str = "org.neard.Tag";
const RECORD: &str = "org.neard.Record";

static ENABLED: AtomicBool = AtomicBool::new(false);
static SCREEN_ON: AtomicBool = AtomicBool::new(true);
static ADAPTER_PRESENT: AtomicBool = AtomicBool::new(false);
static WAKE: OnceLock<Sender<()>> = OnceLock::new();
/// Failed tries in a row at what the adapter should be doing.
static RETRIES: AtomicU32 = AtomicU32::new(0);
const MAX_RETRIES: u32 = 6;
/// Notifications whose tap opens a link, by id.
static LINKS: Mutex<Option<HashMap<u32, String>>> = Mutex::new(None);

/// The phone has an NFC adapter that neard drives.
pub(crate) fn available() -> bool {
    ADAPTER_PRESENT.load(Ordering::Relaxed)
}

/// The NFC setting; the first call starts following neard.
pub(crate) fn enable(on: bool) {
    ENABLED.store(on, Ordering::Relaxed);
    wake();
}

pub(crate) fn screen(on: bool) {
    SCREEN_ON.store(on, Ordering::Relaxed);
    if WAKE.get().is_some() {
        wake();
    }
}

fn wake() {
    let wake = WAKE.get_or_init(|| {
        let (tx, rx) = async_channel::bounded(4);
        io::each_system_bus(move |bus| run(bus, rx.clone()));
        io::each_session_bus(follow_taps);
        tx
    });
    wake.try_send(()).ok();
}

enum Event {
    Wake,
    Rescan,
    Added(
        OwnedObjectPath,
        HashMap<String, HashMap<String, OwnedValue>>,
    ),
    Removed(OwnedObjectPath, Vec<String>),
    Changed(HashMap<String, OwnedValue>),
}

#[derive(Default)]
struct Neard {
    adapter: Option<OwnedObjectPath>,
    powered: bool,
    polling: bool,
    tags: HashSet<OwnedObjectPath>,
}

async fn run(bus: zbus::Connection, wakes: Receiver<()>) {
    let manager = async {
        ObjectManagerProxy::builder(&bus)
            .destination(NEARD)
            .path("/")
            .build()
            .await
    };
    let manager = match manager.await {
        Ok(m) => m,
        Err(e) => return log::warn("nfc", format_args!("cannot follow neard: {e}")),
    };
    let signals = |interface: &'static str, member: &'static str| {
        let bus = bus.clone();
        async move {
            let rule = MatchRule::builder()
                .msg_type(MessageType::Signal)
                .sender(NEARD)
                .interface(interface)
                .member(member)
                .build()?;
            MessageStream::for_match_rule(rule, &bus, std::num::NonZeroUsize::new(64)).await
        }
    };
    let owners = async {
        DBusProxy::new(&bus)
            .await?
            .receive_name_owner_changed_with_args(&[(0, NEARD)])
            .await
    };
    let (Ok(added), Ok(removed), Ok(changed), Ok(owners)) = (
        signals("org.freedesktop.DBus.ObjectManager", "InterfacesAdded").await,
        signals("org.freedesktop.DBus.ObjectManager", "InterfacesRemoved").await,
        signals("org.freedesktop.DBus.Properties", "PropertiesChanged").await,
        owners.await,
    ) else {
        return log::warn("nfc", "cannot follow neard's signals");
    };
    let events = stream::once(Event::Rescan)
        .chain(wakes.map(|()| Event::Wake))
        .or(owners.map(|_| Event::Rescan))
        .or(added.filter_map(|m| {
            let (path, ifaces) = m.ok()?.body().deserialize().ok()?;
            Some(Event::Added(path, ifaces))
        }))
        .or(removed.filter_map(|m| {
            let (path, ifaces) = m.ok()?.body().deserialize().ok()?;
            Some(Event::Removed(path, ifaces))
        }))
        .or(changed.filter_map(|m| {
            let (iface, changed, _): (String, HashMap<String, OwnedValue>, Vec<String>) =
                m.ok()?.body().deserialize().ok()?;
            (iface == ADAPTER).then_some(Event::Changed(changed))
        }));
    let mut events = std::pin::pin!(events);
    let mut neard = Neard::default();
    while let Some(event) = events.next().await {
        match event {
            Event::Wake => {}
            Event::Rescan => neard = scan(&manager).await,
            Event::Added(path, ifaces) => {
                if let Some(props) = ifaces.get(ADAPTER) {
                    neard.powered = flag(props, "Powered");
                    neard.polling = flag(props, "Polling");
                    neard.adapter = Some(path.clone());
                }
                if ifaces.contains_key(TAG) {
                    neard.tags.insert(path.clone());
                }
                if let Some(record) = ifaces.get(RECORD) {
                    show(record).await;
                }
            }
            Event::Removed(path, ifaces) => {
                if ifaces.iter().any(|i| i == ADAPTER) {
                    neard = Neard::default();
                }
                if ifaces.iter().any(|i| i == TAG) {
                    neard.tags.remove(&path);
                }
            }
            Event::Changed(changed) => {
                if changed.contains_key("Powered") {
                    neard.powered = flag(&changed, "Powered");
                }
                if changed.contains_key("Polling") {
                    neard.polling = flag(&changed, "Polling");
                }
            }
        }
        let present = neard.adapter.is_some();
        if ADAPTER_PRESENT.swap(present, Ordering::Relaxed) != present {
            crate::power::state_changed();
        }
        apply(&bus, &mut neard).await;
    }
}

async fn scan(manager: &ObjectManagerProxy<'_>) -> Neard {
    let mut neard = Neard::default();
    for (path, ifaces) in manager.get_managed_objects().await.unwrap_or_default() {
        if let Some(props) = ifaces
            .iter()
            .find(|(i, _)| i.as_str() == ADAPTER)
            .map(|(_, p)| p)
        {
            let props: HashMap<String, OwnedValue> = props
                .iter()
                .filter_map(|(k, v)| Some((k.clone(), v.try_clone().ok()?)))
                .collect();
            neard.powered = flag(&props, "Powered");
            neard.polling = flag(&props, "Polling");
            neard.adapter = Some(path.clone());
        }
        if ifaces.iter().any(|(i, _)| i.as_str() == TAG) {
            neard.tags.insert(path);
        }
    }
    neard
}

fn flag(props: &HashMap<String, OwnedValue>, key: &str) -> bool {
    props
        .get(key)
        .and_then(|v| bool::try_from(v).ok())
        .unwrap_or(false)
}

fn text(props: &HashMap<String, OwnedValue>, key: &str) -> Option<String> {
    props
        .get(key)
        .and_then(|v| String::try_from(v.try_clone().ok()?).ok())
        .filter(|s| !s.is_empty())
}

/// Powered with the setting; polling with the screen on and no tag held.
async fn apply(bus: &zbus::Connection, neard: &mut Neard) {
    let Some(path) = neard.adapter.clone() else {
        return;
    };
    let enabled = ENABLED.load(Ordering::Relaxed);
    let poll = enabled && SCREEN_ON.load(Ordering::Relaxed) && neard.tags.is_empty();
    let adapter = match zbus::Proxy::new(bus, NEARD, path.clone(), ADAPTER).await {
        Ok(a) => a,
        Err(e) => return log::warn("nfc", format_args!("adapter: {e}")),
    };
    if neard.powered != enabled {
        // neard can answer with an error when the adapter did come up (the
        // kernel complains about the secure element), and with "already
        // enabled" once it is: what it reports is what counts.
        if let Err(e) = adapter.set_property("Powered", enabled).await {
            let now: bool = adapter.get_property("Powered").await.unwrap_or(!enabled);
            if now != enabled {
                log::warn("nfc", format_args!("Powered {enabled}: {e}"));
                return retry_later();
            }
        }
        neard.powered = enabled;
        neard.polling &= enabled;
    }
    if poll && !neard.polling {
        match adapter.call_method("StartPollLoop", &("Initiator",)).await {
            Ok(_) => neard.polling = true,
            // Still busy coming up, right after power-on.
            Err(e) => {
                log::warn("nfc", format_args!("StartPollLoop: {e}"));
                return retry_later();
            }
        }
    } else if !poll && neard.polling && neard.powered {
        match adapter.call_method("StopPollLoop", &()).await {
            Ok(_) => neard.polling = false,
            Err(e) => log::warn("nfc", format_args!("StopPollLoop: {e}")),
        }
    }
    RETRIES.store(0, Ordering::Relaxed);
}

/// Tries again a second later, then two, four... for a few tries.
fn retry_later() {
    let tries = RETRIES.fetch_add(1, Ordering::Relaxed);
    if tries >= MAX_RETRIES {
        return;
    }
    io::spawn(async move {
        Timer::after(Duration::from_secs(1 << tries)).await;
        wake();
    });
}

/// A record as a notification: a link, else its text.
async fn show(record: &HashMap<String, OwnedValue>) {
    let uri = text(record, "URI");
    let body = uri
        .clone()
        .or_else(|| text(record, "Representation"))
        .or_else(|| text(record, "MIMEType"))
        .unwrap_or_else(|| fl!("nfc-tag-empty"));
    let link = uri.filter(|u| u.starts_with("https://") || u.starts_with("http://"));
    let open = fl!("nfc-open");
    let actions: Vec<&str> = match link {
        Some(_) => vec!["default", open.as_str()],
        None => Vec::new(),
    };
    let notices = async { NotificationsProxy::new(&io::session_bus().await?).await };
    let sent = match notices.await {
        Ok(n) => {
            n.notify(
                &fl!("nfc-app"),
                0,
                "contactless-payment",
                &fl!("nfc-tag-title"),
                &body,
                &actions,
                HashMap::new(),
                0,
            )
            .await
        }
        Err(e) => Err(e),
    };
    match (sent, link) {
        (Ok(id), Some(link)) => {
            if let Ok(mut links) = LINKS.lock() {
                links.get_or_insert_with(HashMap::new).insert(id, link);
            }
        }
        (Ok(_), None) => {}
        (Err(e), _) => log::warn("nfc", format_args!("tag notice: {e}")),
    }
}

async fn follow_taps(session: zbus::Connection) {
    let actions = async {
        NotificationsProxy::new(&session)
            .await?
            .receive_action_invoked()
            .await
    };
    let mut actions = match actions.await {
        Ok(actions) => actions,
        Err(e) => return log::warn("nfc", format_args!("no notification actions: {e}")),
    };
    while let Some(signal) = actions.next().await {
        let Ok(args) = signal.args() else { continue };
        let link = LINKS
            .lock()
            .ok()
            .and_then(|mut l| l.as_mut()?.remove(&args.id));
        let Some(link) = link else { continue };
        let opened = session
            .call_method(
                Some("org.shipwright.pacific.ui"),
                "/ui",
                Some("org.shipwright.pacific.ui"),
                "openUrl",
                &(vec![link.as_str()],),
            )
            .await;
        if let Err(e) = opened {
            log::warn("nfc", format_args!("cannot open {link}: {e}"));
        }
    }
}
