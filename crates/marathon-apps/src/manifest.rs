//! App manifest lint (`docs/APP_MANIFEST_SCHEMA.md`): the v1 JSON Schema, then
//! the rules a schema cannot express.

use std::collections::BTreeSet;
use std::fmt;
use std::fs;
use std::path::Path;
use std::sync::OnceLock;

use regex::Regex;
use serde_json::Value;
use walkdir::WalkDir;

use crate::permissions::permissions;

pub const SCHEMA: &str = include_str!("../../../schemas/marathon-app-manifest-v1.schema.json");
const MARATHON_DBUS_PREFIX: &str = "org.marathonos";

fn validator() -> &'static jsonschema::Validator {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    VALIDATOR.get_or_init(|| {
        #[allow(
            clippy::expect_used,
            reason = "compiled-in schema, compiled by a unit test"
        )]
        let schema: Value = serde_json::from_str(SCHEMA).expect("the manifest schema parses");
        #[allow(
            clippy::expect_used,
            reason = "compiled-in schema, compiled by a unit test"
        )]
        jsonschema::validator_for(&schema).expect("the manifest schema compiles")
    })
}

/// One rule broken. Errors fail the lint; warnings do not.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Finding {
    pub error: bool,
    pub rule: &'static str,
    /// JSON pointer into the manifest, or a file of the app.
    pub path: String,
    pub message: String,
}

impl fmt::Display for Finding {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let level = if self.error { "error" } else { "warning" };
        let path = if self.path.is_empty() {
            "/"
        } else {
            &self.path
        };
        write!(f, "{level}[{}] {path}: {}", self.rule, self.message)
    }
}

#[derive(Default)]
struct Lint {
    findings: Vec<Finding>,
}

impl Lint {
    fn error(&mut self, rule: &'static str, path: &str, message: impl Into<String>) {
        self.add(true, rule, path, message);
    }

    fn add(&mut self, error: bool, rule: &'static str, path: &str, message: impl Into<String>) {
        self.findings.push(Finding {
            error,
            rule,
            path: path.to_owned(),
            message: message.into(),
        });
    }

    fn manifest(&mut self, manifest: &Value, system_app: bool) {
        for e in validator().iter_errors(manifest) {
            self.error("schema", e.instance_path().as_str(), e.to_string());
        }
        let id = manifest
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or_default();
        if !system_app && !id.is_empty() {
            if !id.contains('.') {
                self.error(
                    "id",
                    "/id",
                    format!("single-word ids are reserved for Marathon's own apps; use a reverse-DNS id such as com.example.{id}"),
                );
            } else if id == MARATHON_DBUS_PREFIX
                || id.starts_with(&format!("{MARATHON_DBUS_PREFIX}."))
            {
                self.error(
                    "id",
                    "/id",
                    format!("{MARATHON_DBUS_PREFIX} is reserved for Marathon"),
                );
            }
        }
        if !system_app && manifest.get("protected") == Some(&Value::Bool(true)) {
            self.error(
                "protected",
                "/protected",
                "only Marathon's own apps are protected",
            );
        }
        self.permissions(manifest, system_app);
    }

    fn permissions(&mut self, manifest: &Value, system_app: bool) {
        let requested: Vec<&str> = manifest
            .get("permissions")
            .and_then(Value::as_array)
            .map(|list| list.iter().filter_map(Value::as_str).collect())
            .unwrap_or_default();
        let reasons = manifest.get("permissionReasons").and_then(Value::as_object);
        for (i, name) in requested.iter().enumerate() {
            let Some(permission) = permissions().get(*name) else {
                continue;
            };
            let path = format!("/permissions/{i}");
            if permission.restricted && !system_app {
                self.error(
                    "permission",
                    &path,
                    format!("\"{name}\" is restricted to Marathon's own apps"),
                );
            }
            if permission.sensitive && !reasons.is_some_and(|r| r.contains_key(*name)) {
                self.error(
                    "permission-reason",
                    &path,
                    format!(
                        "\"{name}\" is sensitive: say why the app needs it in permissionReasons"
                    ),
                );
            }
        }
        for name in reasons.into_iter().flat_map(|r| r.keys()) {
            if !requested.contains(&name.as_str()) {
                self.error(
                    "permission-reason",
                    &format!("/permissionReasons/{name}"),
                    format!("a reason for \"{name}\", which the app does not request"),
                );
            }
        }
    }

