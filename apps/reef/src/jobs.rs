// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Work that must not run on the GUI thread: downloads, `ssu`, `PackageKit`
//! transactions and command runs. Each job is a plain function run on a
//! worker thread; the bridge posts its result back to the Qt thread with
//! CXX-Qt's `CxxQtThread::queue`. Nothing here touches Qt.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command as Process;
use std::time::Duration;

use futures_lite::future::block_on;
use reef_backend::catalogue::Catalogue;
use reef_backend::claim_codes::{PendingClaim, PendingClaims};
use reef_backend::index::parse_index;
use reef_backend::licences::{LicenceStore, EMBEDDED_KEYS};
use reef_backend::metadata::MetadataCheck;
use reef_backend::packagekit::dbus::PackageKitClient;
use reef_backend::packagekit::{PackageInfo, PackageManager, Progress};
use reef_backend::plan::Plan;
use reef_backend::release::SailfishRelease;
use reef_backend::repo::{parse_ssu_lr, Command, PinState, RepoConfig, SsuRepo};
use reef_backend::store::Store;
use reef_licence::{KeySet, Policy};

use crate::rows::{display_claims, message};

/// Largest catalogue, token or revocation list accepted.
pub const MAX_DOWNLOAD: u64 = 8 * 1024 * 1024;

/// A downloaded body, plus the licence service's detached signature header
/// when present.
#[derive(Debug)]
pub struct Fetched {
    pub body: Vec<u8>,
    pub signature: Option<String>,
}

/// Why a download failed. `Status` keeps the HTTP code so callers can treat
/// 404 and 410 as answers rather than failures.
#[derive(Debug, PartialEq, Eq)]
pub enum FetchError {
    Status(u16),
    Other(String),
}

impl std::fmt::Display for FetchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FetchError::Status(code) => write!(f, "server answered HTTP {code}"),
            FetchError::Other(e) => f.write_str(e),
        }
    }
}

/// Fetches `https://`, `http://` or `file://` URLs. `file://` exists for
/// local repositories and tests; a phone uses https.
pub fn fetch(url: &str) -> Result<Fetched, FetchError> {
    if let Some(path) = url.strip_prefix("file://") {
        return fetch_file(Path::new(path));
    }
    if !(url.starts_with("https://") || url.starts_with("http://")) {
        return Err(FetchError::Other(format!("unsupported URL {url}")));
    }
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(Duration::from_secs(60)))
        .timeout_connect(Some(Duration::from_secs(15)))
        .user_agent(concat!("shipwright-reef/", env!("CARGO_PKG_VERSION")))
        .build()
        .into();
    let mut resp = agent.get(url).call().map_err(|e| match e {
        ureq::Error::StatusCode(code) => FetchError::Status(code),
        other => FetchError::Other(format!("{url}: {other}")),
    })?;
    let signature = resp
        .headers()
        .get("shipwright-signature")
        .and_then(|v| v.to_str().ok())
        .map(str::to_string);
    let body = resp
        .body_mut()
        .with_config()
        .limit(MAX_DOWNLOAD)
        .read_to_vec()
        .map_err(|e| FetchError::Other(format!("{url}: {e}")))?;
    Ok(Fetched { body, signature })
}

fn fetch_file(path: &Path) -> Result<Fetched, FetchError> {
    if !path.is_absolute() {
        return Err(FetchError::Other(format!(
            "file URL must be absolute: {}",
            path.display()
        )));
    }
    let file = std::fs::File::open(path).map_err(|e| match e.kind() {
        std::io::ErrorKind::NotFound => FetchError::Status(404),
        _ => FetchError::Other(format!("{}: {e}", path.display())),
    })?;
    let mut body = Vec::new();
    file.take(MAX_DOWNLOAD + 1)
        .read_to_end(&mut body)
        .map_err(|e| FetchError::Other(format!("{}: {e}", path.display())))?;
    if body.len() as u64 > MAX_DOWNLOAD {
        return Err(FetchError::Other(format!(
            "{} is too large",
            path.display()
        )));
    }
    Ok(Fetched {
        body,
        signature: None,
    })
}

/// Largest icon or screenshot accepted.
pub const MAX_ASSET: usize = 2 * 1024 * 1024;

/// Where a repository's icons and screenshots are cached: beside the
/// catalogue cache.
pub fn asset_dir(cache_path: &Path) -> PathBuf {
    cache_path.with_file_name("assets")
}

/// The cache file for a repository-relative asset path (one the catalogue
/// parser accepted): the path flattened, so `assets/shots/a.webp` is
/// `assets__shots__a.webp`. A changed image needs a new name: the publisher
/// puts a content hash in the file name, and the client never re-fetches a
/// name it has.
pub fn asset_file(dir: &Path, rel: &str) -> PathBuf {
    dir.join(rel.replace('/', "__"))
}

/// The cached file for `rel` as a path string, or empty when not cached.
pub fn asset_path(dir: &Path, rel: &str) -> String {
    let f = asset_file(dir, rel);
    if f.is_file() {
        f.to_string_lossy().into_owned()
    } else {
        String::new()
    }
}

/// PNG or JPEG by magic number: the only images the store shows (the
/// formats every Qt build decodes without an extra plugin).
pub fn is_image(bytes: &[u8]) -> bool {
    bytes.starts_with(b"\x89PNG\r\n\x1a\n") || bytes.starts_with(&[0xFF, 0xD8, 0xFF])
}

/// Every icon and screenshot the catalogue names, once each, in order,
/// and the banner of each featured app.
pub fn catalogue_assets(catalogue: &Catalogue) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for p in &catalogue.packages {
        let hero = p
            .hero
            .iter()
            .filter(|_| catalogue.featured.contains(&p.name));
        for a in p.icon.iter().chain(p.screenshots.iter()).chain(hero) {
            if !out.contains(a) {
                out.push(a.clone());
            }
        }
    }
    out
}

/// Fetches the assets not yet cached from `base` (the repository directory
/// the catalogue came from, which the paths are relative to), checks each
/// is an image of a sane size, writes it atomically, and removes cached
/// files the catalogue no longer names. Returns what failed: a missing
/// image is a blank in the store, never an error shown to the user.
pub fn fetch_assets(base: &str, dir: &Path, rels: &[String]) -> Vec<String> {
    let mut errors = Vec::new();
    if let Err(e) = std::fs::create_dir_all(dir) {
        return vec![format!("{}: {e}", dir.display())];
    }
    for rel in rels {
        let file = asset_file(dir, rel);
        if file.is_file() {
            continue;
        }
        match fetch(&format!("{base}{rel}")) {
            Ok(f) if f.body.len() > MAX_ASSET => {
                errors.push(format!("{rel}: larger than {MAX_ASSET} bytes"));
            }
            Ok(f) if !is_image(&f.body) => {
                errors.push(format!("{rel}: not a PNG or JPEG image"));
            }
            Ok(f) => {
                let tmp = file.with_extension(format!("{}.tmp", std::process::id()));
                if let Err(e) =
                    std::fs::write(&tmp, &f.body).and_then(|()| std::fs::rename(&tmp, &file))
                {
                    let _ = std::fs::remove_file(&tmp);
                    errors.push(format!("{rel}: {e}"));
                }
            }
            Err(e) => errors.push(format!("{rel}: {e}")),
        }
    }
    let keep: std::collections::HashSet<PathBuf> =
        rels.iter().map(|r| asset_file(dir, r)).collect();
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            if !keep.contains(&entry.path()) {
                let _ = std::fs::remove_file(entry.path());
            }
        }
    }
    errors
}

