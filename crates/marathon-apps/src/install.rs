//! Installing and removing the user's apps: a signed `.marathon` package (or,
//! for development, a directory) becomes `<user_installs>/<id>/files` plus a
//! receipt of the permissions the user approved.

use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{json, Value};

use crate::{apps, archive, paths, permissions, signature};

/// What a permission means, for the install screen.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Disclosure {
    pub id: String,
    pub label: String,
    pub detail: String,
    pub sensitive: bool,
}

/// What installing would do.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Plan {
    pub id: String,
    pub name: String,
    pub version: String,
    /// The signing key's id, empty if unsigned.
    pub signer: String,
    pub update: bool,
    pub permissions: Vec<Disclosure>,
    /// Permissions the installed version doesn't have.
    pub added: Vec<String>,
}

#[derive(Debug)]
pub enum Refusal {
    /// An update asks for permissions not in `approved`: install again with
    /// them once the user agrees.
    Held(Box<Plan>),
    Failed(String),
}

impl From<String> for Refusal {
    fn from(message: String) -> Self {
        Self::Failed(message)
    }
}

/// Security events go to the auth log, as the system's own do.
fn audit(priority: libc::c_int, message: &str) {
    let Ok(text) = std::ffi::CString::new(message) else { return };
    // SAFETY: a constant format string and a NUL-terminated argument.
    unsafe { libc::syslog(libc::LOG_AUTH | priority, c"%s".as_ptr(), text.as_ptr()) };
}

/// `MARATHON_ALLOW_UNSIGNED=1`: the developer override for unsigned packages
/// and directory installs. Signatures that are present are still checked.
pub fn unsigned_allowed() -> bool {
    std::env::var("MARATHON_ALLOW_UNSIGNED").is_ok_and(|v| v == "1")
}

fn text<'a>(manifest: &'a Value, key: &str) -> &'a str {
    manifest.get(key).and_then(Value::as_str).unwrap_or_default()
}

fn permissions_of(manifest: &Value) -> Vec<String> {
    let mut list: Vec<String> = Vec::new();
    for p in manifest.get("permissions").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
        if !list.iter().any(|x| x == p) {
            list.push(p.to_owned());
        }
    }
    list
}

fn read_json(path: &Path) -> Option<Value> {
    serde_json::from_slice(&fs::read(path).ok()?).ok().filter(Value::is_object)
}

/// The manifest's id and entry point stay inside the app's own directory.
fn check_manifest(manifest: &Value) -> Result<String, Refusal> {
    let id = text(manifest, "id");
    if id.is_empty() || text(manifest, "name").is_empty() || text(manifest, "entryPoint").is_empty() {
        return Err("Invalid or missing manifest.json".to_owned().into());
    }
    if id.contains("..") || id.contains(['/', '\\']) || id.starts_with('.') {
        audit(libc::LOG_ALERT, &format!("[SECURITY] Path traversal blocked: appId={id}"));
        return Err("Invalid app ID".to_owned().into());
    }
    let entry = text(manifest, "entryPoint");
    if entry.contains("..") || entry.starts_with(['/', '\\']) {
        audit(libc::LOG_ALERT, &format!("[SECURITY] Path traversal blocked: app={id} entryPoint={entry}"));
        return Err("Invalid entry point".to_owned().into());
    }
    Ok(id.to_owned())
}

/// An update that asks for permissions the installed version doesn't have
/// is held until those are in `approved`.
fn plan(manifest: &Value, signer: &str, approved: &[String]) -> Result<Plan, Refusal> {
    let id = text(manifest, "id").to_owned();
    let wanted = permissions_of(manifest);
    let mut disclosures = Vec::new();
    let mut undisclosed = Vec::new();
    for p in &wanted {
        match permissions::describe(p) {
            Some(d) => disclosures.push(Disclosure { id: p.clone(), label: d.label.clone(), detail: d.description.clone(), sensitive: d.sensitive }),
            None => undisclosed.push(p.clone()),
        }
    }
    if !undisclosed.is_empty() {
        let list = undisclosed.join(", ");
        audit(libc::LOG_ALERT, &format!("[SECURITY] Undisclosed permissions refused: app={id} perms={list}"));
        return Err(format!("Permissions with no description: {list}").into());
    }
    let installed = read_json(&paths::receipt(&id));
    let added: Vec<String> = installed.as_ref().map_or_else(Vec::new, |r| {
        let had = permissions_of(r);
        wanted.iter().filter(|p| !had.contains(p)).cloned().collect()
    });
    let plan = Plan {
        name: text(manifest, "name").to_owned(),
        version: text(manifest, "version").to_owned(),
        signer: signer.to_owned(),
        update: installed.is_some(),
        permissions: disclosures,
        added,
        id,
    };
    if plan.added.iter().all(|p| approved.contains(p)) {
        Ok(plan)
    } else {
        audit(libc::LOG_NOTICE, &format!("[SECURITY] Update held for consent: app={} new perms={}", plan.id, plan.added.join(", ")));
        Err(Refusal::Held(Box::new(plan)))
    }
}

