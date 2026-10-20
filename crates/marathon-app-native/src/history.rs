//! `CallHistory`: the shell's `CallHistory1`, the calls made and missed.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use futures_lite::StreamExt;
use zbus::zvariant::OwnedValue;

use crate::shell::{relay, Service};
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
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QList_QVariant, history, READ, NOTIFY = history_changed)]
        #[qproperty(i32, count, READ, NOTIFY = history_changed)]
        type CallHistory = super::CallHistoryRust;

        #[qsignal]
        #[cxx_name = "historyChanged"]
        fn history_changed(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "callAdded"]
        fn call_added(self: Pin<&mut Self>, id: i32);

        #[qinvokable]
        fn refresh(self: &CallHistory);
        #[qinvokable]
        #[cxx_name = "addCall"]
        fn add_call(self: &CallHistory, number: &QString, kind: &QString, timestamp: i64, duration: i32);
        #[qinvokable]
        #[cxx_name = "deleteCall"]
        fn delete_call(self: &CallHistory, id: i32);
        #[qinvokable]
        #[cxx_name = "clearHistory"]
        fn clear_history(self: &CallHistory);
        #[qinvokable]
        #[cxx_name = "getCallById"]
        fn get_call_by_id(self: &CallHistory, id: i32) -> QMap_QString_QVariant;
        #[qinvokable]
        #[cxx_name = "getCallsByNumber"]
        fn get_calls_by_number(self: &CallHistory, number: &QString) -> QList_QVariant;
    }

    impl cxx_qt::Threading for CallHistory {}
    impl cxx_qt::Initialize for CallHistory {}
}

use qobject::CallHistory;

const HISTORY: Service = Service("CallHistory");

#[derive(Default)]
pub struct CallHistoryRust {
    history: QList<QVariant>,
    count: i32,
}

type Qt = cxx_qt::CxxQtThread<CallHistory>;

impl cxx_qt::Initialize for CallHistory {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        relay(qt.clone(), HISTORY, "CallAdded", |obj, (id,): (i32,)| obj.call_added(id));
        io::spawn(async move {
            read(&qt).await;
            let Ok(changes) = HISTORY.signals::<()>("HistoryChanged").await else { return };
            let mut changes = std::pin::pin!(changes);
            while changes.next().await.is_some() {
                read(&qt).await;
            }
        });
    }
}

async fn read(qt: &Qt) {
    if let Ok(history) = HISTORY.ask::<_, Vec<OwnedValue>>("GetHistory", &()).await {
        qt.queue(move |mut obj| {
            let mut h = obj.as_mut().rust_mut();
            h.history = variant::qlist(&history);
            h.count = i32::try_from(history.len()).unwrap_or(i32::MAX);
            obj.history_changed();
        })
        .ok();
    }
}

impl CallHistory {
    crate::shell::calls! { HISTORY;
        add_call(number: &QString, kind: &QString, timestamp: i64, duration: i32) => "AddCall";
        delete_call(id: i32) => "DeleteCall";
        clear_history() => "ClearHistory";
    }
    crate::shell::asks! { HISTORY;
        get_call_by_id(id: i32) -> QMap<QMapPair_QString_QVariant> => "GetCallById";
        get_calls_by_number(number: &QString) -> QList<QVariant> => "GetCallsByNumber";
    }

    fn refresh(&self) {
        let qt = self.qt_thread();
        io::spawn(async move { read(&qt).await });
    }
}
