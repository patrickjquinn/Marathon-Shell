// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

use cxx_qt_build::{CxxQtBuilder, QmlModule};

// Links Keel's SailfishApp library (libkeel-sailfishapp) for cpp/launcher.cpp;
// brings `Path` and `PathBuf` into scope.
include!("../../../tools/keel-launcher/link_sailfishapp.rs");
// Compiles the UI's QML into the app (tools/keel-launcher/precompile_qml.rs).
include!("../../../tools/keel-launcher/precompile_qml.rs");

fn main() {
    let repo = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../..");
    let sailfishapp_include = link_keel_sailfishapp(&repo);
    // `Shipwright.Reef 1.0`: the module the QML in ../ui/qml imports. It
    // holds only the Rust types; the UI's own .qml files are installed to
    // /usr/share/shipwright-reef/qml and loaded from disk.
    let builder = CxxQtBuilder::new_qml_module(QmlModule::new("Shipwright.Reef").version(1, 0))
        .qt_module("Quick")
        .qt_module("Network")
        .files(["src/bridge.rs"])
        // Creates the list models as children of the Reef object; CXX-Qt
        // cannot `new` a QObject from Rust.
        .cpp_file("cpp/factory.cpp")
        .include_dir(sailfishapp_include)
        .cpp_file("cpp/launcher.cpp");
    // GCC 16 warns (-Wsfinae-incomplete) inside Qt's own headers (qchar.h,
    // qmetatype.h probe completeness on purpose); older compilers ignore
    // the flag.
    // SAFETY: a warning flag only; it changes no generated code or ABI.
    let builder = unsafe {
        builder.cc_builder(|cc| {
            cc.flag_if_supported("-Wno-sfinae-incomplete");
        })
    };
    builder.build();
    // The UI's QML and JavaScript, compiled ahead of time for where the
    // package installs them.
    precompile_app_qml(
        &repo.join("reef/client/ui/qml"),
        "/usr/share/shipwright-reef/qml",
        &[],
    );
    // Keel Actions (ADR-0018): actions.json and the D-Bus files from the QML
    // declarations, into $OUT_DIR (keel::manifest!() in src/lib.rs) and
    // target/[<triple>/]<profile>/keel-actions/<app-id>/ for the RPM.
    keel_actions_codegen::Config {
        qml: vec![repo.join("reef/client/ui/qml")],
        desktop: Some(repo.join("reef/client/app/packaging/shipwright-reef.desktop")),
        // No [X-Sailjail] names (unsandboxed): the app ID is given.
        app_id: Some("org.shipwright.reef".into()),
        ..Default::default()
    }
    .build_script();
}
