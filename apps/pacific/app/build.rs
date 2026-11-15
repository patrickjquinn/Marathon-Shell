// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

use std::path::{Path, PathBuf};

use cxx_qt_build::{CxxQtBuilder, PluginType, QmlModule};

// Compiles the UI's QML ahead of time (precompile_app_qml_typed).
include!("../../../tools/keel-launcher/precompile_qml.rs");

fn main() {
    let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..");
    // `Shipwright.Pacific 1.0`: the Rust singleton and models, a QML plugin
    // the runner loads (the package installs the library and the qmldir
    // CXX-Qt writes to <target>/cxxqt/qml_modules/Shipwright/Pacific).
    let builder = CxxQtBuilder::new_qml_module(
        QmlModule::new("Shipwright.Pacific")
            .version(1, 0)
            .plugin_type(PluginType::Dynamic),
    )
    .qt_module("Gui")
    .qt_module("Quick")
    .files(["src/bridge.rs", "src/models.rs"]);
    // GCC 16 warns (-Wsfinae-incomplete) inside Qt's own headers.
    // SAFETY: a warning flag only; it changes no generated code or ABI.
    let builder = unsafe {
        builder.cc_builder(|cc| {
            cc.flag_if_supported("-Wno-sfinae-incomplete");
        })
    };
    builder.build();
    // The UI's QML and JavaScript, compiled ahead of time for where the
    // package installs them, against Keel's modules and, when its build tree
    // is there (PACIFIC_WEBVIEW_QML_DIR), Shipwright.Pacific.WebView: what
    // uses their types becomes C++. The plugin hands the engine these units
    // once it is loaded; the entry file, read before, is compiled on the
    // phone.
    println!("cargo:rerun-if-env-changed=PACIFIC_WEBVIEW_QML_DIR");
    let webview = std::env::var_os("PACIFIC_WEBVIEW_QML_DIR").map_or_else(
        || repo.join("target/pacific-webview-build/qml"),
        PathBuf::from,
    );
    let imports: Vec<PathBuf> = webview
        .join("Shipwright/Pacific/WebView/qmldir")
        .is_file()
        .then_some(webview)
        .into_iter()
        .collect();
    precompile_app_qml_typed(
        &repo.join("apps/pacific/ui/qml"),
        "/usr/share/marathon-apps/shipwright-pacific/ui/qml",
        &imports,
    );
    // Keel Actions (ADR-0018): actions.json and the D-Bus files from the
    // QML declarations.
    keel_actions_codegen::Config {
        qml: vec![repo.join("apps/pacific/ui/qml")],
        desktop: Some(repo.join("apps/pacific/shipwright-pacific.desktop")),
        app_id: Some("org.marathonos.shipwright-pacific".into()),
        ..Default::default()
    }
    .build_script();
}
