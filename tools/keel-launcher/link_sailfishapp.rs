// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

// Build-script helper shared by the Qt 6 apps (reef/client/app,
// shoal/*/app): links Keel's SailfishApp library, libkeel-sailfishapp, for
// the apps' cpp/launcher.cpp. Each app's build.rs pulls it in with
// `include!("<path to here>/link_sailfishapp.rs")` and calls
// `link_keel_sailfishapp(repo)`, which prints the cargo directives and
// returns the directory holding sailfishapp.h. See README.md here.
//
// Where the library comes from, first match wins:
// 1. `KEEL_SAILFISHAPP_INCLUDEDIR` and `KEEL_SAILFISHAPP_LIBDIR`
//    (`KEEL_SAILFISHAPP_RPATH=1` adds an rpath);
// 2. a Keel `CMake` build tree in `KEEL_BUILD_DIR` (with an rpath);
// 3. host builds only: the Keel build `keel run` keeps in
//    ~/.cache/keel-dev/keel-build (with an rpath), then
//    `pkg-config keel-sailfishapp` (shipwright-keel-sailfishapp-devel);
// 4. otherwise the library is compiled from this repository's
//    keel/sailfishapp/src (sailfishapp.cpp, keellauncher.cpp) and
//    keel/qt5compat/src/qt5source.cpp into the build-script output
//    directory, with the compiler cc would use for the target (the Sailfish
//    SDK cross compiler under tools/build/sdk/cxxqt-sailfish.sh) and the Qt
//    that qmake reports. Host builds get an rpath to it. In a cross build it
//    is only linked against: on the phone the binary loads
//    /usr/lib64/libkeel-sailfishapp.so.1 from shipwright-keel-sailfishapp,
//    built from the same source.
//
// It also makes the app's cdylib executable, so that the RPM can install it
// as /usr/bin/<app> and booster-keel (keel/booster, mapplauncherd) can
// dlopen() the same file and call its `main`; executable_cdylib() says why
// the app is a library and not a binary.

use std::path::{Path, PathBuf};
use std::process::Command;

/// Runs `pkg-config` with `args`; its trimmed output on success.
fn sailfishapp_pkg_config(args: &[&str]) -> Option<String> {
    let out = Command::new("pkg-config").args(args).output().ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).trim().to_owned())
}

/// (include dir, library dir) of a Keel `CMake` build tree.
fn sailfishapp_from_build_tree(build: &Path) -> Option<(PathBuf, PathBuf)> {
    let cache = std::fs::read_to_string(build.join("CMakeCache.txt")).ok()?;
    let source = cache
        .lines()
        .find_map(|l| l.strip_prefix("CMAKE_HOME_DIRECTORY:INTERNAL="))?;
    let lib = build.join("sailfishapp");
    lib.join("libkeel-sailfishapp.so")
        .exists()
        .then(|| (Path::new(source).join("sailfishapp/include"), lib))
}

/// `qmake -query <key>`, with qmake from `QMAKE`, else `qmake6`, else
/// `qmake` (the order cxx-qt-build uses).
fn sailfishapp_qmake_query(key: &str) -> String {
    let candidates: Vec<String> = std::env::var("QMAKE")
        .ok()
        .into_iter()
        .chain(["qmake6".to_owned(), "qmake".to_owned()])
        .collect();
    for qmake in candidates {
        if let Ok(out) = Command::new(&qmake).args(["-query", key]).output() {
            if out.status.success() {
                return String::from_utf8_lossy(&out.stdout).trim().to_owned();
            }
        }
    }
    panic!("cannot run qmake (set QMAKE) to find Qt for libkeel-sailfishapp");
}

