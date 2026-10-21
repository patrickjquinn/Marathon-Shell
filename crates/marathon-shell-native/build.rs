use cxx_qt_build::CxxQtBuilder;

fn main() {
    CxxQtBuilder::new()
        .file("src/alarms.rs")
        .file("src/ambience.rs")
        .file("src/audio.rs")
        .file("src/bluetooth.rs")
        .file("src/cgroup.rs")
        .file("src/clipboard.rs")
        .file("src/contacts.rs")
        .file("src/desktop.rs")
        .file("src/display.rs")
        .file("src/flashlight.rs")
        .file("src/haptics.rs")
        .file("src/gate.rs")
        .file("src/identity.rs")
        .file("src/ipc.rs")
        .file("src/location.rs")
        .file("src/modem.rs")
        .file("src/motion.rs")
        .file("src/mpris.rs")
        .file("src/network.rs")
        .file("src/ngf.rs")
        .file("src/pilot.rs")
        .file("src/permissions.rs")
        .file("src/power.rs")
        .file("src/pressure.rs")
        .file("src/push.rs")
        .file("src/sandbox.rs")
        .file("src/security.rs")
        .file("src/telephonyd.rs")
        .file("src/timezone.rs")
        .file("src/updates.rs")
        .file("src/weather.rs")
        .file("src/words.rs")
        .build();

    let oxford = std::path::Path::new("../../thirdparty/oxford-step-counter");
    println!("cargo::rerun-if-changed={}", oxford.display());
    let mut cc = cc::Build::new();
    cc.include(oxford.join("include")).std("c11").warnings(false);
    for c in std::fs::read_dir(oxford.join("src")).into_iter().flatten().flatten().map(|e| e.path()) {
        if c.extension().is_some_and(|e| e == "c") {
            cc.file(c);
        }
    }
    cc.compile("oxford-step-counter");
}