    fn files(&mut self, dir: &Path, manifest: &Value) {
        for key in ["entryPoint", "icon"] {
            let Some(file) = manifest.get(key).and_then(Value::as_str) else {
                continue;
            };
            if !dir.join(file).is_file() {
                self.error(
                    "files",
                    &format!("/{key}"),
                    format!("{file} is not in the app"),
                );
            }
        }
    }

    fn cmake(&mut self, dir: &Path, id: &str) -> Option<String> {
        let text = fs::read_to_string(dir.join("CMakeLists.txt")).ok()?;
        let app_name = capture(r"set\(\s*APP_NAME\s+([^\s)]+)", &text);
        let resolve = |arg: String| {
            if arg == "${APP_NAME}" {
                app_name.clone().unwrap_or(arg)
            } else {
                arg
            }
        };
        for (call, what) in [
            ("add_marathon_app", "install directory"),
            ("install_keel_actions", "D-Bus name"),
        ] {
            let Some(name) = capture(&format!(r"{call}\(\s*([^\s)]+)"), &text).map(resolve) else {
                continue;
            };
            if name != id {
                self.error(
                    "id-cmake",
                    "CMakeLists.txt",
                    format!("{call}({name}) gives the {what} {name}, not the app id {id}"),
                );
            }
        }
        capture(r"install_keel_actions\(\s*[^\s)]+\s+([^\s)]+)", &text)
    }

    fn keel_actions(&mut self, dir: &Path, id: &str, declared: Option<String>) {
        let file = declared.unwrap_or_else(|| "keel-actions.json".to_owned());
        let Ok(text) = fs::read_to_string(dir.join(&file)) else {
            return;
        };
        let expected = format!("{MARATHON_DBUS_PREFIX}.{id}");
        let app_id = serde_json::from_str::<Value>(&text)
            .ok()
            .and_then(|v| v.get("appId").and_then(Value::as_str).map(str::to_owned))
            .unwrap_or_default();
        if app_id != expected {
            self.error(
                "id-keel-actions",
                &file,
                format!("appId is \"{app_id}\"; the app's D-Bus name is {expected}"),
            );
        }
    }

    fn tested_on(&mut self, dir: &Path, manifest: &Value) {
        let tests = dir.join("tests");
        if !tests.is_dir() {
            return;
        }
        let (Ok(width), Ok(key)) = (
            Regex::new(r"\bwidth:\s*(\d+)\b"),
            Regex::new(r"\bkey(Click|Press|Release|Sequence)\("),
        ) else {
            return;
        };
        let mut widths = BTreeSet::new();
        let mut keys = false;
        for entry in WalkDir::new(&tests).into_iter().filter_map(Result::ok) {
            if entry.path().extension().is_some_and(|e| e == "qml") {
                let text = fs::read_to_string(entry.path()).unwrap_or_default();
                widths.extend(
                    width
                        .captures_iter(&text)
                        .filter_map(|c| c[1].parse::<u64>().ok()),
                );
                keys |= key.is_match(&text);
            }
        }
        let declared = |field: &str| {
            manifest
                .pointer(&format!("/testedOn/{field}"))
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default()
        };
        for (i, w) in declared("widths").iter().enumerate() {
            if let Some(w) = w.as_u64().filter(|w| !widths.contains(w)) {
                self.error(
                    "tested-on",
                    &format!("/testedOn/widths/{i}"),
                    format!("no test under tests/ lays the app out {w} pixels wide"),
                );
            }
        }
        for (i, mode) in declared("inputModes").iter().enumerate() {
            if mode == "keyboard" && !keys {
                self.error(
                    "tested-on",
                    &format!("/testedOn/inputModes/{i}"),
                    "no test under tests/ sends key events",
                );
            }
        }
    }
}

fn capture(pattern: &str, text: &str) -> Option<String> {
    Regex::new(pattern)
        .ok()?
        .captures(text)
        .map(|c| c[1].to_owned())
}

/// Which manifest namespace and permissions an app may use.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppClass {
    System,
    ThirdParty,
}

impl AppClass {
    const fn is_system(self) -> bool {
        matches!(self, Self::System)
    }
}

