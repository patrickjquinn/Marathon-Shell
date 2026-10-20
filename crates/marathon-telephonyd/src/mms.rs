//! MMS through mmsd-tng (`org.ofono.mms` on the session bus,
//! doc/service-api.txt and doc/message-api.txt in mmsd-tng). mmsd-tng is
//! bus-activated; it is asked for its service at start and whenever it
//! takes its name.

use std::collections::HashMap;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;
use std::sync::PoisonError;

use futures_lite::StreamExt;
use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
use image::{DynamicImage, ImageDecoder, ImageReader};
use marathon_rt::log;
use zbus::fdo;
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Value};
use zbus::{MatchRule, MessageStream};

use crate::{modem, Core, SmsService};

const BUS: &str = "org.ofono.mms";
const MANAGER: &str = "/org/ofono/mms";
const SERVICE: &str = "org.ofono.mms.Service";
const MODEM_MANAGER: &str = "org.ofono.mms.ModemManager";
const CARRIER_KEYS: &[&str] = &["CarrierMMSC", "MMS_APN", "CarrierMMSProxy", "DefaultModemNumber", "AutoProcessOnConnection"];
const SERVICE_KEYS: &[&str] = &["UseDeliveryReports"];
/// When mmsd-tng reports no carrier limit.
const DEFAULT_LIMIT: i64 = 300 * 1024;

/// mmsd-tng's service, while it has one.
#[derive(Default)]
pub struct Service {
    path: Option<OwnedObjectPath>,
    max_size: i64,
}

type Props = HashMap<String, OwnedValue>;

fn field<T: TryFrom<OwnedValue>>(props: &Props, key: &str) -> Option<T> {
    props.get(key).and_then(|v| v.try_clone().ok()).and_then(|v| T::try_from(v).ok())
}

fn service(core: &Core) -> Option<OwnedObjectPath> {
    core.mms.lock().unwrap_or_else(PoisonError::into_inner).path.clone()
}

pub fn available(core: &Core) -> bool {
    service(core).is_some()
}

async fn call<R>(core: &Core, path: &str, interface: &str, method: &str, body: &(impl serde::Serialize + zbus::zvariant::DynamicType)) -> zbus::Result<R>
where
    R: serde::de::DeserializeOwned + zbus::zvariant::Type,
{
    core.bus.call_method(Some(BUS), path, Some(interface), method, body).await?.body().deserialize()
}

async fn discover(core: &Core) {
    let services: Vec<(OwnedObjectPath, Props)> = match call(core, MANAGER, "org.ofono.mms.Manager", "GetServices", &()).await {
        Ok(services) => services,
        Err(e) => return log::warn("Mms", format_args!("no mmsd-tng service: {e}")),
    };
    let Some((path, _)) = services.into_iter().next() else { return };
    let props: Props = call(core, path.as_str(), SERVICE, "GetProperties", &()).await.unwrap_or_default();
    let max_size = field::<i64>(&props, "TotalMaxAttachmentSize").or_else(|| field::<u32>(&props, "TotalMaxAttachmentSize").map(i64::from));
    let was = {
        let mut state = core.mms.lock().unwrap_or_else(PoisonError::into_inner);
        let was = state.path.replace(path).is_some();
        state.max_size = max_size.unwrap_or_default();
        was
    };
    if !was {
        SmsService::mms_available_changed(&core.sms(), true).await.ok();
    }
}

async fn forget(core: &Core) {
    let was = core.mms.lock().unwrap_or_else(PoisonError::into_inner).path.take().is_some();
    if was {
        SmsService::mms_available_changed(&core.sms(), false).await.ok();
    }
}

/// A received MMS joins its sender's thread; its pictures are copied out of
/// mmsd-tng's store, its text parts joined.
async fn added(core: &Core, path: String, props: Props) {
    let status: String = field(&props, "Status").unwrap_or_default();
    if status == "sent" || status == "sending_failed" {
        return status_changed(core, path, &status).await;
    }
    if status != "received" && status != "read" {
        return;
    }
    let parts: Vec<(String, String, String, u64, u64)> = field(&props, "Attachments").unwrap_or_default();
    let (text, attachments) = blocking::unblock(move || {
        let mut text = String::new();
        let mut attachments = Vec::new();
        for (id, content_type, file, offset, length) in parts {
            let mut data = Vec::new();
            let read = std::fs::File::open(&file).and_then(|mut f| {
                f.seek(SeekFrom::Start(offset))?;
                f.take(length).read_to_end(&mut data)
            });
            if read.is_err() || content_type.starts_with("application/smil") {
                continue;
            }
            if content_type.starts_with("text/plain") {
                if !text.is_empty() {
                    text.push('\n');
                }
                text.push_str(&String::from_utf8_lossy(&data));
            } else {
                attachments.push((content_type, id, data));
            }
        }
        (text, attachments)
    })
    .await;
    let sender: String = field(&props, "Sender").unwrap_or_default();
    let when = field::<String>(&props, "Date").and_then(|d| modem::iso_ms(&d)).unwrap_or_else(crate::now_ms);
    core.receive(sender, text, when, path, attachments).await;
}

