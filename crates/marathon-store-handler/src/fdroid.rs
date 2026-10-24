//! Android apps from F-Droid, installed through Deckard (deckardd's
//! org.marathonos.Deckard1.Packages, no Android UI).
//!
//! `fdroid-sync` verifies `entry.jar` against F-Droid's pinned certificate,
//! streams `index-v2.json` (66 MB raw, never held whole) through a SHA-256
//! check against the entry, and keeps a compact catalogue: per app the best
//! version this phone can run (arm64-v8a or no native code, Android 13 or
//! older, no beta channel).

use std::collections::HashMap;
use std::fmt;
use std::fs;
use std::io::{self, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use base64::Engine;
use regex::Regex;
use serde::de::{DeserializeSeed, IgnoredAny, MapAccess, Visitor};
use serde::{Deserialize, Deserializer};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use zbus::blocking::{Connection, MessageIterator};
use zbus::zvariant::OwnedValue;

use crate::jar;
use crate::notice::Notice;
use crate::state::{now, Progress, StateDir};

pub const REPO: &str = "https://f-droid.org/repo";
/// The SDK level of Deckard's Android (`LineageOS` 20).
pub const SDK: i64 = 33;
const ABI: &str = "arm64-v8a";
const DESCRIPTION_MAX: usize = 800;
const DECKARD: &str = "org.marathonos.Deckard";
const PACKAGES_PATH: &str = "/org/marathonos/Deckard";
const PACKAGES_IFACE: &str = "org.marathonos.Deckard1.Packages";

/// Android's package-name shape.
pub static PACKAGE_RE: LazyLock<Regex> = LazyLock::new(|| {
    #[allow(clippy::unwrap_used, reason = "constant pattern")]
    Regex::new(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$").unwrap()
});

/// Store ids for Android apps: `android:<package>`.
pub fn package_of(app_id: &str) -> Option<&str> {
    app_id
        .strip_prefix("android:")
        .filter(|pkg| pkg.len() <= 255 && PACKAGE_RE.is_match(pkg))
}

#[derive(Deserialize)]
struct FileRef {
    name: String,
    sha256: Option<String>,
    size: Option<u64>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct Metadata {
    name: Option<HashMap<String, String>>,
    summary: Option<HashMap<String, String>>,
    description: Option<HashMap<String, String>>,
    icon: Option<HashMap<String, FileRef>>,
    categories: Option<Vec<String>>,
    license: Option<String>,
    last_updated: Option<u64>,
    author_name: Option<String>,
    web_site: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UsesSdk {
    min_sdk_version: Option<i64>,
    target_sdk_version: Option<i64>,
}

#[derive(Deserialize)]
struct Permission {
    name: String,
    #[serde(rename = "maxSdkVersion")]
    max_sdk_version: Option<i64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Manifest {
    version_name: Option<String>,
    version_code: i64,
    uses_sdk: Option<UsesSdk>,
    nativecode: Option<Vec<String>>,
    uses_permission: Option<Vec<Permission>>,
    features: Option<Vec<Value>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Version {
    file: FileRef,
    manifest: Manifest,
    anti_features: Option<serde_json::Map<String, Value>>,
    release_channels: Option<Vec<String>>,
}

#[derive(Deserialize)]
struct Package {
    #[serde(default)]
    metadata: Metadata,
    #[serde(default)]
    versions: HashMap<String, Version>,
}

fn localized(map: Option<&HashMap<String, String>>) -> String {
    let Some(map) = map else { return String::new() };
    ["en-US", "en", "en-GB"]
        .iter()
        .find_map(|l| map.get(*l))
        .or_else(|| map.values().next())
        .cloned()
        .unwrap_or_default()
}

fn truncate(text: &str, max: usize) -> String {
    match text.char_indices().nth(max) {
        Some((i, _)) => format!("{}…", &text[..i]),
        None => text.to_owned(),
    }
}

fn runs_here(v: &Version) -> bool {
    let native_ok = v
        .manifest
        .nativecode
        .as_ref()
        .is_none_or(|abis| abis.is_empty() || abis.iter().any(|a| a == ABI));
    let sdk_ok = v
        .manifest
        .uses_sdk
        .as_ref()
        .and_then(|s| s.min_sdk_version)
        .unwrap_or(1)
        <= SDK;
    let stable = v.release_channels.as_ref().is_none_or(Vec::is_empty);
    native_ok && sdk_ok && stable
}

/// The catalogue row for one package, or None when nothing in it runs here.
fn entry(pkg: &str, p: &Package) -> Option<Value> {
    if !PACKAGE_RE.is_match(pkg) {
        return None;
    }
    let v = p
        .versions
        .values()
        .filter(|v| runs_here(v))
        .max_by_key(|v| v.manifest.version_code)?;
    let sha256 = v.file.sha256.as_deref().filter(|s| s.len() == 64)?;
    let m = &p.metadata;
    let icon = m
        .icon
        .as_ref()
        .and_then(|icons| {
            ["en-US", "en"]
                .iter()
                .find_map(|l| icons.get(*l))
                .or_else(|| icons.values().next())
        })
        .map(|f| format!("{REPO}{}", f.name))
        .unwrap_or_default();
    let mut anti: Vec<&str> = v
        .anti_features
        .as_ref()
        .map(|a| a.keys().map(String::as_str).collect())
        .unwrap_or_default();
    anti.sort_unstable();
    let permissions: Vec<&str> = v
        .manifest
        .uses_permission
        .as_ref()
        .map(|perms| {
            perms
                .iter()
                .filter(|p| p.max_sdk_version.is_none_or(|max| max >= SDK))
                .map(|p| p.name.as_str())
                .collect()
        })
        .unwrap_or_default();
    let features: Vec<&str> = v
        .manifest
        .features
        .as_ref()
        .map(|list| {
            list.iter()
                .filter_map(|f| f.get("name").and_then(Value::as_str).or_else(|| f.as_str()))
                .filter(|f| PACKAGE_RE.is_match(f))
                .take(64)
                .collect()
        })
        .unwrap_or_default();
    let name = localized(m.name.as_ref());
    Some(json!({
        "app_id": format!("android:{pkg}"),
        "pkg": pkg,
        "name": if name.is_empty() { pkg.to_owned() } else { name },
        "summary": truncate(&localized(m.summary.as_ref()), 200),
        "description": truncate(&localized(m.description.as_ref()), DESCRIPTION_MAX),
        "icon": icon,
        "categories": m.categories.clone().unwrap_or_default(),
        "license": m.license.clone().unwrap_or_default(),
        "author": m.author_name.clone().unwrap_or_default(),
        "website": m.web_site.clone().unwrap_or_default(),
        "lastUpdated": m.last_updated.unwrap_or(0) / 1000,
        "antiFeatures": anti,
        "version": {
            "name": v.manifest.version_name.clone().unwrap_or_default(),
            "code": v.manifest.version_code,
            "minSdk": v.manifest.uses_sdk.as_ref().and_then(|s| s.min_sdk_version).unwrap_or(1),
            "targetSdk": v.manifest.uses_sdk.as_ref().and_then(|s| s.target_sdk_version).unwrap_or(0),
            "apk": v.file.name,
            "sha256": sha256,
            "size": v.file.size.unwrap_or(0),
            "permissions": permissions,
            "features": features,
        },
    }))
}

struct Packages<'a>(&'a mut Vec<Value>);

impl<'de> DeserializeSeed<'de> for Packages<'_> {
    type Value = ();
    fn deserialize<D: Deserializer<'de>>(self, d: D) -> Result<(), D::Error> {
        d.deserialize_map(self)
    }
}

impl<'de> Visitor<'de> for Packages<'_> {
    type Value = ();
    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("a map of packages")
    }
    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<(), A::Error> {
        while let Some((name, package)) = map.next_entry::<String, Package>()? {
            if let Some(row) = entry(&name, &package) {
                self.0.push(row);
            }
        }
        Ok(())
    }
}

struct Index<'a>(&'a mut Vec<Value>);

