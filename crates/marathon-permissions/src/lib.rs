//! The app permission vocabulary, `schemas/marathon-permissions-v1.json`:
//! the one list of names the lint, the installer's disclosures and the
//! shell's permission prompt share. A package that declares a permission
//! with no entry here is refused, so nothing an app can reach goes
//! undisclosed.

use std::collections::BTreeMap;
use std::sync::OnceLock;

use serde::Deserialize;

pub const VOCABULARY: &str = include_str!("../../../schemas/marathon-permissions-v1.json");

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Permission {
    /// The permission's name on the install screen, the prompt and Settings.
    pub label: String,
    /// What it lets an app do.
    pub description: String,
    /// The manifest must say why it asks (`permissionReasons`).
    pub sensitive: bool,
    /// Only Marathon's own apps may ask, and only its protected apps hold it.
    pub restricted: bool,
}

#[derive(Deserialize)]
struct Vocabulary {
    permissions: BTreeMap<String, Permission>,
    aliases: BTreeMap<String, String>,
}

fn vocabulary() -> &'static Vocabulary {
    static PARSED: OnceLock<Vocabulary> = OnceLock::new();
    PARSED.get_or_init(|| {
        #[allow(
            clippy::expect_used,
            reason = "compiled-in data, parsed by a unit test"
        )]
        serde_json::from_str(VOCABULARY).expect("schemas/marathon-permissions-v1.json parses")
    })
}

/// Every permission, by name. Aliases are not listed.
pub fn permissions() -> &'static BTreeMap<String, Permission> {
    &vocabulary().permissions
}

/// The permission a name means: itself, or what an alias stands for.
pub fn canonical(name: &str) -> Option<&'static str> {
    let vocabulary = vocabulary();
    let name = vocabulary.aliases.get(name).map_or(name, String::as_str);
    vocabulary
        .permissions
        .get_key_value(name)
        .map(|(key, _)| key.as_str())
}

/// A permission by name or alias.
pub fn describe(name: &str) -> Option<&'static Permission> {
    canonical(name).and_then(|name| permissions().get(name))
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used, reason = "tests")]
mod tests {
    use super::*;
    use std::collections::BTreeSet;
    use std::fs;
    use std::path::Path;

    #[test]
    fn the_vocabulary_parses() {
        assert!(permissions().len() > 10);
        for (name, p) in permissions() {
            assert!(!p.label.is_empty() && !p.description.is_empty(), "{name}");
            assert!(p.sensitive || !p.restricted, "{name}");
        }
        for (alias, name) in &vocabulary().aliases {
            assert!(permissions().contains_key(name), "{alias} -> {name}");
            assert!(!permissions().contains_key(alias), "{alias}");
        }
    }

    #[test]
    fn known_permissions_are_described() {
        let camera = describe("camera").unwrap();
        assert_eq!(camera.label, "Camera");
        assert!(camera.sensitive);
        assert!(!describe("network").unwrap().sensitive);
        assert!(describe("system").unwrap().restricted);
    }

    #[test]
    fn aliases_mean_their_permission() {
        assert_eq!(canonical("phone"), Some("telephony"));
        assert_eq!(canonical("telephony"), Some("telephony"));
        assert_eq!(describe("phone").unwrap().label, "Phone");
    }

    #[test]
    fn unknown_permissions_have_no_words() {
        assert!(describe("root").is_none());
        assert!(describe("Camera").is_none());
        assert!(describe("").is_none());
        assert_eq!(canonical("root"), None);
    }

    // A shipped app must be installable as a package.
    #[test]
    fn every_permission_an_app_in_the_tree_declares_is_described() {
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

    // Every name a gate in the shell, the runner or the sandbox checks.
    #[test]
    fn every_permission_a_gate_accepts_is_in_the_vocabulary() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let name = r#"(?:QStringLiteral\()?"([a-z][a-z-]*)"\)?"#;
        let gates: Vec<regex::Regex> = [
            r#"requirePermission\("[A-Za-z.]+",\s*\{([^}]*)\}"#.to_owned(),
            r"hasAnyPermission\(m_permissions,[^{;]*\{([^}]*)\}".to_owned(),
            format!(r"hasPerm\({name}\)"),
            format!(r"permissions\.contains\({name}\)"),
            format!(r"hasPermission\([^,()]+,\s*{name}\)"),
            format!(r#""(?:Has|Request)Permission", m_appId, {name}"#),
            format!(r"allowed\({name},"),
            format!(r#"answers\("\w+",\s*{name}\)"#),
        ]
        .iter()
        .map(|p| regex::Regex::new(p).unwrap())
        .collect();
        let quoted = regex::Regex::new(r#""([a-z][a-z-]*)""#).unwrap();
        let mut seen = BTreeSet::new();
        let clients = fs::read_dir(root.join("crates/marathon-app-native/src")).unwrap();
        let files = [
            "shell/src/ipc/shellservices.h",
            "shell/src/ipc/shellservices.cpp",
            "shell/src/services/applaunchservice.cpp",
            "shell/main.cpp",
            "tools/marathon-app-runner/main.cpp",
        ]
        .map(|file| root.join(file))
        .into_iter()
        .chain(clients.map(|entry| entry.unwrap().path()));
        for file in files {
            let text = fs::read_to_string(file).unwrap();
            for gate in &gates {
                for capture in gate.captures_iter(&text) {
                    let names = &capture[1];
                    if names.contains('"') {
                        seen.extend(quoted.captures_iter(names).map(|c| c[1].to_owned()));
                    } else {
                        seen.insert(names.to_owned());
                    }
                }
            }
        }
        assert!(seen.len() > 8, "{seen:?}");
        for name in &seen {
            assert!(canonical(name).is_some(), "a gate accepts \"{name}\"");
        }
    }

    // docs/PERMISSION_GUIDE.md has a section for each permission, in its
    // words, and no other.
    #[test]
    fn the_permission_guide_follows_the_vocabulary() {
        let guide = fs::read_to_string(
            Path::new(env!("CARGO_MANIFEST_DIR")).join("../../docs/PERMISSION_GUIDE.md"),
        )
        .unwrap();
        let documented: BTreeSet<&str> = guide
            .lines()
            .filter_map(|line| line.strip_prefix("### `"))
            .filter_map(|rest| rest.strip_suffix('`'))
            .collect();
        let vocabulary: BTreeSet<&str> = permissions().keys().map(String::as_str).collect();
        assert_eq!(documented, vocabulary);
        for (name, p) in permissions() {
            let section = format!("### `{name}`\n\n**{}**: {}.\n", p.label, p.description);
            assert!(guide.contains(&section), "{section}");
        }
    }
}
