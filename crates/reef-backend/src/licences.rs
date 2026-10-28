// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! Licence tokens the store client holds for the user's paid apps.
//!
//! The client verifies every token with reef-licence before storing it and
//! again when listing. It does no networking itself: the UI layer fetches
//! (`GET /v1/licences/{id}/token`, `GET /v1/revocations`) and hands the bytes
//! here, which keeps this crate free of an HTTP stack and fully testable.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use reef_licence::{
    Error as LicenceError, KeySet, Licence, Plan, Policy, RevocationList, Standing,
};

/// Public keys the client trusts, as `(kid, base64url key)`.
///
/// Set at build time from `SHIPWRIGHT_LICENCE_KEYS` (`kid:base64url`,
/// comma-separated, as `shipwright-licence-service public-key` prints it;
/// see build.rs and `reef_licence::build`). Unset, the set is empty and
/// rejects every token, which is the safe failure. A release build refuses
/// `staging*` and `test*` key ids. Never embed a key whose seed has been
/// anywhere but the licence service's key file.
pub const EMBEDDED_KEYS: &[(&str, &str)] = include!(concat!(env!("OUT_DIR"), "/licence_keys.rs"));

/// Refresh a subscription token when it expires within this many seconds.
pub const REFRESH_WINDOW_SECS: i64 = 3 * 24 * 60 * 60;

/// The revocation list and its signature in one file, written once (so a
/// crash cannot leave a body with another list's signature): the signature
/// header on the first line, then the body bytes exactly as served.
const REVOCATIONS_FILE: &str = "revocations.signed";
/// The earlier two-file form, read when the new file is absent and removed
/// once a list is stored in the new form.
const LEGACY_REVOCATIONS: (&str, &str) = ("revocations.json", "revocations.sig");

#[derive(Debug)]
pub enum StoreError {
    Licence(LicenceError),
    Io(std::io::Error),
    /// A revocation list older than the one already held.
    StaleRevocations,
    /// An app id that is not a safe file name (`handoff::valid_app_id`).
    InvalidAppId(String),
}

impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            StoreError::Licence(e) => write!(f, "{e}"),
            StoreError::Io(e) => write!(f, "licence storage: {e}"),
            StoreError::StaleRevocations => {
                write!(f, "revocation list is older than the stored one")
            }
            StoreError::InvalidAppId(id) => write!(f, "{id:?} is not a valid app id"),
        }
    }
}

impl std::error::Error for StoreError {}

impl From<LicenceError> for StoreError {
    fn from(e: LicenceError) -> Self {
        StoreError::Licence(e)
    }
}

impl From<std::io::Error> for StoreError {
    fn from(e: std::io::Error) -> Self {
        StoreError::Io(e)
    }
}

/// One stored token and what verifying it now says.
#[derive(Debug)]
pub struct StoredLicence {
    pub app_id: String,
    pub token: String,
    pub status: Result<Licence, LicenceError>,
    pub revoked: bool,
}

impl StoredLicence {
    /// Whether the client should fetch a fresh token when online.
    pub fn needs_refresh(&self, now: i64) -> bool {
        match &self.status {
            Ok(l) if l.claims.plan == Plan::Subscription => match l.standing {
                Standing::Grace { .. } => true,
                Standing::Active => l.claims.exp.is_some_and(|e| e - now < REFRESH_WINDOW_SECS),
            },
            // An expired subscription might have been renewed since.
            Err(LicenceError::Expired { .. }) => true,
            _ => false,
        }
    }
}

/// Tokens on disk, one file per app: `<dir>/<app id>.token`.
pub struct LicenceStore {
    dir: PathBuf,
    keys: KeySet,
    policy: Policy,
}

impl LicenceStore {
    pub fn new(dir: impl Into<PathBuf>, keys: KeySet, policy: Policy) -> Self {
        Self {
            dir: dir.into(),
            keys,
            policy,
        }
    }

