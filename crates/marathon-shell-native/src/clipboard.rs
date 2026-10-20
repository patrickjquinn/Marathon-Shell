//! `Clipboard`: the last 20 things copied, newest first, kept in
//! `$XDG_STATE_HOME/marathon/clipboard.json` and written on the I/O thread.

use std::path::PathBuf;
use std::pin::Pin;
use std::time::{SystemTime, UNIX_EPOCH};

use async_channel::{Receiver, Sender};
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QList, QMap, QMapPair_QString_QVariant, QString, QVariant};
use serde::{Deserialize, Serialize};

use crate::{io, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        /// Each entry a map of text, type and timestamp (ms).
        #[qproperty(QList_QVariant, history, READ, NOTIFY)]
        type Clipboard = super::ClipboardRust;

        #[qinvokable]
        #[cxx_name = "copyToClipboard"]
        fn copy_to_clipboard(self: Pin<&mut Clipboard>, text: &QString);
        #[qinvokable]
        #[cxx_name = "deleteItem"]
        fn delete_item(self: Pin<&mut Clipboard>, index: i32);
        #[qinvokable]
        #[cxx_name = "clearHistory"]
        fn clear_history(self: Pin<&mut Clipboard>);
    }

    impl cxx_qt::Threading for Clipboard {}
    impl cxx_qt::Initialize for Clipboard {}
}

use qobject::Clipboard;

const MAX: usize = 20;

#[derive(Default)]
pub struct ClipboardRust {
    history: QList<QVariant>,
    items: Vec<Item>,
    writer: Option<Sender<Vec<u8>>>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
struct Item {
    text: String,
    #[serde(rename = "type")]
    kind: String,
    timestamp: i64,
}

impl cxx_qt::Initialize for Clipboard {
    fn initialize(mut self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        let (tx, rx) = async_channel::bounded(4);
        io::spawn(async move {
            let items: Vec<Item> = blocking::unblock(|| std::fs::read(path()).ok().and_then(|b| serde_json::from_slice(&b).ok()))
                .await
                .unwrap_or_default();
            qt.queue(move |obj| obj.show(items)).ok();
            writer(rx).await;
        });
        self.as_mut().rust_mut().writer = Some(tx);
    }
}

impl Clipboard {
    fn copy_to_clipboard(mut self: Pin<&mut Self>, text: &QString) {
        let text = text.to_string();
        if text.is_empty() {
            return;
        }
        let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX));
        let mut items = std::mem::take(&mut self.as_mut().rust_mut().items);
        add(&mut items, Item { text, kind: "text".to_owned(), timestamp: now });
        self.save(items);
    }

    fn delete_item(mut self: Pin<&mut Self>, index: i32) {
        let mut items = std::mem::take(&mut self.as_mut().rust_mut().items);
        if let Ok(i) = usize::try_from(index) {
            if i < items.len() {
                items.remove(i);
            }
        }
        self.save(items);
    }

    fn clear_history(self: Pin<&mut Self>) {
        if !self.items.is_empty() {
            self.save(Vec::new());
        }
    }

    fn save(self: Pin<&mut Self>, items: Vec<Item>) {
        match serde_json::to_vec(&items) {
            Ok(json) => {
                if let Some(writer) = &self.writer {
                    writer.try_send(json).ok();
                }
            }
            Err(e) => log::warn("clipboard", e),
        }
        self.show(items);
    }

    fn show(mut self: Pin<&mut Self>, items: Vec<Item>) {
        let mut history = QList::<QVariant>::default();
        for item in &items {
            let mut map = QMap::<QMapPair_QString_QVariant>::default();
            map.insert(QString::from("text"), QVariant::from(&QString::from(item.text.as_str())));
            map.insert(QString::from("type"), QVariant::from(&QString::from(item.kind.as_str())));
            map.insert(QString::from("timestamp"), QVariant::from(&item.timestamp));
            history.append(QVariant::from(&map));
        }
        let mut rust = self.as_mut().rust_mut();
        rust.history = history;
        rust.items = items;
        self.history_changed();
    }
}

/// Newest first, once each, at most `MAX`.
fn add(items: &mut Vec<Item>, item: Item) {
    items.retain(|i| i.text != item.text);
    items.insert(0, item);
    items.truncate(MAX);
}

fn path() -> PathBuf {
    let state = std::env::var_os("XDG_STATE_HOME")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/state")))
        .unwrap_or_default();
    state.join("marathon/clipboard.json")
}

/// Writes each history in turn, skipping to the newest queued.
async fn writer(histories: Receiver<Vec<u8>>) {
    while let Ok(mut json) = histories.recv().await {
        while let Ok(newer) = histories.try_recv() {
            json = newer;
        }
        if let Err(e) = blocking::unblock(move || write(&json)).await {
            log::warn("clipboard", e);
        }
    }
}

fn write(json: &[u8]) -> std::io::Result<()> {
    let path = path();
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let partial = path.with_extension("json.new");
    std::fs::write(&partial, json)?;
    std::fs::rename(partial, path)
}

#[cfg(test)]
mod tests {
    use super::{add, Item, MAX};

    fn item(text: &str) -> Item {
        Item { text: text.to_owned(), kind: "text".to_owned(), timestamp: 0 }
    }

    #[test]
    fn copying_again_moves_it_to_the_top_and_the_oldest_falls_off() {
        let mut items = Vec::new();
        for i in 0..=MAX {
            add(&mut items, item(&i.to_string()));
        }
        assert_eq!(items.len(), MAX);
        assert_eq!(items.last().map(|i| i.text.as_str()), Some("1"));
        add(&mut items, item("5"));
        let texts: Vec<&str> = items.iter().take(3).map(|i| i.text.as_str()).collect();
        assert_eq!(texts, ["5", "20", "19"]);
        assert_eq!(items.len(), MAX);
    }
}