impl<'de> Visitor<'de> for Index<'_> {
    type Value = ();
    fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str("an F-Droid index-v2")
    }
    fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<(), A::Error> {
        while let Some(key) = map.next_key::<String>()? {
            if key == "packages" {
                map.next_value_seed(Packages(&mut *self.0))?;
            } else {
                map.next_value::<IgnoredAny>()?;
            }
        }
        Ok(())
    }
}

/// Hashes and counts what passes through.
struct Tee<R> {
    inner: R,
    hasher: Sha256,
    bytes: u64,
}

impl<R: Read> Read for Tee<R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let n = self.inner.read(buf)?;
        self.hasher.update(&buf[..n]);
        self.bytes += n as u64;
        Ok(n)
    }
}

/// The catalogue rows from an index, and the index's SHA-256 and size.
pub fn parse_index<R: Read>(reader: R) -> io::Result<(Vec<Value>, String, u64)> {
    let mut tee = Tee {
        inner: reader,
        hasher: Sha256::new(),
        bytes: 0,
    };
    let mut rows = Vec::new();
    {
        let mut de = serde_json::Deserializer::from_reader(BufReader::new(&mut tee));
        de.deserialize_map(Index(&mut rows))
            .map_err(io::Error::other)?;
    }
    io::copy(&mut tee, &mut io::sink())?;
    rows.sort_by(|a, b| {
        a["name"]
            .as_str()
            .unwrap_or("")
            .to_lowercase()
            .cmp(&b["name"].as_str().unwrap_or("").to_lowercase())
    });
    Ok((rows, jar::hex(&tee.hasher.finalize()), tee.bytes))
}

