//! `KeyboardLayouts` (QML `LanguageManager`): the on-screen keyboard's
//! layouts, built into the shell, and the one in use.

use std::pin::Pin;

use cxx_qt::CxxQtType;
use cxx_qt_lib::{QList, QString, QStringList};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QString, current_language, cxx_name = "currentLanguage", READ, NOTIFY)]
        /// The layout as JSON (keyboard/Layouts/languages/*.json).
        #[qproperty(QString, current_layout, cxx_name = "currentLayout", READ, NOTIFY)]
        #[qproperty(QStringList, available_languages, cxx_name = "availableLanguages", READ, CONSTANT)]
        type KeyboardLayouts = super::KeyboardLayoutsRust;

        /// An unknown language loads US English.
        #[qinvokable]
        #[cxx_name = "loadLanguage"]
        fn load_language(self: Pin<&mut KeyboardLayouts>, language: &QString);

        /// The settings and the word list follow it (main.cpp connects them).
        #[qsignal]
        #[cxx_name = "languageChanged"]
        fn language_changed(self: Pin<&mut KeyboardLayouts>, language: &QString, dictionary: &QString);
        #[qsignal]
        #[cxx_name = "layoutLoaded"]
        fn layout_loaded(self: Pin<&mut KeyboardLayouts>, layout: &QString);
    }
}

use qobject::KeyboardLayouts;

macro_rules! layouts {
    ($($id:literal),*) => {
        const LAYOUTS: &[(&str, &str)] = &[$(($id, include_str!(concat!("../../../shell/qml/keyboard/Layouts/languages/", $id, ".json")))),*];
    };
}
layouts!("en_US", "fr_FR", "de_DE", "es_ES", "pt_BR", "it_IT", "ru_RU", "ar_SA", "zh_CN", "ja_JP");

pub struct KeyboardLayoutsRust {
    current_language: QString,
    current_layout: QString,
    available_languages: QStringList,
}

impl Default for KeyboardLayoutsRust {
    fn default() -> Self {
        let mut ids = QList::<QString>::default();
        for (id, _) in LAYOUTS {
            ids.append(QString::from(*id));
        }
        Self { current_language: QString::default(), current_layout: QString::default(), available_languages: QStringList::from(&ids) }
    }
}

impl KeyboardLayouts {
    fn load_language(mut self: Pin<&mut Self>, language: &QString) {
        let wanted = language.to_string();
        let (id, json) = LAYOUTS.iter().find(|(id, _)| *id == wanted).unwrap_or(&LAYOUTS[0]);
        let dictionary = serde_json::from_str::<serde_json::Value>(json)
            .ok()
            .and_then(|v| v["dictionary"].as_str().map(str::to_owned))
            .unwrap_or_else(|| (*id).to_owned());
        let layout = QString::from(*json);
        set!(self, current_layout, current_layout_changed, layout.clone());
        set!(self, current_language, current_language_changed, QString::from(*id));
        self.as_mut().language_changed(&QString::from(*id), &QString::from(&dictionary));
        self.layout_loaded(&layout);
    }
}
