//! Texts through `ModemManager`: a received text moves from the modem's
//! storage into `messages.db`; a sent one goes out through the first modem
//! that has `Messaging`.

use std::collections::HashMap;
use std::time::Duration;

use async_io::Timer;
use futures_lite::StreamExt;
use marathon_rt::{io, log};
use zbus::fdo::{ObjectManagerProxy, PropertiesProxy};
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};
use zbus::{MatchRule, MessageStream};

use crate::store::Message;
use crate::{now_ms, Core, SmsService};

const MM: &str = "org.freedesktop.ModemManager1";
const MESSAGING: &str = "org.freedesktop.ModemManager1.Modem.Messaging";
const SMS: &str = "org.freedesktop.ModemManager1.Sms";
/// `MMSmsState`.
const RECEIVED: u32 = 3;
const SENT: u32 = 5;

#[zbus::proxy(
    interface = "org.freedesktop.ModemManager1.Modem.Messaging",
    default_service = "org.freedesktop.ModemManager1"
)]
trait Messaging {
    fn list(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
    fn create(&self, properties: HashMap<&str, Value<'_>>) -> zbus::Result<OwnedObjectPath>;
    fn delete(&self, path: &OwnedObjectPath) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.freedesktop.ModemManager1.Sms",
    default_service = "org.freedesktop.ModemManager1"
)]
trait Sms {
    fn send(&self) -> zbus::Result<()>;
}

/// An ISO 8601 time (`ModemManager`'s and mmsd-tng's) as Unix milliseconds.
pub fn iso_ms(text: &str) -> Option<i64> {
    let digits = |s: &str| s.parse::<u8>().ok();
    let (date, time) = text.trim().split_once('T')?;
    let mut ymd = date.splitn(3, '-');
    let year: i32 = ymd.next()?.parse().ok()?;
    let (month, day) = (digits(ymd.next()?)?, digits(ymd.next()?)?);
    let zone_at = time.find(['Z', '+', '-']).unwrap_or(time.len());
    let (clock, zone) = time.split_at(zone_at);
    let mut hms = clock.split(':');
    let (hour, minute) = (digits(hms.next()?)?, digits(hms.next()?)?);
    let second = hms
        .next()
        .map_or(Some(0), |s| digits(s.split('.').next()?))?;
    let offset = match zone.chars().next() {
        Some(sign @ ('+' | '-')) => {
            let zone: String = zone[1..].chars().filter(char::is_ascii_digit).collect();
            let hours: i64 = zone.get(..2)?.parse().ok()?;
            let minutes: i64 = zone.get(2..4).map_or(Some(0), |m| m.parse().ok())?;
            (hours * 60 + minutes) * 60 * if sign == '-' { -1 } else { 1 }
        }
        _ => 0,
    };
    let utc = tz::UtcDateTime::new(year, month, day, hour, minute, second, 0).ok()?;
    Some((utc.unix_time() - offset) * 1000)
}

async fn modems(bus: &zbus::Connection) -> zbus::Result<Vec<MessagingProxy<'static>>> {
    let manager = ObjectManagerProxy::builder(bus)
        .destination(MM)?
        .path("/org/freedesktop/ModemManager1")?
        .build()
        .await?;
    let mut found = Vec::new();
    for (path, interfaces) in manager.get_managed_objects().await? {
        if interfaces.keys().any(|i| i.as_str() == MESSAGING) {
            found.push(MessagingProxy::builder(bus).path(path)?.build().await?);
        }
    }
    Ok(found)
}

fn field<T: TryFrom<OwnedValue>>(props: &HashMap<String, OwnedValue>, key: &str) -> Option<T> {
    props
        .get(key)
        .and_then(|v| v.try_clone().ok())
        .and_then(|v| T::try_from(v).ok())
}

/// Moves each received text into the store. A text still arriving is
/// left, and one without text (an MMS notification) is left for mmsd-tng.
async fn drain(core: &Core, bus: &zbus::Connection) -> zbus::Result<()> {
    for modem in modems(bus).await? {
        for path in modem.list().await? {
            let props = PropertiesProxy::builder(bus)
                .destination(MM)?
                .path(&path)?
                .build()
                .await?;
            let props = props.get_all(SMS.try_into()?).await?;
            let state: u32 = field(&props, "State").unwrap_or_default();
            let text: String = field(&props, "Text").unwrap_or_default();
            if state == SENT {
                modem.delete(&path).await.ok();
            }
            if state != RECEIVED || text.is_empty() {
                continue;
            }
            let sender: String = field(&props, "Number").unwrap_or_default();
            let timestamp = field::<String>(&props, "Timestamp")
                .and_then(|t| iso_ms(&t))
                .unwrap_or_else(now_ms);
            let (who, said) = (sender.clone(), text.clone());
            match core
                .store
                .with(move |s| s.has(&who, timestamp, &said))
                .await
            {
                Ok(false) => {
                    core.receive(sender.clone(), text, timestamp, String::new(), Vec::new())
                        .await;
                }
                Ok(true) => {}
                Err(e) => {
                    log::warn(
                        "Sms",
                        format_args!("cannot check whether a text from {sender} is stored: {e}"),
                    );
                    continue;
                }
            }
            if let Err(e) = modem.delete(&path).await {
                log::warn(
                    "Sms",
                    format_args!("cannot delete {path} from the modem: {e}"),
                );
            }
        }
    }
    Ok(())
}