/// Up to this many apps' details are fetched with the index; above it,
/// only the featured apps', and the others' when needed.
pub const EAGER_DETAILS: usize = 200;

/// Where the downloaded index and its signature are kept for `gpgv`:
/// beside the catalogue cache.
pub fn index_dir(cache_path: &Path) -> PathBuf {
    cache_path.with_file_name("store")
}

/// Where apps' details files are cached, by SHA-256: beside the catalogue
/// cache.
pub fn details_dir(cache_path: &Path) -> PathBuf {
    cache_path.with_file_name("details")
}

/// The store index of the repository directory `base` (ending in `/`):
/// downloaded with its signature into `dir`, checked with `check` (the
/// signature, then the revision), parsed. `Ok(None)` when the repository
/// has no index (published before it existed).
pub fn fetch_index(
    base: &str,
    arch: &str,
    check: &MetadataCheck,
    dir: &Path,
) -> Result<Option<Catalogue>, String> {
    let body = match fetch(&format!("{base}store/index.json")) {
        Ok(f) => f.body,
        Err(FetchError::Status(404)) => return Ok(None),
        Err(e) => return Err(e.to_string()),
    };
    let sig = fetch(&format!("{base}store/index.json.asc"))
        .map_err(|e| format!("index.json.asc: {e}"))?
        .body;
    std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let index = dir.join("index.json");
    let asc = dir.join("index.json.asc");
    std::fs::write(&index, &body)
        .and_then(|()| std::fs::write(&asc, &sig))
        .map_err(|e| format!("{}: {e}", dir.display()))?;
    check
        .verify_index(&index, &asc)
        .map_err(|e| e.to_string())?;
    let (catalogue, revision) = parse_index(&body, arch).map_err(|e| e.to_string())?;
    check
        .accept_index_revision(revision)
        .map_err(|e| e.to_string())?;
    Ok(Some(catalogue))
}

/// One app's details file: from the cache in `dir` (by SHA-256), else
/// fetched from `base` + `store/` and cached. Not checked here:
/// `Catalogue::merge_details` checks it against the index.
pub fn details_bytes(
    base: &str,
    dir: &Path,
    d: &reef_backend::catalogue::DetailsRef,
) -> Result<Vec<u8>, String> {
    let file = dir.join(format!("{}.json", d.sha256));
    if let Ok(b) = std::fs::read(&file) {
        return Ok(b);
    }
    let body = fetch(&format!("{base}store/{}", d.path))
        .map_err(|e| e.to_string())?
        .body;
    let _ = std::fs::create_dir_all(dir);
    let tmp = file.with_extension(format!("{}.tmp", std::process::id()));
    if std::fs::write(&tmp, &body)
        .and_then(|()| std::fs::rename(&tmp, &file))
        .is_err()
    {
        let _ = std::fs::remove_file(&tmp);
    }
    Ok(body)
}

/// Merges apps' details into `catalogue`: those of `names` (all pending
/// ones when empty). A cached file (in `dir`, by SHA-256) is used as it
/// is; a missing one is fetched from `base` + `store/` when `fetch_missing`.
/// With `prune`, cached files no longer named by the catalogue are removed.
/// Returns what failed: that app keeps waiting for its details.
pub fn load_details(
    catalogue: &mut Catalogue,
    base: &str,
    dir: &Path,
    names: &[String],
    prune: bool,
) -> Vec<String> {
    let mut errors = Vec::new();
    let wanted: Vec<(String, reef_backend::catalogue::DetailsRef)> = catalogue
        .pending_details()
        .into_iter()
        .filter(|(n, _)| names.is_empty() || names.iter().any(|x| x == n))
        .map(|(n, d)| (n.to_owned(), d.clone()))
        .collect();
    let keep: std::collections::HashSet<String> = catalogue
        .pending_details()
        .into_iter()
        .map(|(_, d)| format!("{}.json", d.sha256))
        .collect();
    if let Err(e) = std::fs::create_dir_all(dir) {
        return vec![format!("{}: {e}", dir.display())];
    }
    for (name, d) in wanted {
        let bytes = match details_bytes(base, dir, &d) {
            Ok(b) => b,
            Err(e) => {
                errors.push(format!("{name}: {e}"));
                continue;
            }
        };
        if let Err(e) = catalogue.merge_details(&name, &bytes) {
            // A corrupt cached file is fetched again next time.
            let _ = std::fs::remove_file(dir.join(format!("{}.json", d.sha256)));
            errors.push(e.to_string());
        }
    }
    if prune {
        // Kept: the files of every app the index names (merged or not: the
        // next refresh parses the index afresh and merges them again).
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                if !keep.contains(&*entry.file_name().to_string_lossy()) {
                    let _ = std::fs::remove_file(entry.path());
                }
            }
        }
    }
    errors
}

