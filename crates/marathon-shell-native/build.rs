use cxx_qt_build::CxxQtBuilder;

fn main() {
    CxxQtBuilder::new()
        .file("src/display.rs")
        .file("src/identity.rs")
        .file("src/modem.rs")
        .file("src/network.rs")
        .file("src/power.rs")
        .file("src/security.rs")
        .build();
}
