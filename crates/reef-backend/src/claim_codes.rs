// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! Claim codes: how a licence bought on the web reaches the phone.
//!
//! When the user taps Buy, the client makes a secret claim code (128 random
//! bits as 32 lowercase hex characters), records it here as pending, and
//! opens the purchase URL with `claim=<code>` added. The checkout page hands
//! the code to the licence service with the order; once the order is paid,
//! `GET /v1/claims/{code}` answers with the licence token. The client asks
//! for every pending code during a licence refresh (when Reef starts, on
//! `refreshLicences()`, and when Reef returns to the foreground while a code
//! is pending), stores the token in [`crate::licences::LicenceStore`] and
//! forgets the code.
//!
//! Anyone holding a code can fetch the token, so codes are kept like
//! tokens: one owner-only file per code, `<dir>/<code>`, holding
//! `{"app_id": …, "created_at": …}`, in a directory only the owner can
//! open. At most [`MAX_PENDING`] are kept, none older than
//! [`MAX_AGE_SECS`]. As with licences, the networking is the UI layer's.

use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::licences::write_private;

/// Hex characters in a claim code (128 bits).
pub const CLAIM_LEN: usize = 32;

/// Pending codes kept; the oldest goes when a new one would pass this.
pub const MAX_PENDING: usize = 20;

/// A code not redeemed within this many seconds (30 days) is dropped.
pub const MAX_AGE_SECS: i64 = 30 * 24 * 60 * 60;

/// A new claim code from the operating system's random source.
pub fn new_claim() -> Result<String, getrandom::Error> {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut bytes = [0u8; CLAIM_LEN / 2];
    getrandom::fill(&mut bytes)?;
    Ok(bytes
        .iter()
        .flat_map(|b| [HEX[usize::from(b >> 4)], HEX[usize::from(b & 0xf)]])
        .map(char::from)
        .collect())
}

/// Exactly [`CLAIM_LEN`] lowercase hex characters: the only names a code
/// file may have, and the only codes put in a URL.
pub fn is_claim(code: &str) -> bool {
    code.len() == CLAIM_LEN && code.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

/// `purchase_url` with `claim=<code>` added to its query: after `&` when it
/// has a query already, after `?` otherwise, and before any `#fragment`.
pub fn purchase_url_with_claim(purchase_url: &str, code: &str) -> String {
    let (base, fragment) = match purchase_url.find('#') {
        Some(i) => purchase_url.split_at(i),
        None => (purchase_url, ""),
    };
    let sep = if !base.contains('?') {
        "?"
    } else if base.ends_with('?') || base.ends_with('&') {
        ""
    } else {
        "&"
    };
    format!("{base}{sep}claim={code}{fragment}")
}

/// What a pending code was made for.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PendingClaim {
    #[serde(skip)]
    pub code: String,
    pub app_id: String,
    pub created_at: i64,
}

/// The pending codes on disk.
pub struct PendingClaims {
    dir: PathBuf,
}