/// `ssu lr`, parsed, in the C locale: `parse_ssu_lr` reads its English
/// section headers ("Enabled repositories").
pub fn ssu_repos() -> Result<Vec<SsuRepo>, String> {
    let out = reef_backend::c_locale(&mut Process::new("ssu"))
        .arg("lr")
        .output()
        .map_err(|e| format!("cannot run ssu: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "ssu lr failed: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    Ok(parse_ssu_lr(&String::from_utf8_lossy(&out.stdout)))
}

/// Runs repair or registration commands in order, stopping at the first
/// failure. Returns the error text for the UI.
pub fn run_commands(commands: &[Command]) -> Result<(), String> {
    for cmd in commands {
        log::info!("running {}", cmd.to_shell());
        let out = Process::new(cmd.program)
            .args(&cmd.args)
            .output()
            .map_err(|e| format!("{}: {e}", cmd.to_shell()))?;
        if !out.status.success() {
            let stderr = String::from_utf8_lossy(&out.stderr);
            return Err(format!(
                "{} failed ({}): {}",
                cmd.to_shell(),
                out.status,
                stderr.trim()
            ));
        }
    }
    Ok(())
}

/// What `PackageKit` says about Reef's packages.
#[derive(Debug, Clone, Default)]
pub struct PkState {
    pub installed: Vec<PackageInfo>,
    pub updates: Vec<PackageInfo>,
    /// The names among `installed` Reef may remove (it installed them):
    /// the others are shown as installed, without Remove.
    pub removable: Vec<String>,
}

async fn pk_state<P: PackageManager>(
    store: &Store<P>,
    catalogue: Option<&Catalogue>,
) -> reef_backend::packagekit::Result<PkState> {
    let installed = match catalogue {
        Some(c) => store.installed(c).await?,
        None => Vec::new(),
    };
    let updates = store.updates().await?;
    Ok(PkState {
        removable: store.removable(&installed),
        installed,
        updates,
    })
}

/// Inputs to a refresh, copied off the GUI thread's state.
#[derive(Debug, Clone)]
pub struct RefreshInput {
    pub config: RepoConfig,
    pub release: Option<SailfishRelease>,
    pub arch: String,
    /// The catalogue already shown, used for install state if the download
    /// fails.
    pub previous: Option<Catalogue>,
    pub licence_dir: Option<PathBuf>,
    pub licence_server: String,
    /// Where a downloaded catalogue is cached for the next start.
    pub cache_path: Option<PathBuf>,
    /// How the store index's signature is checked (`MetadataCheck::device`
    /// on a phone). `None`: the index is not used, only `catalogue.json`.
    pub index_check: Option<MetadataCheck>,
}

/// Result of a refresh. Each part is independent: a failed download still
/// updates the repository state, and so on.
#[derive(Debug, Default)]
pub struct RefreshOutput {
    pub catalogue: Option<Catalogue>,
    pub repos: Option<Vec<SsuRepo>>,
    pub pk: Option<PkState>,
    pub errors: Vec<String>,
}

/// With a cache: the catalogue's details (every app's when there are
/// few, so each page and the install plans then work offline; else the
/// featured apps', the rest when their page opens), then the catalogue
/// itself and its images, from this repository directory and nowhere
/// else (a failure is a blank image). On the worker, not the GUI thread.
fn cache_catalogue(input: &RefreshInput, base: &str, c: &mut Catalogue) {
    let Some(path) = &input.cache_path else {
        return;
    };
    let names: Vec<String> = if c.pending_details().len() <= EAGER_DETAILS {
        Vec::new()
    } else {
        c.featured.clone()
    };
    for e in load_details(c, base, &details_dir(path), &names, true) {
        log::warn!("details: {e}");
    }
    if let Err(e) = write_cache(path, c) {
        log::warn!("caching the catalogue in {}: {e}", path.display());
    }
    for e in fetch_assets(base, &asset_dir(path), &catalogue_assets(c)) {
        log::warn!("asset: {e}");
    }
}

/// `refresh()`: catalogue, `ssu lr`, installed and updates, licences.
pub fn refresh(input: &RefreshInput) -> RefreshOutput {
    let mut out = RefreshOutput::default();
    let Some(release) = &input.release else {
        out.errors.push(message("no_release", &[]));
        return out;
    };

    // The signed store index first; a repository published before it
    // existed, or an index that does not verify, falls back to
    // catalogue.json (unsigned, as every client read it until then).
    let base = input.config.resolved_url(release, &input.arch);
    let mut from_index = None;
    if let Some(check) = &input.index_check {
        let dir = input
            .cache_path
            .as_deref()
            .map_or_else(std::env::temp_dir, index_dir);
        match fetch_index(&base, &input.arch, check, &dir) {
            Ok(found) => from_index = found,
            Err(e) => log::warn!("store index: {e}; reading catalogue.json"),
        }
    }
    let fetched = match from_index {
        Some(c) => Ok(c),
        None => match fetch(&input.config.catalogue_url(release, &input.arch)) {
            Ok(f) => Catalogue::parse(&f.body, &input.arch).map_err(|e| e.to_string()),
            Err(FetchError::Status(404)) => Err(message(
                "catalogue_missing",
                &[&release.full(), &input.arch],
            )),
            Err(e) => Err(message("catalogue_download_failed", &[&e.to_string()])),
        },
    };
    match fetched {
        Ok(mut c) => {
            cache_catalogue(input, &base, &mut c);
            out.catalogue = Some(c);
        }
        Err(e) => out.errors.push(e),
    }

    let mut pinned = false;
    match ssu_repos() {
        Ok(mut repos) => {
            let mut state = input.config.pin_state(&repos, release, &input.arch);
            if reenable_due(
                &state,
                &std::fs::read_to_string(NO_REPOSITORY_MARKER).unwrap_or_default(),
                release,
                out.catalogue.is_some(),
                &reenabled_note().map_or_else(String::new, |p| {
                    std::fs::read_to_string(p).unwrap_or_default()
                }),
            ) {
                // The package turned the repository off because this
                // release had none; it has one now.
                log::info!(
                    "Reef's repository for {} is published: turning it on",
                    release.full()
                );
                match run_commands(&input.config.repair_commands(&state, release)) {
                    Ok(()) => {
                        if let Some(p) = reenabled_note() {
                            let _ = std::fs::write(p, release.full());
                        }
                        if let Ok(r) = ssu_repos() {
                            repos = r;
                            state = input.config.pin_state(&repos, release, &input.arch);
                        }
                    }
                    Err(e) => out.errors.push(e),
                }
            }
            pinned = state == PinState::Pinned;
            out.repos = Some(repos);
        }
        Err(e) => out.errors.push(e),
    }

    let catalogue = out.catalogue.as_ref().or(input.previous.as_ref());
    let alias = input.config.alias.clone();
    let pk = block_on(async {
        let pm = PackageKitClient::system().await?;
        if pinned {
            // New metadata, so updates published since the last refresh
            // show up. A failure here is not fatal: the cached metadata
            // still answers the queries below.
            if let Err(e) = pm.refresh_repo(&alias).await {
                log::warn!("refreshing {alias}: {e}");
            }
        }
        let store = Store::new(pm, alias).with_ledger(ledger());
        pk_state(&store, catalogue).await
    });
    match pk {
        Ok(state) => out.pk = Some(state),
        Err(e) => out.errors.push(e.to_string()),
    }

    // Licences are best effort during a catalogue refresh: an unreachable
    // licence service must not hide the catalogue. Explicit
    // refreshLicences() reports its errors.
    if let Some(dir) = &input.licence_dir {
        if let Err(e) = refresh_licences(dir, &input.licence_server, unix_now()) {
            log::warn!("licence refresh: {e}");
        }
    }
    out
}

/// Written by the package's `%triggerin` (reef/rpm/shipwright-reef.spec):
/// the release for which it turned Reef's repository off, because Reef
/// published nothing for it; empty or absent otherwise.
pub const NO_REPOSITORY_MARKER: &str = "/var/lib/shipwright-reef/no-repository";

/// Where Reef notes the release it turned the repository back on for, so
/// that it does so once: a person who turns it off again later is obeyed.
fn reenabled_note() -> Option<PathBuf> {
    cache_dir().map(|d| d.join("repository-reenabled"))
}

/// Whether a refresh turns Reef's repository back on: it is disabled, the
/// package turned it off for this very release (`marker`), the release's
/// catalogue now downloads, and Reef has not done this for the release
/// before (`done_for`).
pub fn reenable_due(
    state: &PinState,
    marker: &str,
    release: &SailfishRelease,
    catalogue_ok: bool,
    done_for: &str,
) -> bool {
    *state == PinState::Disabled
        && catalogue_ok
        && marker.trim() == release.full()
        && done_for.trim() != release.full()
}

/// Writes the catalogue cache atomically (a temporary file, then rename),
/// so a crash never leaves a truncated cache, and reports serialisation
/// errors instead of writing an empty file. The temporary name is unique to
/// the process and the call: the app and `--check-updates` may write at the
/// same time, and each must rename only its own complete file.
pub fn write_cache(path: &Path, catalogue: &Catalogue) -> std::io::Result<()> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let bytes = serde_json::to_vec(catalogue)?;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let tmp = path.with_extension(format!(
        "json.{}.{}.tmp",
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ));
    if let Err(e) = std::fs::write(&tmp, bytes) {
        let _ = std::fs::remove_file(&tmp);
        return Err(e);
    }
    std::fs::rename(tmp, path)
}

/// The record of what Reef installed (reef-backend's `InstallLedger`).
fn ledger() -> Option<reef_backend::store::InstallLedger> {
    reef_backend::store::InstallLedger::default_path().map(reef_backend::store::InstallLedger::new)
}

/// Makes the install ledger and its directory the owner's only, as Reef 27
/// and earlier left them world-writable on a phone (fix at every start).
pub fn secure_ledger() {
    if let Some(ledger) = ledger() {
        if let Err(e) = ledger.repair_permissions() {
            log::warn!("making the install record private: {e}");
        }
    }
}

/// Errors for `lastError`, one per line: the UI translates keyed messages
/// line by line, so a key must start its line.
pub fn join_errors(errors: &[String]) -> String {
    errors.join("\n")
}

/// The client's licence store at `dir`, trusting only the embedded keys.
pub fn licence_store(dir: &Path) -> LicenceStore {
    let keys = KeySet::from_embedded(EMBEDDED_KEYS).unwrap_or_else(|_| KeySet::new());
    LicenceStore::new(dir, keys, Policy::default())
}

#[derive(serde::Deserialize)]
struct TokenResponse {
    token: Option<String>,
}

/// `refreshLicences()`: first the pending claim codes of web purchases
/// (`GET /v1/claims/{code}`), then a fresh token for every licence that
/// needs one, then the revocation list. Returns how many tokens were stored
/// (bought or renewed). Does nothing (and asks nothing of the network) when
/// no licence is stored and no claim is pending.
pub fn refresh_licences(dir: &Path, server: &str, now: i64) -> Result<usize, String> {
    refresh_licences_in(
        &licence_store(dir),
        &PendingClaims::beside(dir),
        server,
        now,
    )
}

/// [`refresh_licences`] on the stores given (tests trust their own key).
fn refresh_licences_in(
    store: &LicenceStore,
    claims: &PendingClaims,
    server: &str,
    now: i64,
) -> Result<usize, String> {
    let stored = store.list(now);
    let pending = claims.list(now);
    if stored.is_empty() && pending.is_empty() {
        return Ok(0);
    }
    let base = server.trim().trim_end_matches('/');
    if base.is_empty() {
        return Err(message("no_licence_server", &[]));
    }
    let mut errors = Vec::new();
    let mut renewed = redeem_claims(store, claims, &pending, base, now, &mut errors);
    for s in stored.iter().filter(|s| s.needs_refresh(now)) {
        let Some(claims) = display_claims(s) else {
            continue;
        };
        let url = format!("{base}/v1/licences/{}/token", claims.lid);
        match fetch(&url) {
            Ok(f) => match serde_json::from_slice::<TokenResponse>(&f.body) {
                Ok(TokenResponse { token: Some(t) }) => match store.save(&t, now) {
                    Ok(_) => renewed += 1,
                    Err(e) => errors.push(format!("{}: {e}", s.app_id)),
                },
                Ok(TokenResponse { token: None }) => {}
                Err(e) => errors.push(format!("{}: bad response: {e}", s.app_id)),
            },
            // 410: the licence ended (cancelled or revoked); keep what we have.
            Err(FetchError::Status(410)) => {}
            Err(e) => errors.push(format!("{}: {e}", s.app_id)),
        }
    }
    // Nothing held and nothing bought: no list to check against.
    if !stored.is_empty() || renewed > 0 {
        match fetch(&format!("{base}/v1/revocations")) {
            Ok(Fetched {
                body,
                signature: Some(sig),
            }) => {
                if let Err(e) = store.accept_revocations(&body, &sig) {
                    errors.push(format!("revocation list: {e}"));
                }
            }
            Ok(_) => errors.push(message("revocations_unsigned", &[])),
            Err(e) => errors.push(format!("revocation list: {e}")),
        }
    }
    if errors.is_empty() {
        Ok(renewed)
    } else {
        Err(join_errors(&errors))
    }
}

/// Asks the licence service for the token of each pending claim code.
/// A token is stored (the store verifies it, whatever app the code was made
/// for) and the code forgotten; 404 (not paid yet) keeps the code for the
/// next try, 410 (refunded or revoked) and 400 (not a code the service
/// knows) forget it, and anything else keeps it and is reported. Returns how
/// many tokens were stored.
fn redeem_claims(
    store: &LicenceStore,
    claims: &PendingClaims,
    pending: &[PendingClaim],
    base: &str,
    now: i64,
    errors: &mut Vec<String>,
) -> usize {
    let mut redeemed = 0;
    for c in pending {
        let forget = match fetch(&format!("{base}/v1/claims/{}", c.code)) {
            Ok(f) => match serde_json::from_slice::<TokenResponse>(&f.body) {
                Ok(TokenResponse { token: Some(t) }) => match store.save(&t, now) {
                    Ok(_) => {
                        redeemed += 1;
                        true
                    }
                    Err(e) => {
                        errors.push(format!("{}: {e}", c.app_id));
                        false
                    }
                },
                Ok(TokenResponse { token: None }) => false,
                Err(e) => {
                    errors.push(format!("{}: bad response: {e}", c.app_id));
                    false
                }
            },
            Err(FetchError::Status(404)) => false,
            Err(FetchError::Status(400 | 410)) => true,
            Err(e) => {
                // The code fetches the licence: never shown or logged.
                let e = e.to_string().replace(&c.code, "…");
                errors.push(format!("{}: {e}", c.app_id));
                false
            }
        };
        if forget {
            if let Err(e) = claims.remove(&c.code) {
                errors.push(format!("{}: {e}", c.app_id));
            }
        }
    }
    redeemed
}

/// A package operation the person asked for in the UI (or through a Keel
/// Action), before they have seen what it does.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Ask {
    Install(String),
    Update(String),
    UpdateAll,
    Remove(String),
}