pub(crate) fn cache_dir() -> PathBuf {
    marathon_rt::dirs::cache().join("marathon-store")
}

pub(crate) fn write_atomic(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let dir = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(dir)?;
    let mut tmp = tempfile::NamedTempFile::new_in(dir)?;
    tmp.write_all(bytes)?;
    tmp.persist(path).map_err(|e| e.error)?;
    Ok(())
}

fn http() -> ureq::Agent {
    ureq::Agent::config_builder()
        .user_agent("Marathon Store")
        .build()
        .into()
}

fn system_property(dest: &str, path: &str, iface: &str, name: &str) -> Option<OwnedValue> {
    let conn = Connection::system().ok()?;
    let reply = conn
        .call_method(
            Some(dest),
            path,
            Some("org.freedesktop.DBus.Properties"),
            "Get",
            &(iface, name),
        )
        .ok()?;
    reply.body().deserialize::<OwnedValue>().ok()
}

/// A metered network (`NetworkManager`'s Metered yes or guessed yes) or a
/// battery under 20 % and discharging (`UPower`): no 16 MB index download.
pub(crate) fn should_wait() -> bool {
    metered() || low_battery()
}

pub(crate) fn metered() -> bool {
    system_property(
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
        "Metered",
    )
    .and_then(|v| u32::try_from(v).ok())
    .is_some_and(|m| m == 1 || m == 3)
}

pub(crate) fn low_battery() -> bool {
    let device = "/org/freedesktop/UPower/devices/DisplayDevice";
    let iface = "org.freedesktop.UPower.Device";
    let discharging = system_property("org.freedesktop.UPower", device, iface, "State")
        .and_then(|v| u32::try_from(v).ok())
        .is_some_and(|s| s == 2);
    let low = system_property("org.freedesktop.UPower", device, iface, "Percentage")
        .and_then(|v| f64::try_from(v).ok())
        .is_some_and(|p| p < 20.0);
    discharging && low
}

