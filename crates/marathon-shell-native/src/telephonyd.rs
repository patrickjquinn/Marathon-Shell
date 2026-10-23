//! `Telephonyd`: the shell's client of marathon-telephonyd, for the texts
//! it notifies about, the replies it sends and the calls it logs.

use std::pin::Pin;

use cxx_qt::Threading;
use cxx_qt_lib::QString;
use futures_lite::StreamExt;
use zbus::fdo::DBusProxy;
use zbus::{MatchRule, MessageStream};

use crate::{io, log};

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
        fn message_received(self: Pin<&mut Self>, sender: &QString, text: &QString, timestamp: i64);

        #[qinvokable]
        #[cxx_name = "sendMessage"]
        fn send_message(self: &Telephonyd, recipient: &QString, text: &QString);
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

#[derive(Default)]
pub struct TelephonydRust;

impl cxx_qt::Initialize for Telephonyd {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let Ok(bus) = io::session_bus().await else {
                return log::warn("Telephonyd", "no session bus");
            };
            let rule = MatchRule::builder()
                .msg_type(zbus::message::Type::Signal)
                .sender(BUS)
                .and_then(|r| r.interface("org.marathonos.Shell.Sms1"))
                .and_then(|r| r.member("MessageReceived"));
            let received = match rule {
                Ok(rule) => MessageStream::for_match_rule(rule.build(), &bus, None).await,
                Err(e) => Err(e),
            };
            let Ok(received) = received else {
                return log::warn("Telephonyd", "cannot follow received texts");
            };
            if let Err(e) = start(&bus).await {
                log::warn("Telephonyd", format_args!("cannot start {BUS}: {e}"));
            }
            let mut texts = std::pin::pin!(received.filter_map(|m| m
                .ok()?
                .body()
                .deserialize::<(String, String, i64)>()
                .ok()));
            while let Some((sender, text, at)) = texts.next().await {
                qt.queue(move |obj| {
                    obj.message_received(&QString::from(&sender), &QString::from(&text), at);
                })
                .ok();
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
    B: serde::Serialize + zbus::zvariant::DynamicType + Send + Sync + 'static,
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
            "/org/marathonos/Shell/Sms",
            "org.marathonos.Shell.Sms1",
            "SendMessage",
            (recipient.to_string(), text.to_string()),
        );
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
