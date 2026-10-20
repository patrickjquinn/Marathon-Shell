//! Marathon's messages and call log: `org.marathonos.Telephony` on the
//! session bus, serving `Sms1` and `CallHistory1` where the shell served
//! them. Texts go through `ModemManager`, MMS through mmsd-tng
//! (docs/MMS.md); the shell admits each caller (`Permissions1.Admit`).

mod history;
mod mms;
mod modem;
mod store;

use std::collections::HashMap;
use std::io::Read;
use std::process::ExitCode;
use std::sync::{Arc, Mutex};

use marathon_rt::daemon::{admit, shell_data, Shared};
use marathon_rt::{io, log};
use zbus::message::Header;
use zbus::object_server::SignalEmitter;
use zbus::zvariant::{ObjectPath, OwnedFd, OwnedValue, Value};
use zbus::{fdo, interface, Connection};

use history::CallLog;
use store::{Message, Store};

const BUS_NAME: &str = "org.marathonos.Telephony";
const SMS_PATH: &str = "/org/marathonos/Shell/Sms";
const HISTORY_PATH: &str = "/org/marathonos/Shell/CallHistory";
const SMS: &[&str] = &["sms", "phone"];
const PHONE: &[&str] = &["telephony", "phone"];

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .and_then(|d| i64::try_from(d.as_millis()).ok())
        .unwrap_or_default()
}

/// A failed call's words, as the service gave them.
pub fn reason(e: &zbus::Error) -> String {
    match e {
        zbus::Error::MethodError(_, Some(text), _) => text.clone(),
        other => other.to_string(),
    }
}

fn failed(e: &rusqlite::Error) -> fdo::Error {
    fdo::Error::Failed(e.to_string())
}

#[derive(Clone)]
pub struct Core {
    pub bus: Connection,
    pub store: Shared<Store>,
    pub mms: Arc<Mutex<mms::Service>>,
}

impl Core {
    pub fn sms(&self) -> SignalEmitter<'static> {
        SignalEmitter::from_parts(self.bus.clone(), ObjectPath::from_static_str_unchecked(SMS_PATH))
    }

    /// Stores an incoming message with its attachments and tells the apps.
    pub async fn receive(&self, sender: String, text: String, timestamp: i64, mms_path: String, attachments: Vec<(String, String, Vec<u8>)>) {
        let (from, body) = (sender.clone(), text.clone());
        let stored = self
            .store
            .with(move |s| {
                let m = Message { sender: &from, recipient: "me", text: &body, timestamp, outgoing: false, status: "received", mms_path: &mms_path };
                let id = s.insert(&m)?;
                for (content_type, name, data) in &attachments {
                    s.add_attachment(id, content_type, name, data);
                }
                Ok::<_, rusqlite::Error>(())
            })
            .await;
        if let Err(e) = stored {
            return log::warn("Sms", format_args!("cannot store a message from {sender}: {e}"));
        }
        SmsService::conversations_changed(&self.sms()).await.ok();
        SmsService::message_received(&self.sms(), &sender, &text, timestamp).await.ok();
    }

    /// A sent message's new status, when it changed.
    pub async fn set_status(&self, id: i32, status: &'static str) {
        if self.store.with(move |s| s.set_status(id, status)).await {
            SmsService::message_status_changed(&self.sms(), id, status).await.ok();
        }
    }

    pub async fn send_failed(&self, recipient: &str, reason: &str) {
        SmsService::send_failed(&self.sms(), recipient, reason).await.ok();
    }
}

struct SmsService(Core);

#[interface(name = "org.marathonos.Shell.Sms1")]
impl SmsService {
    async fn get_conversations(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<Vec<Value<'static>>> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        let rows = self.0.store.with(|s| s.conversations()).await.map_err(|e| failed(&e))?;
        Ok(rows.into_iter().map(Value::from).collect())
    }

    async fn get_messages(&self, #[zbus(header)] h: Header<'_>, conversation_id: String) -> fdo::Result<Vec<Value<'static>>> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        let rows = self.0.store.with(move |s| s.messages(&conversation_id)).await.map_err(|e| failed(&e))?;
        Ok(rows.into_iter().map(Value::from).collect())
    }

    async fn send_message(&self, #[zbus(header)] h: Header<'_>, recipient: String, text: String) -> fdo::Result<()> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        let core = self.0.clone();
        io::spawn(async move { modem::send(&core, recipient, text).await });
        Ok(())
    }

    async fn delete_conversation(&self, #[zbus(header)] h: Header<'_>, conversation_id: String) -> fdo::Result<()> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        self.0.store.with(move |s| s.delete_conversation(&conversation_id)).await.map_err(|e| failed(&e))?;
        Self::conversations_changed(&self.0.sms()).await.ok();
        Ok(())
    }

