// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! The Keel Actions build step (ADR-0018, `docs/specs/pilot.md` 9.2).
//!
//! From an app's QML tree, its Rust sources and its `.desktop` file it
//! writes:
//!
//! | File | What |
//! | --- | --- |
//! | `actions.json` | the manifest: MCP tools, entities, context, prompts |
//! | `<app-id>.actions.xml` | D-Bus introspection of `org.shipwright.Keel.Actions` with the app's actions |
//! | `<app-id>.service` | session-bus activation (headless, `--keel-actions`) |
//! | `<app-id>.sailjail` | lines for the desktop file's `[X-Sailjail]` section |
//! | `keel_actions.c` | the adaptor for C/C++ apps: `keel_actions_manifest()` (Rust apps use `keel::manifest!()`) |
//! | `tst_keel_actions.qml`, `keel_actions_tests.rs` | test stubs (into the tests directory, only when missing) |
//!
//! Use it from `keel actions` (tools/keel-dev), from a `build.rs`
//! ([`Config::build_script`]) or from a CMake build (`keel_add_actions()` in
//! `keel/actions/cmake/KeelActions.cmake`).

pub mod desktop;
pub mod from_qml;
pub mod from_rust;
pub mod qml;
pub mod stubs;

use std::fmt;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

use keel_actions_schema::decl::App;
use keel_actions_schema::{is_action_name, is_app_id, is_word, review};
use serde_json::Value;

pub use desktop::Desktop;

/// The `org.shipwright.Keel.Actions` interface (no app annotations).
pub const INTERFACE_XML: &str = include_str!("../../dbus/org.shipwright.Keel.Actions.xml");

/// Errors and warnings, with where they come from.
#[derive(Debug, Default)]
pub struct Diagnostics {
    pub errors: Vec<(String, String)>,
    pub warnings: Vec<(String, String)>,
}

impl Diagnostics {
    pub fn error(&mut self, at: String, message: impl Into<String>) {
        self.errors.push((at, message.into()));
    }
    pub fn warning(&mut self, at: String, message: impl Into<String>) {
        self.warnings.push((at, message.into()));
    }
}

impl fmt::Display for Diagnostics {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (at, m) in &self.errors {
            writeln!(f, "{at}: error: {m}")?;
        }
        for (at, m) in &self.warnings {
            writeln!(f, "{at}: warning: {m}")?;
        }
        Ok(())
    }
}

/// What to read.
#[derive(Clone, Debug, Default)]
pub struct Config {
    /// QML directories or files (searched for `*.qml`).
    pub qml: Vec<PathBuf>,
    /// Rust source directories or files (searched for `*.rs`).
    pub rust: Vec<PathBuf>,
    /// The app's desktop file (app ID and executable).
    pub desktop: Option<PathBuf>,
    /// Overrides the desktop file's app ID.
    pub app_id: Option<String>,
    /// Overrides the desktop file's executable.
    pub executable: Option<String>,
}

/// A generated file, by name relative to the output directory.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Artefact {
    pub name: String,
    pub contents: String,
}

/// Everything generated.
#[derive(Debug)]
pub struct Output {
    pub app: App,
    pub manifest: Value,
    /// Into the output directory.
    pub artefacts: Vec<Artefact>,
    /// Into the tests directory, only when missing.
    pub stubs: Vec<Artefact>,
    pub diagnostics: Diagnostics,
}

impl Output {
    pub fn artefact(&self, name: &str) -> Option<&str> {
        self.artefacts
            .iter()
            .chain(&self.stubs)
            .find(|a| a.name == name)
            .map(|a| a.contents.as_str())
    }
}

#[derive(Debug)]
pub struct Failed(pub Diagnostics);

impl fmt::Display for Failed {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "keel actions: the declarations have errors:\n{}", self.0)
    }
}

impl std::error::Error for Failed {}

