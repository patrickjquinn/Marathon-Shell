//! `Contacts`: the shell's Contacts1, the address book.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use futures_lite::StreamExt;
use zbus::OwnedVariant as OwnedValue;

use crate::shell::{relay, Service};
use crate::variant;
use marathon_rt::{io, log};

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QList_QVariant, contacts, READ, NOTIFY = contacts_changed)]
        #[qproperty(i32, count, READ, NOTIFY = contacts_changed)]
        type Contacts = super::ContactsRust;

        #[qsignal]
        #[cxx_name = "contactsChanged"]
        fn contacts_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "contactAdded"]
        fn contact_added(self: Pin<&mut Self>, id: i32);
        #[qsignal]
        #[cxx_name = "contactUpdated"]
        fn contact_updated(self: Pin<&mut Self>, id: i32);
        #[qsignal]
        #[cxx_name = "contactDeleted"]
        fn contact_deleted(self: Pin<&mut Self>, id: i32);

        #[qinvokable]
        fn refresh(self: &Contacts);
        #[qinvokable]
        #[cxx_name = "addContact"]
        fn add_contact(self: &Contacts, name: &QString, phone: &QString, email: &QString);
        #[qinvokable]
        #[cxx_name = "updateContact"]
        fn update_contact(self: &Contacts, id: i32, data: &QMap_QString_QVariant);
        #[qinvokable]
        #[cxx_name = "deleteContact"]
        fn delete_contact(self: &Contacts, id: i32);
        #[qinvokable]
        #[cxx_name = "searchContacts"]
        fn search_contacts(self: &Contacts, query: &QString) -> QList_QVariant;
        #[qinvokable]
        #[cxx_name = "getContact"]
        fn get_contact(self: &Contacts, id: i32) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "getContactByNumber"]
        fn get_contact_by_number(self: &Contacts, phone_number: &QString) -> QMap_QString_QVariant;
    }

    impl cxx_qt::Threading for Contacts {}
    impl cxx_qt::Initialize for Contacts {}
}

use qobject::Contacts;

const CONTACTS: Service = Service::on("org.marathonos.Dav", "Contacts");

#[derive(Default)]
pub struct ContactsRust {
    contacts: QList<QVariant>,
    count: i32,
}

type Qt = cxx_qt::CxxQtThread<Contacts>;

impl cxx_qt::Initialize for Contacts {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(
            qt.clone(),
            CONTACTS,
            "ContactAdded",
            |obj, (id,): (i32,)| obj.contact_added(id),
        );
        relay(
            qt.clone(),
            CONTACTS,
            "ContactUpdated",
            |obj, (id,): (i32,)| obj.contact_updated(id),
        );
        relay(
            qt.clone(),
            CONTACTS,
            "ContactDeleted",
            |obj, (id,): (i32,)| obj.contact_deleted(id),
        );
        io::spawn(async move {
            read(&qt).await;
            let Ok(changes) = CONTACTS.signals::<()>("ContactsChanged").await else {
                return;
            };
            let mut changes = std::pin::pin!(changes);
            while changes.next().await.is_some() {
                read(&qt).await;
            }
        });
    }
}

async fn read(qt: &Qt) {
    match CONTACTS.ask::<_, Vec<OwnedValue>>("GetContacts", &()).await {
        Ok(contacts) => {
            qt.queue(move |mut obj| {
                let mut c = obj.as_mut().rust_mut();
                c.contacts = variant::qlist(&contacts);
                c.count = i32::try_from(contacts.len()).unwrap_or(i32::MAX);
                obj.contacts_changed();
            })
            .ok();
        }
        Err(e) => log::warn("Contacts", format_args!("GetContacts: {e}")),
    }
}

impl Contacts {
    crate::shell::calls! { CONTACTS;
        delete_contact(id: i32) => "DeleteContact";
        add_contact(name: &QString, phone: &QString, email: &QString) => "AddContact";
    }
    fn refresh(&self) {
        let qt = self.qt_thread();
        io::spawn(async move { read(&qt).await });
    }

    fn update_contact(&self, id: i32, data: &QMap<QMapPair_QString_QVariant>) {
        CONTACTS.call("UpdateContact", (id, variant::map(data)));
    }

    crate::shell::asks! { CONTACTS;
        search_contacts(query: &QString) -> QList<QVariant> => "SearchContacts";
        get_contact(id: i32) -> QMap<QMapPair_QString_QVariant> => "GetContact";
        get_contact_by_number(phone_number: &QString) -> QMap<QMapPair_QString_QVariant> => "GetContactByNumber";
    }
}
