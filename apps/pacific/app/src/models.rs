// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! The CXX-Qt declarations of the list models: `TabModel` (tabs.rs),
//! `SuggestionModel` (suggestions.rs) and `PacificList` (lists.rs). They
//! share one bridge because each bridge that declares `QAbstractListModel`
//! generates the same upcast symbols.

#![allow(
    clippy::unnecessary_box_returns,
    reason = "cxx_qt::bridge generates the boxed default constructor of the Rust structs"
)]

pub use crate::lists::PacificListRust;
pub use crate::suggestions::SuggestionModelRust;
pub use crate::tabs::TabModelRust;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qvariant.h");
        type QVariant = cxx_qt_lib::QVariant;
        include!("cxx-qt-lib/qmodelindex.h");
        type QModelIndex = cxx_qt_lib::QModelIndex;
        include!("cxx-qt-lib/qhash.h");
        type QHash_i32_QByteArray = cxx_qt_lib::QHash<cxx_qt_lib::QHashPair_i32_QByteArray>;
        include!("cxx-qt-lib/qlist.h");
        type QList_i32 = cxx_qt_lib::QList<i32>;
    }

    extern "C++Qt" {
        include!(<QtCore/QAbstractListModel>);
        #[qobject]
        type QAbstractListModel;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[base = QAbstractListModel]
        /// Private tabs (set once, when the model is created).
        #[qproperty(bool, private_tabs, cxx_name = "privateTabs", READ, WRITE, NOTIFY)]
        #[qproperty(i32, count, READ, NOTIFY)]
        #[qproperty(i32, active_id, cxx_name = "activeId", READ, NOTIFY)]
        #[qproperty(i32, active_index, cxx_name = "activeIndex", READ, NOTIFY)]
        #[qproperty(i32, closed_count, cxx_name = "closedCount", READ, NOTIFY)]
        type TabModel = super::TabModelRust;

        /// Opens a tab after the active one; returns its id. `background`
        /// keeps the active tab in front.
        #[qinvokable]
        fn add_tab(
            self: Pin<&mut TabModel>,
            url: &QString,
            title: &QString,
            background: bool,
        ) -> i32;

        /// Closes tab `id`; returns the tab now in front (0 when none).
        #[qinvokable]
        fn close_tab(self: Pin<&mut TabModel>, id: i32) -> i32;

        /// Reopens the most recently closed tab; returns its id (0: none).
        #[qinvokable]
        fn reopen_closed(self: Pin<&mut TabModel>) -> i32;

        #[qinvokable]
        fn activate(self: Pin<&mut TabModel>, id: i32);

        /// Changes tab `id` from a JSON object with any of: url, title,
        /// icon, thumbnail, loading, progress, audible, live, formDirty,
        /// engineState, scrollY, desktop, history (`[{url, title}]`),
        /// historyIndex.
        #[qinvokable]
        fn update(self: Pin<&mut TabModel>, id: i32, json: &QString);

        #[qinvokable]
        fn move_tab(self: Pin<&mut TabModel>, from: i32, to: i32);

        #[qinvokable]
        fn set_pinned(self: Pin<&mut TabModel>, id: i32, pinned: bool);

        #[qinvokable]
        fn close_all(self: Pin<&mut TabModel>);

        #[qinvokable]
        fn pinned_count(self: &TabModel) -> i32;

        #[qinvokable]
        fn index_of(self: &TabModel, id: i32) -> i32;

        #[qinvokable]
        fn id_at(self: &TabModel, index: i32) -> i32;

        /// The tab `step` places from `id` (-1 left, 1 right), 0 at an end.
        #[qinvokable]
        fn neighbour(self: &TabModel, id: i32, step: i32) -> i32;

        /// One tab as JSON (`{}` when unknown).
        #[qinvokable]
        fn get(self: &TabModel, id: i32) -> QString;

        /// Restores a saved session (Pacific.savedSession); returns the id
        /// of the tab in front.
        #[qinvokable]
        fn restore(self: Pin<&mut TabModel>, json: &QString) -> i32;

        /// The session to save (normal tabs and recently closed ones).
        #[qinvokable]
        fn session_json(self: &TabModel) -> QString;

        /// For Pacific.lifecycle.
        #[qinvokable]
        fn lifecycle_json(self: &TabModel) -> QString;

        /// `[{id, url, title}]` (address-bar "switch to tab").
        #[qinvokable]
        fn tabs_json(self: &TabModel) -> QString;

        #[cxx_override]
        fn data(self: &TabModel, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_override]
        fn row_count(self: &TabModel, parent: &QModelIndex) -> i32;
        #[cxx_override]
        fn role_names(self: &TabModel) -> QHash_i32_QByteArray;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[inherit]
        fn index(self: &TabModel, row: i32, column: i32, parent: &QModelIndex) -> QModelIndex;
        #[inherit]
        #[qsignal]
        fn data_changed(
            self: Pin<&mut TabModel>,
            top_left: &QModelIndex,
            bottom_right: &QModelIndex,
            roles: &QList_i32,
        );
        #[inherit]
        unsafe fn begin_insert_rows(
            self: Pin<&mut TabModel>,
            parent: &QModelIndex,
            first: i32,
            last: i32,
        );
        #[inherit]
        unsafe fn end_insert_rows(self: Pin<&mut TabModel>);
        #[inherit]
        unsafe fn begin_remove_rows(
            self: Pin<&mut TabModel>,
            parent: &QModelIndex,
            first: i32,
            last: i32,
        );
        #[inherit]
        unsafe fn end_remove_rows(self: Pin<&mut TabModel>);
        #[inherit]
        unsafe fn begin_move_rows(
            self: Pin<&mut TabModel>,
            source_parent: &QModelIndex,
            source_first: i32,
            source_last: i32,
            destination_parent: &QModelIndex,
            destination_child: i32,
        ) -> bool;
        #[inherit]
        unsafe fn end_move_rows(self: Pin<&mut TabModel>);
    }
    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[base = QAbstractListModel]
        #[qproperty(QString, text, READ, WRITE = set_text, NOTIFY)]
        /// Ask the search engine too (the setting, and never in private tabs).
        #[qproperty(bool, remote_enabled, cxx_name = "remoteEnabled", READ, WRITE, NOTIFY)]
        /// Open tabs (`TabModel.tabsJson()`), for "switch to tab".
        #[qproperty(QString, tabs, READ, WRITE, NOTIFY)]
        /// The inline completion of `text` (empty when none).
        #[qproperty(QString, autofill, READ, NOTIFY)]
        #[qproperty(i32, count, READ, NOTIFY)]
        type SuggestionModel = super::SuggestionModelRust;

        fn set_text(self: Pin<&mut SuggestionModel>, text: QString);

        /// Reads the suggestions for the current text again (the recent
        /// searches before anything is typed).
        #[qinvokable]
        fn refresh(self: Pin<&mut SuggestionModel>);

        /// Row `index` as JSON.
        #[qinvokable]
        fn get(self: &SuggestionModel, index: i32) -> QString;

        #[cxx_override]
        fn data(self: &SuggestionModel, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_override]
        fn row_count(self: &SuggestionModel, parent: &QModelIndex) -> i32;
        #[cxx_override]
        fn role_names(self: &SuggestionModel) -> QHash_i32_QByteArray;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[inherit]
        fn begin_reset_model(self: Pin<&mut SuggestionModel>);
        #[inherit]
        fn end_reset_model(self: Pin<&mut SuggestionModel>);
    }

    impl cxx_qt::Threading for SuggestionModel {}

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[base = QAbstractListModel]
        #[qproperty(QString, kind, READ, WRITE = set_kind, NOTIFY)]
        #[qproperty(QString, query, READ, WRITE = set_query, NOTIFY)]
        #[qproperty(i32, folder, READ, WRITE = set_folder, NOTIFY)]
        #[qproperty(i32, limit, READ, WRITE = set_limit, NOTIFY)]
        #[qproperty(i32, revision, READ, WRITE = set_revision, NOTIFY)]
        #[qproperty(i32, count, READ, NOTIFY)]
        /// True until the first rows arrived.
        #[qproperty(bool, loading, READ, NOTIFY)]
        type PacificList = super::PacificListRust;

        fn set_kind(self: Pin<&mut PacificList>, kind: QString);
        fn set_query(self: Pin<&mut PacificList>, query: QString);
        fn set_folder(self: Pin<&mut PacificList>, folder: i32);
        fn set_limit(self: Pin<&mut PacificList>, limit: i32);
        fn set_revision(self: Pin<&mut PacificList>, revision: i32);

        /// Reads the rows again.
        #[qinvokable]
        fn refresh(self: Pin<&mut PacificList>);

        /// Row `index` as JSON (`{}` when out of range).
        #[qinvokable]
        fn get(self: &PacificList, index: i32) -> QString;

        #[cxx_override]
        fn data(self: &PacificList, index: &QModelIndex, role: i32) -> QVariant;
        #[cxx_override]
        fn row_count(self: &PacificList, parent: &QModelIndex) -> i32;
        #[cxx_override]
        fn role_names(self: &PacificList) -> QHash_i32_QByteArray;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[inherit]
        fn begin_reset_model(self: Pin<&mut PacificList>);
        #[inherit]
        fn end_reset_model(self: Pin<&mut PacificList>);
    }

    impl cxx_qt::Threading for PacificList {}
}