/// The receipt is what the user approved: the permissions the plan disclosed
/// and, for an update, consented to. The scanner trusts it, not the manifest.
fn write_receipt(manifest: &Value, signer: &str, migrated: bool) -> std::io::Result<()> {
    let id = text(manifest, "id");
    let mut receipt = json!({"id": id, "version": text(manifest, "version"), "signer": signer, "permissions": permissions_of(manifest)});
    if migrated {
        receipt["migrated"] = Value::Bool(true);
    }
    let path = paths::receipt(id);
    let mut file = tempfile::NamedTempFile::new_in(path.parent().unwrap_or_else(|| Path::new(".")))?;
    serde_json::to_writer_pretty(&mut file, &receipt)?;
    file.persist(path).map(drop).map_err(|e| e.error)
}

fn copy_tree(from: &Path, to: &Path) -> std::io::Result<()> {
    for entry in walkdir::WalkDir::new(from) {
        let entry = entry?;
        let target = to.join(entry.path().strip_prefix(from).unwrap_or_else(|_| entry.path()));
        if entry.file_type().is_dir() {
            fs::create_dir_all(&target)?;
        } else {
            fs::copy(entry.path(), &target)?;
        }
    }
    Ok(())
}

fn remove(path: &Path) -> std::io::Result<()> {
    match fs::remove_dir_all(path) {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => Err(e),
        _ => Ok(()),
    }
}

fn place(manifest: &Value, source: &Path, signer: &str, moved: bool) -> Result<(), Refusal> {
    let id = text(manifest, "id");
    if paths::system_app(id).join("manifest.json").exists() {
        return Err("A system app has this id".to_owned().into());
    }
    let dest = paths::install_dir(id);
    remove(&dest).map_err(|e| format!("Failed to remove existing installation: {e}"))?;
    fs::create_dir_all(&dest).map_err(|e| format!("Failed to create {}: {e}", dest.display()))?;
    let files = paths::files_dir(id);
    let placed = (moved && fs::rename(source, &files).is_ok()) || copy_tree(source, &files).is_ok();
    if !placed || write_receipt(manifest, signer, false).is_err() {
        remove(&dest).ok();
        return Err(if placed { "Failed to record the installation" } else { "Failed to copy app files" }.to_owned().into());
    }
    Ok(())
}

/// A copy of `package` (and its signature) checked and unpacked in a private
/// directory, so the archive can't be swapped between the two.
pub fn install_package(package: &Path, approved: &[String]) -> Result<Plan, Refusal> {
    let tmp = tempfile::tempdir().map_err(|e| format!("Failed to create a temporary directory: {e}"))?;
    let copy = tmp.path().join("package.marathon");
    fs::copy(package, &copy).map_err(|e| format!("Failed to read package: {e}"))?;
    let sig = signature::signature_path(package);
    if sig.exists() {
        fs::copy(&sig, signature::signature_path(&copy)).map_err(|e| format!("Failed to read package: {e}"))?;
    }
    let signer = verify(&copy)?;
    let extracted = tmp.path().join("extracted");
    archive::extract(&copy, &extracted).map_err(|e| {
        audit(libc::LOG_ALERT, &format!("[SECURITY] Package refused: package={} reason={e}", package.display()));
        format!("Failed to extract package: {e}")
    })?;
    let manifest = read_json(&extracted.join("manifest.json")).ok_or_else(|| "Invalid manifest.json".to_owned())?;
    check_manifest(&manifest)?;
    let plan = plan(&manifest, &signer, approved)?;
    place(&manifest, &extracted, &signer, true)?;
    Ok(plan)
}

/// Development only (`MARATHON_ALLOW_UNSIGNED=1`): a directory is not signed.
pub fn install_directory(dir: &Path, approved: &[String]) -> Result<Plan, Refusal> {
    if !unsigned_allowed() {
        audit(libc::LOG_ALERT, &format!("[SECURITY] Unsigned directory install refused: dir={}", dir.display()));
        return Err("A directory is not signed: install a signed package, or set MARATHON_ALLOW_UNSIGNED=1 for development".to_owned().into());
    }
    audit(libc::LOG_WARNING, &format!("[SECURITY] Unsigned directory install allowed by MARATHON_ALLOW_UNSIGNED: dir={}", dir.display()));
    let manifest = read_json(&dir.join("manifest.json")).ok_or_else(|| "Invalid or missing manifest.json".to_owned())?;
    check_manifest(&manifest)?;
    let plan = plan(&manifest, "", approved)?;
    place(&manifest, dir, "", false)?;
    Ok(plan)
}

