//! marathon-dev: build, sign, check and install Marathon apps.

#![allow(clippy::print_stdout, clippy::print_stderr, reason = "a command-line tool")]

use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use marathon_apps::{archive, install, manifest, paths, signature};

#[derive(Parser)]
#[command(version, about = "Build and package Marathon apps")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Create a new app from the template.
    Init { name: String },
    /// Package (and sign) an app as a .marathon file.
    Package {
        app_dir: PathBuf,
        output: Option<PathBuf>,
        /// A minisign secret key to sign it with.
        #[arg(long)]
        key: Option<PathBuf>,
    },
    /// Sign a package with a minisign key (default ~/.minisign/minisign.key).
    Sign { package: PathBuf, key: Option<PathBuf> },
    /// Check a package's signature.
    Verify { package: PathBuf },
    /// Install an app locally.
    Install {
        path: PathBuf,
        /// Allow the new permissions an update asks for.
        #[arg(long)]
        approve_permissions: bool,
    },
    /// Check apps against the manifest contract.
    Lint {
        #[arg(long)]
        system_app: bool,
        #[arg(required = true)]
        paths: Vec<PathBuf>,
    },
}

fn ok(message: &str) {
    println!("\x1b[32m✓\x1b[0m {message}");
}

fn info(message: &str) {
    println!("\x1b[34mℹ\x1b[0m {message}");
}

fn fail(message: &str) -> ExitCode {
    eprintln!("\x1b[31m✗\x1b[0m {message}");
    ExitCode::FAILURE
}

fn package(app_dir: &Path, output: Option<PathBuf>, key: Option<&Path>) -> ExitCode {
    let output = output.unwrap_or_else(|| {
        let name = fs::canonicalize(app_dir).ok().and_then(|p| p.file_name().map(ToOwned::to_owned)).unwrap_or_default();
        PathBuf::from(format!("{}.marathon", name.to_string_lossy()))
    });
    info(&format!("Packaging {} as {}", app_dir.display(), output.display()));
    if let Err(e) = archive::package(app_dir, &output) {
        return fail(&format!("Failed to create package: {e}"));
    }
    ok(&format!("Package created: {} ({} KB)", output.display(), fs::metadata(&output).map_or(0, |m| m.len() / 1024)));
    // A signature left from an earlier build would not match the new archive.
    fs::remove_file(signature::signature_path(&output)).ok();
    match key {
        None => {
            info(&format!("Unsigned: sign it with marathon-dev sign {} before installing it", output.display()));
            ExitCode::SUCCESS
        }
        Some(key) => sign(&output, key),
    }
}

fn sign(package: &Path, key: &Path) -> ExitCode {
    match signature::sign(package, key) {
        Ok(()) => {
            ok(&format!("Signed: {}", signature::signature_path(package).display()));
            ExitCode::SUCCESS
        }
        Err(e) => {
            info("Create a key with: minisign -G");
            fail(&format!("Failed to sign package: {e}"))
        }
    }
}

fn verify(package: &Path) -> ExitCode {
    match install::verify(package) {
        Ok(key) if key.is_empty() => {
            info("Unsigned, accepted only because MARATHON_ALLOW_UNSIGNED=1");
            ExitCode::SUCCESS
        }
        Ok(key) => {
            ok(&format!("Signed by trusted key {key}"));
            ExitCode::SUCCESS
        }
        Err(e) => {
            let dirs: Vec<String> = paths::trusted_keys().iter().map(|d| d.display().to_string()).collect();
            info(&format!("Trusted keys live in: {}", dirs.join(", ")));
            fail(&e)
        }
    }
}

fn lint(paths: &[PathBuf], system_app: bool) -> ExitCode {
    let mut errors = 0;
    for path in paths {
        let findings = if path.is_dir() { manifest::lint_dir(path, system_app) } else { manifest::lint_package(path, system_app) };
        for f in findings {
            errors += usize::from(f.error);
            let at = if f.path.is_empty() { "/" } else { &f.path };
            println!("{}: {}[{}] {at}: {}", path.display(), if f.error { "error" } else { "warning" }, f.rule, f.message);
        }
    }
    if errors > 0 {
        return fail(&format!("{errors} error(s)"));
    }
    ok(&format!("{} app(s) pass", paths.len()));
    ExitCode::SUCCESS
}