impl Ask {
    /// The RPM name for `busyPackage` and `operationFinished`, or empty.
    pub fn package(&self) -> &str {
        match self {
            Ask::Install(n) | Ask::Update(n) | Ask::Remove(n) => n,
            Ask::UpdateAll => "",
        }
    }
}

/// An operation the person agreed to: what they asked for, and the plan
/// they saw on the confirmation sheet and tapped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Op {
    pub ask: Ask,
    pub plan: Plan,
}

impl Op {
    pub fn package(&self) -> &str {
        self.ask.package()
    }
}

/// The store as the app uses it: the install ledger, and installs and
/// updates only on the repository's signed metadata
/// (`reef_backend::metadata`: zypp itself does not check it on Sailfish).
fn store(pm: PackageKitClient, alias: &str) -> Store<PackageKitClient> {
    Store::new(pm, alias)
        .with_ledger(ledger())
        .with_metadata_check(reef_backend::metadata::MetadataCheck::device(alias))
}

/// What `ask` would do: the plan the confirmation sheet shows. Nothing is
/// installed, updated or removed.
pub fn preview(ask: &Ask, alias: &str, catalogue: Option<&Catalogue>) -> Result<Plan, String> {
    block_on(async {
        let store = store(PackageKitClient::system().await?, alias);
        match ask {
            Ask::Install(name) => store.preview_install(name, catalogue).await.map(Some),
            Ask::Update(name) => store.preview_update(name, catalogue).await,
            Ask::UpdateAll => store
                .preview_update_all(catalogue)
                .await
                .map(|p| Some(p).filter(|p| !p.items.is_empty())),
            Ask::Remove(name) => store.preview_remove(name, catalogue).await.map(Some),
        }
    })
    .map_err(|e: reef_backend::packagekit::Error| e.to_string())?
    .ok_or_else(|| match ask {
        Ask::UpdateAll => message("all_up_to_date", &[]),
        other => message("up_to_date", &[other.package()]),
    })
}

