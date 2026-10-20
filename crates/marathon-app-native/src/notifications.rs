//! `Notifications`: notifications the app posts, through Marathon's
//! notification server, or any freedesktop one when it is not there.

use std::collections::HashMap;
use std::pin::Pin;

use async_lock::OnceCell;
use cxx_qt::Threading;
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString, QVariant};
use futures_lite::StreamExt;
use zbus::zvariant::Value;
use zbus::{MatchRule, MessageStream};

use crate::shell::allowed;
use marathon_rt::{io, log};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        type Notifications = super::NotificationsRust;

        #[qsignal]
        #[cxx_name = "notificationClosed"]
        fn notification_closed(self: Pin<&mut Self>, id: i32, reason: i32);
        #[qsignal]
        #[cxx_name = "actionInvoked"]
        fn action_invoked(self: Pin<&mut Self>, id: i32, action: &QString);

        /// Options: `actions` (a list of names), `category`, `priority`
        /// (low, normal, high), `icon` and `persistent`. The id, or -1.
        #[qinvokable]
        #[cxx_name = "sendNotification"]
        fn send_notification(self: &Notifications, app_id: &QString, title: &QString, body: &QString, options: &QMap_QString_QVariant) -> i32;
        #[qinvokable]
        #[cxx_name = "dismissNotification"]
        fn dismiss_notification(self: &Notifications, id: i32);
        #[qinvokable]
        #[cxx_name = "dismissAllNotifications"]
        fn dismiss_all_notifications(self: &Notifications);
    }

    impl cxx_qt::Threading for Notifications {}
    impl cxx_qt::Initialize for Notifications {}
}

use qobject::Notifications;

#[derive(Default)]
pub struct NotificationsRust;

const PATH: &str = "/org/freedesktop/Notifications";
const INTERFACE: &str = "org.freedesktop.Notifications";

/// Marathon's server when it runs, else the freedesktop name.
async fn server() -> &'static str {
    static SERVER: OnceCell<&str> = OnceCell::new();
    SERVER
        .get_or_init(|| async {
            let ours = async {
                let bus = io::session_bus().await.ok()?;
                let dbus = zbus::fdo::DBusProxy::new(&bus).await.ok()?;
                dbus.name_has_owner("org.marathon.Notifications".try_into().ok()?).await.ok()
            };
            if ours.await == Some(true) { "org.marathon.Notifications" } else { INTERFACE }
        })
        .await
}

pub(crate) async fn call<B>(method: &str, body: &B) -> zbus::Result<zbus::Message>
where
    B: serde::Serialize + zbus::zvariant::DynamicType,
{
    io::session_bus().await?.call_method(Some(server().await), PATH, Some(INTERFACE), method, body).await
}

impl cxx_qt::Initialize for Notifications {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let rule = |member| -> zbus::Result<MatchRule<'static>> {
                Ok(MatchRule::builder().msg_type(zbus::message::Type::Signal).path(PATH)?.interface(INTERFACE)?.member(member)?.build())
            };
            let streams = async {
                let bus = io::session_bus().await?;
                zbus::Result::Ok((
                    MessageStream::for_match_rule(rule("NotificationClosed")?, &bus, None).await?,
                    MessageStream::for_match_rule(rule("ActionInvoked")?, &bus, None).await?,
                ))
            };
            let Ok((closed, invoked)) = streams.await else { return log::warn("Notifications", "no session bus") };
            let mut events = std::pin::pin!(closed.or(invoked));
            while let Some(Ok(message)) = events.next().await {
                let member = message.header().member().map(ToString::to_string).unwrap_or_default();
                let body = message.body();
                if member == "NotificationClosed" {
                    if let Ok((id, reason)) = body.deserialize::<(u32, u32)>() {
                        let (id, reason) = (i32::try_from(id).unwrap_or(-1), i32::try_from(reason).unwrap_or(0));
                        qt.queue(move |obj| obj.notification_closed(id, reason)).ok();
                    }
                } else if let Ok((id, action)) = body.deserialize::<(u32, String)>() {
                    let id = i32::try_from(id).unwrap_or(-1);
                    qt.queue(move |obj| obj.action_invoked(id, &QString::from(&action))).ok();
                }
            }
        });
    }
}

impl Notifications {
    fn send_notification(&self, app_id: &QString, title: &QString, body: &QString, options: &QMap<QMapPair_QString_QVariant>) -> i32 {
        let option = |key: &str| options.get(&QString::from(key));
        let text = |key: &str| option(key).and_then(|v| v.value::<QString>()).map(|v| v.to_string()).unwrap_or_default();
        let actions: Vec<String> = option("actions")
            .and_then(|v| v.value::<cxx_qt_lib::QList<QVariant>>())
            .map(|list| list.iter().filter_map(QVariant::value::<QString>).flat_map(|a| [a.to_string(), a.to_string()]).collect())
            .unwrap_or_default();
        let mut hints: HashMap<&str, Value<'_>> = HashMap::new();
        if option("category").is_some() {
            hints.insert("category", Value::from(text("category")));
        }
        if option("priority").is_some() {
            hints.insert("urgency", Value::U8(match text("priority").as_str() { "high" => 2, "low" => 0, _ => 1 }));
        }
        hints.insert("desktop-entry", Value::from(app_id.to_string()));
        let persistent = option("persistent").and_then(|v| v.value::<bool>()).unwrap_or(false);
        let timeout = if persistent { 0 } else { 5000 };
        let body = (app_id.to_string(), 0u32, text("icon"), title.to_string(), body.to_string(), actions, hints, timeout);
        let sent = async_io::block_on(async {
            if !allowed("notifications", &mut false).await? {
                return Ok(None);
            }
            call("Notify", &body).await?.body().deserialize::<u32>().map(Some)
        });
        match sent {
            Ok(Some(id)) => i32::try_from(id).unwrap_or(-1),
            Ok(None) => -1,
            Err(e) => {
                log::warn("Notifications", format_args!("Notify for {app_id}: {e}"));
                -1
            }
        }
    }

    fn dismiss_notification(&self, id: i32) {
        let id = u32::try_from(id).unwrap_or(0);
        io::spawn(async move {
            if let Err(e) = call("CloseNotification", &(id,)).await {
                log::warn("Notifications", format_args!("CloseNotification: {e}"));
            }
        });
    }

    fn dismiss_all_notifications(&self) {}
}
