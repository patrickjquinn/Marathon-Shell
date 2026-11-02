//! `Telephonyd`: the shell's client of marathon-telephonyd, for the texts
//! it notifies about, the replies it sends and the calls it logs. A text's
//! notification is tagged `sms:<thread>` and goes once the thread is read,
//! wherever it was read.

use std::collections::HashMap;
use std::pin::Pin;

use cxx_qt::Threading;
use cxx_qt_lib::QString;
use futures_lite::StreamExt;
use zbus::fdo::DBusProxy;
use zbus::{MatchRule, MessageStream, OwnedVariant};

use crate::{io, log, notifications};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        type Telephonyd = super::TelephonydRust;

        #[qsignal]
        #[cxx_name = "messageReceived"]
        fn message_received(
            self: Pin<&mut Self>,
            sender: &QString,
            text: &QString,
            timestamp: i64,
            thread: &QString,
        );

        #[qinvokable]
        #[cxx_name = "sendMessage"]
        fn send_message(self: &Telephonyd, recipient: &QString, text: &QString);
        #[qinvokable]
        #[cxx_name = "markRead"]
        fn mark_read(self: &Telephonyd, thread: &QString);
        #[qinvokable]
        #[cxx_name = "logCall"]
        fn log_call(
            self: &Telephonyd,
            number: &QString,
            kind: &QString,
            started_ms: i64,
            duration_seconds: i32,
        );
    }

    impl cxx_qt::Threading for Telephonyd {}
    impl cxx_qt::Initialize for Telephonyd {}
}

use qobject::Telephonyd;

const BUS: &str = "org.marathonos.Telephony";
const SMS_PATH: &str = "/org/marathonos/Shell/Sms";
const SMS: &str = "org.marathonos.Shell.Sms1";

#[derive(Default)]
pub struct TelephonydRust;

impl cxx_qt::Initialize for Telephonyd {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let Ok(bus) = io::session_bus().await else {
                return log::warn("Telephonyd", "no session bus");
            };
            let (Ok(received), Ok(changes)) = (
                follow(&bus, "MessageReceived").await,
                follow(&bus, "ConversationsChanged").await,
            ) else {
                return log::warn("Telephonyd", "cannot follow texts");
            };
            if let Err(e) = start(&bus).await {
                log::warn("Telephonyd", format_args!("cannot start {BUS}: {e}"));
            }
            io::spawn(dismiss_read(bus.clone(), changes));
            let mut texts = std::pin::pin!(received.filter_map(|m| m
                .ok()?
                .body()
                .deserialize::<(String, String, i64)>()
                .ok()));
            while let Some((sender, text, at)) = texts.next().await {
                let thread = ask::<String>(&bus, "GenerateConversationId", &(&sender,))
                    .await
                    .unwrap_or_default();
                qt.queue(move |obj| {
                    obj.message_received(
                        &QString::from(&sender),
                        &QString::from(&text),
                        at,
                        &QString::from(&thread),
                    );
                })
                .ok();
            }
        });
    }
}

async fn follow(bus: &zbus::Connection, member: &'static str) -> zbus::Result<MessageStream> {
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(BUS)
        .interface(SMS)
        .member(member)
        .build()?;
    MessageStream::for_match_rule(rule, bus, None).await
}

async fn ask<R: serde::de::DeserializeOwned + zbus::Type>(
    bus: &zbus::Connection,
    method: &'static str,
    body: &(impl serde::Serialize + zbus::DynamicType),
) -> zbus::Result<R> {
    bus.call_method(Some(BUS), SMS_PATH, Some(SMS), method, body)
        .await?
        .body()
        .deserialize()
}

/// Dismisses the notifications of every thread with nothing unread, each
/// time a thread changes.
async fn dismiss_read(bus: zbus::Connection, changes: MessageStream) {
    let mut changes = std::pin::pin!(changes);
    while changes.next().await.is_some() {
        let threads = match ask::<Vec<OwnedVariant>>(&bus, "GetConversations", &()).await {
            Ok(threads) => threads,
            Err(e) => {
                log::warn("Telephonyd", format_args!("GetConversations: {e}"));
                continue;
            }
        };
        let read: Vec<String> = threads
            .into_iter()
            .filter_map(|t| HashMap::<String, OwnedVariant>::try_from(t).ok())
            .filter(|t| t.get("unreadCount").and_then(|n| i32::try_from(n).ok()) == Some(0))
            .filter_map(|t| Some(<&str>::try_from(t.get("id")?).ok()?.to_owned()))
            .collect();
        notifications::with(move |mut n| {
            let app = QString::from("messages");
            for thread in &read {
                n.as_mut()
                    .dismiss_tagged(&app, &QString::from(&format!("sms:{thread}")));
            }
        });
    }
}

/// Starts the daemon with the shell: texts arrive whether or not an app asked.
async fn start(bus: &zbus::Connection) -> zbus::Result<()> {
    DBusProxy::new(bus)
        .await?
        .start_service_by_name(BUS.try_into()?, 0)
        .await?;
    Ok(())
}

fn call<B>(path: &'static str, interface: &'static str, method: &'static str, body: B)
where
    B: serde::Serialize + zbus::DynamicType + Send + Sync + 'static,
{
    io::spawn(async move {
        let sent = match io::session_bus().await {
            Ok(bus) => bus
                .call_method(Some(BUS), path, Some(interface), method, &body)
                .await
                .map(drop),
            Err(e) => Err(e),
        };
        if let Err(e) = sent {
            log::warn("Telephonyd", format_args!("{method}: {e}"));
        }
    });
}

#[allow(clippy::unused_self, reason = "invokables are the QObject's methods")]
impl Telephonyd {
    fn send_message(&self, recipient: &QString, text: &QString) {
        call(
            SMS_PATH,
            SMS,
            "SendMessage",
            (recipient.to_string(), text.to_string()),
        );
    }

    fn mark_read(&self, thread: &QString) {
        mark_read(thread.to_string());
    }

    fn log_call(&self, number: &QString, kind: &QString, started_ms: i64, duration_seconds: i32) {
        let body = (
            number.to_string(),
            kind.to_string(),
            started_ms,
            duration_seconds,
        );
        call(
            "/org/marathonos/Shell/CallHistory",
            "org.marathonos.Shell.CallHistory1",
            "AddCall",
            body,
        );
    }
}

/// Marks a thread's texts read, which also takes its notification away.
pub(crate) fn mark_read(thread: String) {
    if !thread.is_empty() {
        call(SMS_PATH, SMS, "MarkAsRead", (thread,));
    }
}