/// Runs one operation the person agreed to, then re-reads install state so
/// the models follow. Returns the operation's outcome (message on success,
/// error text on failure) and the new state when it could be read.
pub fn run_op(
    op: &Op,
    alias: &str,
    catalogue: Option<&Catalogue>,
    progress: &mut dyn FnMut(Progress),
) -> (Result<String, String>, Option<PkState>) {
    block_on(async {
        let store = match PackageKitClient::system().await {
            Ok(pm) => store(pm, alias),
            Err(e) => return (Err(e.to_string()), None),
        };
        let plan = &op.plan;
        let result = match &op.ask {
            Ask::Install(name) => store
                .install(name, plan, progress)
                .await
                .map(|()| String::new()),
            Ask::Remove(name) => store
                .remove(name, plan, progress)
                .await
                .map(|()| String::new()),
            Ask::UpdateAll => store
                .update_all(plan, progress)
                .await
                .map(|n| message("updated", &[&n.to_string()])),
            // Store::update applies Reef's update only (A-06).
            Ask::Update(name) => store.update(name, plan, progress).await.map(|done| {
                if done {
                    String::new()
                } else {
                    message("up_to_date", &[name])
                }
            }),
        };
        let state = pk_state(&store, catalogue).await.ok();
        (result.map_err(|e| e.to_string()), state)
    })
}

/// Install state only (start-up check): no transaction, no network.
pub fn local_state(alias: &str, catalogue: Option<&Catalogue>) -> Result<PkState, String> {
    block_on(async {
        let pm = PackageKitClient::system().await?;
        pk_state(&Store::new(pm, alias).with_ledger(ledger()), catalogue).await
    })
    .map_err(|e| e.to_string())
}

/// How the store index's signature is checked on this phone
/// (`MetadataCheck::device`), with Reef's key read under [`sysroot`], so a
/// test root carries its own.
pub fn index_check(alias: &str) -> Option<MetadataCheck> {
    let mut check = MetadataCheck::device(alias)?;
    let key = check
        .key
        .strip_prefix("/")
        .unwrap_or(&check.key)
        .to_path_buf();
    check.key = sysroot().join(key);
    Some(check)
}

/// The root the release files are read from: `/`, or `$REEF_SYSROOT`
/// (tests and development only; never set on a phone).
pub fn sysroot() -> PathBuf {
    std::env::var_os("REEF_SYSROOT")
        .filter(|v| !v.is_empty())
        .map_or_else(|| PathBuf::from("/"), PathBuf::from)
}

/// The repository configuration: the installed `repo.conf` (the one the
/// installer registered with, so granularity and URL agree), under
/// `root`, else the built-in defaults. `$REEF_URL_TEMPLATE` overrides the
/// URL (tests and development only).
pub fn repo_config(root: &Path) -> RepoConfig {
    let conf = root.join(
        reef_backend::repo::CLIENT_REPO_CONF
            .strip_prefix('/')
            .unwrap_or(reef_backend::repo::CLIENT_REPO_CONF),
    );
    let mut config = match std::fs::read_to_string(&conf) {
        Ok(text) => RepoConfig::from_repo_conf(&text).unwrap_or_else(|e| {
            log::warn!(
                "{}: {e}; using the built-in repository settings",
                conf.display()
            );
            RepoConfig::default()
        }),
        Err(_) => RepoConfig::default(),
    };
    if let Some(template) = std::env::var("REEF_URL_TEMPLATE")
        .ok()
        .filter(|t| !t.is_empty())
    {
        config.url_template = template;
    }
    config
}

/// `$XDG_CACHE_HOME/shipwright-reef`, or under `~/.cache`.
pub fn cache_dir() -> Option<PathBuf> {
    let env = |v: &str| {
        std::env::var_os(v)
            .filter(|x| !x.is_empty())
            .map(PathBuf::from)
    };
    let base = env("XDG_CACHE_HOME").or_else(|| env("HOME").map(|h| h.join(".cache")))?;
    Some(base.join("shipwright-reef"))
}

/// The catalogue cache, read at start-up before (or without) a refresh.
pub fn cache_path() -> Option<PathBuf> {
    cache_dir().map(|d| d.join("catalogue.json"))
}