async fn status_changed(core: &Core, path: String, status: &str) {
    let status = if status == "sent" { "sent" } else { "failed" };
    if let Some(id) = core.store.with(move |s| s.sent_as(&path)).await {
        core.set_status(id, status).await;
    }
}

/// Follows mmsd-tng: its name, its service, its messages and its settings.
pub async fn watch(core: &Core) {
    let rule = MatchRule::builder().msg_type(zbus::message::Type::Signal).sender(BUS).map(zbus::match_rule::Builder::build);
    let owner = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender("org.freedesktop.DBus")
        .and_then(|r| r.member("NameOwnerChanged"))
        .and_then(|r| r.arg(0, BUS))
        .map(zbus::match_rule::Builder::build);
    let (Ok(rule), Ok(owner)) = (rule, owner) else { return };
    let (Ok(signals), Ok(owners)) =
        (MessageStream::for_match_rule(rule, &core.bus, None).await, MessageStream::for_match_rule(owner, &core.bus, None).await)
    else {
        return log::warn("Mms", "cannot follow mmsd-tng");
    };
    discover(core).await;
    let mut events = std::pin::pin!(signals.or(owners));
    while let Some(Ok(message)) = events.next().await {
        let header = message.header();
        let (Some(interface), Some(member)) = (header.interface(), header.member()) else { continue };
        let path = header.path().map(ToString::to_string).unwrap_or_default();
        let body = message.body();
        match (interface.as_str(), member.as_str()) {
            ("org.freedesktop.DBus", "NameOwnerChanged") => match body.deserialize::<(String, String, String)>() {
                Ok((_, _, new)) if new.is_empty() => forget(core).await,
                Ok(_) => discover(core).await,
                Err(_) => {}
            },
            (SERVICE, "MessageAdded") => {
                if let Ok((path, props)) = body.deserialize::<(OwnedObjectPath, Props)>() {
                    added(core, path.to_string(), props).await;
                }
            }
            (SERVICE, "MessageSendError") => {
                if let Some(path) = body.deserialize::<Props>().ok().and_then(|info| field::<String>(&info, "MessagePath")) {
                    status_changed(core, path, "sending_failed").await;
                }
            }
            ("org.ofono.mms.Message", "PropertyChanged") => {
                if let Ok((name, value)) = body.deserialize::<(String, OwnedValue)>() {
                    if let (true, Ok(status)) = (name == "Status", String::try_from(value)) {
                        if status == "sent" || status == "sending_failed" {
                            status_changed(core, path, &status).await;
                        }
                    }
                }
            }
            (MODEM_MANAGER, "SettingsChanged") => {
                if let Ok((apn, mmsc, proxy)) = body.deserialize::<(String, String, String)>() {
                    let settings = HashMap::from([
                        ("MMS_APN".to_owned(), OwnedValue::from(zbus::zvariant::Str::from(apn))),
                        ("CarrierMMSC".to_owned(), OwnedValue::from(zbus::zvariant::Str::from(mmsc))),
                        ("CarrierMMSProxy".to_owned(), OwnedValue::from(zbus::zvariant::Str::from(proxy))),
                    ]);
                    SmsService::mms_settings_changed(&core.sms(), settings).await.ok();
                }
            }
            (MODEM_MANAGER, "BearerHandlerError") => {
                if let Ok((code,)) = body.deserialize::<(u32,)>() {
                    SmsService::mms_bearer_error(&core.sms(), code).await.ok();
                }
            }
            _ => {}
        }
    }
}

/// A picture over `budget` bytes re-encoded as a smaller JPEG.
fn shrink(path: &Path, budget: i64) -> Option<Vec<u8>> {
    let budget = usize::try_from(budget).ok().filter(|b| *b > 0)?;
    let mut decoder = ImageReader::open(path).ok()?.with_guessed_format().ok()?.into_decoder().ok()?;
    let orientation = decoder.orientation().ok()?;
    let mut image = DynamicImage::from_decoder(decoder).ok()?;
    image.apply_orientation(orientation);
    let mut image = DynamicImage::ImageRgb8(image.to_rgb8());
    let mut quality = 85;
    while image.width() >= 160 {
        let mut jpeg = Vec::new();
        image.write_with_encoder(JpegEncoder::new_with_quality(&mut jpeg, quality)).ok()?;
        if jpeg.len() <= budget {
            return Some(jpeg);
        }
        #[allow(clippy::cast_precision_loss, clippy::cast_possible_truncation, clippy::cast_sign_loss, reason = "pixel sizes")]
        let scale = |side: u32| (f64::from(side) * (budget as f64 / jpeg.len() as f64).sqrt().min(0.9)).round() as u32;
        image = image.resize(scale(image.width()), scale(image.height()), FilterType::Triangle);
        quality = (quality - 10).max(60);
    }
    None
}

