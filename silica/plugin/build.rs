// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

use cxx_qt_build::CxxQtBuilder;

fn main() {
    // No QML module here: the C++ plugin in keel/silica/plugin/cpp registers
    // the generated QObject under the `Keel` URI itself, so that the plugin
    // library, qmldir and qmltypes are produced by qt_add_qml_module.
    let builder = CxxQtBuilder::new()
        .file("src/ambience.rs")
        .file("src/linkparser.rs");
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
}
