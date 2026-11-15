// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! "Add to home screen": a launcher entry in
//! `~/.local/share/applications` that opens one page in Pacific (the
//! Sailfish form of a web-app shortcut, as sailfish-browser does).

use std::path::PathBuf;

use self::sha2_lite::short_hash;

/// The desktop entry for `url` titled `title`.
pub fn entry(url: &str, title: &str) -> String {
    let clean = |s: &str| s.chars().filter(|c| !c.is_control()).collect::<String>();
    let name = if title.trim().is_empty() {
        pacific_core::util::display_host(url)
    } else {
        clean(title.trim())
    };
    // Exec arguments are quoted per the Desktop Entry spec.
    let quoted = clean(url)
        .replace('\\', "\\\\\\\\")
        .replace('"', "\\\\\"")
        .replace('`', "\\\\`")
        .replace('$', "\\\\$");
    format!(
        "[Desktop Entry]\nType=Application\nName={name}\nIcon=shipwright-pacific\nExec=/usr/bin/shipwright-pacific \"{quoted}\"\nX-Nemo-Single-Instance=no\nX-Shipwright-Pacific-Url={}\nCategories=Network;WebBrowser;\n",
        clean(url)
    )
}

fn applications_dir() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .filter(|v| !v.is_empty())
        .map_or_else(
            || {
                std::env::var_os("HOME")
                    .map_or_else(|| PathBuf::from("/tmp"), PathBuf::from)
                    .join(".local/share")
            },
            PathBuf::from,
        )
        .join("applications")
}

/// Writes the entry; the error is a message for the person.
pub fn write(url: &str, title: &str) -> Result<(), String> {
    let parsed = url::Url::parse(url).map_err(|_| format!("{url} is not a web address"))?;
    if !matches!(parsed.scheme(), "http" | "https") {
        return Err("only web pages can be added to the home screen".into());
    }
    let path = applications_dir().join(format!("shipwright-pacific-{}.desktop", short_hash(url)));
    pacific_core::util::write_atomic(&path, entry(url, title).as_bytes()).map_err(|e| e.to_string())
}

/// A short stable hash for file names (FNV-1a, 64 bits, hex).
mod sha2_lite {
    pub fn short_hash(s: &str) -> String {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        for b in s.bytes() {
            h ^= u64::from(b);
            h = h.wrapping_mul(0x0100_0000_01b3);
        }
        format!("{h:016x}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entries_quote_and_name() {
        let e = entry("https://e.example/a?b=\"c\"$d", "My\nPage");
        assert!(e.contains("Name=MyPage\n"));
        assert!(
            e.contains(
                "Exec=/usr/bin/shipwright-pacific \"https://e.example/a?b=\\\\\"c\\\\\"\\\\$d\""
            ),
            "{e}"
        );
        assert!(entry("https://news.example/", " ").contains("Name=news.example\n"));
        assert_eq!(short_hash("a"), short_hash("a"));
        assert_ne!(short_hash("a"), short_hash("b"));
    }

    #[test]
    fn refuses_non_web() {
        assert!(write("file:///etc/passwd", "x").is_err());
        assert!(write("nonsense", "x").is_err());
    }
}
