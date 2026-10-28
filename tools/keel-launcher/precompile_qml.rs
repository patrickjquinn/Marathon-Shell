// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Build-script helper (`include!`d by a Keel app's build.rs, after its
// CxxQtBuilder has built): compiles the app's own QML and JavaScript ahead
// of time with qmlcachegen and links the result into the app, so the QML
// engine never compiles them on the phone.
//
// The files stay installed where they were (/usr/share/<app>/qml/...): their
// relative imports, URLs and `Qt.resolvedUrl` keep working. Each file is
// compiled with its installed path as its resource path, and a generated
// loader registers a unit cache hook (the mechanism of qmlcachegen's own
// qrc loader) that hands the engine the compiled unit for exactly that
// `file:` URL. qmlcachegen compiles what it can of each binding and function
// to C++ (with the types of the import paths given) and the rest to
// bytecode; nothing is left for the engine to parse. QML_DISABLE_DISK_CACHE
// or a changed file on disk does not matter: the units come from the binary,
// unless KEEL_QML_FROM_DISK is set (for editing the installed files while
// developing).
//
// Needs: qmlcachegen of the Qt the app is built against (qmake's
// QT_INSTALL_LIBEXECS, or QT_HOST_LIBEXECS when cross-compiling), and the
// `cc` build dependency.

/// Compiles every .qml, .js and .mjs file under `src` (the directory the
/// package installs as `install`, e.g. "/usr/share/<app>/qml") and links the
/// units into the crate. `imports` are extra QML import directories for
/// qmlcachegen (besides `src` itself, Qt's own and the CXX-Qt modules this
/// build generated); with Keel's modules among them it compiles more to C++.
#[allow(dead_code)]
fn precompile_app_qml(src: &Path, install: &str, imports: &[PathBuf]) {
    keel_precompile_qml(src, install, imports, false);
}

/// As `precompile_app_qml`, compiling more of the QML to C++: against Keel's
/// modules (`keel_qml_imports()`) besides `imports`, and with the app's files
/// mapped to where they are installed, so that qmlcachegen also knows the
/// types the app's directory imports (`import "components"`) bring.
#[allow(dead_code)]
fn precompile_app_qml_typed(src: &Path, install: &str, imports: &[PathBuf]) {
    let mut all = keel_qml_imports();
    all.extend(imports.iter().cloned());
    keel_precompile_qml(src, install, &all, true);
}

#[allow(dead_code)]
fn keel_precompile_qml(src: &Path, install: &str, imports: &[PathBuf], map_installed: bool) {
    let out = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR")).join("keel-qmlcache");
    let _ = std::fs::remove_dir_all(&out);
    std::fs::create_dir_all(&out).expect("cannot create the qmlcache directory");

    let qmlcachegen = keel_qt_tool("qmlcachegen");
    let mut files = Vec::new();
    keel_qml_files(src, &mut files);
    println!("cargo:rerun-if-changed={}", src.display());

    // The QML modules CXX-Qt generated for this crate (their qmltypes).
    let generated = PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("qt-build-utils/qml_modules");
    let mut import_args = Vec::new();
    for dir in std::iter::once(src.to_path_buf()).chain(imports.iter().cloned()).chain(Some(generated)) {
        if dir.is_dir() {
            import_args.push("-I".to_owned());
            import_args.push(dir.display().to_string());
        }
    }

    // The installed paths of the files, as a resource file that qmlcachegen
    // reads to find what a file's directory imports name.
    if map_installed {
        use std::fmt::Write as _;
        let qrc = out.join("installed.qrc");
        let mut text = String::from("<RCC>\n<qresource prefix=\"/\">\n");
        for file in &files {
            let rel = file.strip_prefix(src).unwrap();
            let installed = format!("{}/{}", install.trim_matches('/'), rel.display());
            writeln!(text, "<file alias=\"{installed}\">{}</file>", file.display()).unwrap();
        }
        text += "</qresource>\n</RCC>\n";
        std::fs::write(&qrc, text).expect("write installed.qrc");
        import_args.push("--resource".to_owned());
        import_args.push(qrc.display().to_string());
    }

    let mut units = Vec::new(); // (installed path, C++ namespace)
    let mut sources = Vec::new();
    let (mut functions, mut compiled) = (0usize, 0usize);
    for (n, file) in files.iter().enumerate() {
        let rel = file.strip_prefix(src).unwrap();
        let installed = format!("{}/{}", install.trim_end_matches('/'), rel.display());
        let cpp = out.join(format!("unit{n}.cpp"));
        let (ns, f, c) = keel_compile_qml_unit(&qmlcachegen, &import_args, install, &installed, file, &cpp);
        functions += f;
        compiled += c;
        units.push((installed, ns));
        sources.push(cpp);
    }

    let loader_path = out.join("loader.cpp");
    std::fs::write(&loader_path, keel_qml_loader(&units)).unwrap();

    let headers = PathBuf::from(keel_qmake_query("QT_INSTALL_HEADERS"));
    let mut cc = cc::Build::new();
    cc.cpp(true)
        .std("c++17")
        .pic(true)
        .warnings(false)
        .define("QT_NO_DEBUG", None)
        .include(&headers);
    for module in ["QtCore", "QtGui", "QtQml", "QtQuick"] {
        cc.include(headers.join(module));
    }
    cc.files(&sources).file(&loader_path);
    // The loader registers itself from a static constructor that nothing
    // references: keep every object.
    cc.link_lib_modifier("+whole-archive");
    cc.compile("keel_app_qmlcache");
    // In the build script's output (cargo -vv, or target/*/build/*/output),
    // not a cargo warning: a clean build has none.
    println!(
        "QML precompiled: {} files, {compiled} of {functions} functions and bindings as C++, the rest as bytecode",
        units.len()
    );
}