/// Fits each attachment to the carrier's limit and queues the message with
/// mmsd-tng; its status follows in `MessageStatusChanged`.
pub async fn send(core: &Core, id: i32, recipients: Vec<String>, text: String, attachments: Vec<i32>) {
    let to = recipients.join(",");
    let fail = |reason: &'static str| async move {
        core.set_status(id, "failed").await;
        core.send_failed(&to, reason).await;
    };
    let Some(service) = service(core) else { return fail("MMS isn't available").await };
    let limit = match core.mms.lock().unwrap_or_else(PoisonError::into_inner).max_size {
        0 => DEFAULT_LIMIT,
        limit => limit,
    };
    let count = i64::try_from(attachments.len()).unwrap_or(1).max(1);
    let budget = if attachments.is_empty() { limit } else { (limit - i64::try_from(text.len()).unwrap_or(limit) - 2048) / count };
    let parts = core
        .store
        .with(move |s| {
            let mut parts = Vec::new();
            for attachment in attachments {
                let a = s.attachment(attachment)?;
                if a.size > budget {
                    let jpeg = a.content_type.starts_with("image/").then(|| shrink(&a.path, budget)).flatten()?;
                    std::fs::write(&a.path, &jpeg).ok()?;
                    s.became_jpeg(attachment, &a.name, i64::try_from(jpeg.len()).ok()?).then_some(())?;
                }
                let a = s.attachment(attachment)?;
                parts.push((a.name, a.content_type, a.path.to_string_lossy().into_owned()));
            }
            Some(parts)
        })
        .await;
    let Some(mut parts) = parts else { return fail("Too big to send as MMS").await };
    let body = (!text.is_empty()).then(|| std::env::temp_dir().join(format!("marathon/mms-out/text-{id}.txt")));
    if let Some(file) = &body {
        let written = file.parent().map(std::fs::create_dir_all).transpose().and_then(|_| std::fs::write(file, &text));
        if written.is_err() {
            return fail("The message could not be prepared").await;
        }
        parts.insert(0, ("text.txt".to_owned(), "text/plain;charset=utf-8".to_owned(), file.to_string_lossy().into_owned()));
    }
    let queued: zbus::Result<OwnedObjectPath> = call(core, service.as_str(), SERVICE, "SendMessage", &(recipients, Value::from(""), parts)).await;
    body.as_deref().map(std::fs::remove_file);
    match queued {
        Ok(path) => {
            let path = path.to_string();
            core.store.with(move |s| s.set_mms_path(id, &path)).await.ok();
        }
        Err(e) => {
            core.set_status(id, "failed").await;
            core.send_failed("", &crate::reason(&e)).await;
        }
    }
}

/// mmsd-tng's carrier settings merged with its service's properties.
pub async fn settings(core: &Core) -> Props {
    let Some(service) = service(core) else { return Props::new() };
    let mut all: Props = call(core, MANAGER, MODEM_MANAGER, "ViewSettings", &()).await.unwrap_or_default();
    all.extend(call::<Props>(core, service.as_str(), SERVICE, "GetProperties", &()).await.unwrap_or_default());
    all
}

/// Carrier keys go to `ChangeSettings`, then the queue is processed again;
/// service keys to `SetProperty`. Nothing changes when a key is unknown.
pub async fn change_settings(core: &Core, values: &Props) -> fdo::Result<()> {
    let Some(service) = service(core) else { return Err(fdo::Error::NotSupported("MMS isn't available".into())) };
    if let Some(key) = values.keys().find(|k| !CARRIER_KEYS.contains(&k.as_str()) && !SERVICE_KEYS.contains(&k.as_str())) {
        return Err(fdo::Error::InvalidArgs(format!("{key} can't be changed")));
    }
    let invalid = |e: zbus::Error| fdo::Error::InvalidArgs(crate::reason(&e));
    let mut carrier = false;
    for (key, value) in values {
        let value = Value::from(value.try_clone().map_err(|e| fdo::Error::InvalidArgs(e.to_string()))?);
        if CARRIER_KEYS.contains(&key.as_str()) {
            carrier = true;
            call::<()>(core, MANAGER, MODEM_MANAGER, "ChangeSettings", &(key, value)).await.map_err(invalid)?;
        } else {
            call::<()>(core, service.as_str(), SERVICE, "SetProperty", &(key, value)).await.map_err(invalid)?;
        }
    }
    if carrier {
        call::<()>(core, MANAGER, MODEM_MANAGER, "ProcessMessageQueue", &()).await.map_err(invalid)?;
    }
    Ok(())
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn a_big_photo_is_scaled_down_to_fit() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("big.png");
        let noise = image::RgbImage::from_fn(1600, 1200, |x, y| image::Rgb([((x * 7) ^ (y * 13)).to_le_bytes()[0], (x * y).to_le_bytes()[0], (x + y).to_le_bytes()[0]]));
        noise.save(&path).unwrap();
        let jpeg = shrink(&path, 100 * 1024).unwrap();
        assert!(jpeg.len() <= 100 * 1024);
        assert!(image::load_from_memory(&jpeg).unwrap().width() < 1600);
        assert!(shrink(&path, 10).is_none());
    }
}