/// `fdroid-sync`: refresh the catalogue when F-Droid's index changed, then
/// hand the Store its copy. Waits for a better moment on a metered network
/// or a low battery, unless there is no catalogue yet.
pub fn sync(state: &StateDir) -> io::Result<()> {
    if !crate::settings::load().fdroid {
        return Ok(());
    }
    let cached = cache_dir().join("fdroid.json");
    if cached.is_file() && should_wait() {
        fs::copy(&cached, state.dir().join("fdroid.json"))?;
        return Ok(());
    }
    let agent = http();
    let jar_bytes = agent
        .get(&format!("{REPO}/entry.jar"))
        .call()
        .map_err(io::Error::other)?
        .body_mut()
        .with_config()
        .limit(1 << 20)
        .read_to_vec()
        .map_err(io::Error::other)?;
    let entry = jar::verified_entry(&jar_bytes, "entry.json", jar::FDROID_CERT_SHA256)
        .map_err(|e| io::Error::other(format!("entry.jar: {e}")))?;
    let entry: Value = serde_json::from_slice(&entry)?;
    let index = &entry["index"];
    let (Some(name), Some(sha256), Some(size)) = (
        index["name"].as_str(),
        index["sha256"].as_str(),
        index["size"].as_u64(),
    ) else {
        return Err(io::Error::other("entry.json lacks the index"));
    };
    if !name.starts_with('/') || name.contains("..") {
        return Err(io::Error::other("bad index name"));
    }
    let current: Option<Value> = fs::read(&cached)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok());
    if current.as_ref().and_then(|c| c["index"].as_str()) != Some(sha256) {
        let body = agent
            .get(&format!("{REPO}{name}"))
            .call()
            .map_err(io::Error::other)?
            .into_body()
            .into_reader();
        let (rows, got_sha, got_size) = parse_index(body)?;
        if got_sha != sha256 || got_size != size {
            return Err(io::Error::other("index doesn't match the signed entry"));
        }
        let catalogue = json!({ "index": sha256, "ts": now(), "apps": rows });
        write_atomic(&cached, catalogue.to_string().as_bytes())?;
    }
    fs::copy(&cached, state.dir().join("fdroid.json"))?;
    refresh(state)
}

/// The app's name in the synced F-Droid catalogue.
pub fn catalogue_name(app_id: &str) -> Option<String> {
    let entry = catalogue_entry(package_of(app_id)?)?;
    entry["name"]
        .as_str()
        .filter(|name| !name.is_empty())
        .map(str::to_owned)
}

fn catalogue_entry(pkg: &str) -> Option<Value> {
    let text = fs::read(cache_dir().join("fdroid.json")).ok()?;
    let catalogue: Value = serde_json::from_slice(&text).ok()?;
    catalogue["apps"]
        .as_array()?
        .iter()
        .find(|a| a["pkg"].as_str() == Some(pkg))
        .cloned()
}

fn bus() -> io::Result<Connection> {
    Connection::session().map_err(io::Error::other)
}

fn packages_call<B>(conn: &Connection, method: &str, body: &B) -> io::Result<zbus::message::Message>
where
    B: serde::ser::Serialize + zbus::zvariant::DynamicType,
{
    conn.call_method(
        Some(DECKARD),
        PACKAGES_PATH,
        Some(PACKAGES_IFACE),
        method,
        body,
    )
    .map_err(io::Error::other)
}

/// Runs an install or removal job and waits for its Finished signal.
fn run_job(
    method: &str,
    arg: &str,
    mut on_progress: impl FnMut(i32),
) -> io::Result<(bool, String)> {
    let conn = bus()?;
    let rule = zbus::MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface(PACKAGES_IFACE)
        .map_err(io::Error::other)?
        .path(PACKAGES_PATH)
        .map_err(io::Error::other)?
        .build();
    let signals =
        MessageIterator::for_match_rule(rule, &conn, Some(64)).map_err(io::Error::other)?;
    let job: String = packages_call(&conn, method, &(arg,))?
        .body()
        .deserialize()
        .map_err(io::Error::other)?;
    for message in signals {
        let message = message.map_err(io::Error::other)?;
        let header = message.header();
        match header.member().map(zbus::names::MemberName::as_str) {
            Some("Progress") => {
                if let Ok((id, percent)) = message.body().deserialize::<(String, i32)>() {
                    if id == job {
                        on_progress(percent);
                    }
                }
            }
            Some("Finished") => {
                if let Ok((id, ok, _pkg, text)) = message
                    .body()
                    .deserialize::<(String, bool, String, String)>()
                {
                    if id == job {
                        return Ok((ok, text));
                    }
                }
            }
            _ => {}
        }
    }
    Err(io::Error::other("deckardd went away"))
}