/// Keel's QML modules (Sailfish.Silica, Keel.Actions, ...) as import
/// directories for `precompile_app_qml`: the directories in
/// `KEEL_QML_IMPORT_PATH` (colon-separated), which
/// tools/build/sdk/cxxqt-sailfish.sh sets from keel/tools/qml-sdk.sh for the
/// phone's Qt. With them qmlcachegen compiles to C++ the bindings and
/// functions that use Silica's types (Theme, Label, Page ...); without, those
/// are bytecode. Empty when unset.
#[allow(dead_code)]
fn keel_qml_imports() -> Vec<PathBuf> {
    println!("cargo:rerun-if-env-changed=KEEL_QML_IMPORT_PATH");
    std::env::var_os("KEEL_QML_IMPORT_PATH")
        .map(|p| std::env::split_paths(&p).filter(|d| d.is_dir()).collect())
        .unwrap_or_default()
}

/// The .qml, .js and .mjs files under `dir`, in a stable order.
#[allow(dead_code)]
fn keel_qml_files(dir: &Path, files: &mut Vec<PathBuf>) {
    let mut entries: Vec<_> = std::fs::read_dir(dir)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", dir.display()))
        .flatten()
        .map(|e| e.path())
        .collect();
    entries.sort();
    for p in entries {
        if p.is_dir() {
            keel_qml_files(&p, files);
        } else if matches!(p.extension().and_then(|e| e.to_str()), Some("qml" | "js" | "mjs")) {
            files.push(p);
        }
    }
}

/// Compiles one file to `cpp` with qmlcachegen; returns the unit's C++
/// namespace and, from qmlcachegen's statistics, how many of its functions
/// and bindings there are and how many became C++.
#[allow(dead_code)]
fn keel_compile_qml_unit(
    qmlcachegen: &Path,
    import_args: &[String],
    install: &str,
    installed: &str,
    file: &Path,
    cpp: &Path,
) -> (String, usize, usize) {
    let status = std::process::Command::new(qmlcachegen)
        .args(import_args)
        .arg("--resource-path")
        .arg(installed)
        .arg("--dump-aot-stats")
        .arg("--module-id")
        .arg(install)
        .arg("-o")
        .arg(cpp)
        .arg(file)
        .status()
        .unwrap_or_else(|e| panic!("cannot run {}: {e}", qmlcachegen.display()));
    assert!(status.success(), "qmlcachegen failed on {}", file.display());
    let text = std::fs::read_to_string(cpp).unwrap();
    let ns = text
        .lines()
        .skip_while(|l| !l.starts_with("namespace QmlCacheGeneratedCode"))
        .nth(1)
        .and_then(|l| l.strip_prefix("namespace "))
        .map_or_else(
            || panic!("no unit namespace in {}", cpp.display()),
            |l| l.trim_end_matches(" {").trim().to_owned(),
        );
    let (mut functions, mut compiled) = (0, 0);
    if let Ok(stats) = std::fs::read_to_string(cpp.with_extension("cpp.aotstats")) {
        functions = stats.matches("\"codegenResult\"").count() + stats.matches("\"codegenSuccessful\"").count();
        compiled = stats.matches("\"codegenResult\": 0").count() + stats.matches("\"codegenSuccessful\": true").count();
    }
    (ns, functions, compiled)
}

