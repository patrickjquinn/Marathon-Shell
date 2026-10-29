//! `RemoteTextInput`: Marathon's keyboard for the apps whose input method is
//! a session service (Deckard's Android IME, through deckardd), not
//! text-input on their surface. It serves `TextInput1` to that one service
//! and holds the editor it reports; the shell's event filter (C++, beside the
//! compositor) answers the keyboard's queries from it and hands it commits.

use std::pin::Pin;

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use futures_lite::StreamExt as _;
use zbus::message::Header;
use zbus::{fdo, names::BusName};

use crate::{gate, io, ipc, log};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[namespace = "marathon::text_input"]
    extern "Rust" {
        fn should_target_editor(
            editor: &QString,
            object_app_id: &QString,
            accepts_input_method: bool,
            front_app_id: &QString,
        ) -> bool;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QString, app_id_prefix, cxx_name = "appIdPrefix", READ, NOTIFY)]
        /// The app shown in the app window, or empty.
        #[qproperty(QString, front_app_id, cxx_name = "frontAppId", READ, WRITE, NOTIFY)]
        type RemoteTextInput = super::RemoteTextInputRust;

        /// How much of the app's window the keyboard covers, out of its height.
        #[qinvokable]
        #[cxx_name = "setPanel"]
        fn set_panel(self: Pin<&mut RemoteTextInput>, app_id: &QString, covered: i32, height: i32);

        // The editor, for the shell's event filter.
        #[cxx_name = "editorAppId"]
        fn editor_app_id(self: &RemoteTextInput) -> QString;
        /// zwp_text_input_v3 content purpose and hints.
        #[cxx_name = "editorPurpose"]
        fn editor_purpose(self: &RemoteTextInput) -> u32;
        #[cxx_name = "editorHints"]
        fn editor_hints(self: &RemoteTextInput) -> u32;
        #[cxx_name = "editorText"]
        fn editor_text(self: &RemoteTextInput) -> QString;
        #[cxx_name = "editorCursor"]
        fn editor_cursor(self: &RemoteTextInput) -> i32;
        #[cxx_name = "editorAnchor"]
        fn editor_anchor(self: &RemoteTextInput) -> i32;
        /// The keyboard's text, replacing `before` and `after` UTF-16 units
        /// around the cursor.
        fn commit(self: Pin<&mut RemoteTextInput>, text: &QString, before: i32, after: i32);
        /// backspace, enter, left, right, up, down, tab or escape.
        fn key(self: Pin<&mut RemoteTextInput>, name: &QString);

        #[qsignal]
        #[cxx_name = "hintsChanged"]
        fn hints_changed(self: Pin<&mut RemoteTextInput>);
        /// The service asks; main.cpp shows the panel only for the window in
        /// front (`panelRequested`).
        #[qsignal]
        #[cxx_name = "panelWanted"]
        fn panel_wanted(self: Pin<&mut RemoteTextInput>, show: bool);
        #[qsignal]
        #[cxx_name = "panelRequested"]
        fn panel_requested(self: Pin<&mut RemoteTextInput>, show: bool);
    }

    impl cxx_qt::Threading for RemoteTextInput {}
    impl cxx_qt::Initialize for RemoteTextInput {}
}

use qobject::RemoteTextInput;

fn should_target_editor(
    editor: &QString,
    object_app_id: &QString,
    accepts_input_method: bool,
    front_app_id: &QString,
) -> bool {
    if editor.is_empty() {
        return false;
    }
    if !object_app_id.is_empty() {
        return object_app_id == editor;
    }
    !accepts_input_method && front_app_id == editor
}

type Qt = cxx_qt::CxxQtThread<RemoteTextInput>;

const PATH: &str = "/org/marathonos/Shell/TextInput";
const INTERFACE: &str = "org.marathonos.Shell.TextInput1";

#[derive(Default)]
struct Editor {
    app_id: String,
    purpose: u32,
    hints: u32,
    text: Vec<u16>,
    cursor: usize,
    anchor: usize,
}

#[derive(Default)]
pub struct RemoteTextInputRust {
    app_id_prefix: QString,
    front_app_id: QString,
    /// The registered service's unique bus name.
    owner: String,
    editor: Editor,
    panel: (String, i32, i32),
}

impl cxx_qt::Initialize for RemoteTextInput {
    fn initialize(self: Pin<&mut Self>) {
        ipc::export(
            "TextInput",
            TextInput1 {
                qt: self.qt_thread(),
            },
        );
    }
}

fn to_i32(n: usize) -> i32 {
    i32::try_from(n).unwrap_or(i32::MAX)
}

fn to_usize(n: i32) -> usize {
    usize::try_from(n).unwrap_or(0)
}