fn files(paths: &[PathBuf], extension: &str, out: &mut Vec<PathBuf>) {
    for path in paths {
        if path.is_dir() {
            let mut entries: Vec<PathBuf> = fs::read_dir(path)
                .into_iter()
                .flatten()
                .flatten()
                .map(|e| e.path())
                .collect();
            entries.sort();
            for entry in entries {
                let name = entry
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or_default();
                if name.starts_with('.') || name == "target" {
                    continue;
                }
                if entry.is_dir() {
                    files(&[entry], extension, out);
                } else if entry.extension().and_then(|e| e.to_str()) == Some(extension) {
                    out.push(entry);
                }
            }
        } else if path.is_file() {
            out.push(path.clone());
        }
    }
}

/// Keys sorted at every level, so output does not depend on map order.
fn canonical(value: &Value) -> Value {
    match value {
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            Value::Object(
                keys.into_iter()
                    .map(|k| (k.clone(), canonical(&map[k])))
                    .collect(),
            )
        }
        Value::Array(items) => Value::Array(items.iter().map(canonical).collect()),
        other => other.clone(),
    }
}

/// Pretty JSON with a final newline.
pub fn to_pretty(value: &Value) -> String {
    let mut s = serde_json::to_string_pretty(&canonical(value)).unwrap_or_default();
    s.push('\n');
    s
}

fn check(app: &App, diag: &mut Diagnostics) {
    if !is_app_id(&app.app_id) {
        diag.error(
            "app".into(),
            format!(
                "\"{}\" is not an app ID (OrganizationName.ApplicationName in [X-Sailjail])",
                app.app_id
            ),
        );
    }
    let mut names = std::collections::BTreeSet::new();
    for a in &app.actions {
        if !is_action_name(&a.name) {
            diag.error(
                a.source.clone(),
                format!(
                    "action name \"{}\" is not domain.verb (lower-case words)",
                    a.name
                ),
            );
        }
        if !names.insert(a.name.clone()) {
            diag.error(
                a.source.clone(),
                format!("action \"{}\" is declared twice", a.name),
            );
        }
        let mut params = std::collections::BTreeSet::new();
        for p in &a.params {
            if !params.insert(&p.name) {
                diag.error(
                    a.source.clone(),
                    format!("parameter \"{}\" is declared twice", p.name),
                );
            }
        }
        if a.read_only && a.destructive {
            diag.error(
                a.source.clone(),
                "an action cannot be both readOnly and destructive",
            );
        }
    }
    let mut types = std::collections::BTreeSet::new();
    for e in &app.entities {
        if !is_word(&e.type_name) {
            diag.error(
                e.source.clone(),
                format!("entity type \"{}\" is not a lower-case word", e.type_name),
            );
        }
        if !types.insert(e.type_name.clone()) {
            diag.error(
                e.source.clone(),
                format!("entity type \"{}\" is declared twice", e.type_name),
            );
        }
        if names.contains(&format!("{}.find", e.type_name)) {
            diag.error(
                e.source.clone(),
                format!(
                    "action {}.find clashes with the entity's find tool",
                    e.type_name
                ),
            );
        }
    }
    for s in &app.shortcuts {
        if !s.name.split('-').all(is_word) {
            diag.error(
                s.source.clone(),
                format!(
                    "shortcut name \"{}\" is not lower-case words joined by -",
                    s.name
                ),
            );
        }
        let arguments: Vec<&str> = s.arguments.iter().map(|p| p.name.as_str()).collect();
        for step in &s.steps {
            if !step.action.contains('/') && !names.contains(&step.action) {
                diag.error(
                    s.source.clone(),
                    format!("step action \"{}\" is not declared", step.action),
                );
            }
            let text = step.arguments.to_string();
            let mut rest = text.as_str();
            while let Some(start) = rest.find("{{") {
                let after = &rest[start + 2..];
                let Some(end) = after.find("}}") else { break };
                let name = &after[..end];
                if !arguments.contains(&name) {
                    diag.error(s.source.clone(), format!("step uses {{{{{name}}}}}, which is not one of the shortcut's arguments"));
                }
                rest = &after[end + 2..];
            }
        }
    }
}

