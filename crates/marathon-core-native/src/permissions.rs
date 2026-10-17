//! What each manifest permission lets an app do, in the words the install
//! screen shows. A package that declares a permission with no entry here is
//! refused, so nothing an app can reach goes undisclosed.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Disclosure {
    pub id: &'static str,
    pub label: &'static str,
    pub detail: &'static str,
    /// Reaches personal data, other apps' data or the system.
    pub sensitive: bool,
}

const fn entry(
    id: &'static str,
    label: &'static str,
    detail: &'static str,
    sensitive: bool,
) -> Disclosure {
    Disclosure {
        id,
        label,
        detail,
        sensitive,
    }
}

// What the app runner and sandbox grant for each id: see
// tools/marathon-app-runner/main.cpp (hasPerm) and applaunchservice.cpp.
const CATALOGUE: &[Disclosure] = &[
    entry(
        "network",
        "Internet",
        "Connect to the internet and devices on your network",
        false,
    ),
    entry("location", "Location", "See where the device is", true),
    entry("camera", "Camera", "Take photos and record video", true),
    entry("microphone", "Microphone", "Record audio", true),
    entry(
        "contacts",
        "Contacts",
        "Read and change your contacts",
        true,
    ),
    entry(
        "calendar",
        "Calendar",
        "Read and change your calendar events",
        true,
    ),
    entry(
        "storage",
        "Your files",
        "Read and change every file in your home folder",
        true,
    ),
    entry(
        "notifications",
        "Notifications",
        "Show notifications",
        false,
    ),
    entry("alarms", "Alarms", "Set alarms and timers", false),
    entry(
        "telephony",
        "Phone",
        "Make and answer calls and see your call history",
        true,
    ),
    entry(
        "phone",
        "Phone",
        "Make and answer calls and see your call history",
        true,
    ),
    entry("sms", "Messages", "Send and read SMS messages", true),
    entry(
        "bluetooth",
        "Bluetooth",
        "Connect to Bluetooth devices",
        false,
    ),
    entry(
        "sensors",
        "Sensors",
        "Read the motion and light sensors",
        false,
    ),
    entry(
        "secret-service",
        "Passwords",
        "Save and read passwords in your keyring",
        true,
    ),
    entry(
        "system",
        "System settings",
        "Change Wi-Fi, Bluetooth, display, sound, security and other device settings",
        true,
    ),
    entry(
        "terminal",
        "Terminal",
        "Run commands with full access to the system",
        true,
    ),
];

/// The words for one manifest permission, if it has any.
pub fn describe(id: &str) -> Option<&'static Disclosure> {
    CATALOGUE.iter().find(|d| d.id == id)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, reason = "tests")]
mod tests {
    use super::*;
    use std::fs;
    use std::path::Path;

    #[test]
    fn known_permissions_are_described() {
        let camera = describe("camera").unwrap();
        assert_eq!(camera.label, "Camera");
        assert!(camera.sensitive);
        assert!(!describe("network").unwrap().sensitive);
    }

    #[test]
    fn unknown_permissions_have_no_words() {
        assert_eq!(describe("root"), None);
        assert_eq!(describe("Camera"), None);
        assert_eq!(describe(""), None);
    }

    #[test]
    fn every_entry_has_words() {
        for d in CATALOGUE {
            assert!(!d.label.is_empty() && !d.detail.is_empty(), "{}", d.id);
            assert_eq!(
                CATALOGUE.iter().filter(|o| o.id == d.id).count(),
                1,
                "{}",
                d.id
            );
        }
    }

    // A shipped app must be installable as a package.
    #[test]
    fn every_permission_an_app_in_the_tree_declares_is_disclosed() {
        let apps = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../apps");
        let mut checked = 0;
        for entry in fs::read_dir(&apps).unwrap() {
            let manifest = entry.unwrap().path().join("manifest.json");
            let Ok(text) = fs::read_to_string(&manifest) else {
                continue;
            };
            let json: serde_json::Value = serde_json::from_str(&text).unwrap();
            for id in json["permissions"].as_array().into_iter().flatten() {
                let id = id.as_str().unwrap_or_default();
                assert!(describe(id).is_some(), "{}: {id}", manifest.display());
            }
            checked += 1;
        }
        assert!(
            checked > 10,
            "only {checked} manifests under {}",
            apps.display()
        );
    }
}
