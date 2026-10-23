//! `Ui` (QML `UIStore`): which of the shell's surfaces are open, the app on
//! screen and the Quick Settings shade.
#![allow(clippy::float_cmp, reason = "the shade heights' generated setters")]

use std::pin::Pin;

use cxx_qt::CxxQtType;
use cxx_qt_lib::{QString, QVariant};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(
            bool,
            quick_settings_open,
            cxx_name = "quickSettingsOpen",
            READ,
            NOTIFY
        )]
        #[qproperty(
            f64,
            quick_settings_height,
            cxx_name = "quickSettingsHeight",
            READ,
            WRITE,
            NOTIFY
        )]
        #[qproperty(
            bool,
            quick_settings_dragging,
            cxx_name = "quickSettingsDragging",
            READ,
            WRITE,
            NOTIFY
        )]
        /// The shade fully open, as the shell lays it out.
        #[qproperty(
            f64,
            max_quick_settings_height,
            cxx_name = "maxQuickSettingsHeight",
            READ,
            WRITE,
            NOTIFY
        )]
        /// How far a pull must go to open the shade.
        #[qproperty(
            f64,
            quick_settings_threshold,
            cxx_name = "quickSettingsThreshold",
            READ,
            WRITE,
            NOTIFY
        )]
        #[qproperty(bool, app_window_open, cxx_name = "appWindowOpen", READ, NOTIFY)]
        #[qproperty(QString, current_app_id, cxx_name = "currentAppId", READ, NOTIFY)]
        #[qproperty(QString, current_app_name, cxx_name = "currentAppName", READ, NOTIFY)]
        #[qproperty(QString, current_app_icon, cxx_name = "currentAppIcon", READ, NOTIFY)]
        #[qproperty(bool, settings_open, cxx_name = "settingsOpen", READ, NOTIFY)]
        #[qproperty(bool, search_open, cxx_name = "searchOpen", READ, NOTIFY)]
        #[qproperty(
            bool,
            clipboard_manager_open,
            cxx_name = "clipboardManagerOpen",
            READ,
            NOTIFY
        )]
        type Ui = super::UiRust;

        #[qinvokable]
        #[cxx_name = "openSearch"]
        fn open_search(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "closeSearch"]
        fn close_search(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "toggleSearch"]
        fn toggle_search(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "openClipboardManager"]
        fn open_clipboard_manager(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "closeClipboardManager"]
        fn close_clipboard_manager(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "openQuickSettings"]
        fn open_quick_settings(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "closeQuickSettings"]
        fn close_quick_settings(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "toggleQuickSettings"]
        fn toggle_quick_settings(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "openApp"]
        fn open_app(self: Pin<&mut Ui>, app_id: &QVariant, name: &QVariant, icon: &QVariant);
        #[qinvokable]
        #[cxx_name = "restoreApp"]
        fn restore_app(self: Pin<&mut Ui>, app_id: &QVariant, name: &QVariant, icon: &QVariant);
        #[qinvokable]
        #[cxx_name = "closeApp"]
        fn close_app(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "minimizeApp"]
        fn minimize_app(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "openSettings"]
        fn open_settings(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "closeSettings"]
        fn close_settings(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "minimizeSettings"]
        fn minimize_settings(self: Pin<&mut Ui>);
        #[qinvokable]
        #[cxx_name = "closeAll"]
        fn close_all(self: Pin<&mut Ui>);

        #[qsignal]
        #[cxx_name = "showConfirmDialog"]
        fn show_confirm_dialog(
            self: Pin<&mut Ui>,
            title: &QString,
            message: &QString,
            on_confirm: &QVariant,
            confirm_text: &QString,
        );
    }
}

use qobject::Ui;

#[allow(clippy::struct_excessive_bools, reason = "the QML properties")]
pub struct UiRust {
    quick_settings_open: bool,
    quick_settings_height: f64,
    quick_settings_dragging: bool,
    max_quick_settings_height: f64,
    quick_settings_threshold: f64,
    app_window_open: bool,
    current_app_id: QString,
    current_app_name: QString,
    current_app_icon: QString,
    settings_open: bool,
    search_open: bool,
    clipboard_manager_open: bool,
}