    /// The default location, `$XDG_DATA_HOME/shipwright-reef/licences`.
    pub fn default_dir() -> Option<PathBuf> {
        let base = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| Path::new(&h).join(".local/share")))?;
        Some(base.join("shipwright-reef/licences"))
    }

    /// The token file for `app_id`, or `None` for an id that is not a safe
    /// file name. App ids reach here from verified tokens, but also from the
    /// unsigned catalogue and from QML, so the check is here and not only in
    /// token verification: `[A-Za-z0-9._-]`, no leading dot, so the path
    /// cannot leave the directory or name a hidden file.
    fn path_for(&self, app_id: &str) -> Option<PathBuf> {
        reef_licence::handoff::valid_app_id(app_id)
            .then(|| self.dir.join(format!("{app_id}.token")))
    }

    /// Verifies and stores a token (from a purchase or a refresh).
    ///
    /// A subscription token never replaces a stored one for the same licence
    /// that runs longer, so a delayed or replayed refresh response cannot
    /// shorten a subscription.
    pub fn save(&self, token: &str, now: i64) -> Result<Licence, StoreError> {
        let new = Licence::verify_any_app(token.trim(), &self.keys, &self.policy, now)?;
        let path = self
            .path_for(&new.claims.app)
            .ok_or_else(|| StoreError::InvalidAppId(new.claims.app.clone()))?;
        if let Some(Ok(old)) = self.load(&new.claims.app).map(|t| self.verify(&t, now)) {
            let longer = |l: &Licence| l.claims.exp.unwrap_or(i64::MAX);
            if old.claims.lid == new.claims.lid && longer(&old) > longer(&new) {
                return Ok(old);
            }
        }
        fs::create_dir_all(&self.dir)?;
        write_private(&path, token.trim().as_bytes())?;
        Ok(new)
    }

    pub fn load(&self, app_id: &str) -> Option<String> {
        fs::read_to_string(self.path_for(app_id)?)
            .ok()
            .map(|s| s.trim().to_string())
    }

    fn verify(&self, token: &str, now: i64) -> Result<Licence, LicenceError> {
        Licence::verify_any_app(token, &self.keys, &self.policy, now)
    }

    /// Checks the licence for `app_id`, including revocation.
    pub fn check(&self, app_id: &str, now: i64) -> Option<StoredLicence> {
        self.check_with(app_id, now, self.revocations().as_ref())
    }

    /// [`Self::check`] against a revocation list loaded (and verified) once
    /// by the caller.
    fn check_with(
        &self,
        app_id: &str,
        now: i64,
        revocations: Option<&RevocationList>,
    ) -> Option<StoredLicence> {
        let token = self.load(app_id)?;
        let status = Licence::verify(&token, app_id, &self.keys, &self.policy, now);
        let revoked = status
            .as_ref()
            .is_ok_and(|l| revocations.is_some_and(|r| r.is_revoked(&l.claims.lid)));
        Some(StoredLicence {
            app_id: app_id.to_string(),
            token,
            status,
            revoked,
        })
    }

    /// Every stored licence, sorted by app id.
    pub fn list(&self, now: i64) -> Vec<StoredLicence> {
        let Ok(entries) = fs::read_dir(&self.dir) else {
            return Vec::new();
        };
        let mut apps: Vec<String> = entries
            .filter_map(Result::ok)
            .filter_map(|e| {
                e.file_name()
                    .to_str()?
                    .strip_suffix(".token")
                    .map(String::from)
            })
            .collect();
        apps.sort();
        // One read and one Ed25519 verification of the list for all apps.
        let revocations = self.revocations();
        apps.iter()
            .filter_map(|a| self.check_with(a, now, revocations.as_ref()))
            .collect()
    }

    pub fn remove(&self, app_id: &str) -> std::io::Result<()> {
        let Some(path) = self.path_for(app_id) else {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                format!("{app_id:?} is not a valid app id"),
            ));
        };
        match fs::remove_file(path) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            other => other,
        }
    }

    /// Verifies and stores a revocation list fetched from the service,
    /// refusing one older than the list already held.
    pub fn accept_revocations(
        &self,
        body: &[u8],
        signature: &str,
    ) -> Result<RevocationList, StoreError> {
        let list = RevocationList::verify(body, signature, &self.keys)?;
        if let Some(current) = self.revocations() {
            if list.generated_at < current.generated_at {
                return Err(StoreError::StaleRevocations);
            }
        }
        fs::create_dir_all(&self.dir)?;
        // Signature and body in one file, written once, so the cached copy
        // can be re-verified on load and never pairs with another list.
        let mut file = signature.trim().as_bytes().to_vec();
        file.push(b'\n');
        file.extend_from_slice(body);
        write_private(&self.dir.join(REVOCATIONS_FILE), &file)?;
        for legacy in [LEGACY_REVOCATIONS.0, LEGACY_REVOCATIONS.1] {
            let _ = fs::remove_file(self.dir.join(legacy));
        }
        Ok(list)
    }

    fn revocations(&self) -> Option<RevocationList> {
        let (sig, body) = match fs::read(self.dir.join(REVOCATIONS_FILE)) {
            Ok(file) => {
                let nl = file.iter().position(|b| *b == b'\n')?;
                let sig = String::from_utf8(file[..nl].to_vec()).ok()?;
                (sig, file[nl + 1..].to_vec())
            }
            Err(_) => (
                fs::read_to_string(self.dir.join(LEGACY_REVOCATIONS.1)).ok()?,
                fs::read(self.dir.join(LEGACY_REVOCATIONS.0)).ok()?,
            ),
        };
        RevocationList::verify(&body, &sig, &self.keys).ok()
    }
}