/// The manifest-only rules: the schema, the id namespace, `protected` and
/// the permissions. System apps may use Marathon's single-word IDs,
/// protection flag and restricted permissions.
pub fn lint_manifest(manifest: &Value, class: AppClass) -> Vec<Finding> {
    let mut lint = Lint::default();
    lint.manifest(manifest, class.is_system());
    lint.findings
}

fn read_manifest(dir: &Path, lint: &mut Lint) -> Option<Value> {
    let text = match fs::read_to_string(dir.join("manifest.json")) {
        Ok(text) => text,
        Err(e) => {
            lint.error("manifest", "manifest.json", e.to_string());
            return None;
        }
    };
    match serde_json::from_str(&text) {
        Ok(value) => Some(value),
        Err(e) => {
            lint.error("manifest", "manifest.json", e.to_string());
            None
        }
    }
}

fn lint_tree(dir: &Path, system_app: bool, lint: &mut Lint) -> Option<String> {
    let manifest = read_manifest(dir, lint)?;
    lint.manifest(&manifest, system_app);
    lint.files(dir, &manifest);
    lint.tested_on(dir, &manifest);
    let id = manifest.get("id").and_then(Value::as_str)?.to_owned();
    let keel = lint.cmake(dir, &id);
    lint.keel_actions(dir, &id, keel);
    Some(id)
}

/// Lints an app source or install directory.
pub fn lint_dir(dir: &Path, class: AppClass) -> Vec<Finding> {
    let mut lint = Lint::default();
    let id = lint_tree(dir, class.is_system(), &mut lint);
    // A third-party source tree may be named anything; the installer
    // names the installed directory after the id.
    if let Some(id) = id.filter(|_| class.is_system()) {
        let name = fs::canonicalize(dir)
            .ok()
            .and_then(|d| d.file_name().map(|n| n.to_string_lossy().into_owned()))
            .unwrap_or_default();
        if name != id {
            lint.error(
                "id-directory",
                "",
                format!("the directory is {name}, the app id {id}"),
            );
        }
    }
    lint.findings
}