/// Downloads into `to`, checking size and SHA-256 as it goes.
fn download(
    url: &str,
    to: &Path,
    size: u64,
    sha256: &str,
    mut on_progress: impl FnMut(i32),
) -> io::Result<()> {
    let mut reader = http()
        .get(url)
        .call()
        .map_err(io::Error::other)?
        .into_body()
        .into_reader();
    if let Some(dir) = to.parent() {
        fs::create_dir_all(dir)?;
    }
    let mut file = fs::File::create(to)?;
    let mut hasher = Sha256::new();
    let mut done: u64 = 0;
    let mut buf = vec![0u8; 256 * 1024];
    let mut last = -1;
    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        done += n as u64;
        if size > 0 && done > size {
            return Err(io::Error::other("download larger than the index says"));
        }
        hasher.update(&buf[..n]);
        file.write_all(&buf[..n])?;
        let percent = i32::try_from(done * 90 / size.max(1)).unwrap_or(90);
        if percent != last {
            last = percent;
            on_progress(percent);
        }
    }
    if (size > 0 && done != size) || jar::hex(&hasher.finalize()) != sha256 {
        return Err(io::Error::other("download doesn't match the index"));
    }
    file.sync_all()
}

fn android_icon(pkg: &str) -> String {
    let path = cache_dir()
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join(format!("deckard/icons/{pkg}.png"));
    if path.is_file() {
        format!("file://{}", path.display())
    } else {
        String::new()
    }
}

/// install or update an F-Droid app, through the same state file and Hub
/// row as a flatpak.
pub fn install(state: &StateDir, app_id: &str, verb: &str, mut notice: Notice) -> io::Result<()> {
    let record = |s: &'static str, percent: i32, error: &str| {
        state.write_progress(&Progress {
            app_id,
            verb,
            state: s,
            percent,
            error,
        })
    };
    record("pending", -1, "")?;
    notice.progress(-1);
    let result = (|| -> io::Result<(bool, String)> {
        let pkg = package_of(app_id).ok_or_else(|| io::Error::other("not an Android app"))?;
        let app =
            catalogue_entry(pkg).ok_or_else(|| io::Error::other("not in the F-Droid catalogue"))?;
        let v = &app["version"];
        let apk_name = v["apk"].as_str().unwrap_or_default();
        if !apk_name.starts_with('/')
            || apk_name.contains("..")
            || !Path::new(apk_name)
                .extension()
                .is_some_and(|e| e.eq_ignore_ascii_case("apk"))
        {
            return Err(io::Error::other("bad file name in the index"));
        }
        let apk = cache_dir().join("apk").join(format!("{pkg}.apk"));
        let fetched = download(
            &format!("{REPO}{apk_name}"),
            &apk,
            v["size"].as_u64().unwrap_or(0),
            v["sha256"].as_str().unwrap_or_default(),
            |p| {
                record("installing", p, "").ok();
                notice.progress(p);
            },
        );
        if let Err(e) = fetched {
            fs::remove_file(&apk).ok();
            return Err(e);
        }
        let path = apk.to_string_lossy().into_owned();
        let outcome = run_job("InstallPackage", &path, |p| {
            let p = 90 + p / 10;
            record("installing", p, "").ok();
            notice.progress(p);
        });
        fs::remove_file(&apk).ok();
        outcome
    })();
    finish(state, app_id, verb, result, &mut notice)
}

