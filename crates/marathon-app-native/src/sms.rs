//! `Sms`: the shell's Sms1, text and picture messages.

use std::fs::File;
use std::os::fd::AsFd;
use std::path::Path;
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QStringList, QVariant};
use futures_lite::StreamExt;
use zbus::zvariant::{Fd, OwnedFd, OwnedValue};

use crate::shell::{allowed, answers, cache_dir, relay, Arg, Service};
use crate::variant;
use marathon_rt::{io, log};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QList_QVariant, conversations, READ, NOTIFY)]
        #[qproperty(bool, mms_available, cxx_name = "mmsAvailable", READ, NOTIFY)]
        type Sms = super::SmsRust;

        #[qsignal]
        #[cxx_name = "messageReceived"]
        fn message_received(self: Pin<&mut Self>, sender: &QString, text: &QString, timestamp: i64);
        #[qsignal]
        #[cxx_name = "messageSent"]
        fn message_sent(self: Pin<&mut Self>, recipient: &QString, timestamp: i64);
        #[qsignal]
        #[cxx_name = "sendFailed"]
        fn send_failed(self: Pin<&mut Self>, recipient: &QString, reason: &QString);
        #[qsignal]
        #[cxx_name = "messageStatusChanged"]
        fn message_status_changed(self: Pin<&mut Self>, id: i32, status: &QString);

        #[qinvokable]
        fn refresh(self: &Sms);
        #[qinvokable]
        #[cxx_name = "sendMessage"]
        fn send_message(self: &Sms, recipient: &QString, text: &QString);
        #[qinvokable]
        #[cxx_name = "getMessages"]
        fn get_messages(self: &Sms, conversation_id: &QString) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "deleteConversation"]
        fn delete_conversation(self: &Sms, conversation_id: &QString);
        #[qinvokable]
        #[cxx_name = "deleteMessage"]
        fn delete_message(self: &Sms, id: i32) -> bool;
        #[qinvokable]
        #[cxx_name = "markAsRead"]
        fn mark_as_read(self: &Sms, conversation_id: &QString);
        #[qinvokable]
        #[cxx_name = "generateConversationId"]
        fn generate_conversation_id(self: &Sms, number: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "simulateIncomingSMS"]
        fn simulate_incoming_sms(self: &Sms, sender: &QString, message: &QString);
        /// Sends the files themselves, as descriptors: no path crosses the
        /// bus. The message's id, or -1.
        #[qinvokable]
        #[cxx_name = "sendMms"]
        fn send_mms(self: &Sms, recipients: &QStringList, text: &QString, attachments: &QList_QVariant) -> i32;
        /// A received attachment as a file in the app's cache, where an
        /// `Image` can read it; empty if there is none.
        #[qinvokable]
        #[cxx_name = "openAttachment"]
        fn open_attachment(self: &Sms, id: i32, name: &QString) -> QString;
    }

    impl cxx_qt::Threading for Sms {}
    impl cxx_qt::Initialize for Sms {}
}

use qobject::Sms;

const SMS: Service = Service("Sms");

#[derive(Default)]
pub struct SmsRust {
    conversations: QList<QVariant>,
    mms_available: bool,
}

type Qt = cxx_qt::CxxQtThread<Sms>;

impl cxx_qt::Initialize for Sms {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), SMS, "MessageReceived", |obj, (sender, text, at): (String, String, i64)| {
            obj.message_received(&QString::from(&sender), &QString::from(&text), at);
        });
        relay(qt.clone(), SMS, "MessageSent", |obj, (to, at): (String, i64)| obj.message_sent(&QString::from(&to), at));
        relay(qt.clone(), SMS, "SendFailed", |obj, (to, why): (String, String)| {
            obj.send_failed(&QString::from(&to), &QString::from(&why));
        });
        relay(qt.clone(), SMS, "MessageStatusChanged", |obj, (id, status): (i32, String)| {
            obj.message_status_changed(id, &QString::from(&status));
        });
        relay(qt.clone(), SMS, "MmsAvailableChanged", |mut obj, (available,): (bool,)| {
            set!(obj, mms_available, mms_available_changed, available);
        });
        io::spawn(async move {
            let mut asked = false;
            read(&qt, &mut asked).await;
            let (Ok(changes), Ok(grants)) =
                (SMS.signals::<()>("ConversationsChanged").await, answers("PermissionGranted", "sms").await)
            else {
                return;
            };
            let mut events = std::pin::pin!(changes.or(grants));
            while events.next().await.is_some() {
                read(&qt, &mut asked).await;
            }
        });
    }
}

