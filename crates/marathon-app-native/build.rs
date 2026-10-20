use cxx_qt_build::CxxQtBuilder;

fn main() {
    CxxQtBuilder::new()
        .file("src/alarms.rs")
        .file("src/audio.rs")
        .file("src/contacts.rs")
        .file("src/display.rs")
        .file("src/location.rs")
        .file("src/modem.rs")
        .file("src/network.rs")
        .file("src/permissions.rs")
        .file("src/power.rs")
        .file("src/sensors.rs")
        .file("src/settings.rs")
        .file("src/shell.rs")
        .file("src/sms.rs")
        .file("src/telephony.rs")
        .build();
}