pub fn install_file(
    state: &StateDir,
    app_id: &str,
    path: &str,
    mut notice: Notice,
) -> io::Result<()> {
    state.write_progress(&Progress {
        app_id,
        verb: "install",
        state: "installing",
        percent: -1,
        error: "",
    })?;
    notice.progress(-1);
    let result = run_job("InstallPackage", path, |p| {
        state
            .write_progress(&Progress {
                app_id,
                verb: "install",
                state: "installing",
                percent: p,
                error: "",
            })
            .ok();
        notice.progress(p);
    });
    finish(state, app_id, "install", result, &mut notice)
}

pub fn uninstall(state: &StateDir, app_id: &str) -> io::Result<()> {
    let verb = "uninstall";
    state.write_progress(&Progress {
        app_id,
        verb,
        state: "removing",
        percent: -1,
        error: "",
    })?;
    let result = package_of(app_id)
        .ok_or_else(|| io::Error::other("not an Android app"))
        .and_then(|pkg| run_job("UninstallPackage", pkg, |_| {}));
    let (ok, error) = match &result {
        Ok((true, _)) => (true, String::new()),
        Ok((false, text)) => (false, text.clone()),
        Err(e) => (false, e.to_string()),
    };
    state.write_progress(&Progress {
        app_id,
        verb,
        state: if ok { "removed" } else { "failed" },
        percent: if ok { 100 } else { -1 },
        error: &error,
    })?;
    refresh(state)
}

fn finish(
    state: &StateDir,
    app_id: &str,
    verb: &str,
    result: io::Result<(bool, String)>,
    notice: &mut Notice,
) -> io::Result<()> {
    let (ok, error) = match result {
        Ok((true, _)) => (true, String::new()),
        Ok((false, text)) => (false, text),
        Err(e) => (false, e.to_string()),
    };
    let pkg = package_of(app_id).unwrap_or_default();
    if ok {
        notice.finish(&format!("deckard.{pkg}"), &android_icon(pkg));
    } else {
        notice.close();
    }
    state.write_progress(&Progress {
        app_id,
        verb,
        state: if ok { "done" } else { "failed" },
        percent: if ok { 100 } else { -1 },
        error: &error,
    })?;
    refresh(state)
}

/// `apk-inspect`: what the Store's confirmation shows, as apk-inspect.json.
pub fn inspect(state: &StateDir, path: &str) -> io::Result<()> {
    let info: HashMap<String, OwnedValue> = bus()
        .and_then(|conn| packages_call(&conn, "InspectPackage", &(path,)))
        .and_then(|reply| reply.body().deserialize().map_err(io::Error::other))
        .unwrap_or_else(|e| {
            HashMap::from([(
                "message".to_owned(),
                OwnedValue::from(zbus::zvariant::Str::from(e.to_string())),
            )])
        });
    let get_str = |k: &str| {
        info.get(k)
            .and_then(|v| String::try_from(v.clone()).ok())
            .unwrap_or_default()
    };
    let get_i64 = |k: &str| info.get(k).and_then(|v| i64::try_from(v.clone()).ok());
    let ok = info
        .get("ok")
        .and_then(|v| bool::try_from(v.clone()).ok())
        .unwrap_or(false);
    let permissions: Vec<String> = info
        .get("permissions")
        .and_then(|v| Vec::<String>::try_from(v.clone()).ok())
        .unwrap_or_default();
    let list = |k: &str| {
        info.get(k)
            .and_then(|v| Vec::<String>::try_from(v.clone()).ok())
            .unwrap_or_default()
    };
    let icon: Vec<u8> = info
        .get("icon")
        .and_then(|v| Vec::<u8>::try_from(v.clone()).ok())
        .unwrap_or_default();
    let record = json!({
        "path": path,
        "ok": ok,
        "message": get_str("message"),
        "pkg": get_str("pkg"),
        "name": get_str("label"),
        "versionName": get_str("versionName"),
        "versionCode": get_i64("versionCode"),
        "minSdk": info.get("minSdk").and_then(|v| i32::try_from(v.clone()).ok()),
        "targetSdk": info.get("targetSdk").and_then(|v| i32::try_from(v.clone()).ok()),
        "features": list("features"),
        "libraries": list("libraries"),
        "abis": list("abis"),
        "gms": info.get("gms").and_then(|v| bool::try_from(v.clone()).ok()).unwrap_or(false),
        "installedVersionName": get_str("installedVersionName"),
        "installedVersionCode": get_i64("installedVersionCode"),
        "permissions": permissions,
        "icon": if icon.is_empty() { String::new() } else {
            format!("data:image/png;base64,{}", base64::engine::general_purpose::STANDARD.encode(icon))
        },
        "ts": now(),
    });
    device_profile(state);
    state.write_json("apk-inspect.json", &record)
}