/// Compiles libkeel-sailfishapp.so.1 from the repository's source into
/// `$OUT_DIR/keel-sailfishapp`; returns (include dir, library dir).
fn sailfishapp_from_source(repo: &Path, cross: bool) -> (PathBuf, PathBuf) {
    let src = repo.join("keel/sailfishapp");
    let include = src.join("include");
    // The Qt 5 source rewrite (keel/qt5compat/src) is part of the library,
    // as keel/sailfishapp/CMakeLists.txt links it in.
    let qt5source = repo.join("keel/qt5compat/src");
    let sources = [
        src.join("src/sailfishapp.cpp"),
        src.join("src/keellauncher.cpp"),
        qt5source.join("qt5source.cpp"),
    ];
    for file in sources.iter().chain(&[
        src.join("src/keellauncher_p.h"),
        include.join("sailfishapp.h"),
        include.join("keellauncher.h"),
        qt5source.join("qt5source.h"),
    ]) {
        println!("cargo:rerun-if-changed={}", file.display());
    }
    let out = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR")).join("keel-sailfishapp");
    std::fs::create_dir_all(&out).expect("create the libkeel-sailfishapp directory");

    let headers = PathBuf::from(sailfishapp_qmake_query("QT_INSTALL_HEADERS"));
    let libs = sailfishapp_qmake_query("QT_INSTALL_LIBS");
    let mut cmd = cc::Build::new()
        .cpp(true)
        .cargo_metadata(false)
        .get_compiler()
        .to_command();
    cmd.args(["-std=c++17", "-fPIC", "-shared", "-O2"])
        .arg("-DKEEL_SAILFISHAPP_LIBRARY")
        .arg("-DKEEL_SAILFISHAPP_SHARE_DIR=\"/usr/share\"")
        .arg("-fvisibility=hidden")
        .arg(format!("-I{}", include.display()))
        .arg(format!("-I{}", qt5source.display()))
        .arg(format!("-I{}", headers.display()));
    for module in ["QtCore", "QtGui", "QtQml", "QtQuick"] {
        cmd.arg(format!("-I{}", headers.join(module).display()));
    }
    cmd.args(&sources)
        .arg("-Wl,-soname,libkeel-sailfishapp.so.1")
        .arg("-o")
        .arg(out.join("libkeel-sailfishapp.so.1"));
    // A host copy is loaded at run time, so it links Qt itself. A cross
    // copy is only linked against; the app links Qt.
    if !cross {
        cmd.arg(format!("-L{libs}"))
            .args(["-lQt6Quick", "-lQt6Qml", "-lQt6Gui", "-lQt6Core"]);
    }
    let status = cmd
        .status()
        .unwrap_or_else(|e| panic!("cannot run the C++ compiler for libkeel-sailfishapp: {e}"));
    assert!(status.success(), "compiling libkeel-sailfishapp failed ({status})");
    let link = out.join("libkeel-sailfishapp.so");
    let _ = std::fs::remove_file(&link);
    #[cfg(unix)]
    std::os::unix::fs::symlink("libkeel-sailfishapp.so.1", &link)
        .expect("link libkeel-sailfishapp.so");
    (include, out)
}

/// Links libkeel-sailfishapp (see the top of this file); returns the
/// directory holding sailfishapp.h.
fn link_keel_sailfishapp(repo: &Path) -> PathBuf {
    for var in [
        "KEEL_SAILFISHAPP_INCLUDEDIR",
        "KEEL_SAILFISHAPP_LIBDIR",
        "KEEL_SAILFISHAPP_RPATH",
        "KEEL_BUILD_DIR",
        "QMAKE",
    ] {
        println!("cargo:rerun-if-env-changed={var}");
    }
    let cross = std::env::var("TARGET").ok() != std::env::var("HOST").ok();

    let explicit = match (
        std::env::var_os("KEEL_SAILFISHAPP_INCLUDEDIR"),
        std::env::var_os("KEEL_SAILFISHAPP_LIBDIR"),
    ) {
        (Some(inc), Some(lib)) => Some((
            PathBuf::from(inc),
            Some(PathBuf::from(lib)),
            std::env::var("KEEL_SAILFISHAPP_RPATH").as_deref() == Ok("1"),
        )),
        _ => None,
    };
    let build_tree = || {
        let cache = (!cross)
            .then(|| {
                std::env::var_os("XDG_CACHE_HOME")
                    .map(PathBuf::from)
                    .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
                    .map(|c| c.join("keel-dev/keel-build"))
            })
            .flatten();
        std::env::var_os("KEEL_BUILD_DIR")
            .map(PathBuf::from)
            .or(cache)
            .and_then(|b| sailfishapp_from_build_tree(&b))
            .map(|(inc, lib)| (inc, Some(lib), true))
    };
    let installed = || {
        if cross {
            return None;
        }
        let inc = sailfishapp_pkg_config(&["--variable=includedir", "keel-sailfishapp"])?;
        let lib = sailfishapp_pkg_config(&["--variable=libdir", "keel-sailfishapp"]);
        Some((PathBuf::from(inc), lib.map(PathBuf::from), false))
    };
    let (include, libdir, rpath) = explicit
        .or_else(build_tree)
        .or_else(installed)
        .unwrap_or_else(|| {
            let (inc, lib) = sailfishapp_from_source(repo, cross);
            (inc, Some(lib), !cross)
        });

    if let Some(lib) = &libdir {
        println!("cargo:rustc-link-search=native={}", lib.display());
        if rpath {
            println!("cargo:rustc-link-arg=-Wl,-rpath,{}", lib.display());
        }
    }
    println!("cargo:rustc-link-lib=keel-sailfishapp");
    // rustc passes the crate's own `-l` libraries (these, and the Qt modules
    // cxx-qt-build declares) under `--as-needed` before the static archives
    // holding the app's C++ (cpp/launcher.cpp, the cxx-qt bridges) that use
    // them, so GNU ld can drop them: the app then fails at start with an
    // undefined `SailfishApp::` or `QQuickItem::` symbol (seen with Fedora's
    // toolchain). Name them again after every object, recorded regardless.
    println!(
        "cargo:rustc-link-arg=-Wl,--push-state,--no-as-needed,-lkeel-sailfishapp,-lQt6Quick,--pop-state"
    );
    executable_cdylib();
    include
}