/// Seconds since the Unix epoch.
pub fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .and_then(|d| i64::try_from(d.as_secs()).ok())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "shipwright-reef-jobs-{name}-{}",
            std::process::id()
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn file_urls() {
        let dir = scratch("file");
        let f = dir.join("catalogue.json");
        std::fs::write(&f, b"{}").unwrap();
        let got = fetch(&format!("file://{}", f.display())).unwrap();
        assert_eq!(got.body, b"{}");
        assert_eq!(got.signature, None);
        assert_eq!(
            fetch(&format!("file://{}/missing.json", dir.display())).unwrap_err(),
            FetchError::Status(404)
        );
        assert!(matches!(
            fetch("file://relative/path"),
            Err(FetchError::Other(_))
        ));
        assert!(matches!(
            fetch("ftp://example.invalid/x"),
            Err(FetchError::Other(_))
        ));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn refresh_reports_missing_release_without_touching_anything() {
        let out = refresh(&RefreshInput {
            config: RepoConfig::default(),
            release: None,
            arch: "aarch64".into(),
            previous: None,
            licence_dir: None,
            licence_server: String::new(),
            cache_path: None,
            index_check: None,
        });
        assert!(out.catalogue.is_none() && out.repos.is_none() && out.pk.is_none());
        assert_eq!(out.errors.len(), 1);
    }

    #[test]
    fn no_licences_means_no_network() {
        let dir = scratch("licences");
        // An unroutable server: would fail if contacted.
        assert_eq!(
            refresh_licences(&dir.join("licences"), "http://127.0.0.1:1", 0),
            Ok(0)
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    /// A local licence service: answers each path in `routes` with its
    /// status, body and signature header (404 for any other path), and
    /// records the paths asked for. Serves until the test process ends.
    fn serve(
        routes: Vec<(String, u16, String, Option<String>)>,
    ) -> (String, std::sync::Arc<std::sync::Mutex<Vec<String>>>) {
        use std::io::{BufRead, BufReader, Write};
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let log = seen.clone();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                let mut reader = BufReader::new(stream.try_clone().unwrap());
                let mut line = String::new();
                reader.read_line(&mut line).unwrap();
                let path = line.split(' ').nth(1).unwrap_or("").to_string();
                loop {
                    let mut header = String::new();
                    if reader.read_line(&mut header).unwrap_or(0) == 0 || header == "\r\n" {
                        break;
                    }
                }
                log.lock().unwrap().push(path.clone());
                let (status, body, sig) = routes
                    .iter()
                    .find(|r| r.0 == path)
                    .map_or((404, String::new(), None), |r| {
                        (r.1, r.2.clone(), r.3.clone())
                    });
                let sig =
                    sig.map_or_else(String::new, |s| format!("Shipwright-Signature: {s}\r\n"));
                let _ = write!(
                    stream,
                    "HTTP/1.1 {status} X\r\nContent-Length: {}\r\n{sig}Connection: close\r\n\r\n{body}",
                    body.len()
                );
            }
        });
        (base, seen)
    }

    struct Service {
        signer: reef_licence::Signer,
        store: LicenceStore,
        claims: PendingClaims,
    }

    const T0: i64 = 1_790_000_000;

    fn service(dir: &Path) -> Service {
        let signer = reef_licence::Signer::from_seed("k1", [7; 32]).unwrap();
        let mut keys = KeySet::new();
        keys.insert_text(&signer.public_key_text()).unwrap();
        let licences = dir.join("licences");
        Service {
            store: LicenceStore::new(&licences, keys, Policy::default()),
            claims: PendingClaims::beside(&licences),
            signer,
        }
    }

    fn token(s: &Service, app: &str) -> String {
        s.signer
            .issue(&reef_licence::Claims {
                app: app.into(),
                exp: None,
                iat: T0,
                kid: "k1".into(),
                lid: format!("lic_{app}"),
                plan: reef_licence::Plan::OneOff,
            })
            .unwrap()
    }

    fn revocations(s: &Service) -> (String, u16, String, Option<String>) {
        let body = format!(r#"{{"generated_at":{T0},"revoked":[]}}"#);
        let sig = s.signer.sign_detached(body.as_bytes());
        ("/v1/revocations".into(), 200, body, Some(sig))
    }

    #[test]
    fn claims_are_redeemed_by_status() {
        let dir = scratch("claims");
        let s = service(&dir);
        let paid = s.claims.create("shoal-bridge", T0).unwrap();
        let other_app = s.claims.create("shoal-bridge", T0).unwrap();
        let unpaid = s.claims.create("shoal-bridge", T0).unwrap();
        let revoked = s.claims.create("shoal-bridge", T0).unwrap();
        let malformed = s.claims.create("shoal-bridge", T0).unwrap();
        let claim = |c: &str| format!("/v1/claims/{c}");
        let json = |t: String| format!(r#"{{"token":"{t}"}}"#);
        let (base, seen) = serve(vec![
            (claim(&paid), 200, json(token(&s, "shoal-bridge")), None),
            // A token for another app than the code was made for is
            // stored all the same: the store verifies it.
            (claim(&other_app), 200, json(token(&s, "shoal-keys")), None),
            (claim(&revoked), 410, String::new(), None),
            (claim(&malformed), 400, String::new(), None),
            revocations(&s),
        ]);
        assert_eq!(refresh_licences_in(&s.store, &s.claims, &base, T0), Ok(2));
        assert!(s.store.check("shoal-bridge", T0).unwrap().status.is_ok());
        assert!(s.store.check("shoal-keys", T0).unwrap().status.is_ok());
        let left: Vec<String> = s.claims.list(T0).into_iter().map(|c| c.code).collect();
        assert_eq!(
            left,
            std::slice::from_ref(&unpaid),
            "only the unpaid code is kept"
        );
        let seen = seen.lock().unwrap().clone();
        assert!(seen.contains(&claim(&unpaid)) && seen.contains(&"/v1/revocations".to_string()));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn claims_are_asked_for_with_no_licence_stored() {
        // The early return for "no licence" must not skip a pending code.
        let dir = scratch("claims-first");
        let s = service(&dir);
        let code = s.claims.create("shoal-bridge", T0).unwrap();
        let (base, seen) = serve(vec![]);
        assert_eq!(refresh_licences_in(&s.store, &s.claims, &base, T0), Ok(0));
        // Not paid yet: kept, and no revocation list for an empty store.
        assert_eq!(*seen.lock().unwrap(), [format!("/v1/claims/{code}")]);
        assert!(s.claims.any(T0));
        // And through the public entry point, beside the licence directory.
        assert_eq!(s.claims.dir(), dir.join("claims"));
        assert_eq!(refresh_licences(&dir.join("licences"), &base, T0), Ok(0));
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn failed_claims_are_kept_and_reported() {
        let dir = scratch("claims-fail");
        let s = service(&dir);
        let broken = s.claims.create("shoal-bridge", T0).unwrap();
        let garbled = s.claims.create("shoal-keys", T0).unwrap();
        let forged = s.claims.create("shoal-mail", T0).unwrap();
        let claim = |c: &str| format!("/v1/claims/{c}");
        let (base, _) = serve(vec![
            (claim(&broken), 500, String::new(), None),
            (claim(&garbled), 200, "not json".into(), None),
            (
                claim(&forged),
                200,
                r#"{"token":"v1.k1.forged"}"#.into(),
                None,
            ),
        ]);
        let err = refresh_licences_in(&s.store, &s.claims, &base, T0).unwrap_err();
        assert_eq!(err.lines().count(), 3, "{err}");
        assert!(
            err.contains("shoal-bridge: server answered HTTP 500"),
            "{err}"
        );
        assert!(err.contains("shoal-keys: bad response"), "{err}");
        assert_eq!(s.claims.list(T0).len(), 3, "all kept for the next try");
        // Unreachable service: kept too, and the secret code is not in
        // the error the UI shows.
        let err = refresh_licences_in(&s.store, &s.claims, "http://127.0.0.1:1", T0).unwrap_err();
        assert!(err.contains("/v1/claims/…"), "{err}");
        assert!(!err.contains(&broken), "{err}");
        assert_eq!(s.claims.list(T0).len(), 3);
        // No service configured.
        assert_eq!(
            refresh_licences_in(&s.store, &s.claims, " ", T0),
            Err(message("no_licence_server", &[]))
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn refresh_downloads_and_caches_atomically() {
        // A-03: the worker writes the cache, through a temporary file.
        let dir = scratch("cache");
        let repo = dir.join("repo/sailfishos/5.2.0.17/aarch64");
        std::fs::create_dir_all(&repo).unwrap();
        std::fs::write(
            repo.join("catalogue.json"),
            br#"{"schema":1,"release":"5.2.0.17","arch":"aarch64","packages":[]}"#,
        )
        .unwrap();
        let cache = dir.join("cache/shipwright-reef/catalogue.json");
        let config = RepoConfig {
            url_template: format!(
                "file://{}/repo/sailfishos/{{release}}/{{arch}}/",
                dir.display()
            ),
            ..RepoConfig::default()
        };
        let out = refresh(&RefreshInput {
            config,
            release: SailfishRelease::parse("5.2.0.17"),
            arch: "aarch64".into(),
            previous: None,
            licence_dir: None,
            licence_server: String::new(),
            cache_path: Some(cache.clone()),
            index_check: None,
        });
        assert!(out.catalogue.is_some(), "{:?}", out.errors);
        let cached = std::fs::read(&cache).unwrap();
        assert!(Catalogue::parse(&cached, "aarch64").is_ok());
        let leftovers: Vec<_> = std::fs::read_dir(cache.parent().unwrap())
            .unwrap()
            .filter_map(Result::ok)
            .filter(|e| e.file_name().to_string_lossy().ends_with(".tmp"))
            .collect();
        assert!(leftovers.is_empty());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn assets_are_fetched_checked_and_pruned() {
        let dir = scratch("assets");
        let repo = dir.join("repo/sailfishos/5.2.0.17/aarch64");
        std::fs::create_dir_all(repo.join("assets/shots")).unwrap();
        std::fs::write(
            repo.join("catalogue.json"),
            br#"{"schema":1,"release":"5.2.0.17","arch":"aarch64","packages":[
                {"name":"a","version":"1-1","title":"A","summary":"s","tested_on":["5.2.0.17"],
                 "licence":{"model":"free"},"icon":"assets/a.png",
                 "screenshots":["assets/shots/a1.jpg","assets/shots/fake.png","assets/shots/missing.png"]}]}"#,
        )
        .unwrap();
        std::fs::write(repo.join("assets/a.png"), b"\x89PNG\r\n\x1a\nrest").unwrap();
        std::fs::write(
            repo.join("assets/shots/a1.jpg"),
            [0xFF, 0xD8, 0xFF, 0xE0, 0, 0],
        )
        .unwrap();
        std::fs::write(repo.join("assets/shots/fake.png"), b"<html>not an image").unwrap();
        let cache = dir.join("cache/shipwright-reef/catalogue.json");
        let assets = asset_dir(&cache);
        std::fs::create_dir_all(&assets).unwrap();
        std::fs::write(assets.join("assets__stale.png"), b"old").unwrap();

        let config = RepoConfig {
            url_template: format!(
                "file://{}/repo/sailfishos/{{release}}/{{arch}}/",
                dir.display()
            ),
            ..RepoConfig::default()
        };
        let out = refresh(&RefreshInput {
            config,
            release: SailfishRelease::parse("5.2.0.17"),
            arch: "aarch64".into(),
            previous: None,
            licence_dir: None,
            licence_server: String::new(),
            cache_path: Some(cache.clone()),
            index_check: None,
        });
        let c = out.catalogue.expect("catalogue");
        assert_eq!(
            catalogue_assets(&c),
            [
                "assets/a.png",
                "assets/shots/a1.jpg",
                "assets/shots/fake.png",
                "assets/shots/missing.png"
            ]
        );
        assert_eq!(
            asset_path(&assets, "assets/a.png"),
            assets.join("assets__a.png").to_string_lossy()
        );
        assert!(assets.join("assets__shots__a1.jpg").is_file());
        assert!(
            !assets.join("assets__shots__fake.png").exists(),
            "not an image"
        );
        assert_eq!(asset_path(&assets, "assets/shots/missing.png"), "");
        assert!(!assets.join("assets__stale.png").exists(), "pruned");
        // Nothing is fetched twice: a changed source file is not re-read.
        std::fs::write(repo.join("assets/a.png"), b"\x89PNG\r\n\x1a\nchanged").unwrap();
        assert!(fetch_assets(
            &format!("file://{}/", repo.display()),
            &assets,
            &catalogue_assets(&c)
        )
        .iter()
        .all(|e| e.contains("fake.png") || e.contains("missing.png")));
        assert_eq!(
            std::fs::read(assets.join("assets__a.png")).unwrap(),
            b"\x89PNG\r\n\x1a\nrest"
        );
        assert!(is_image(&[0xFF, 0xD8, 0xFF, 0xE0]) && !is_image(b"GIF89a"));
        assert!(
            !is_image(b"RIFF\0\0\0\0WEBPVP8 "),
            "WebP needs a plugin the phone may lack"
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn concurrent_cache_writers_never_leave_a_torn_file() {
        // The app and --check-updates may write the cache at once.
        let dir = scratch("cache-race");
        let path = dir.join("catalogue.json");
        let small = Catalogue::parse(
            br#"{"schema":1,"release":"5.2.0.17","arch":"aarch64","packages":[]}"#,
            "aarch64",
        )
        .unwrap();
        let mut big = small.clone();
        big.generated_at = "x".repeat(200_000);
        std::thread::scope(|s| {
            for c in [&small, &big] {
                let path = &path;
                s.spawn(move || {
                    for _ in 0..50 {
                        write_cache(path, c).unwrap();
                    }
                });
            }
            for _ in 0..200 {
                if let Ok(bytes) = std::fs::read(&path) {
                    assert!(Catalogue::parse(&bytes, "aarch64").is_ok(), "torn cache");
                }
            }
        });
        assert!(Catalogue::parse(&std::fs::read(&path).unwrap(), "aarch64").is_ok());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn keyed_errors_start_their_own_line() {
        let joined = join_errors(&[
            "a: server answered HTTP 500".into(),
            message("revocations_unsigned", &[]),
        ]);
        for line in joined.lines().skip(1) {
            assert!(line.starts_with(crate::rows::MESSAGE_MARK), "{line:?}");
        }
        assert!(!joined.contains("; \u{1e}"));
    }

    #[test]
    fn the_repository_comes_back_once_the_release_has_one() {
        let r = SailfishRelease::parse("5.2.0.19").unwrap();
        let due = |state: &PinState, marker: &str, ok: bool, done: &str| {
            reenable_due(state, marker, &r, ok, done)
        };
        assert!(due(&PinState::Disabled, "5.2.0.19\n", true, ""));
        // Not published yet, or turned off by the person (no marker, or a
        // marker for another release), or already turned on once.
        assert!(!due(&PinState::Disabled, "5.2.0.19", false, ""));
        assert!(!due(&PinState::Disabled, "", true, ""));
        assert!(!due(&PinState::Disabled, "5.2.0.18", true, ""));
        assert!(!due(&PinState::Disabled, "5.2.0.19", true, "5.2.0.19"));
        assert!(!due(&PinState::Pinned, "5.2.0.19", true, ""));
    }

    #[test]
    fn op_names() {
        assert_eq!(Ask::Install("a".into()).package(), "a");
        assert_eq!(Ask::UpdateAll.package(), "");
        let plan = Plan {
            action: reef_backend::plan::Action::Remove,
            target: "b".into(),
            items: Vec::new(),
            download_size: None,
            alongside: Vec::new(),
        };
        let op = Op {
            ask: Ask::Remove("b".into()),
            plan,
        };
        assert_eq!(op.package(), "b");
    }

    /// The signed store index is read first, its details merged and cached;
    /// an index that does not verify, or goes backwards, falls back to
    /// catalogue.json.
    #[test]
    #[allow(
        clippy::too_many_lines,
        reason = "one scenario: a signed index, then forged, rolled back, newer"
    )]
    fn store_index_signed_details_and_fallback() {
        use sha2::{Digest, Sha256};
        let gpg = ["gpg2", "gpg"].into_iter().find(|g| {
            std::process::Command::new(g)
                .arg("--version")
                .output()
                .is_ok()
        });
        let gpgv = ["gpgv2", "gpgv"].into_iter().find(|g| {
            std::process::Command::new(g)
                .arg("--version")
                .output()
                .is_ok()
        });
        let (Some(gpg), Some(gpgv)) = (gpg, gpgv) else {
            eprintln!("no gpg; skipped");
            return;
        };
        let dir = scratch("index");
        let home = dir.join("gnupg");
        std::fs::create_dir_all(&home).unwrap();
        let g = |args: &[&str]| {
            let out = std::process::Command::new(gpg)
                .arg("--batch")
                .arg("--homedir")
                .arg(&home)
                .args(args)
                .output()
                .unwrap();
            assert!(
                out.status.success(),
                "{}",
                String::from_utf8_lossy(&out.stderr)
            );
            out.stdout
        };
        g(&[
            "--passphrase",
            "",
            "--quick-gen-key",
            "Reef Test <t@example.com>",
            "rsa2048",
            "sign",
            "never",
        ]);
        let key = dir.join("key.asc");
        std::fs::write(&key, g(&["--armor", "--export", "t@example.com"])).unwrap();

        let repo = dir.join("repo/sailfishos/5.2.0.22/aarch64");
        std::fs::create_dir_all(repo.join("store/apps")).unwrap();
        std::fs::write(
            repo.join("catalogue.json"),
            br#"{"schema":1,"release":"5.2.0.22","arch":"aarch64","packages":[
                {"name":"fx","version":"1-1","title":"From v1","summary":"s",
                 "tested_on":["5.2.0.22"],"licence":{"model":"free"}}]}"#,
        )
        .unwrap();
        let details = br#"{"name":"fx","version":"1-1","title":"From index","summary":"s","description":"Long","tested_on":["5.2.0.22"],"licence":{"model":"free"}}"#;
        std::fs::write(repo.join("store/apps/fx.abc.json"), details).unwrap();
        let sha = Sha256::digest(details)
            .iter()
            .fold(String::new(), |mut s, b| {
                use std::fmt::Write as _;
                let _ = write!(s, "{b:02x}");
                s
            });
        let publish = |title: &str, revision: u64, sign: bool| {
            let index = format!(
                r#"{{"schema":2,"release":"5.2.0.22","arch":"aarch64","revision":{revision},
                "categories":[{{"id":"Utilities","label":"Utilities","icon":"icon-m-flashlight","count":1}}],
                "collections":[{{"id":"picks","title":"Picks","apps":["fx"]}}],
                "apps":[{{"id":"fx","title":"{title}","summary":"s","version":"1-1",
                  "licence":{{"model":"free"}},"tested_on":["5.2.0.22"],"keywords":["torch"],
                  "sources":[{{"kind":"rpm","package":"fx"}}],
                  "details":{{"path":"apps/fx.abc.json","sha256":"{sha}","size":{}}}}}]}}"#,
                details.len()
            );
            let path = repo.join("store/index.json");
            std::fs::write(&path, index).unwrap();
            if sign {
                let asc = repo.join("store/index.json.asc");
                let _ = std::fs::remove_file(&asc);
                g(&[
                    "--local-user",
                    "t@example.com",
                    "--armor",
                    "--detach-sign",
                    "--output",
                    asc.to_str().unwrap(),
                    path.to_str().unwrap(),
                ]);
            }
        };
        let cache = dir.join("cache/shipwright-reef/catalogue.json");
        let check = MetadataCheck {
            zypp_conf: dir.join("zypp.conf"),
            alias: "shipwright-reef".into(),
            key,
            state: dir.join("state/metadata-revision"),
            gpg: gpg.into(),
            gpgv: gpgv.into(),
        };
        let run = || {
            refresh(&RefreshInput {
                config: RepoConfig {
                    url_template: format!(
                        "file://{}/repo/sailfishos/{{release}}/{{arch}}/",
                        dir.display()
                    ),
                    ..RepoConfig::default()
                },
                release: SailfishRelease::parse("5.2.0.22"),
                arch: "aarch64".into(),
                previous: None,
                licence_dir: None,
                licence_server: String::new(),
                cache_path: Some(cache.clone()),
                index_check: Some(check.clone()),
            })
            .catalogue
            .expect("catalogue")
        };

        publish("From index", 200, true);
        let c = run();
        let p = &c.packages[0];
        assert_eq!(p.title, "From index");
        assert_eq!(p.description, "Long", "details merged");
        assert_eq!(p.keywords, ["torch"]);
        assert!(p.details.is_none());
        assert_eq!(c.collections[0].apps, ["fx"]);
        assert!(details_dir(&cache).join(format!("{sha}.json")).is_file());
        let cached = Catalogue::parse(&std::fs::read(&cache).unwrap(), "aarch64").unwrap();
        assert_eq!(cached.categories.len(), 1);

        // Changed after signing: catalogue.json instead.
        publish("Forged", 300, false);
        assert_eq!(run().packages[0].title, "From v1");
        // Signed, but older than what was accepted: the same.
        publish("Old", 100, true);
        assert_eq!(run().packages[0].title, "From v1");
        // Newer and signed: the index again (the title its details give).
        publish("Newer", 300, true);
        assert_eq!(run().packages[0].title, "From index");
        std::fs::remove_dir_all(dir).unwrap();
    }
}