/// This phone's Android, which the Store compares an app's needs with:
/// android-device.json. Left as it was when Android isn't running.
pub fn device_profile(state: &StateDir) {
    let Ok(info) = bus()
        .and_then(|conn| packages_call(&conn, "DeviceProfile", &()))
        .and_then(|reply| {
            reply
                .body()
                .deserialize::<HashMap<String, OwnedValue>>()
                .map_err(io::Error::other)
        })
    else {
        return;
    };
    let list = |k: &str| {
        info.get(k)
            .and_then(|v| Vec::<String>::try_from(v.clone()).ok())
            .unwrap_or_default()
    };
    let record = json!({
        "features": list("features"),
        "libraries": list("libraries"),
        "abis": list("abis"),
        "sdk": info.get("sdk").and_then(|v| i32::try_from(v.clone()).ok()).unwrap_or(0),
        "gms": info.get("gms").and_then(|v| bool::try_from(v.clone()).ok()).unwrap_or(false),
        "ts": now(),
    });
    let _written = state.write_json("android-device.json", &record);
}

/// Installed Android apps the user added, and the ones F-Droid has newer.
pub fn lists() -> (Vec<Value>, Vec<Value>) {
    let listed: Vec<HashMap<String, OwnedValue>> = bus()
        .and_then(|conn| packages_call(&conn, "ListPackages", &()))
        .and_then(|reply| reply.body().deserialize().map_err(io::Error::other))
        .unwrap_or_default();
    let catalogue: Value = fs::read(cache_dir().join("fdroid.json"))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or(Value::Null);
    let codes: HashMap<&str, i64> = catalogue["apps"]
        .as_array()
        .map(|apps| {
            apps.iter()
                .filter_map(|a| Some((a["pkg"].as_str()?, a["version"]["code"].as_i64()?)))
                .collect()
        })
        .unwrap_or_default();
    let mut installed = Vec::new();
    let mut updates = Vec::new();
    for p in &listed {
        let get_str = |k: &str| {
            p.get(k)
                .and_then(|v| String::try_from(v.clone()).ok())
                .unwrap_or_default()
        };
        if p.get("system")
            .and_then(|v| bool::try_from(v.clone()).ok())
            .unwrap_or(true)
        {
            continue;
        }
        let pkg = get_str("pkg");
        if !PACKAGE_RE.is_match(&pkg) || pkg.starts_with("org.marathonos.deckard.") {
            continue;
        }
        let code = p
            .get("versionCode")
            .and_then(|v| i64::try_from(v.clone()).ok())
            .unwrap_or(0);
        let app_id = format!("android:{pkg}");
        installed.push(json!({
            "app_id": app_id,
            "name": get_str("label"),
            "version": get_str("versionName"),
            "icon": android_icon(&pkg),
            "launchable": p
                .get("launchable")
                .and_then(|v| bool::try_from(v.clone()).ok())
                .unwrap_or(true),
        }));
        if codes.get(pkg.as_str()).is_some_and(|&newer| newer > code) {
            updates.push(json!({ "app_id": app_id }));
        }
    }
    (installed, updates)
}