/// The loader: a unit cache hook that hands the engine each compiled unit
/// for its installed file's `file:` URL. `units`: (installed path, namespace).
#[allow(dead_code)]
fn keel_qml_loader(units: &[(String, String)]) -> String {
    use std::fmt::Write as _;
    let mut loader = String::from(
        "// Generated by tools/keel-launcher/precompile_qml.rs: the app's QML,\n\
         // compiled ahead of time, by installed path.\n\
         #include <QtQml/qqmlprivate.h>\n#include <QtCore/qdir.h>\n#include <QtCore/qglobal.h>\n#include <QtCore/qhash.h>\n\
         #include <QtCore/qstring.h>\n#include <QtCore/qurl.h>\n\nnamespace QmlCacheGeneratedCode {\n",
    );
    for (_, ns) in units {
        let _ = write!(
            loader,
            "namespace {ns} {{\n    extern const unsigned char qmlData[];\n    \
             extern const QQmlPrivate::AOTCompiledFunction aotBuiltFunctions[];\n    \
             const QQmlPrivate::CachedQmlUnit unit = {{\n        \
             reinterpret_cast<const QV4::CompiledData::Unit *>(&qmlData), &aotBuiltFunctions[0], nullptr\n    }};\n}}\n"
        );
    }
    loader += "}\n\nnamespace {\nstruct KeelAppQmlCache {\n    KeelAppQmlCache();\n    \
               QHash<QString, const QQmlPrivate::CachedQmlUnit *> units;\n    \
               static const QQmlPrivate::CachedQmlUnit *lookup(const QUrl &url);\n};\n\
               Q_GLOBAL_STATIC(KeelAppQmlCache, keelAppQmlCache)\n\
               KeelAppQmlCache::KeelAppQmlCache()\n{\n    \
               // KEEL_QML_FROM_DISK=1: the installed files as they are on disk,\n    \
               // edited there while developing, instead of the compiled units.\n    \
               if (qEnvironmentVariableIsSet(\"KEEL_QML_FROM_DISK\"))\n        return;\n";
    for (path, ns) in units {
        let _ = writeln!(
            loader,
            "    units.insert(QStringLiteral(\"{path}\"), &QmlCacheGeneratedCode::{ns}::unit);"
        );
    }
    loader += "    QQmlPrivate::RegisterQmlUnitCacheHook registration;\n    \
               registration.structVersion = 0;\n    registration.lookupCachedQmlUnit = &lookup;\n    \
               QQmlPrivate::qmlregister(QQmlPrivate::QmlUnitCacheHookRegistration, &registration);\n}\n\
               // The installed files, by their file: URL (and nothing else).\n\
               const QQmlPrivate::CachedQmlUnit *KeelAppQmlCache::lookup(const QUrl &url)\n{\n    \
               if (!url.isLocalFile())\n        return nullptr;\n    \
               return keelAppQmlCache()->units.value(QDir::cleanPath(url.toLocalFile()), nullptr);\n}\n\
               int keelInitAppQmlCache()\n{\n    keelAppQmlCache();\n    return 1;\n}\n\
               Q_CONSTRUCTOR_FUNCTION(keelInitAppQmlCache)\n} // namespace\n";
    loader
}

/// `qmake -query KEY` for the Qt the crate builds against ($QMAKE, else
/// qmake6, else qmake).
#[allow(dead_code)]
fn keel_qmake_query(key: &str) -> String {
    let candidates = std::env::var("QMAKE").ok().into_iter().chain(["qmake6".to_owned(), "qmake".to_owned()]);
    for qmake in candidates {
        if let Ok(out) = std::process::Command::new(&qmake).args(["-query", key]).output() {
            if out.status.success() {
                return String::from_utf8_lossy(&out.stdout).trim().to_owned();
            }
        }
    }
    panic!("qmake -query {key} failed: set QMAKE to Qt 6's qmake");
}

/// A Qt build tool (qmlcachegen, ...) for the host the build runs on.
#[allow(dead_code)]
fn keel_qt_tool(name: &str) -> PathBuf {
    for key in ["QT_HOST_LIBEXECS", "QT_INSTALL_LIBEXECS"] {
        let p = PathBuf::from(keel_qmake_query(key)).join(name);
        if p.exists() {
            return p;
        }
    }
    panic!("{name} not found (qmake's QT_HOST_LIBEXECS / QT_INSTALL_LIBEXECS)");
}