fn install(path: &Path, approve: bool) -> ExitCode {
    let run = |approved: &[String]| {
        if path.is_dir() {
            install::install_directory(path, approved)
        } else {
            install::install_package(path, approved)
        }
    };
    if !path.is_dir() && path.extension().is_none_or(|e| e != "marathon") {
        return fail("Expected an app directory or a .marathon package");
    }
    info(&format!("Installing: {}", path.display()));
    let result = match run(&[]) {
        Err(install::Refusal::Held(plan)) => {
            eprintln!("This update asks for new permissions: {}", plan.added.join(", "));
            if !approve {
                info("Re-run with --approve-permissions to allow them");
                return ExitCode::FAILURE;
            }
            info("Allowed by --approve-permissions");
            run(&plan.added)
        }
        other => other,
    };
    match result {
        Ok(plan) => {
            info(if plan.permissions.is_empty() { "Permissions: none" } else { "Permissions:" });
            for p in &plan.permissions {
                info(&format!("  {} {}: {}", if p.sensitive { "!" } else { " " }, p.label, p.detail));
            }
            ok(&format!("Installed {} in {}", plan.id, paths::install_dir(&plan.id).display()));
            ExitCode::SUCCESS
        }
        Err(install::Refusal::Held(plan)) => fail(&format!("Still held for: {}", plan.added.join(", "))),
        Err(install::Refusal::Failed(e)) => fail(&e),
    }
}

fn init(name: &str) -> ExitCode {
    let slug = name.to_lowercase().replace(' ', "-");
    let id = format!("com.example.{slug}");
    let entry = format!("{}App.qml", slug.replace('-', ""));
    let dir = Path::new(&slug);
    let manifest = serde_json::json!({
        "manifestVersion": 1, "id": id, "name": name, "version": "1.0.0", "entryPoint": entry,
        "icon": "assets/icon.svg", "author": "Your Name", "permissions": [], "minShellVersion": "1.0.0",
        "protected": false, "testedOn": {"widths": [540], "inputModes": ["touch"]},
        "dataLifecycle": {"appData": "remove", "cache": "remove"},
    });
    let qml = format!(
        "import QtQuick\nimport Sailfish.Silica 1.0\nimport Marathon.Silica 1.0\n\nApplicationWindow {{\n    appId: \"{id}\"\n\n    initialPage: Component {{\n        Page {{\n            PageHeader {{\n                title: \"{name}\"\n            }}\n\n            ViewPlaceholder {{\n                enabled: true\n                text: \"Welcome to {name}!\"\n            }}\n        }}\n    }}\n}}\n"
    );
    let icon = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"512\" height=\"512\" viewBox=\"0 0 512 512\">\n  <rect width=\"512\" height=\"512\" rx=\"112\" fill=\"#0e3b36\"/>\n  <path d=\"M152 344 L256 168 L360 344 Z\" fill=\"none\" stroke=\"#5dffdc\" stroke-width=\"28\" stroke-linejoin=\"round\"/>\n</svg>\n";
    let written = fs::create_dir(dir)
        .and_then(|()| ["pages", "components", "assets"].iter().try_for_each(|d| fs::create_dir(dir.join(d))))
        .and_then(|()| fs::write(dir.join("manifest.json"), serde_json::to_string_pretty(&manifest).unwrap_or_default()))
        .and_then(|()| fs::write(dir.join(&entry), qml))
        .and_then(|()| fs::write(dir.join("qmldir"), format!("module {}\n", slug.replace('-', ""))))
        .and_then(|()| fs::write(dir.join("assets/icon.svg"), icon));
    if let Err(e) = written {
        return fail(&format!("Failed to create {slug}: {e}"));
    }
    ok(&format!("App created: {id}"));
    info(&format!("Next: cd {slug}, edit manifest.json and {entry}, check with marathon-dev lint ., package with marathon-dev package . --key <secret-key>"));
    ExitCode::SUCCESS
}

fn main() -> ExitCode {
    match Cli::parse().command {
        Command::Init { name } => init(&name),
        Command::Package { app_dir, output, key } => package(&app_dir, output, key.as_deref()),
        Command::Sign { package, key } => {
            let key = key.unwrap_or_else(|| dirs::home_dir().unwrap_or_default().join(".minisign/minisign.key"));
            sign(&package, &key)
        }
        Command::Verify { package } => verify(&package),
        Command::Install { path, approve_permissions } => install(&path, approve_permissions),
        Command::Lint { system_app, paths } => lint(&paths, system_app),
    }
}