impl Config {
    /// Reads the declarations and generates everything.
    #[allow(clippy::too_many_lines, reason = "read, check, emit: one pass")]
    pub fn generate(&self) -> Result<Output, Failed> {
        let mut diag = Diagnostics::default();
        let desktop = match &self.desktop {
            Some(path) => match fs::read_to_string(path) {
                Ok(text) => Some(Desktop::parse(
                    &path
                        .file_name()
                        .map(|n| n.to_string_lossy().into_owned())
                        .unwrap_or_default(),
                    &text,
                )),
                Err(e) => {
                    diag.error(path.display().to_string(), format!("cannot read: {e}"));
                    None
                }
            },
            None => None,
        };
        let app_id = self
            .app_id
            .clone()
            .or_else(|| desktop.as_ref().and_then(Desktop::app_id))
            .unwrap_or_default();
        let executable = self
            .executable
            .clone()
            .or_else(|| desktop.as_ref().and_then(Desktop::executable));

        let mut app = App {
            app_id,
            ..App::default()
        };
        let mut qml_files = Vec::new();
        files(&self.qml, "qml", &mut qml_files);
        for path in &qml_files {
            let shown = path.display().to_string();
            let text = match fs::read_to_string(path) {
                Ok(t) => t,
                Err(e) => {
                    diag.error(shown, format!("cannot read: {e}"));
                    continue;
                }
            };
            if !text.contains("Keel.Actions") {
                continue;
            }
            match qml::parse(&text) {
                Ok(doc) => {
                    let found = from_qml::read(&doc, &shown, &mut diag);
                    app.actions.extend(found.actions);
                    app.entities.extend(found.entities);
                    app.context |= found.contexts > 0;
                    app.shortcuts.extend(found.shortcuts);
                }
                Err(e) => diag.error(format!("{shown}:{}", e.line), e.message),
            }
        }
        let mut rust_files = Vec::new();
        files(&self.rust, "rs", &mut rust_files);
        let mut parsed = Vec::new();
        for path in &rust_files {
            let shown = path.display().to_string();
            let Ok(text) = fs::read_to_string(path) else {
                continue;
            };
            if !text.contains("keel::") {
                continue;
            }
            match syn::parse_file(&text) {
                Ok(file) => parsed.push((shown, file)),
                Err(e) => diag.error(shown, format!("cannot parse: {e}")),
            }
        }
        let found = from_rust::read(&parsed, &mut diag);
        app.actions.extend(found.actions);
        app.entities.extend(found.entities);

        check(&app, &mut diag);
        let manifest = app.manifest();
        for finding in review::review(&manifest, None) {
            diag.error(
                format!("actions.json{}", finding.path),
                format!("[{}] {}", finding.rule, finding.message),
            );
        }
        if executable.is_none() {
            diag.warning("desktop".into(), "no executable known (Exec in the desktop file, or --exec): the .service file is not written");
        }
        if !diag.errors.is_empty() {
            return Err(Failed(diag));
        }

        let mut artefacts = vec![Artefact {
            name: "actions.json".into(),
            contents: to_pretty(&manifest),
        }];
        artefacts.push(Artefact {
            name: format!("{}.actions.xml", app.app_id),
            contents: introspection(&app),
        });
        if let Some(exec) = &executable {
            let desktop_name = desktop.as_ref().map_or_else(
                || format!("{}.desktop", app.app_id),
                |d| d.file_name.clone(),
            );
            artefacts.push(Artefact {
                name: format!("{}.service", app.app_id),
                contents: service(&app.app_id, exec, &desktop_name),
            });
            artefacts.push(Artefact {
                name: format!("{}.sailjail", app.app_id),
                contents: sailjail(exec, &desktop_name),
            });
        }
        artefacts.push(Artefact {
            name: "keel_actions.c".into(),
            contents: c_adaptor(&manifest),
        });
        let stubs = stubs::stubs(&app, &manifest);
        Ok(Output {
            app,
            manifest,
            artefacts,
            stubs,
            diagnostics: diag,
        })
    }