/// Drains the modem at start, on each `Messaging.Added` and once a minute.
pub async fn watch(core: &Core) {
    let Ok(bus) = io::system_bus().await else {
        return log::warn("Sms", "no system bus");
    };
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(MM)
        .and_then(|r| r.interface(MESSAGING))
        .and_then(|r| r.member("Added"));
    let added = match rule {
        Ok(rule) => MessageStream::for_match_rule(rule.build(), &bus, None).await,
        Err(e) => Err(e),
    };
    let mut added = match added {
        Ok(stream) => stream.map(|_| ()).boxed(),
        Err(e) => {
            log::warn("Sms", format_args!("no Messaging.Added: {e}"));
            futures_lite::stream::pending().boxed()
        }
    };
    loop {
        if let Err(e) = drain(core, &bus).await {
            log::warn("Sms", format_args!("cannot read the modem's texts: {e}"));
        }
        futures_lite::future::or(async { added.next().await.unwrap_or(()) }, async {
            Timer::after(Duration::from_mins(1)).await;
        })
        .await;
    }
}

async fn send_through_modem(recipient: &str, text: &str) -> Result<(), String> {
    let bus = io::system_bus()
        .await
        .map_err(|e| format!("No modem available: {e}"))?;
    let modem = modems(&bus)
        .await
        .map_err(|e| format!("No modem available: {e}"))?;
    let modem = modem
        .into_iter()
        .next()
        .ok_or("No SMS-capable modem available")?;
    let properties = HashMap::from([
        ("number", Value::from(recipient)),
        ("text", Value::from(text)),
    ]);
    let path = modem
        .create(properties)
        .await
        .map_err(|e| format!("Failed to create SMS: {e}"))?;
    let sms = SmsProxy::builder(&bus)
        .path(path)
        .map_err(|e| e.to_string())?
        .build()
        .await
        .map_err(|e| e.to_string())?;
    sms.send()
        .await
        .map_err(|e| format!("Failed to send SMS: {e}"))
}

/// Sends a text and stores it as sent, or as failed with `SendFailed`.
pub async fn send(core: &Core, recipient: String, text: String) {
    if recipient.is_empty() || text.is_empty() {
        return core
            .send_failed(&recipient, "Message text or recipient is empty")
            .await;
    }
    let sent = send_through_modem(&recipient, &text).await;
    let timestamp = now_ms();
    let (to, body, ok) = (recipient.clone(), text, sent.is_ok());
    let stored = core
        .store
        .with(move |s| {
            let status = if ok { "sent" } else { "failed" };
            s.insert(&Message {
                sender: "me",
                recipient: &to,
                text: &body,
                timestamp,
                outgoing: true,
                status,
                mms_path: "",
            })
        })
        .await;
    if let Err(e) = stored {
        log::warn(
            "Sms",
            format_args!("cannot store a text to {recipient}: {e}"),
        );
    }
    SmsService::conversations_changed(&core.sms()).await.ok();
    match sent {
        Ok(()) => SmsService::message_sent(&core.sms(), &recipient, timestamp)
            .await
            .ok(),
        Err(reason) => {
            log::warn("Sms", format_args!("{reason}"));
            SmsService::send_failed(&core.sms(), &recipient, &reason)
                .await
                .ok()
        }
    };
}

#[cfg(test)]
mod tests {
    use super::iso_ms;

    #[test]
    fn modem_times_keep_their_zone() {
        assert_eq!(iso_ms("2026-10-20T10:00:00Z"), Some(1_792_490_400_000));
        assert_eq!(iso_ms("2026-10-20T12:00:00+02"), Some(1_792_490_400_000));
        assert_eq!(iso_ms("2026-10-20T05:30:00-0430"), Some(1_792_490_400_000));
        assert_eq!(
            iso_ms("2026-10-20T10:00:00.5+00:00"),
            Some(1_792_490_400_000)
        );
        assert_eq!(iso_ms("yesterday"), None);
    }
}
