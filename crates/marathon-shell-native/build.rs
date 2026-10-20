use cxx_qt_build::CxxQtBuilder;

fn main() {
    let builder = CxxQtBuilder::new()
        .file("src/backlight.rs")
        .file("src/identity.rs")
        .file("src/iio.rs")
        .file("src/network.rs")
        .file("src/power.rs")
        .file("src/security.rs");
    // SAFETY: an include path for the shell's own headers (securityaudit.h);
    // it changes no generated code.
    let builder = unsafe { builder.cc_builder(|cc| { cc.include("../../shell/src"); }) };
    builder.build();
    // components/pamauth.h calls libpam.
    println!("cargo::rustc-link-lib=pam");
}