    /// For `build.rs`: generates into `$OUT_DIR` and into
    /// `target/[<triple>/]<profile>/keel-actions/<app-id>/` (for the RPM),
    /// prints `cargo:` lines and fails the build on errors. The crate then
    /// calls `keel::manifest!()`.
    ///
    /// # Panics
    ///
    /// On declaration errors or when `$OUT_DIR` cannot be written: a build
    /// script reports failure by panicking.
    pub fn build_script(&self) -> Output {
        for path in self.qml.iter().chain(&self.rust).chain(&self.desktop) {
            println!("cargo:rerun-if-changed={}", path.display());
        }
        let out_dir = PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR is set by cargo"));
        match self.generate() {
            Ok(output) => {
                for (at, m) in &output.diagnostics.warnings {
                    println!("cargo:warning=keel actions: {at}: {m}");
                }
                if let Err(e) = write(&output.artefacts, &out_dir) {
                    panic!("keel actions: cannot write {}: {e}", out_dir.display());
                }
                // Also next to the binary, for packaging:
                // target/[<triple>/]<profile>/keel-actions/<app-id>/.
                if let Some(profile) = out_dir.ancestors().nth(3) {
                    let packaged = profile.join("keel-actions").join(&output.app.app_id);
                    if let Err(e) = write(&output.artefacts, &packaged) {
                        println!(
                            "cargo:warning=keel actions: cannot write {}: {e}",
                            packaged.display()
                        );
                    }
                }
                output
            }
            Err(failed) => panic!("{failed}"),
        }
    }
}

/// Writes artefacts into `dir`; returns the names that changed.
pub fn write(artefacts: &[Artefact], dir: &Path) -> std::io::Result<Vec<String>> {
    fs::create_dir_all(dir)?;
    let mut changed = Vec::new();
    for a in artefacts {
        let path = dir.join(&a.name);
        if fs::read_to_string(&path).ok().as_deref() != Some(a.contents.as_str()) {
            fs::write(&path, &a.contents)?;
            changed.push(a.name.clone());
        }
    }
    Ok(changed)
}

/// Writes stubs that do not exist yet; returns the names written.
pub fn write_stubs(stubs: &[Artefact], dir: &Path) -> std::io::Result<Vec<String>> {
    let missing: Vec<Artefact> = stubs
        .iter()
        .filter(|s| !dir.join(&s.name).exists())
        .map(|s| stubs::place(s, dir))
        .collect();
    write(&missing, dir)
}