/// The signing key's id, empty for an unsigned package the developer
/// override admits.
pub fn verify(package: &Path) -> Result<String, String> {
    use signature::Verdict;
    let dirs = paths::trusted_keys();
    let dirs: Vec<&Path> = dirs.iter().map(PathBuf::as_path).collect();
    let verdict = signature::TrustStore::load(&dirs)
        .map_or_else(|e| Verdict::Failed(format!("Failed to load trusted keys: {e}")), |store| signature::verify(package, &store));
    let refused = match verdict {
        Verdict::Valid(id) => {
            audit(libc::LOG_INFO, &format!("[SECURITY] Package signature verified: package={} key={id}", package.display()));
            return Ok(id);
        }
        Verdict::Unsigned if unsigned_allowed() => {
            audit(libc::LOG_WARNING, &format!("[SECURITY] Unsigned package allowed by MARATHON_ALLOW_UNSIGNED: package={}", package.display()));
            return Ok(String::new());
        }
        Verdict::Unsigned => "Package is not signed (no .minisig signature beside it)".to_owned(),
        Verdict::InvalidSignature(detail) => format!("Invalid signature: {detail}"),
        Verdict::UntrustedKey(id) => format!("Package is signed by key {id}, which is not trusted"),
        Verdict::RevokedKey(id) => format!("Package is signed by key {id}, which is revoked"),
        Verdict::Failed(detail) => format!("Signature verification failed: {detail}"),
    };
    audit(libc::LOG_ALERT, &format!("[SECURITY] Package rejected: package={} reason={refused}", package.display()));
    Err(format!("Package verification failed: {refused}"))
}

pub fn can_uninstall(app_id: &str) -> bool {
    apps::find(app_id).is_some_and(|a| !a.is_protected && a.path == paths::files_dir(app_id))
}

/// `dataLifecycle` (`docs/APP_MANIFEST_SCHEMA.md`): the cache always goes; app
/// data unless the app says "keep"; files in the user's media folders never.
/// Whether the app's data went too.
pub fn uninstall(app_id: &str) -> Result<bool, String> {
    if !can_uninstall(app_id) {
        return Err(if apps::find(app_id).is_some() { "Cannot uninstall a protected or system app" } else { "App not found" }.to_owned());
    }
    let keep = read_json(&paths::files_dir(app_id).join("manifest.json"))
        .is_some_and(|m| m.pointer("/dataLifecycle/appData").and_then(Value::as_str) == Some("keep"));
    remove(&paths::install_dir(app_id)).map_err(|e| format!("Failed to remove app files: {e}"))?;
    remove(&paths::cache_dir(app_id)).ok();
    if !keep {
        remove(&paths::data_dir(app_id)).ok();
        remove(&paths::config_dir(app_id)).ok();
    }
    Ok(!keep)
}

/// Installs used to live in the directory that is also the app's writable
/// data, so an app could rewrite its own manifest. Each is copied into the
/// read-only install root with a receipt for the permissions its manifest
/// declares now; the old directory stays as the app's data. The ids whose
/// manifest claimed "protected", which a user install never is: their
/// stored grants came from that claim.
pub fn migrate_legacy_installs() -> Vec<String> {
    let legacy = paths::legacy_installs();
    if fs::canonicalize(&legacy).ok() == fs::canonicalize(paths::system_apps()).ok() {
        return Vec::new();
    }
    let mut claimed = Vec::new();
    for entry in fs::read_dir(&legacy).into_iter().flatten().flatten() {
        let Ok(id) = entry.file_name().into_string() else { continue };
        let Some(manifest) = read_json(&entry.path().join("manifest.json")) else { continue };
        if text(&manifest, "id") != id || paths::install_dir(&id).exists() || paths::system_app(&id).join("manifest.json").exists() {
            continue;
        }
        let copied = fs::create_dir_all(paths::install_dir(&id)).is_ok()
            && copy_tree(&entry.path(), &paths::files_dir(&id)).is_ok()
            && write_receipt(&manifest, "", true).is_ok();
        if !copied {
            remove(&paths::install_dir(&id)).ok();
            continue;
        }
        audit(libc::LOG_NOTICE, &format!("[SECURITY] Install moved out of its data directory: app={id}"));
        if manifest.get("protected").and_then(Value::as_bool) == Some(true) {
            claimed.push(id);
        }
    }
    claimed
}
