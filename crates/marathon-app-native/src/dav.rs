//! `DavSync`: the shell's `Dav1`, `CalDAV` and `CardDAV` accounts and syncing.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QString, QVariant};
use futures_lite::StreamExt;
use zbus::zvariant::OwnedValue;

use crate::shell::{get, mirror, relay, Service, Update};
use crate::variant;
use marathon_rt::io;

#[cxx_qt::bridge(namespace = "marathon::platform")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QList_QVariant, accounts, READ, NOTIFY = accounts_changed)]
        #[qproperty(i32, account_count, cxx_name = "accountCount", READ, NOTIFY = accounts_changed)]
        #[qproperty(bool, syncing, READ, NOTIFY = state_changed)]
        #[qproperty(QString, last_error, cxx_name = "lastError", READ, NOTIFY = state_changed)]
        #[qproperty(i64, last_sync_ms, cxx_name = "lastSyncMs", READ, NOTIFY = state_changed)]
        type DavSync = super::DavSyncRust;

        #[qsignal]
        #[cxx_name = "accountsChanged"]
        fn accounts_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "stateChanged"]
        fn state_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "syncFinished"]
        fn sync_finished(self: Pin<&mut Self>, account_id: &QString);
        #[qsignal]
        #[cxx_name = "accountDiscovered"]
        fn account_discovered(self: Pin<&mut Self>, account_id: &QString);
        #[qsignal]
        #[cxx_name = "accountDiscoveryFailed"]
        fn account_discovery_failed(self: Pin<&mut Self>, account_id: &QString, reason: &QString);

        #[qinvokable]
        #[cxx_name = "addAccount"]
        fn add_account(self: &DavSync, display_name: &QString, base_url: &QString, username: &QString, secret: &QString, auth_kind: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "removeAccount"]
        fn remove_account(self: &DavSync, id: &QString) -> bool;
        #[qinvokable]
        #[cxx_name = "enableAccount"]
        fn enable_account(self: &DavSync, id: &QString, enabled: bool);
        #[qinvokable]
        #[cxx_name = "syncNow"]
        fn sync_now(self: &DavSync);
        #[qinvokable]
        fn refresh(self: &DavSync);
    }

    impl cxx_qt::Threading for DavSync {}
    impl cxx_qt::Initialize for DavSync {}
}

use qobject::DavSync;

const DAV: Service = Service("Dav");

#[derive(Default)]
pub struct DavSyncRust {
    accounts: QList<QVariant>,
    account_count: i32,
    syncing: bool,
    last_error: QString,
    last_sync_ms: i64,
}

type Qt = cxx_qt::CxxQtThread<DavSync>;

impl cxx_qt::Initialize for DavSync {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), DAV, "SyncFinished", |obj, (id,): (String,)| obj.sync_finished(&QString::from(&id)));
        relay(qt.clone(), DAV, "AccountDiscovered", |obj, (id,): (String,)| obj.account_discovered(&QString::from(&id)));
        relay(qt.clone(), DAV, "AccountDiscoveryFailed", |obj, (id, why): (String, String)| {
            obj.account_discovery_failed(&QString::from(&id), &QString::from(&why));
        });
        mirror(qt.clone(), DAV, "system", |mut obj, update| {
            let Update::State(s) = update else { return };
            let mut d = obj.as_mut().rust_mut();
            d.syncing = get(&s, "syncing");
            d.last_error = get(&s, "lastError");
            d.last_sync_ms = get(&s, "lastSyncMs");
            obj.state_changed();
        });
        io::spawn(async move {
            accounts(&qt).await;
            let Ok(changes) = DAV.signals::<()>("AccountsChanged").await else { return };
            let mut changes = std::pin::pin!(changes);
            while changes.next().await.is_some() {
                accounts(&qt).await;
            }
        });
    }
}

async fn accounts(qt: &Qt) {
    if let Ok(accounts) = DAV.ask::<_, Vec<OwnedValue>>("ListAccounts", &()).await {
        qt.queue(move |mut obj| {
            let mut d = obj.as_mut().rust_mut();
            d.accounts = variant::qlist(&accounts);
            d.account_count = i32::try_from(accounts.len()).unwrap_or(i32::MAX);
            obj.accounts_changed();
        })
        .ok();
    }
}

impl DavSync {
    crate::shell::calls! { DAV;
        enable_account(id: &QString, enabled: bool) => "EnableAccount";
        sync_now() => "SyncNow";
    }
    crate::shell::asks! { DAV;
        add_account(display_name: &QString, base_url: &QString, username: &QString, secret: &QString, auth_kind: &QString) -> QString => "AddAccount";
        remove_account(id: &QString) -> bool => "RemoveAccount";
    }

    fn refresh(&self) {
        let qt = self.qt_thread();
        io::spawn(async move { accounts(&qt).await });
    }
}