impl RemoteTextInput {
    fn owns(&self, app_id: &str) -> bool {
        let prefix = self.app_id_prefix.to_string();
        !prefix.is_empty() && app_id.len() > prefix.len() && app_id.starts_with(&prefix)
    }

    fn editor_app_id(&self) -> QString {
        QString::from(&self.editor.app_id)
    }

    fn editor_purpose(&self) -> u32 {
        self.editor.purpose
    }

    fn editor_hints(&self) -> u32 {
        self.editor.hints
    }

    fn editor_text(&self) -> QString {
        QString::from(&String::from_utf16_lossy(&self.editor.text))
    }

    fn editor_cursor(&self) -> i32 {
        to_i32(self.editor.cursor)
    }

    fn editor_anchor(&self) -> i32 {
        to_i32(self.editor.anchor)
    }

    /// Applied to the reported text at once, so the keyboard's next query
    /// sees it before the app reports back.
    fn edit(mut self: Pin<&mut Self>, text: &str, before: usize, after: usize) {
        let mut rust = self.as_mut().rust_mut();
        let e = &mut rust.editor;
        let (mut from, mut to) = (e.cursor.min(e.anchor), e.cursor.max(e.anchor));
        if from == to {
            from = from.saturating_sub(before);
            to = (to + after).min(e.text.len());
        }
        let inserted: Vec<u16> = text.encode_utf16().collect();
        e.cursor = from + inserted.len();
        e.anchor = e.cursor;
        e.text.splice(from..to, inserted);
    }

    fn commit(mut self: Pin<&mut Self>, text: &QString, before: i32, after: i32) {
        let text = text.to_string();
        self.as_mut().edit(&text, to_usize(before), to_usize(after));
        self.send(
            "CommitString",
            (self.editor.app_id.clone(), text, before, after),
        );
    }

    fn key(mut self: Pin<&mut Self>, name: &QString) {
        let name = name.to_string();
        if name == "backspace" {
            self.as_mut().edit("", 1, 0);
        }
        self.send("Key", (self.editor.app_id.clone(), name));
    }

    fn set_panel(mut self: Pin<&mut Self>, app_id: &QString, covered: i32, height: i32) {
        let app_id = app_id.to_string();
        if !self.owns(&app_id) {
            return;
        }
        let panel = (app_id, covered.max(0), height);
        if panel == self.panel {
            return;
        }
        self.send("PanelChanged", panel.clone());
        self.as_mut().rust_mut().panel = panel;
    }

    /// A signal for the registered service alone.
    fn send<B>(&self, member: &'static str, body: B)
    where
        B: serde::Serialize + zbus::DynamicType + Send + Sync + 'static,
    {
        if self.owner.is_empty() {
            return;
        }
        let owner = self.owner.clone();
        io::spawn(async move {
            let Ok(bus) = io::session_bus().await else {
                return;
            };
            if let Err(e) = bus
                .emit_signal(Some(owner.as_str()), PATH, INTERFACE, member, &body)
                .await
            {
                log::warn("text-input", format_args!("{member}: {e}"));
            }
        });
    }

    fn set_service(mut self: Pin<&mut Self>, owner: String, prefix: &str) {
        let mut rust = self.as_mut().rust_mut();
        rust.owner = owner;
        rust.editor = Editor::default();
        set!(
            self,
            app_id_prefix,
            app_id_prefix_changed,
            QString::from(prefix)
        );
    }

    fn check_owner(&self, sender: &str) -> fdo::Result<()> {
        if !self.owner.is_empty() && sender == self.owner {
            return Ok(());
        }
        Err(fdo::Error::AccessDenied(
            "Not the registered input method".into(),
        ))
    }
}

struct TextInput1 {
    qt: Qt,
}

fn sender(h: &Header<'_>) -> String {
    h.sender().map(ToString::to_string).unwrap_or_default()
}

/// The owner's name gone from the bus: the keyboard is no one's.
fn watch_owner(qt: Qt, owner: String) {
    io::spawn(async move {
        let gone = async {
            let bus = io::session_bus().await?;
            let name = BusName::try_from(owner.as_str())?;
            let mut changes = fdo::DBusProxy::new(&bus)
                .await?
                .receive_name_owner_changed_with_args(&[(0, name.as_str())])
                .await?;
            while let Some(change) = changes.next().await {
                if change.args().is_ok_and(|a| a.new_owner().is_none()) {
                    break;
                }
            }
            zbus::Result::Ok(())
        };
        if gone.await.is_ok() {
            qt.queue(move |obj| {
                if obj.owner == owner {
                    obj.set_service(String::new(), "");
                }
            })
            .ok();
        }
    });
}

/// For one session service declaring the "text-input" permission; its
/// events go to it alone, as targeted signals.
#[zbus::interface(name = "org.marathonos.Shell.TextInput1")]
impl TextInput1 {
    /// Claims the windows whose app id starts with `app_id_prefix`, from any
    /// earlier owner.
    async fn register(
        &self,
        app_id_prefix: String,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        let caller = ipc::caller(&h).await.unwrap_or_default();
        if !gate::service_or_test(&caller, "text-input") {
            return Err(fdo::Error::AccessDenied(
                "Needs the text-input permission".into(),
            ));
        }
        if app_id_prefix.len() < 2 || !app_id_prefix.ends_with('.') {
            return Err(fdo::Error::InvalidArgs(
                "An app id prefix ends in '.'".into(),
            ));
        }
        let owner = sender(&h);
        watch_owner(self.qt.clone(), owner.clone());
        ipc::on_gui(&self.qt, move |obj| obj.set_service(owner, &app_id_prefix)).await
    }