impl PendingClaims {
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    /// The codes directory beside a licence directory: `claims/` next to
    /// `licences/` (`$XDG_DATA_HOME/shipwright-reef/claims`).
    pub fn beside(licence_dir: &Path) -> Self {
        Self::new(licence_dir.with_file_name("claims"))
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    /// Makes a code for `app_id`, records it, and returns it. Expired codes
    /// and, past [`MAX_PENDING`], the oldest ones are dropped first.
    pub fn create(&self, app_id: &str, now: i64) -> std::io::Result<String> {
        let code = new_claim().map_err(std::io::Error::other)?;
        self.add(&code, app_id, now)?;
        Ok(code)
    }

    /// Records `code` (already made) for `app_id`.
    pub fn add(&self, code: &str, app_id: &str, now: i64) -> std::io::Result<()> {
        if !is_claim(code) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "not a claim code",
            ));
        }
        let pending = self.list(now);
        for old in pending
            .iter()
            .take((pending.len() + 1).saturating_sub(MAX_PENDING))
        {
            self.remove(&old.code)?;
        }
        let mut builder = fs::DirBuilder::new();
        builder.recursive(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::DirBuilderExt;
            builder.mode(0o700);
        }
        builder.create(&self.dir)?;
        let record = PendingClaim {
            code: code.to_string(),
            app_id: app_id.to_string(),
            created_at: now,
        };
        write_private(&self.dir.join(code), &serde_json::to_vec(&record)?)
    }

    /// Every pending code, oldest first. Expired and unreadable files are
    /// removed on the way.
    pub fn list(&self, now: i64) -> Vec<PendingClaim> {
        let Ok(entries) = fs::read_dir(&self.dir) else {
            return Vec::new();
        };
        let mut out: Vec<PendingClaim> = Vec::new();
        for entry in entries.filter_map(Result::ok) {
            let Some(code) = entry.file_name().to_str().map(String::from) else {
                continue;
            };
            if !is_claim(&code) {
                continue;
            }
            let record = fs::read(entry.path())
                .ok()
                .and_then(|b| serde_json::from_slice::<PendingClaim>(&b).ok());
            match record {
                Some(r) if now - r.created_at <= MAX_AGE_SECS => {
                    out.push(PendingClaim { code, ..r });
                }
                _ => {
                    let _ = fs::remove_file(entry.path());
                }
            }
        }
        out.sort_by(|a, b| a.created_at.cmp(&b.created_at).then(a.code.cmp(&b.code)));
        out
    }

    /// Whether any code is pending (expired ones are dropped).
    pub fn any(&self, now: i64) -> bool {
        !self.list(now).is_empty()
    }

    /// Forgets `code` (redeemed, revoked or refused); a missing one is fine.
    pub fn remove(&self, code: &str) -> std::io::Result<()> {
        if !is_claim(code) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "not a claim code",
            ));
        }
        match fs::remove_file(self.dir.join(code)) {
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            other => other,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const T0: i64 = 1_790_000_000;
    const DAY: i64 = 86_400;

    struct Dir(PathBuf);

    impl Drop for Dir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn scratch(name: &str) -> (Dir, PendingClaims) {
        let root = std::env::temp_dir().join(format!("reef-claims-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        let claims = PendingClaims::beside(&root.join("licences"));
        (Dir(root), claims)
    }

    #[test]
    fn codes_are_32_lowercase_hex_and_differ() {
        let a = new_claim().unwrap();
        let b = new_claim().unwrap();
        assert!(is_claim(&a) && is_claim(&b), "{a} {b}");
        assert_ne!(a, b);
        assert!(!is_claim(&a.to_uppercase()));
        assert!(!is_claim(&a[1..]));
        assert!(!is_claim(&format!("{a}0")));
        assert!(!is_claim("0123456789abcdef0123456789abcdeg"));
        assert!(!is_claim("../123456789abcdef0123456789abcde"));
        assert!(!is_claim(""));
    }

    #[test]
    fn claim_goes_into_the_query_before_the_fragment() {
        let c = "0123456789abcdef0123456789abcdef";
        assert_eq!(
            purchase_url_with_claim("https://shipwright.example/buy/x", c),
            format!("https://shipwright.example/buy/x?claim={c}")
        );
        assert_eq!(
            purchase_url_with_claim("https://shipwright.example/buy?app=x", c),
            format!("https://shipwright.example/buy?app=x&claim={c}")
        );
        assert_eq!(
            purchase_url_with_claim("https://shipwright.example/buy?app=x#pay", c),
            format!("https://shipwright.example/buy?app=x&claim={c}#pay")
        );
        assert_eq!(
            purchase_url_with_claim("https://shipwright.example/buy#pay?not-a-query", c),
            format!("https://shipwright.example/buy?claim={c}#pay?not-a-query")
        );
        assert_eq!(
            purchase_url_with_claim("https://shipwright.example/buy?", c),
            format!("https://shipwright.example/buy?claim={c}")
        );
        assert_eq!(
            purchase_url_with_claim("https://shipwright.example/buy?a=1&", c),
            format!("https://shipwright.example/buy?a=1&claim={c}")
        );
    }

    #[test]
    fn create_list_and_remove() {
        let (root, claims) = scratch("basic");
        assert!(claims.list(T0).is_empty());
        assert!(!claims.any(T0));
        let a = claims.create("shoal-bridge", T0).unwrap();
        let b = claims.create("shoal-keys", T0 + 1).unwrap();
        assert_eq!(claims.dir(), root.0.join("claims"));
        let listed = claims.list(T0 + 2);
        assert_eq!(
            listed
                .iter()
                .map(|c| (c.code.as_str(), c.app_id.as_str()))
                .collect::<Vec<_>>(),
            [(a.as_str(), "shoal-bridge"), (b.as_str(), "shoal-keys")]
        );
        assert_eq!(listed[0].created_at, T0);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = |p: &Path| fs::metadata(p).unwrap().permissions().mode() & 0o777;
            assert_eq!(mode(&claims.dir().join(&a)), 0o600);
            assert_eq!(mode(claims.dir()), 0o700);
        }
        let text = fs::read_to_string(claims.dir().join(&a)).unwrap();
        let json: serde_json::Value = serde_json::from_str(&text).unwrap();
        assert_eq!(json["app_id"], "shoal-bridge");
        assert_eq!(json["created_at"], T0);
        claims.remove(&a).unwrap();
        claims.remove(&a).unwrap();
        assert_eq!(claims.list(T0).len(), 1);
        assert!(claims.remove("../licences").is_err());
        assert!(claims.add("not-a-code", "x", T0).is_err());
    }

    #[test]
    fn old_codes_expire_and_junk_is_dropped() {
        let (_root, claims) = scratch("expire");
        let old = claims.create("shoal-bridge", T0).unwrap();
        let new = claims.create("shoal-bridge", T0 + 20 * DAY).unwrap();
        fs::write(
            claims.dir().join("0123456789abcdef0123456789abcdef"),
            b"junk",
        )
        .unwrap();
        fs::write(claims.dir().join("notes.txt"), b"left alone").unwrap();
        let at_30 = claims.list(T0 + MAX_AGE_SECS);
        assert_eq!(at_30.len(), 2, "exactly 30 days old is kept");
        let later = claims.list(T0 + MAX_AGE_SECS + 1);
        assert_eq!(later.len(), 1);
        assert_eq!(later[0].code, new);
        assert!(!claims.dir().join(&old).exists(), "expired file removed");
        assert!(!claims
            .dir()
            .join("0123456789abcdef0123456789abcdef")
            .exists());
        assert!(claims.dir().join("notes.txt").exists());
    }

    #[test]
    fn at_most_max_pending_are_kept() {
        let (_root, claims) = scratch("cap");
        let mut codes = Vec::new();
        for i in 0..MAX_PENDING + 3 {
            let t = T0 + i64::try_from(i).unwrap();
            codes.push(claims.create("shoal-bridge", t).unwrap());
        }
        let listed: Vec<String> = claims.list(T0 + 100).into_iter().map(|c| c.code).collect();
        assert_eq!(listed.len(), MAX_PENDING);
        assert_eq!(listed, codes[3..], "the oldest went first");
    }
}
