// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Site icons for the address bar, the new-tab page and the tab grid.
//!
//! The web view reports the best icon a page declares (apple-touch-icon
//! and sized icons first). The app fetches it once over HTTPS (never for
//! private tabs, at most [`MAX_BYTES`]) into `<cache>/favicons/<hash>`,
//! which Qt reads by content; pages without one get a letter tile.

use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

/// Larger icons are refused.
pub const MAX_BYTES: usize = 256 * 1024;

/// Where the icon at `icon_url` is cached.
pub fn file_for(dir: &Path, icon_url: &str) -> PathBuf {
    let h = crate::blocker::hex(&Sha256::digest(icon_url.as_bytes()));
    dir.join(&h[..32])
}

/// Whether `icon_url` may be fetched: HTTPS, or a data URL is not needed
/// (the view gives those inline, nothing to fetch).
pub fn fetchable(icon_url: &str) -> bool {
    icon_url.starts_with("https://") && icon_url.len() <= 2048
}

/// Whether `bytes` look like an image Qt reads (PNG, ICO, JPEG, GIF, WebP,
/// SVG), so an error page is never stored as an icon.
pub fn looks_like_image(bytes: &[u8]) -> bool {
    let b = bytes;
    b.starts_with(b"\x89PNG")
        || b.starts_with(&[0, 0, 1, 0])
        || b.starts_with(&[0xFF, 0xD8, 0xFF])
        || b.starts_with(b"GIF8")
        || (b.len() > 12 && &b[..4] == b"RIFF" && &b[8..12] == b"WEBP")
        || {
            let head = String::from_utf8_lossy(&b[..b.len().min(256)]).to_ascii_lowercase();
            head.contains("<svg") && !head.contains("<html")
        }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn files_and_checks() {
        let a = file_for(Path::new("/c"), "https://a.example/icon.png");
        assert_eq!(a, file_for(Path::new("/c"), "https://a.example/icon.png"));
        assert_ne!(a, file_for(Path::new("/c"), "https://b.example/icon.png"));
        assert_eq!(a.file_name().unwrap().len(), 32);
        assert!(fetchable("https://a.example/i.png"));
        assert!(!fetchable("http://a.example/i.png"));
        assert!(!fetchable("data:image/png;base64,AA"));
        assert!(looks_like_image(b"\x89PNG\r\n"));
        assert!(looks_like_image(b"<?xml version='1.0'?><svg xmlns=''>"));
        assert!(!looks_like_image(b"<!doctype html><html>404</html>"));
    }
}