impl Default for UiRust {
    fn default() -> Self {
        Self {
            quick_settings_open: false,
            quick_settings_height: 0.0,
            quick_settings_dragging: false,
            max_quick_settings_height: 1000.0,
            quick_settings_threshold: 400.0,
            app_window_open: false,
            current_app_id: QString::default(),
            current_app_name: QString::default(),
            current_app_icon: QString::default(),
            settings_open: false,
            search_open: false,
            clipboard_manager_open: false,
        }
    }
}

fn text(v: &QVariant) -> QString {
    v.value::<QString>().unwrap_or_default()
}

impl Ui {
    fn open_search(mut self: Pin<&mut Self>) {
        set!(self, search_open, search_open_changed, true);
    }

    fn close_search(mut self: Pin<&mut Self>) {
        set!(self, search_open, search_open_changed, false);
    }

    fn toggle_search(mut self: Pin<&mut Self>) {
        let open = !self.search_open;
        set!(self, search_open, search_open_changed, open);
    }

    fn open_clipboard_manager(mut self: Pin<&mut Self>) {
        set!(
            self,
            clipboard_manager_open,
            clipboard_manager_open_changed,
            true
        );
    }

    fn close_clipboard_manager(mut self: Pin<&mut Self>) {
        set!(
            self,
            clipboard_manager_open,
            clipboard_manager_open_changed,
            false
        );
    }

    fn open_quick_settings(mut self: Pin<&mut Self>) {
        set!(self, quick_settings_open, quick_settings_open_changed, true);
        let height = self.max_quick_settings_height;
        self.set_quick_settings_height(height);
    }

    fn close_quick_settings(mut self: Pin<&mut Self>) {
        set!(
            self,
            quick_settings_open,
            quick_settings_open_changed,
            false
        );
        self.set_quick_settings_height(0.0);
    }

    fn toggle_quick_settings(self: Pin<&mut Self>) {
        if self.quick_settings_open {
            self.close_quick_settings();
        } else {
            self.open_quick_settings();
        }
    }

    fn show_app(mut self: Pin<&mut Self>, app_id: QString, name: QString, icon: QString) {
        let settings = app_id == QString::from("settings");
        set!(self, current_app_id, current_app_id_changed, app_id);
        set!(self, current_app_name, current_app_name_changed, name);
        set!(self, current_app_icon, current_app_icon_changed, icon);
        set!(self, app_window_open, app_window_open_changed, true);
        if settings {
            set!(self, settings_open, settings_open_changed, true);
        }
    }

    fn open_app(self: Pin<&mut Self>, app_id: &QVariant, name: &QVariant, icon: &QVariant) {
        self.show_app(text(app_id), text(name), text(icon));
    }

    fn restore_app(self: Pin<&mut Self>, app_id: &QVariant, name: &QVariant, icon: &QVariant) {
        self.show_app(text(app_id), text(name), text(icon));
    }

    fn close_app(mut self: Pin<&mut Self>) {
        set!(self, app_window_open, app_window_open_changed, false);
        if self.current_app_id == QString::from("settings") {
            set!(self, settings_open, settings_open_changed, false);
        }
        set!(
            self,
            current_app_id,
            current_app_id_changed,
            QString::default()
        );
        set!(
            self,
            current_app_name,
            current_app_name_changed,
            QString::default()
        );
        set!(
            self,
            current_app_icon,
            current_app_icon_changed,
            QString::default()
        );
    }

    fn minimize_app(self: Pin<&mut Self>) {
        self.close_app();
    }

    fn open_settings(mut self: Pin<&mut Self>) {
        set!(self, settings_open, settings_open_changed, true);
    }

    fn close_settings(mut self: Pin<&mut Self>) {
        set!(self, settings_open, settings_open_changed, false);
    }

    fn minimize_settings(self: Pin<&mut Self>) {
        self.close_app();
    }

    fn close_all(mut self: Pin<&mut Self>) {
        self.as_mut().close_quick_settings();
        self.as_mut().close_app();
        self.as_mut().close_settings();
        self.as_mut().close_search();
        self.close_clipboard_manager();
    }
}