    async fn set_editor(
        &self,
        app_id: String,
        purpose: u32,
        hints: u32,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        let h = sender(&h);
        ipc::on_gui(&self.qt, move |mut obj| {
            obj.check_owner(&h)?;
            if !obj.owns(&app_id) {
                return Err(fdo::Error::InvalidArgs("Not one of your apps".into()));
            }
            let changed = obj.editor.app_id != app_id
                || (obj.editor.purpose, obj.editor.hints) != (purpose, hints);
            obj.as_mut().rust_mut().editor = Editor {
                app_id,
                purpose,
                hints,
                ..Editor::default()
            };
            if changed {
                obj.hints_changed();
            }
            Ok(())
        })
        .await?
    }

    async fn set_surrounding_text(
        &self,
        app_id: String,
        text: String,
        cursor: i32,
        anchor: i32,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        let text: Vec<u16> = text.encode_utf16().collect();
        if text.len() > 4096 {
            return Err(fdo::Error::InvalidArgs("Text too long".into()));
        }
        let h = sender(&h);
        ipc::on_gui(&self.qt, move |mut obj| {
            obj.check_owner(&h)?;
            if obj.owns(&app_id) && obj.editor.app_id == app_id {
                let mut rust = obj.as_mut().rust_mut();
                let size = text.len();
                rust.editor.text = text;
                rust.editor.cursor = to_usize(cursor).min(size);
                rust.editor.anchor = to_usize(anchor).min(size);
            }
            Ok(())
        })
        .await?
    }

    async fn clear_editor(&self, app_id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        let h = sender(&h);
        ipc::on_gui(&self.qt, move |mut obj| {
            obj.check_owner(&h)?;
            if obj.owns(&app_id) && obj.editor.app_id == app_id {
                obj.as_mut().rust_mut().editor = Editor::default();
            }
            Ok(())
        })
        .await?
    }

    async fn show_panel(&self, app_id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        self.panel(app_id, true, sender(&h)).await
    }

    async fn hide_panel(&self, app_id: String, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        self.panel(app_id, false, sender(&h)).await
    }
}

impl TextInput1 {
    async fn panel(&self, app_id: String, show: bool, h: String) -> fdo::Result<()> {
        ipc::on_gui(&self.qt, move |obj| {
            obj.check_owner(&h)?;
            if obj.owns(&app_id) && obj.editor.app_id == app_id {
                obj.panel_wanted(show);
            }
            Ok(())
        })
        .await?
    }
}

#[cfg(test)]
mod tests {
    use super::{should_target_editor, QString};

    #[test]
    fn editor_target_fixtures() {
        let fixtures = [
            ("", "deckard.messages", false, "deckard.messages", false),
            ("deckard.messages", "deckard.messages", false, "", true),
            ("deckard.messages", "deckard.messages", true, "", true),
            (
                "deckard.messages",
                "deckard.settings",
                false,
                "deckard.messages",
                false,
            ),
            ("deckard.messages", "", false, "deckard.messages", true),
            ("deckard.messages", "", true, "deckard.messages", false),
            ("deckard.messages", "", false, "deckard.settings", false),
            ("deckard.messages", "", false, "", false),
            ("deckard.caf\u{e9}", "deckard.caf\u{e9}", false, "", true),
            (
                "deckard.caf\u{e9}",
                "deckard.cafe",
                false,
                "deckard.caf\u{e9}",
                false,
            ),
        ];

        for (editor, object_app_id, accepts_input_method, front_app_id, expected) in fixtures {
            assert_eq!(
                should_target_editor(
                    &QString::from(editor),
                    &QString::from(object_app_id),
                    accepts_input_method,
                    &QString::from(front_app_id),
                ),
                expected,
                "editor={editor:?} object={object_app_id:?} accepts={accepts_input_method} front={front_app_id:?}"
            );
        }
    }
}