/// Makes the app's shared library (its cdylib) executable, so that the
/// same file is /usr/bin/<app> and what booster-keel loads (see the top of
/// this file).
///
/// mapplauncherd `dlopen()`s the app and calls its `main`, so the app must
/// be a shared object: code linked into a position-independent executable
/// may use the local-exec TLS model, which assumes the executable's TLS
/// block is the process's first (and upstream glibc refuses to `dlopen()` a
/// PIE at all; Sailfish's glibc reverts that). Linking
/// a Rust binary with `-shared` does not fix that: rustc compiles a binary
/// crate, including the std and tokio generics instantiated in it, for an
/// executable and emits local-exec TLS relocations that a shared object
/// cannot hold (`R_X86_64_TPOFF32`, `R_AARCH64_TLSLE_*`): release builds
/// fail to link, and one that did link would put the app's thread-locals on
/// someone else's memory in the booster (a crash in `std::thread::spawn`).
/// Each app is therefore a library crate built as a `cdylib`, which rustc
/// compiles for a shared object (dynamic TLS models) and links with
/// `-shared` and a version script exporting only `#[no_mangle]` items: the
/// C `main` in the app's src/lib.rs, and cxx's bridge functions. These
/// arguments make that library executable as well, as glibc's own libc.so.6
/// is: the C runtime's `Scrt1.o` start code (its `_start` calls `main`) and a
/// `.interp` section naming the dynamic linker, which makes the linker emit
/// `PT_INTERP`. Linux targets only; elsewhere the library is left as it is.
/// The dynamic linker is the target C library's: glibc's, or musl's
/// (Alpine, Marathon OS), where glibc's path does not exist and the app
/// fails to start ("cannot execute: required file not found").
fn executable_cdylib() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("linux") {
        return;
    }
    let musl = std::env::var("CARGO_CFG_TARGET_ENV").as_deref() == Ok("musl");
    let hard_float = std::env::var("CARGO_CFG_TARGET_ABI").is_ok_and(|abi| abi.ends_with("hf"));
    let interp = match (std::env::var("CARGO_CFG_TARGET_ARCH").as_deref(), musl) {
        (Ok("x86_64"), false) => "/lib64/ld-linux-x86-64.so.2",
        (Ok("aarch64"), false) => "/lib/ld-linux-aarch64.so.1",
        (Ok("arm"), false) => "/lib/ld-linux-armhf.so.3",
        (Ok("x86"), false) => "/lib/ld-linux.so.2",
        (Ok("x86_64"), true) => "/lib/ld-musl-x86_64.so.1",
        (Ok("aarch64"), true) => "/lib/ld-musl-aarch64.so.1",
        (Ok("arm"), true) if hard_float => "/lib/ld-musl-armhf.so.1",
        (Ok("arm"), true) => "/lib/ld-musl-arm.so.1",
        (Ok("x86"), true) => "/lib/ld-musl-i386.so.1",
        _ => return,
    };
    let compiler = cc::Build::new().cargo_metadata(false).get_compiler();
    let scrt1 = compiler
        .to_command()
        .arg("-print-file-name=Scrt1.o")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_owned())
        .filter(|p| Path::new(p).is_absolute());
    let Some(scrt1) = scrt1 else {
        println!("cargo:warning=no Scrt1.o from the C compiler: the app library is not executable");
        return;
    };
    let out = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR"));
    let interp_c = out.join("keel-interp.c");
    let interp_o = out.join("keel-interp.o");
    std::fs::write(
        &interp_c,
        format!(
            "const char keel_interp[] __attribute__((section(\".interp\"), used)) = \"{interp}\";\n"
        ),
    )
    .expect("write keel-interp.c");
    let status = compiler
        .to_command()
        .arg("-c")
        .arg(&interp_c)
        .arg("-o")
        .arg(&interp_o)
        .status()
        .expect("run the C compiler for keel-interp.c");
    assert!(status.success(), "compiling keel-interp.c failed ({status})");
    println!("cargo:rustc-cdylib-link-arg={scrt1}");
    println!("cargo:rustc-cdylib-link-arg={}", interp_o.display());
    // Keeps the section through --gc-sections.
    println!("cargo:rustc-cdylib-link-arg=-Wl,--undefined=keel_interp");
}