/// Re-runs the flatpak refresh, which merges these lists in.
fn refresh(state: &StateDir) -> io::Result<()> {
    crate::ops::refresh(state, crate::FLATPAK)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    const INDEX: &str = r#"{
      "repo": {"name": {"en-US": "F-Droid"}, "timestamp": 1},
      "packages": {
        "org.example.good": {
          "metadata": {"name": {"de": "Gut", "en-US": "Good"}, "summary": {"en-US": "A good app"},
                       "icon": {"en-US": {"name": "/org.example.good/en-US/icon.png"}},
                       "categories": ["Clock"], "license": "GPL-3.0-only", "lastUpdated": 1700000000000},
          "versions": {
            "a": {"file": {"name": "/org.example.good_3.apk", "sha256": "1111111111111111111111111111111111111111111111111111111111111111", "size": 10},
                  "manifest": {"versionName": "3.0-beta", "versionCode": 3, "usesSdk": {"minSdkVersion": 21}},
                  "releaseChannels": ["Beta"]},
            "b": {"file": {"name": "/org.example.good_2.apk", "sha256": "2222222222222222222222222222222222222222222222222222222222222222", "size": 20},
                  "manifest": {"versionName": "2.0", "versionCode": 2, "usesSdk": {"minSdkVersion": 21, "targetSdkVersion": 33},
                               "nativecode": ["armeabi-v7a", "arm64-v8a"],
                               "usesPermission": [{"name": "android.permission.INTERNET"},
                                                  {"name": "android.permission.READ_EXTERNAL_STORAGE", "maxSdkVersion": 28}],
                               "features": [{"name": "android.hardware.telephony"}, {"name": "bad feature"}]},
                  "antiFeatures": {"Tracking": {"en-US": "uses analytics"}}},
            "c": {"file": {"name": "/org.example.good_1.apk", "sha256": "3333333333333333333333333333333333333333333333333333333333333333", "size": 30},
                  "manifest": {"versionName": "1.0", "versionCode": 1}}
          }
        },
        "org.example.x86only": {
          "metadata": {"name": {"en-US": "X86"}},
          "versions": {"a": {"file": {"name": "/x.apk", "sha256": "4444444444444444444444444444444444444444444444444444444444444444"},
                             "manifest": {"versionCode": 1, "nativecode": ["x86"]}}}
        },
        "org.example.tooNew": {
          "versions": {"a": {"file": {"name": "/n.apk", "sha256": "5555555555555555555555555555555555555555555555555555555555555555"},
                             "manifest": {"versionCode": 1, "usesSdk": {"minSdkVersion": 34}}}}
        }
      }
    }"#;

    #[test]
    fn keeps_the_best_version_that_runs_here() {
        let (rows, sha, size) = parse_index(INDEX.as_bytes()).unwrap();
        assert_eq!(size, INDEX.len() as u64);
        assert_eq!(sha, jar::hex(&Sha256::digest(INDEX.as_bytes())));
        assert_eq!(rows.len(), 1);
        let app = &rows[0];
        assert_eq!(app["app_id"], "android:org.example.good");
        assert_eq!(app["name"], "Good");
        assert_eq!(
            app["icon"],
            "https://f-droid.org/repo/org.example.good/en-US/icon.png"
        );
        assert_eq!(app["version"]["code"], 2);
        assert_eq!(app["version"]["apk"], "/org.example.good_2.apk");
        assert_eq!(
            app["version"]["permissions"],
            json!(["android.permission.INTERNET"])
        );
        assert_eq!(app["antiFeatures"], json!(["Tracking"]));
        assert_eq!(
            app["version"]["features"],
            json!(["android.hardware.telephony"])
        );
        assert_eq!(app["lastUpdated"], 1_700_000_000);
    }

    #[test]
    fn android_ids() {
        assert_eq!(
            package_of("android:org.example.app"),
            Some("org.example.app")
        );
        assert_eq!(package_of("android:../etc"), None);
        assert_eq!(package_of("org.example.app"), None);
    }
}