async fn read(qt: &Qt, asked: &mut bool) {
    if !allowed("sms", asked).await.unwrap_or(false) {
        return;
    }
    let mms = SMS.ask::<_, bool>("IsMmsAvailable", &()).await;
    match SMS.ask::<_, Vec<OwnedValue>>("GetConversations", &()).await {
        Ok(conversations) => {
            qt.queue(move |mut obj| {
                if let Ok(mms) = mms {
                    set!(obj, mms_available, mms_available_changed, mms);
                }
                obj.as_mut().rust_mut().conversations = variant::qlist(&conversations);
                obj.conversations_changed();
            })
            .ok();
        }
        Err(e) => log::warn("Sms", format_args!("GetConversations: {e}")),
    }
}

impl Sms {
    crate::shell::calls! { SMS;
        send_message(recipient: &QString, text: &QString) => "SendMessage";
        delete_conversation(conversation_id: &QString) => "DeleteConversation";
        mark_as_read(conversation_id: &QString) => "MarkAsRead";
        simulate_incoming_sms(sender: &QString, message: &QString) => "SimulateIncomingSMS";
    }
    crate::shell::asks! { SMS;
        delete_message(id: i32) -> bool => "DeleteMessage";
    }

    fn refresh(&self) {
        let qt = self.qt_thread();
        io::spawn(async move { read(&qt, &mut false).await });
    }

    fn get_messages(&self, conversation_id: &QString) -> QList<QVariant> {
        let messages: Option<Vec<OwnedValue>> = SMS.ask_now("GetMessages", &(conversation_id.to_string(),));
        variant::qlist(&messages.unwrap_or_default())
    }

    fn generate_conversation_id(&self, number: &QString) -> QString {
        let id: Option<String> = SMS.ask_now("GenerateConversationId", &(number.to_string(),));
        id.map(|id| QString::from(&id)).unwrap_or_default()
    }

    fn send_mms(&self, recipients: &QStringList, text: &QString, attachments: &QList<QVariant>) -> i32 {
        let mut files = Vec::new();
        let mut kinds = Vec::new();
        for attachment in attachments {
            let attachment = attachment.value::<QMap<QMapPair_QString_QVariant>>().unwrap_or_default();
            let field = |key: &str| {
                attachment.get(&QString::from(key)).and_then(|v| v.value::<QString>()).map(|v| v.to_string())
            };
            let path = field("filePath").unwrap_or_default();
            let Ok(file) = File::open(&path) else {
                log::warn("Sms", format_args!("cannot open an attachment: {path}"));
                return -1;
            };
            let name = field("name").filter(|n| !n.is_empty()).unwrap_or_else(|| {
                Path::new(&path).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
            });
            kinds.push((field("contentType").unwrap_or_default(), name));
            files.push(file);
        }
        let parts: Vec<(&str, &str, Fd<'_>)> =
            kinds.iter().zip(&files).map(|((kind, name), file)| (kind.as_str(), name.as_str(), Fd::from(file.as_fd()))).collect();
        SMS.ask_now("SendMms", &(recipients.wire(), text.to_string(), parts)).unwrap_or(-1)
    }

    fn open_attachment(&self, id: i32, name: &QString) -> QString {
        let name = name.to_string();
        let file = match Path::new(&name).file_name().map(|n| n.to_string_lossy().into_owned()) {
            Some(file) if file != "." && file != ".." => file,
            _ => "attachment".to_owned(),
        };
        let dir = Path::new(cache_dir()).join("mms").join(id.to_string());
        let path = dir.join(file);
        let shown = QString::from(&path.to_string_lossy().into_owned());
        if path.exists() {
            return shown;
        }
        let Some(fd) = SMS.ask_now::<_, OwnedFd>("OpenAttachment", &(id,)) else {
            return QString::default();
        };
        let copied = std::fs::create_dir_all(&dir).and_then(|()| {
            let mut source = File::from(std::os::fd::OwnedFd::from(fd));
            std::io::copy(&mut source, &mut File::create(&path)?)
        });
        match copied {
            Ok(_) => shown,
            Err(e) => {
                log::warn("Sms", format_args!("cannot keep attachment {id}: {e}"));
                std::fs::remove_file(&path).ok();
                QString::default()
            }
        }
    }
}
