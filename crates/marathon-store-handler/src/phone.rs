//! Which Flathub apps fit a phone, from Flathub's `AppStream` catalogue as
//! flatpak keeps it. The Store shows only these by default.
//!
//! An app fits when no `<requires>` `display_length` rules out a 360 px
//! shortest side, and it either declares `Purism::form_factor` mobile or has
//! a `display_length` admitting 360 px together with a touch `<control>`, in
//! `requires`, `recommends` or `supports`. Anything else, including an app
//! that says nothing, is left out.

use std::fs::{self, File};
use std::io::{self, BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use quick_xml::events::{BytesStart, Event};
use quick_xml::Reader;
use serde_json::{json, Value};

use crate::state::{now, StateDir};

/// The shortest side of a phone, and the longest side that still counts as
/// one, in logical pixels.
const PHONE: u32 = 360;
const PHONE_MAX: u32 = 768;

#[derive(Default)]
#[allow(clippy::struct_excessive_bools, reason = "one flag per AppStream hint")]
struct Component {
    id: String,
    app: bool,
    required_too_big: bool,
    fits: bool,
    touch: bool,
    mobile: bool,
}

impl Component {
    fn phone_ready(&self) -> bool {
        self.app && !self.required_too_big && (self.mobile || (self.fits && self.touch))
    }
}

/// Whether a `display_length` admits a phone; `None` when it says nothing
/// about the shortest side.
fn admits_phone(compare: &str, side: &str, value: &str) -> Option<bool> {
    if side == "longest" {
        return None;
    }
    let value = value.trim();
    if let Ok(px) = value.trim_end_matches("px").parse::<u32>() {
        return Some(match compare {
            "" | "ge" => px <= PHONE,
            "gt" => px < PHONE,
            "le" => px >= PHONE_MAX,
            "lt" => px > PHONE_MAX,
            _ => false,
        });
    }
    // The named sizes of AppStream before 1.0: small is a phone.
    match (compare, value) {
        ("" | "ge", "xsmall" | "small")
        | ("gt", "xsmall")
        | ("le" | "lt", "small" | "medium" | "large" | "xlarge") => Some(true),
        (_, "xsmall" | "small" | "medium" | "large" | "xlarge") => Some(false),
        _ => None,
    }
}

fn attribute(e: &BytesStart, name: &str) -> String {
    e.try_get_attribute(name)
        .ok()
        .flatten()
        .map(|a| a.value.into_owned())
        .unwrap_or_default()
}

/// The ids of the apps in an `AppStream` catalogue that fit a phone, sorted.
pub fn phone_apps(source: impl BufRead) -> io::Result<Vec<String>> {
    let mut reader = Reader::from_reader(source);
    reader.config_mut().trim_text(true);
    let mut buf = Vec::new();
    let mut path: Vec<String> = Vec::new();
    let mut component = Component::default();
    let mut text = String::new();
    let mut length = (String::new(), String::new());
    let mut custom_key = String::new();
    let mut out = Vec::new();
    loop {
        let event = reader.read_event_into(&mut buf).map_err(io::Error::other)?;
        match event {
            Event::Start(e) => {
                let name = e.name().as_ref().to_owned();
                if path.len() == 1 && name == "component" {
                    let kind = attribute(&e, "type");
                    component = Component {
                        app: matches!(
                            kind.as_str(),
                            "desktop-application" | "desktop" | "console-application"
                        ),
                        ..Component::default()
                    };
                }
                if name == "display_length" {
                    length = (attribute(&e, "compare"), attribute(&e, "side"));
                }
                if name == "value" {
                    custom_key = attribute(&e, "key");
                }
                text.clear();
                path.push(name);
            }
            Event::Text(t) => text.push_str(&t),
            Event::End(_) => {
                let name = path.pop().unwrap_or_default();
                let parent = path.last().map(String::as_str).unwrap_or_default();
                let in_component = path.len() >= 2 && path[1] == "component";
                if !in_component && name == "component" && path.len() == 1 {
                    if component.phone_ready() && !component.id.is_empty() {
                        out.push(std::mem::take(&mut component.id));
                    }
                } else if in_component && path.len() == 2 && name == "id" {
                    text.trim()
                        .trim_end_matches(".desktop")
                        .clone_into(&mut component.id);
                } else if in_component && path.len() == 3 {
                    let relation = matches!(parent, "requires" | "recommends" | "supports");
                    if relation && name == "display_length" {
                        match admits_phone(&length.0, &length.1, &text) {
                            Some(true) => component.fits = true,
                            Some(false) if parent == "requires" => {
                                component.required_too_big = true;
                            }
                            _ => {}
                        }
                    } else if relation && name == "control" && text.trim() == "touch" {
                        component.touch = true;
                    } else if parent == "custom"
                        && name == "value"
                        && custom_key == "Purism::form_factor"
                        && text.to_ascii_lowercase().contains("mobile")
                    {
                        component.mobile = true;
                    }
                }
                text.clear();
            }
            Event::Eof => break,
            _ => {}
        }
        buf.clear();
    }
    out.sort();
    out.dedup();
    Ok(out)
}

/// Flathub's catalogue in the user installation, as `flatpak update
/// --appstream` leaves it.
fn catalogue() -> Option<PathBuf> {
    let data = std::env::var_os("XDG_DATA_HOME").map_or_else(
        || Path::new(&std::env::var_os("HOME").unwrap_or_default()).join(".local/share"),
        PathBuf::from,
    );
    let dir = data
        .join("flatpak/appstream/flathub")
        .join(std::env::consts::ARCH)
        .join("active");
    ["appstream.xml.gz", "appstream.xml"]
        .iter()
        .map(|name| dir.join(name))
        .find(|path| path.is_file())
}

fn modified(path: &Path) -> u64 {
    fs::metadata(path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map_or(0, |d| d.as_secs())
}

/// The phone apps of a catalogue file, gzip or plain.
pub fn read_catalogue(path: &Path) -> io::Result<Vec<String>> {
    let file = BufReader::new(File::open(path)?);
    if path.extension().is_some_and(|e| e == "gz") {
        phone_apps(BufReader::new(flate2::bufread::GzDecoder::new(file)))
    } else {
        phone_apps(file)
    }
}

/// Hands the Store `phone-apps.json`, reading the catalogue again only when
/// flatpak has replaced it. Without a catalogue the Store goes by Flathub's
/// own flag on each listed app.
pub fn publish(state: &StateDir) -> io::Result<()> {
    let Some(source) = catalogue() else {
        return Ok(());
    };
    let cache = crate::fdroid::cache_dir().join("phone-apps.json");
    let stamp = modified(&source);
    let cached: Option<Value> = fs::read(&cache)
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .filter(|v: &Value| v["source"].as_u64() == Some(stamp));
    let record = if let Some(record) = cached {
        record
    } else {
        let record = json!({ "source": stamp, "apps": read_catalogue(&source)?, "ts": now() });
        crate::fdroid::write_atomic(&cache, record.to_string().as_bytes())?;
        record
    };
    state.write_json("phone-apps.json", &record)
}

/// Fetches Flathub's catalogue when there is none or it is a week old,
/// unless the network is metered or the battery low.
pub fn refresh_catalogue(flatpak: &str) {
    let stale =
        catalogue().is_none_or(|path| now().saturating_sub(modified(&path)) > 7 * 24 * 3600);
    if stale && !crate::fdroid::should_wait() {
        let _status = std::process::Command::new("timeout")
            .args([
                "180",
                flatpak,
                "--user",
                "update",
                "--appstream",
                "--noninteractive",
                "flathub",
            ])
            .status();
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    const FIXTURE: &str = include_str!("../tests/appstream-phone.xml");

    #[test]
    fn real_flathub_entries() {
        let apps = phone_apps(FIXTURE.as_bytes()).unwrap();
        assert_eq!(
            apps,
            [
                // requires 360 px, recommends touch, and Purism's mobile form factor
                "app.drey.Dialect",
                // requires 360 px, supports touch
                "app.drey.EarTag",
                // requires 300 px (the longest side's 360 says nothing), recommends touch
                "de.schmidhuberj.DieBahn",
                // requires touch and 360 px, and the form factor
                "dev.tchx84.Portfolio",
                // supports 360 px and touch, as GNOME Software reads supports
                "im.dino.Dino",
            ]
        );
        // Left out: Freelens requires 768 px; Legcord requires 420 px although
        // it would take up to 1200; Karlender requires more than 360 px;
        // Black Box fits but has no touch; GIMP says nothing.
    }

    #[test]
    fn display_lengths() {
        assert_eq!(admits_phone("", "", "360"), Some(true));
        assert_eq!(admits_phone("ge", "shortest", "300"), Some(true));
        assert_eq!(admits_phone("ge", "", "768"), Some(false));
        assert_eq!(admits_phone("gt", "", "360"), Some(false));
        assert_eq!(admits_phone("le", "", "1200"), Some(true));
        assert_eq!(admits_phone("le", "", "500"), Some(false));
        assert_eq!(admits_phone("ge", "longest", "360"), None);
        assert_eq!(admits_phone("ge", "", "small"), Some(true));
        assert_eq!(admits_phone("ge", "", "medium"), Some(false));
        assert_eq!(admits_phone("ge", "", "wide"), None);
    }

    #[test]
    fn form_factor_alone_and_a_veto() {
        let xml = r#"<components>
          <component type="desktop-application"><id>org.example.Mobile.desktop</id>
            <custom><value key="Purism::form_factor">workstation;mobile</value></custom></component>
          <component type="desktop-application"><id>org.example.Big</id>
            <requires><display_length>1024</display_length></requires>
            <recommends><display_length compare="le">2000</display_length><control>touch</control></recommends>
            <custom><value key="Purism::form_factor">mobile</value></custom></component>
          <component type="runtime"><id>org.example.Runtime</id>
            <custom><value key="Purism::form_factor">mobile</value></custom></component>
          <component type="desktop-application"><id>org.example.Nested</id>
            <provides><id>org.example.Other</id></provides>
            <recommends><display_length>360</display_length><control>touch</control></recommends></component>
        </components>"#;
        assert_eq!(
            phone_apps(xml.as_bytes()).unwrap(),
            ["org.example.Mobile", "org.example.Nested"]
        );
    }

    /// `MARATHON_APPSTREAM=<Flathub appstream.xml.gz> cargo test -- --ignored`
    #[test]
    #[ignore = "needs Flathub's catalogue"]
    #[allow(clippy::print_stderr, reason = "a measurement")]
    fn whole_catalogue() {
        let path = PathBuf::from(std::env::var_os("MARATHON_APPSTREAM").unwrap());
        let start = std::time::Instant::now();
        let apps = read_catalogue(&path).unwrap();
        eprintln!("{} phone apps in {:?}", apps.len(), start.elapsed());
        assert!(apps.len() > 100);
    }

    #[test]
    fn gzip_catalogue() {
        use std::io::Write;
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("appstream.xml.gz");
        let mut gz = flate2::write::GzEncoder::new(
            File::create(&path).unwrap(),
            flate2::Compression::fast(),
        );
        gz.write_all(FIXTURE.as_bytes()).unwrap();
        gz.finish().unwrap();
        assert_eq!(read_catalogue(&path).unwrap().len(), 5);
    }
}
