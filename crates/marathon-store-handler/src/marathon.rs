//! Marathon's own apps that Reef updates (`marathon:<app id>`): a newer
//! signed `.marathon` package from Reef's catalogue, installed beside the
//! OS's copy, which it then supersedes (`marathon_apps::apps::find`). The
//! catalogue is the one Reef verified and cached; the package's own
//! signature by a system key is what lets it replace an OS app.

use std::fs;
use std::io;

use marathon_apps::{apps, install};
use serde_json::{json, Value};

use crate::notice::Notice;
use crate::state::{Progress, StateDir};

/// Store ids for Marathon apps: `marathon:<app id>`.
pub fn app_of(app_id: &str) -> Option<&str> {
    app_id.strip_prefix("marathon:").filter(|id| {
        !id.is_empty()
            && id.len() <= 64
            && id
                .bytes()
                .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || matches!(c, b'_' | b'-'))
    })
}

/// What Reef's catalogue offers for an app.
#[derive(Debug, PartialEq, Eq)]
struct Offer {
    app_id: String,
    version: String,
    url: String,
    sha256: String,
    min_image: String,
    size: u64,
}

/// The Marathon packages in Reef's cached catalogue (`jobs::refresh`
/// writes it only once its signature checked out).
fn offers() -> Vec<Offer> {
    let path = marathon_rt::dirs::cache().join("shipwright-reef/catalogue.json");
    let catalogue: Value = fs::read(path)
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or(Value::Null);
    parse_offers(&catalogue)
}

fn parse_offers(catalogue: &Value) -> Vec<Offer> {
    let text = |v: &Value| v.as_str().unwrap_or_default().to_owned();
    catalogue["packages"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|p| p["install"]["kind"] == "marathon")
        .map(|p| Offer {
            app_id: text(&p["install"]["app_id"]),
            version: text(&p["version"]),
            url: text(&p["install"]["url"]),
            sha256: text(&p["install"]["sha256"]),
            min_image: text(&p["install"]["min_image"]),
            size: p["size"].as_u64().unwrap_or(0),
        })
        .filter(|o| app_of(&format!("marathon:{}", o.app_id)).is_some())
        .collect()
}

/// Whether this phone's image can run it.
fn runs_here(offer: &Offer, image: Option<&str>) -> bool {
    offer.min_image.is_empty() || image.is_some_and(|i| !apps::is_newer(&offer.min_image, i))
}

/// The catalogue's Marathon apps this phone has, and those it offers newer
/// for this image. Copies the OS has caught up with are removed first.
pub fn lists() -> (Vec<Value>, Vec<Value>) {
    install::remove_superseded();
    let image = apps::running_image();
    let mut installed = Vec::new();
    let mut updates = Vec::new();
    for offer in offers() {
        let Some(app) = apps::find(&offer.app_id) else {
            continue;
        };
        let app_id = format!("marathon:{}", offer.app_id);
        installed.push(json!({
            "app_id": app_id,
            "name": app.name,
            "version": app.version,
            "icon": app.icon,
            "launchable": true,
        }));
        if apps::is_newer(&offer.version, &app.version) && runs_here(&offer, image.as_deref()) {
            updates.push(json!({ "app_id": app_id }));
        }
    }
    (installed, updates)
}

/// Downloads the package and its signature, then installs it. A newer
/// version that asks for more permissions installs only when a system key
/// signed it, as the OS's own copy would have them.
fn fetch_and_install(offer: &Offer, mut on_progress: impl FnMut(i32)) -> io::Result<()> {
    let dir = crate::fdroid::cache_dir().join("marathon");
    let package = dir.join(format!("{}.marathon", offer.app_id));
    let signature = marathon_apps::signature::signature_path(&package);
    let result = (|| {
        crate::fdroid::download(
            &offer.url,
            &package,
            offer.size,
            &offer.sha256,
            &mut on_progress,
        )?;
        let sig = crate::fdroid::http()
            .get(&format!("{}.minisig", offer.url))
            .call()
            .map_err(io::Error::other)?
            .body_mut()
            .with_config()
            .limit(64 * 1024)
            .read_to_vec()
            .map_err(io::Error::other)?;
        fs::write(&signature, sig)?;
        on_progress(95);
        match install::install_package(&package, &[]) {
            Err(install::Refusal::Held(plan)) if apps::is_system_signer(&plan.signer) => {
                install::install_package(&package, &plan.added)
            }
            other => other,
        }
        .map(drop)
        .map_err(|refusal| {
            io::Error::other(match refusal {
                install::Refusal::Held(plan) => {
                    format!(
                        "{} asks for new permissions: {}",
                        plan.id,
                        plan.added.join(", ")
                    )
                }
                install::Refusal::Failed(e) => e,
            })
        })
    })();
    fs::remove_file(&package).ok();
    fs::remove_file(&signature).ok();
    result
}

/// install or update a Marathon app, through the same state file and Hub
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
    let result = app_of(app_id)
        .ok_or_else(|| io::Error::other("not a Marathon app"))
        .and_then(|id| {
            offers()
                .into_iter()
                .find(|o| o.app_id == id)
                .ok_or_else(|| io::Error::other("not in Reef's catalogue"))
        })
        .and_then(|offer| {
            if !runs_here(&offer, apps::running_image().as_deref()) {
                return Err(io::Error::other(format!(
                    "needs Marathon {} or later: update the phone first",
                    offer.min_image
                )));
            }
            fetch_and_install(&offer, |p| {
                record("installing", p, "").ok();
                notice.progress(p);
            })
        });
    let error = result.as_ref().err().map_or_default(ToString::to_string);
    if result.is_ok() {
        let id = app_of(app_id).unwrap_or_default();
        let icon = apps::find(id).map_or_default(|a| a.icon);
        notice.finish(id, &icon);
    } else {
        notice.close();
    }
    record(
        if result.is_ok() { "done" } else { "failed" },
        if result.is_ok() { 100 } else { -1 },
        &error,
    )?;
    crate::ops::refresh(state, crate::FLATPAK)
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn marathon_ids() {
        assert_eq!(app_of("marathon:maps"), Some("maps"));
        assert_eq!(app_of("marathon:../etc"), None);
        assert_eq!(app_of("marathon:"), None);
        assert_eq!(app_of("maps"), None);
    }

    #[test]
    fn reads_the_offers_in_reefs_catalogue() {
        let catalogue = json!({"packages": [
            {"name": "maps", "version": "1.0.0.2611050000", "size": 42,
             "install": {"kind": "marathon", "app_id": "maps", "url": "https://x/maps.marathon",
                         "sha256": "ab", "min_image": "26110501"}},
            {"name": "bad", "version": "1",
             "install": {"kind": "marathon", "app_id": "../bad", "url": "https://x/b", "sha256": "ab"}},
            {"name": "org.gnome.Maps", "version": "1",
             "install": {"kind": "flatpak", "remote": "flathub", "ref": "org.gnome.Maps"}}
        ]});
        let offers = parse_offers(&catalogue);
        assert_eq!(
            offers,
            [Offer {
                app_id: "maps".into(),
                version: "1.0.0.2611050000".into(),
                url: "https://x/maps.marathon".into(),
                sha256: "ab".into(),
                min_image: "26110501".into(),
                size: 42,
            }]
        );
        assert!(runs_here(&offers[0], Some("26110501")));
        assert!(!runs_here(&offers[0], Some("26110401")));
        assert!(!runs_here(&offers[0], None));
    }
}
