use cxx_qt_build::CxxQtBuilder;

fn main() {
    CxxQtBuilder::new()
        .file("src/cgroup.rs")
        .file("src/desktop.rs")
        .file("src/display.rs")
        .file("src/identity.rs")
        .file("src/modem.rs")
        .file("src/network.rs")
        .file("src/power.rs")
        .file("src/sandbox.rs")
        .file("src/security.rs")
        .build();
}