    async fn delete_message(&self, #[zbus(header)] h: Header<'_>, id: i32) -> fdo::Result<bool> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        let deleted = self.0.store.with(move |s| s.delete_message(id)).await.map_err(|e| failed(&e))?;
        if deleted {
            Self::conversations_changed(&self.0.sms()).await.ok();
        }
        Ok(deleted)
    }

    async fn mark_as_read(&self, #[zbus(header)] h: Header<'_>, conversation_id: String) -> fdo::Result<()> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        self.0.store.with(move |s| s.mark_read(&conversation_id)).await.map_err(|e| failed(&e))?;
        Self::conversations_changed(&self.0.sms()).await.ok();
        Ok(())
    }

    async fn generate_conversation_id(&self, #[zbus(header)] h: Header<'_>, number: String) -> fdo::Result<String> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        Ok(store::conversation_id(&number))
    }

    #[zbus(name = "SimulateIncomingSMS")]
    async fn simulate_incoming_sms(&self, #[zbus(header)] h: Header<'_>, sender: String, message: String) -> fdo::Result<()> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        self.0.receive(sender, message, now_ms(), String::new(), Vec::new()).await;
        Ok(())
    }

    /// Each part is (content type, file name, descriptor): no path crosses
    /// the bus.
    async fn send_mms(&self, #[zbus(header)] h: Header<'_>, recipients: Vec<String>, text: String, parts: Vec<(String, String, OwnedFd)>) -> fdo::Result<i32> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        if recipients.is_empty() || recipients.len() > 20 || parts.len() > 25 {
            return Err(fdo::Error::InvalidArgs("1 to 20 recipients and at most 25 parts".into()));
        }
        if parts.iter().any(|(content_type, _, _)| content_type.is_empty()) {
            return Err(fdo::Error::InvalidArgs("Each part needs a type and a descriptor".into()));
        }
        let to = recipients.join(",");
        if text.is_empty() && parts.is_empty() {
            self.0.send_failed(&to, "Nothing to send").await;
            return Ok(-1);
        }
        let (recipient, body) = (to.clone(), text.clone());
        let stored = self
            .0
            .store
            .with(move |s| {
                let m = Message { sender: "me", recipient: &recipient, text: &body, timestamp: now_ms(), outgoing: true, status: "sending", mms_path: "" };
                let id = s.insert(&m)?;
                let mut kept = Vec::new();
                for (content_type, name, fd) in parts {
                    let mut data = Vec::new();
                    let read = std::fs::File::from(std::os::fd::OwnedFd::from(fd)).read_to_end(&mut data);
                    match read.ok().and_then(|_| s.add_attachment(id, &content_type, &name, &data)) {
                        Some(attachment) => kept.push(attachment),
                        None => return Ok((id, None)),
                    }
                }
                Ok::<_, rusqlite::Error>((id, Some(kept)))
            })
            .await
            .map_err(|e| failed(&e))?;
        Self::conversations_changed(&self.0.sms()).await.ok();
        let (id, attachments) = stored;
        let Some(attachments) = attachments else {
            self.0.set_status(id, "failed").await;
            self.0.send_failed(&to, "An attachment could not be read").await;
            return Ok(id);
        };
        let core = self.0.clone();
        io::spawn(async move { mms::send(&core, id, recipients, text, attachments).await });
        Ok(id)
    }

    async fn open_attachment(&self, #[zbus(header)] h: Header<'_>, id: i32) -> fdo::Result<OwnedFd> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        let file = self.0.store.with(move |s| s.attachment(id).and_then(|a| std::fs::File::open(a.path).ok())).await;
        file.map(|f| OwnedFd::from(std::os::fd::OwnedFd::from(f))).ok_or_else(|| fdo::Error::InvalidArgs("No such attachment".into()))
    }

    async fn is_mms_available(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        admit(&self.0.bus, &h, "Sms", SMS).await?;
        Ok(mms::available(&self.0))
    }

    async fn get_mms_settings(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<HashMap<String, OwnedValue>> {
        admit(&self.0.bus, &h, "Sms.Settings", &["system"]).await?;
        Ok(mms::settings(&self.0).await)
    }

    async fn set_mms_settings(&self, #[zbus(header)] h: Header<'_>, values: HashMap<String, OwnedValue>) -> fdo::Result<()> {
        admit(&self.0.bus, &h, "Sms.Settings", &["system"]).await?;
        mms::change_settings(&self.0, &values).await?;
        Self::mms_settings_changed(&self.0.sms(), values).await.ok();
        Ok(())
    }

    #[zbus(signal)]
    async fn message_received(e: &SignalEmitter<'_>, sender: &str, text: &str, timestamp: i64) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn message_sent(e: &SignalEmitter<'_>, recipient: &str, timestamp: i64) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn send_failed(e: &SignalEmitter<'_>, recipient: &str, reason: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn conversations_changed(e: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn message_status_changed(e: &SignalEmitter<'_>, id: i32, status: &str) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn mms_available_changed(e: &SignalEmitter<'_>, available: bool) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn mms_settings_changed(e: &SignalEmitter<'_>, settings: HashMap<String, OwnedValue>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn mms_bearer_error(e: &SignalEmitter<'_>, code: u32) -> zbus::Result<()>;
}

struct CallHistory {
    bus: Connection,
    log: Shared<CallLog>,
}

impl CallHistory {
    async fn calls(&self, h: &Header<'_>, number: Option<String>) -> fdo::Result<Vec<Value<'static>>> {
        admit(&self.bus, h, "CallHistory", PHONE).await?;
        let rows = self.log.with(move |l| l.calls(number.as_deref())).await.map_err(|e| failed(&e))?;
        Ok(rows.into_iter().map(Value::from).collect())
    }

    /// The contact's name for `number`, or "Unknown".
    async fn name_for(&self, number: &str) -> String {
        let asked = self
            .bus
            .call_method(Some("org.marathonos.Dav"), "/org/marathonos/Shell/Contacts", Some("org.marathonos.Shell.Contacts1"), "GetContactByNumber", &(number,))
            .await;
        let contact: Option<HashMap<String, OwnedValue>> = asked.ok().and_then(|reply| reply.body().deserialize().ok());
        contact
            .and_then(|c| c.get("name").and_then(|n| String::try_from(n.try_clone().ok()?).ok()))
            .filter(|n| !n.is_empty())
            .unwrap_or_else(|| "Unknown".to_owned())
    }

    async fn changed(&self, emitter: &SignalEmitter<'_>) -> fdo::Result<()> {
        Self::history_changed(emitter).await.map_err(fdo::Error::from)
    }
}

#[interface(name = "org.marathonos.Shell.CallHistory1")]
impl CallHistory {
    async fn get_history(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<Vec<Value<'static>>> {
        self.calls(&h, None).await
    }

    async fn get_calls_by_number(&self, #[zbus(header)] h: Header<'_>, number: String) -> fdo::Result<Vec<Value<'static>>> {
        self.calls(&h, Some(number)).await
    }

    async fn get_call_by_id(&self, #[zbus(header)] h: Header<'_>, id: i32) -> fdo::Result<HashMap<&'static str, Value<'static>>> {
        admit(&self.bus, &h, "CallHistory", PHONE).await?;
        Ok(self.log.with(move |l| l.call(id)).await.map_err(|e| failed(&e))?.unwrap_or_default())
    }

    async fn add_call(
        &self,
        #[zbus(header)] h: Header<'_>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
        number: String,
        kind: String,
        timestamp: i64,
        duration: i32,
    ) -> fdo::Result<()> {
        admit(&self.bus, &h, "CallHistory", PHONE).await?;
        if number.is_empty() {
            return Err(fdo::Error::InvalidArgs("A call needs a number".into()));
        }
        let name = self.name_for(&number).await;
        let id = self.log.with(move |l| l.add(&number, &name, &kind, timestamp, duration)).await.map_err(|e| failed(&e))?;
        self.changed(&emitter).await?;
        Self::call_added(&emitter, id).await.map_err(fdo::Error::from)
    }

    async fn delete_call(&self, #[zbus(header)] h: Header<'_>, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>, id: i32) -> fdo::Result<()> {
        admit(&self.bus, &h, "CallHistory", PHONE).await?;
        self.log.with(move |l| l.delete(Some(id))).await.map_err(|e| failed(&e))?;
        self.changed(&emitter).await
    }

    async fn clear_history(&self, #[zbus(header)] h: Header<'_>, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) -> fdo::Result<()> {
        admit(&self.bus, &h, "CallHistory", PHONE).await?;
        self.log.with(|l| l.delete(None)).await.map_err(|e| failed(&e))?;
        self.changed(&emitter).await
    }

    #[zbus(signal)]
    async fn history_changed(e: &SignalEmitter<'_>) -> zbus::Result<()>;
    #[zbus(signal)]
    async fn call_added(e: &SignalEmitter<'_>, id: i32) -> zbus::Result<()>;
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let store = Shared::new(Store::open(&shell_data().join("messages.db"), marathon_rt::dirs::data().join("marathon/mms"))?);
    let log = Shared::new(CallLog::open(&shell_data().join("marathon/callhistory.db"))?);
    let bus = io::session_bus().await?;
    let core = Core { bus: bus.clone(), store, mms: Arc::default() };
    bus.object_server().at(SMS_PATH, SmsService(core.clone())).await?;
    bus.object_server().at(HISTORY_PATH, CallHistory { bus: bus.clone(), log }).await?;
    bus.request_name(BUS_NAME).await?;
    let texts = core.clone();
    io::spawn(async move { modem::watch(&texts).await });
    mms::watch(&core).await;
    Ok(())
}

fn main() -> ExitCode {
    match async_io::block_on(run()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            log::warn("marathon-telephonyd", e);
            ExitCode::FAILURE
        }
    }
}