/// The names whose files in `dir` differ from `artefacts`.
pub fn stale(artefacts: &[Artefact], dir: &Path) -> Vec<String> {
    artefacts
        .iter()
        .filter(|a| {
            fs::read_to_string(dir.join(&a.name)).ok().as_deref() != Some(a.contents.as_str())
        })
        .map(|a| a.name.clone())
        .collect()
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

fn introspection(app: &App) -> String {
    let mut annotations = format!(
        "    <annotation name=\"org.shipwright.Keel.AppId\" value=\"{}\"/>\n",
        xml_escape(&app.app_id)
    );
    let mut actions: Vec<_> = app.actions.iter().collect();
    actions.sort_by(|a, b| a.name.cmp(&b.name));
    for a in actions {
        let mut flags = Vec::new();
        for (on, name) in [
            (a.read_only, "readOnly"),
            (a.destructive, "destructive"),
            (a.idempotent, "idempotent"),
            (a.open_world, "openWorld"),
            (a.confirm, "confirm"),
            (a.sensitive, "sensitive"),
            (a.untrusted, "untrusted"),
            (a.native, "native"),
        ] {
            if on {
                flags.push(name);
            }
        }
        let _ = writeln!(
            annotations,
            "    <annotation name=\"org.shipwright.Keel.Action.{}\" value=\"{}\"/>",
            xml_escape(&a.name),
            flags.join(" ")
        );
    }
    let mut types: Vec<_> = app.entities.iter().map(|e| e.type_name.as_str()).collect();
    types.sort_unstable();
    for t in types {
        let _ = writeln!(
            annotations,
            "    <annotation name=\"org.shipwright.Keel.Entity.{t}\" value=\"\"/>"
        );
    }
    if app.context {
        annotations
            .push_str("    <annotation name=\"org.shipwright.Keel.Context\" value=\"true\"/>\n");
    }
    // The canonical interface, with the app's annotations first in it and
    // the generated-file notice in place of the licence comment.
    let body_start = INTERFACE_XML.find("<node>").unwrap_or(0);
    let header_end = INTERFACE_XML.find("<!--").unwrap_or(body_start);
    let interface = INTERFACE_XML[body_start..].replacen(
        "  <interface name=\"org.shipwright.Keel.Actions\">\n",
        &format!("  <interface name=\"org.shipwright.Keel.Actions\">\n{annotations}"),
        1,
    );
    format!(
        "{}<!-- Generated by `keel actions` for {} (ADR-0018); do not edit. -->\n{}",
        &INTERFACE_XML[..header_end],
        xml_escape(&app.app_id),
        interface.replacen("<node>", "<node name=\"/org/shipwright/Keel/Actions\">", 1)
    )
}

fn service(app_id: &str, exec: &str, desktop: &str) -> String {
    format!(
        "# Generated by `keel actions` (ADR-0018); do not edit.\n\
         # Session-bus activation of {app_id} for Keel Actions: the app starts\n\
         # without showing its window and quits when idle. Sailjail applies the\n\
         # permissions of {desktop}.\n\
         [D-BUS Service]\n\
         Name={app_id}\n\
         Exec=/usr/bin/sailjail -p {desktop} {exec} --keel-actions\n"
    )
}

fn sailjail(exec: &str, desktop: &str) -> String {
    format!(
        "# Generated by `keel actions` (ADR-0018): add these lines to the\n\
         # [X-Sailjail] section of {desktop}. `keel actions --check` verifies\n\
         # that they are there.\n\
         ExecDBus={exec} --keel-actions\n"
    )
}

fn c_adaptor(manifest: &Value) -> String {
    let json = serde_json::to_string(&canonical(manifest)).unwrap_or_default();
    let mut literal = String::new();
    for chunk in json.as_bytes().chunks(100) {
        literal.push_str("    \"");
        for &b in chunk {
            match b {
                b'"' => literal.push_str("\\\""),
                b'\\' => literal.push_str("\\\\"),
                0x20..=0x7e => literal.push(char::from(b)),
                _ => {
                    let _ = write!(literal, "\\{b:03o}");
                }
            }
        }
        literal.push_str("\"\n");
    }
    format!(
        "/* Generated by `keel actions` (ADR-0018); do not edit.\n \
         * The Keel Actions adaptor for a C or C++ app: the Keel.Actions runtime\n \
         * finds this function in the process and enforces the manifest's\n \
         * schemas. Rust apps use keel::manifest!() instead. */\n\
         __attribute__((visibility(\"default\"))) const char *keel_actions_manifest(void);\n\n\
         const char *keel_actions_manifest(void)\n{{\n    return\n{literal}    ;\n}}\n"
    )
}

/// The `ExecDBus` line the desktop file needs, if it lacks it.
pub fn missing_sailjail_line(desktop: &Desktop, exec: &str) -> Option<String> {
    let wanted = format!("{exec} --keel-actions");
    (desktop.get("X-Sailjail", "ExecDBus") != Some(wanted.as_str()))
        .then(|| format!("ExecDBus={wanted}"))
}