/// Writes atomically (temp file then rename) with owner-only permissions.
pub(crate) fn write_private(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let tmp = path.with_extension("tmp");
    let mut options = fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut f = options.open(&tmp)?;
    f.write_all(bytes)?;
    f.sync_all()?;
    fs::rename(tmp, path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use reef_licence::{Claims, Signer};

    const T0: i64 = 1_790_000_000;
    const DAY: i64 = 86_400;

    struct Fixture {
        dir: PathBuf,
        signer: Signer,
        store: LicenceStore,
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.dir);
        }
    }

    fn fixture(name: &str) -> Fixture {
        let dir = std::env::temp_dir().join(format!("reef-lic-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        let signer = Signer::from_seed("k1", [5; 32]).unwrap();
        let mut keys = KeySet::new();
        keys.insert_text(&signer.public_key_text()).unwrap();
        let store = LicenceStore::new(&dir, keys, Policy::default());
        Fixture { dir, signer, store }
    }

    fn token(f: &Fixture, app: &str, plan: Plan, exp: Option<i64>) -> String {
        f.signer
            .issue(&Claims {
                app: app.into(),
                exp,
                iat: T0,
                kid: "k1".into(),
                lid: format!("lic_{app}"),
                plan,
            })
            .unwrap()
    }

    #[test]
    fn embedded_keys_parse() {
        // Whatever SHIPWRIGHT_LICENCE_KEYS embedded (nothing by default)
        // must load at run time exactly as build.rs checked it.
        let keys = KeySet::from_embedded(EMBEDDED_KEYS).unwrap();
        assert_eq!(keys.key_ids().count(), EMBEDDED_KEYS.len());
    }

    #[test]
    fn save_list_and_remove() {
        let f = fixture("save");
        f.store
            .save(&token(&f, "shoal-bridge", Plan::OneOff, None), T0)
            .unwrap();
        f.store
            .save(
                &token(
                    &f,
                    "shoal-messages",
                    Plan::Subscription,
                    Some(T0 + 30 * DAY),
                ),
                T0,
            )
            .unwrap();
        let all = f.store.list(T0);
        assert_eq!(all.len(), 2);
        assert_eq!(all[0].app_id, "shoal-bridge");
        assert!(all.iter().all(|l| l.status.is_ok() && !l.revoked));
        f.store.remove("shoal-bridge").unwrap();
        f.store.remove("shoal-bridge").unwrap();
        assert_eq!(f.store.list(T0).len(), 1);
    }

    #[test]
    fn rejects_forged_tokens() {
        let f = fixture("forged");
        let other = Signer::from_seed("k1", [6; 32]).unwrap();
        let forged = other
            .issue(&Claims {
                app: "shoal-bridge".into(),
                exp: None,
                iat: T0,
                kid: "k1".into(),
                lid: "x".into(),
                plan: Plan::OneOff,
            })
            .unwrap();
        assert!(f.store.save(&forged, T0).is_err());
        assert!(f.store.list(T0).is_empty());
    }

    #[test]
    fn shorter_subscription_does_not_replace_longer() {
        let f = fixture("longer");
        let long = token(
            &f,
            "shoal-messages",
            Plan::Subscription,
            Some(T0 + 60 * DAY),
        );
        let short = token(
            &f,
            "shoal-messages",
            Plan::Subscription,
            Some(T0 + 30 * DAY),
        );
        f.store.save(&long, T0).unwrap();
        let kept = f.store.save(&short, T0).unwrap();
        assert_eq!(kept.claims.exp, Some(T0 + 60 * DAY));
        assert_eq!(f.store.load("shoal-messages").unwrap(), long);
    }

    #[test]
    fn refresh_logic() {
        let f = fixture("refresh");
        let sub = token(
            &f,
            "shoal-messages",
            Plan::Subscription,
            Some(T0 + 30 * DAY),
        );
        f.store.save(&sub, T0).unwrap();
        let at = |now| {
            f.store
                .check("shoal-messages", now)
                .unwrap()
                .needs_refresh(now)
        };
        assert!(!at(T0));
        assert!(at(T0 + 28 * DAY), "inside the refresh window");
        assert!(at(T0 + 31 * DAY), "in grace");
        assert!(at(T0 + 60 * DAY), "expired");
        f.store
            .save(&token(&f, "shoal-bridge", Plan::OneOff, None), T0)
            .unwrap();
        assert!(!f.store.check("shoal-bridge", T0).unwrap().needs_refresh(T0));
    }

    #[test]
    fn revocations_apply_and_never_go_backwards() {
        let f = fixture("revoke");
        f.store
            .save(&token(&f, "shoal-bridge", Plan::OneOff, None), T0)
            .unwrap();
        let newer = RevocationList {
            generated_at: T0 + 10,
            revoked: vec!["lic_shoal-bridge".into()],
        };
        let body = serde_json::to_vec(&newer).unwrap();
        f.store
            .accept_revocations(&body, &f.signer.sign_detached(&body))
            .unwrap();
        assert!(f.store.check("shoal-bridge", T0).unwrap().revoked);

        let older = RevocationList {
            generated_at: T0,
            revoked: vec![],
        };
        let body = serde_json::to_vec(&older).unwrap();
        assert!(matches!(
            f.store
                .accept_revocations(&body, &f.signer.sign_detached(&body)),
            Err(StoreError::StaleRevocations)
        ));
        assert!(f.store.check("shoal-bridge", T0).unwrap().revoked);
        // Unsigned lists are refused outright.
        assert!(f.store.accept_revocations(&body, "v1.k1.AAAA").is_err());
        // B-04: one file holds body and signature together.
        assert!(f.dir.join(REVOCATIONS_FILE).is_file());
        assert!(!f.dir.join(LEGACY_REVOCATIONS.0).exists());
        assert!(f.store.list(T0)[0].revoked, "list() sees the stored list");
    }

    #[test]
    fn legacy_two_file_revocations_still_load() {
        let f = fixture("legacy");
        f.store
            .save(&token(&f, "shoal-bridge", Plan::OneOff, None), T0)
            .unwrap();
        let list = RevocationList {
            generated_at: T0,
            revoked: vec!["lic_shoal-bridge".into()],
        };
        let body = serde_json::to_vec(&list).unwrap();
        fs::write(f.dir.join(LEGACY_REVOCATIONS.0), &body).unwrap();
        fs::write(
            f.dir.join(LEGACY_REVOCATIONS.1),
            f.signer.sign_detached(&body),
        )
        .unwrap();
        assert!(f.store.check("shoal-bridge", T0).unwrap().revoked);
        // A mismatched legacy pair (the crash B-04 describes) is not trusted.
        fs::write(f.dir.join(LEGACY_REVOCATIONS.0), b"{}").unwrap();
        assert!(!f.store.check("shoal-bridge", T0).unwrap().revoked);
    }

    #[test]
    fn app_ids_that_are_not_file_names_are_refused() {
        // B-03: ids from the catalogue or QML never leave the directory.
        let f = fixture("paths");
        fs::create_dir_all(&f.dir).unwrap();
        let outside = f.dir.parent().unwrap().join("reef-lic-paths-victim.token");
        fs::write(&outside, "x").unwrap();
        for bad in ["../reef-lic-paths-victim", ".hidden", "a/b", "", "x\0y"] {
            assert!(f.store.load(bad).is_none(), "{bad:?}");
            assert!(f.store.check(bad, T0).is_none(), "{bad:?}");
            assert!(f.store.remove(bad).is_err(), "{bad:?}");
        }
        assert!(outside.exists(), "remove() must not escape the directory");
        fs::remove_file(outside).unwrap();
    }
}
