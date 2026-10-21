//! `Contacts`: the address book as the shell reads it, mirrored from
//! marathon-davd, so a caller's name is found without a round trip.

use std::collections::HashMap;
use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QMap, QMapPair_QString_QVariant, QString, QVariant};
use futures_lite::StreamExt;
use zbus::zvariant::OwnedValue;
use zbus::{MatchRule, MessageStream};

use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        type Contacts = super::ContactsRust;

        #[qinvokable]
        #[cxx_name = "getContactByNumber"]
        fn get_contact_by_number(self: &Contacts, number: &QString) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "addContact"]
        fn add_contact(self: &Contacts, name: &QString, phone: &QString, email: &QString);
    }

    impl cxx_qt::Threading for Contacts {}
    impl cxx_qt::Initialize for Contacts {}
}

use qobject::Contacts;

const BUS: &str = "org.marathonos.Dav";
const PATH: &str = "/org/marathonos/Shell/Contacts";
const INTERFACE: &str = "org.marathonos.Shell.Contacts1";

struct Known {
    id: i32,
    name: String,
    phone: String,
}

#[derive(Default)]
pub struct ContactsRust {
    known: Vec<Known>,
}

async fn read(bus: &zbus::Connection) -> zbus::Result<Vec<Known>> {
    let reply = bus.call_method(Some(BUS), PATH, Some(INTERFACE), "GetContacts", &()).await?;
    let rows: Vec<OwnedValue> = reply.body().deserialize()?;
    let field = |row: &HashMap<String, OwnedValue>, key: &str| row.get(key).and_then(|v| String::try_from(v.try_clone().ok()?).ok()).unwrap_or_default();
    Ok(rows
        .into_iter()
        .filter_map(|row| HashMap::<String, OwnedValue>::try_from(row).ok())
        .map(|row| Known { id: row.get("id").and_then(|v| i32::try_from(v).ok()).unwrap_or_default(), name: field(&row, "name"), phone: field(&row, "phone") })
        .collect())
}

impl cxx_qt::Initialize for Contacts {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let Ok(bus) = io::session_bus().await else { return log::warn("Contacts", "no session bus") };
            let rule = MatchRule::builder()
                .msg_type(zbus::message::Type::Signal)
                .sender(BUS)
                .and_then(|r| r.interface(INTERFACE))
                .and_then(|r| r.member("ContactsChanged"));
            let changes = match rule {
                Ok(rule) => MessageStream::for_match_rule(rule.build(), &bus, None).await,
                Err(e) => Err(e),
            };
            let Ok(changes) = changes else { return log::warn("Contacts", "cannot follow the address book") };
            crate::ipc::named().await;
            let mut changes = std::pin::pin!(changes);
            loop {
                match read(&bus).await {
                    Ok(known) => {
                        qt.queue(move |mut obj| obj.as_mut().rust_mut().known = known).ok();
                    }
                    Err(e) => log::warn("Contacts", format_args!("GetContacts: {e}")),
                }
                if changes.next().await.is_none() {
                    return;
                }
            }
        });
    }
}

impl Contacts {
    fn get_contact_by_number(&self, number: &QString) -> QMap<QMapPair_QString_QVariant> {
        let number = number.to_string();
        let mut map = QMap::default();
        if let Some(c) = self.rust().known.iter().find(|c| marathon_rt::daemon::same_number(&c.phone, &number)) {
            map.insert(QString::from("id"), QVariant::from(&c.id));
            map.insert(QString::from("name"), QVariant::from(&QString::from(&c.name)));
            map.insert(QString::from("phone"), QVariant::from(&QString::from(&c.phone)));
        }
        map
    }

    #[allow(clippy::unused_self, reason = "invokables are the QObject's methods")]
    fn add_contact(&self, name: &QString, phone: &QString, email: &QString) {
        let body = (name.to_string(), phone.to_string(), email.to_string());
        io::spawn(async move {
            let added = match io::session_bus().await {
                Ok(bus) => bus.call_method(Some(BUS), PATH, Some(INTERFACE), "AddContact", &body).await.map(drop),
                Err(e) => Err(e),
            };
            if let Err(e) = added {
                log::warn("Contacts", format_args!("AddContact: {e}"));
            }
        });
    }
}