/// Lints a `.marathon` package.
pub fn lint_package(archive: &Path, class: AppClass) -> Vec<Finding> {
    let mut lint = Lint::default();
    let extracted = match tempfile::tempdir()
        .map_err(|e| e.to_string())
        .and_then(|dir| crate::archive::extract(archive, dir.path()).map(|()| dir))
    {
        Ok(dir) => dir,
        Err(e) => {
            lint.error("package", &archive.display().to_string(), e);
            return lint.findings;
        }
    };
    if let Some(id) = lint_tree(extracted.path(), class.is_system(), &mut lint) {
        let stem = archive
            .file_stem()
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or_default();
        if stem != id && !stem.starts_with(&format!("{id}-")) {
            lint.add(
                false,
                "id-package",
                &archive.display().to_string(),
                format!("name the package {id}.marathon or {id}-<version>.marathon"),
            );
        }
    }
    lint.findings
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;
    use serde_json::json;

    const SYSTEM: AppClass = AppClass::System;
    const THIRD_PARTY: AppClass = AppClass::ThirdParty;

    fn manifest() -> Value {
        json!({
            "manifestVersion": 1,
            "id": "com.example.notes",
            "name": "Notes",
            "version": "1.2.0",
            "entryPoint": "NotesApp.qml",
            "icon": "assets/icon.svg",
            "author": "Example",
            "permissions": ["network", "location"],
            "permissionReasons": { "location": "Tags each note with where you wrote it" },
            "testedOn": { "widths": [540], "inputModes": ["touch"] },
            "dataLifecycle": { "appData": "remove", "cache": "remove" }
        })
    }

    fn rules(findings: &[Finding]) -> Vec<(&'static str, &str)> {
        findings.iter().map(|f| (f.rule, f.path.as_str())).collect()
    }

    fn with(mut value: Value, pointer: &str, field: Value) -> Value {
        let (parent, key) = pointer.rsplit_once('/').unwrap();
        if let Some(Value::Object(map)) = value.pointer_mut(parent) {
            map.insert(key.to_owned(), field);
        }
        value
    }

    fn without(mut value: Value, key: &str) -> Value {
        if let Value::Object(map) = &mut value {
            map.remove(key);
        }
        value
    }

    #[test]
    fn vocabulary_matches_the_schema() {
        let schema: Value = serde_json::from_str(SCHEMA).unwrap();
        let listed: BTreeSet<&str> = schema
            .pointer("/$defs/permission/enum")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .collect();
        let vocabulary: BTreeSet<&str> = permissions().keys().map(String::as_str).collect();
        assert_eq!(listed, vocabulary);
        assert!(permissions().values().all(|p| !p.description.is_empty()));
        assert!(permissions().values().all(|p| p.sensitive || !p.restricted));
    }

    #[test]
    fn a_complete_manifest_passes() {
        assert_eq!(lint_manifest(&manifest(), THIRD_PARTY), Vec::new());
    }

    #[test]
    fn the_schema_rejects() {
        let cases = [
            (without(manifest(), "testedOn"), ""),
            (with(manifest(), "/category", json!("utilities")), ""),
            (
                with(manifest(), "/permissions", json!(["phone"])),
                "/permissions/0",
            ),
            (with(manifest(), "/id", json!("com.example/../x")), "/id"),
            (with(manifest(), "/version", json!("1.0")), "/version"),
            (
                with(manifest(), "/entryPoint", json!("../Evil.qml")),
                "/entryPoint",
            ),
            (
                with(manifest(), "/icon", json!("/usr/share/icon.svg")),
                "/icon",
            ),
            (
                with(manifest(), "/testedOn/inputModes", json!(["keyboard"])),
                "/testedOn/inputModes",
            ),
            (
                with(manifest(), "/dataLifecycle/cache", json!("keep")),
                "/dataLifecycle/cache",
            ),
            (
                with(manifest(), "/chromiumFlags", json!("--enable-webgl")),
                "",
            ),
        ];
        for (value, path) in cases {
            let findings = lint_manifest(&value, THIRD_PARTY);
            assert!(
                findings
                    .iter()
                    .any(|f| f.rule == "schema" && f.path == path),
                "{value}: {findings:?}"
            );
        }
    }

    #[test]
    fn data_lifecycle_follows_the_permissions() {
        let secrets = with(manifest(), "/permissions", json!(["secret-service"]));
        let secrets = with(
            secrets,
            "/permissionReasons",
            json!({ "secret-service": "Keeps your sign-in token" }),
        );
        assert_eq!(
            rules(&lint_manifest(&secrets, THIRD_PARTY)),
            [("schema", "/dataLifecycle")]
        );
        let declared = with(secrets, "/dataLifecycle/secrets", json!("remove"));
        assert_eq!(lint_manifest(&declared, THIRD_PARTY), Vec::new());

        let undeclared = with(manifest(), "/dataLifecycle/userFiles", json!("preserve"));
        assert_eq!(
            rules(&lint_manifest(&undeclared, THIRD_PARTY)),
            [("schema", "/dataLifecycle")]
        );
        let storage = with(undeclared, "/permissions", json!(["storage"]));
        let storage = with(
            storage,
            "/permissionReasons",
            json!({ "storage": "Saves notes as text files in Documents" }),
        );
        assert_eq!(lint_manifest(&storage, THIRD_PARTY), Vec::new());
        assert_eq!(
            lint_manifest(&without(storage, "dataLifecycle"), THIRD_PARTY).len(),
            1
        );
    }

    #[test]
    fn third_party_namespace() {
        let bare = with(manifest(), "/id", json!("notes"));
        assert_eq!(rules(&lint_manifest(&bare, THIRD_PARTY)), [("id", "/id")]);
        assert_eq!(lint_manifest(&bare, SYSTEM), Vec::new());
        let ours = with(manifest(), "/id", json!("org.marathonos.notes"));
        assert_eq!(rules(&lint_manifest(&ours, THIRD_PARTY)), [("id", "/id")]);
        let protected = with(manifest(), "/protected", json!(true));
        assert_eq!(
            rules(&lint_manifest(&protected, THIRD_PARTY)),
            [("protected", "/protected")]
        );
        assert_eq!(lint_manifest(&protected, SYSTEM), Vec::new());
    }

    #[test]
    fn permission_rules() {
        let no_reason = without(manifest(), "permissionReasons");
        assert_eq!(
            rules(&lint_manifest(&no_reason, THIRD_PARTY)),
            [("permission-reason", "/permissions/1")]
        );

        let stray = with(
            manifest(),
            "/permissionReasons/camera",
            json!("Scans QR codes on notes"),
        );
        assert_eq!(
            rules(&lint_manifest(&stray, THIRD_PARTY)),
            [("permission-reason", "/permissionReasons/camera")]
        );

        let system = with(manifest(), "/permissions", json!(["system"]));
        let system = with(
            system,
            "/permissionReasons",
            json!({ "system": "Changes device settings" }),
        );
        assert_eq!(
            rules(&lint_manifest(&system, THIRD_PARTY)),
            [("permission", "/permissions/0")]
        );
        assert_eq!(lint_manifest(&system, SYSTEM), Vec::new());
    }

    fn write(dir: &Path, file: &str, text: &str) {
        let path = dir.join(file);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).unwrap();
        }
        fs::write(path, text).unwrap();
    }

    fn app(manifest: &Value) -> tempfile::TempDir {
        let root = tempfile::tempdir().unwrap();
        let dir = root.path().join("com.example.notes");
        write(&dir, "manifest.json", &manifest.to_string());
        write(&dir, "NotesApp.qml", "Item {}");
        write(&dir, "assets/icon.svg", "<svg/>");
        write(
            &dir,
            "tests/tst_notes.qml",
            "Item { width: 540; height: 1140 }",
        );
        root
    }

    #[test]
    fn a_complete_app_directory_passes() {
        let root = app(&manifest());
        assert_eq!(
            lint_dir(&root.path().join("com.example.notes"), THIRD_PARTY),
            Vec::new()
        );
    }

    #[test]
    fn app_directory_rules() {
        let tested = json!({ "widths": [540, 720], "inputModes": ["touch", "keyboard"] });
        let root = app(&with(manifest(), "/testedOn", tested));
        let dir = root.path().join("com.example.notes");
        fs::remove_file(dir.join("assets/icon.svg")).unwrap();
        write(&dir, "CMakeLists.txt", "set(APP_NAME notes)\nadd_marathon_app(${APP_NAME} URI x)\ninstall_keel_actions(${APP_NAME} actions.json)\n");
        write(&dir, "actions.json", r#"{"appId": "org.marathonos.notes"}"#);
        assert_eq!(
            rules(&lint_dir(&dir, THIRD_PARTY)),
            [
                ("files", "/icon"),
                ("tested-on", "/testedOn/widths/1"),
                ("tested-on", "/testedOn/inputModes/1"),
                ("id-cmake", "CMakeLists.txt"),
                ("id-cmake", "CMakeLists.txt"),
                ("id-keel-actions", "actions.json"),
            ]
        );
    }

    #[test]
    fn directory_name() {
        let root = app(&manifest());
        let moved = root.path().join("notes");
        fs::rename(root.path().join("com.example.notes"), &moved).unwrap();
        assert_eq!(lint_dir(&moved, THIRD_PARTY), Vec::new());
        let ours = with(manifest(), "/id", json!("notes"));
        fs::write(moved.join("manifest.json"), ours.to_string()).unwrap();
        assert_eq!(lint_dir(&moved, SYSTEM), Vec::new());
        fs::rename(&moved, root.path().join("memo")).unwrap();
        assert_eq!(
            rules(&lint_dir(&root.path().join("memo"), SYSTEM)),
            [("id-directory", "")]
        );
    }

    #[test]
    fn packages() {
        let root = app(&manifest());
        let package = root.path().join("notes.marathon");
        assert_eq!(
            crate::archive::create(&root.path().join("com.example.notes"), &package),
            Ok(())
        );
        assert_eq!(
            rules(&lint_package(&package, THIRD_PARTY)),
            [("id-package", package.to_str().unwrap())]
        );
        let named = root.path().join("com.example.notes-1.2.0.marathon");
        fs::rename(&package, &named).unwrap();
        assert_eq!(lint_package(&named, THIRD_PARTY), Vec::new());
        assert_eq!(
            rules(&lint_package(
                &root.path().join("missing.marathon"),
                THIRD_PARTY
            ))[0]
                .0,
            "package"
        );
    }
}
