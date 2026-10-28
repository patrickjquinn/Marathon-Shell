// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Camera frames before they leave the device (spec section 6.1: "camera
//! frame downscaled and EXIF-stripped on the device before upload").
//!
//! The app downscales and re-encodes the photo (Qt's `QImage`, see
//! `app/cpp/launcher.cpp`); pilotd does not trust that and checks the
//! result itself without decoding it: a baseline or progressive JPEG, no
//! larger than [`MAX_SIDE`] pixels on its long side and [`MAX_BYTES`] in
//! size. Every metadata segment (APP0 to APP15: JFIF thumbnails, EXIF with
//! GPS and the camera serial, XMP, ICC, maker notes; and COM comments) is
//! dropped, and so is anything after the first image's end marker (where
//! multi-picture files keep further images). What remains is the frame
//! header, tables and scan data, byte for byte.

use std::fmt::Write as _;

/// Longest side accepted, in pixels.
pub const MAX_SIDE: u16 = 1600;
/// Largest JPEG accepted; base64 adds a third, and the relay takes 4 MB.
pub const MAX_BYTES: usize = 1_500_000;

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum PhotoError {
    #[error("not a JPEG image")]
    NotJpeg,
    #[error("the photo is damaged")]
    Truncated,
    #[error("the photo is too large ({0} bytes)")]
    TooLarge(usize),
    #[error("the photo is {0}x{1} pixels; at most {MAX_SIDE} on a side")]
    TooWide(u16, u16),
}

/// A checked, metadata-free JPEG.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Photo {
    pub jpeg: Vec<u8>,
    pub width: u16,
    pub height: u16,
}

impl Photo {
    /// As an `image_url` for the chat request.
    pub fn data_url(&self) -> String {
        let mut s = String::with_capacity(self.jpeg.len() * 4 / 3 + 32);
        s.push_str("data:image/jpeg;base64,");
        base64(&self.jpeg, &mut s);
        s
    }
}

fn be16(b: &[u8], i: usize) -> Option<u16> {
    Some(u16::from_be_bytes([*b.get(i)?, *b.get(i + 1)?]))
}

/// Checks `input` and returns it without metadata.
pub fn prepare(input: &[u8]) -> Result<Photo, PhotoError> {
    if input.len() > MAX_BYTES {
        return Err(PhotoError::TooLarge(input.len()));
    }
    if input.get(..2) != Some(&[0xFF, 0xD8]) {
        return Err(PhotoError::NotJpeg);
    }
    let mut out = vec![0xFF, 0xD8];
    let mut size = None;
    let mut i = 2;
    loop {
        // Fill bytes (0xFF) may precede a marker.
        while input.get(i) == Some(&0xFF) && input.get(i + 1) == Some(&0xFF) {
            i += 1;
        }
        if input.get(i) != Some(&0xFF) {
            return Err(PhotoError::Truncated);
        }
        let marker = *input.get(i + 1).ok_or(PhotoError::Truncated)?;
        match marker {
            0xD9 => {
                out.extend_from_slice(&[0xFF, 0xD9]);
                break;
            }
            // Standalone markers outside a scan: keep.
            0x01 | 0xD0..=0xD7 => {
                out.extend_from_slice(&input[i..i + 2]);
                i += 2;
                continue;
            }
            _ => {}
        }
        let len = usize::from(be16(input, i + 2).ok_or(PhotoError::Truncated)?);
        let end = i + 2 + len;
        if len < 2 || end > input.len() {
            return Err(PhotoError::Truncated);
        }
        let segment = &input[i..end];
        match marker {
            // APPn and COM: metadata, dropped.
            0xE0..=0xEF | 0xFE => {}
            // SOFn (not DHT 0xC4, JPG 0xC8, DAC 0xCC): the frame size.
            0xC0..=0xCF if !matches!(marker, 0xC4 | 0xC8 | 0xCC) => {
                let h = be16(segment, 5).ok_or(PhotoError::Truncated)?;
                let w = be16(segment, 7).ok_or(PhotoError::Truncated)?;
                if w == 0 || h == 0 {
                    return Err(PhotoError::Truncated);
                }
                if w > MAX_SIDE || h > MAX_SIDE {
                    return Err(PhotoError::TooWide(w, h));
                }
                size = Some((w, h));
                out.extend_from_slice(segment);
            }
            _ => out.extend_from_slice(segment),
        }
        i = end;
        if marker == 0xDA {
            // Entropy-coded data runs to the next marker that is not a
            // stuffed zero or a restart.
            let start = i;
            loop {
                let b = *input.get(i).ok_or(PhotoError::Truncated)?;
                if b == 0xFF {
                    let next = *input.get(i + 1).ok_or(PhotoError::Truncated)?;
                    if next != 0x00 && !(0xD0..=0xD7).contains(&next) {
                        break;
                    }
                    i += 2;
                } else {
                    i += 1;
                }
            }
            out.extend_from_slice(&input[start..i]);
        }
    }
    let (width, height) = size.ok_or(PhotoError::NotJpeg)?;
    Ok(Photo {
        jpeg: out,
        width,
        height,
    })
}

fn base64(data: &[u8], out: &mut String) {
    const A: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for c in data.chunks(3) {
        let n = (u32::from(c[0]) << 16)
            | (u32::from(*c.get(1).unwrap_or(&0)) << 8)
            | u32::from(*c.get(2).unwrap_or(&0));
        let idx = |s: u32| char::from(A[((n >> s) & 63) as usize]);
        let _ = write!(out, "{}{}", idx(18), idx(12));
        out.push(if c.len() > 1 { idx(6) } else { '=' });
        out.push(if c.len() > 2 { idx(0) } else { '=' });
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    fn seg(marker: u8, payload: &[u8]) -> Vec<u8> {
        let len = u16::try_from(payload.len() + 2).unwrap().to_be_bytes();
        let mut v = vec![0xFF, marker, len[0], len[1]];
        v.extend_from_slice(payload);
        v
    }

    /// A structurally complete JPEG with the given metadata segments.
    pub fn jpeg(w: u16, h: u16, meta: &[Vec<u8>]) -> Vec<u8> {
        let mut v = vec![0xFF, 0xD8];
        for m in meta {
            v.extend_from_slice(m);
        }
        v.extend(seg(0xDB, &[0; 65]));
        let (wb, hb) = (w.to_be_bytes(), h.to_be_bytes());
        v.extend(seg(0xC0, &[8, hb[0], hb[1], wb[0], wb[1], 1, 1, 0x11, 0]));
        v.extend(seg(0xC4, &[0; 20]));
        v.extend(seg(0xDA, &[1, 1, 0, 0, 63, 0]));
        // Scan data with a stuffed 0xFF00 and a restart marker.
        v.extend_from_slice(&[0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD0, 0x56]);
        v.extend_from_slice(&[0xFF, 0xD9]);
        v
    }

    pub fn exif() -> Vec<u8> {
        seg(0xE1, b"Exif\0\0GPS 60.1699N 24.9384E serial 1234")
    }

    #[test]
    fn strips_metadata_and_trailers() {
        let jfif = seg(0xE0, b"JFIF\0\x01\x01\0\0\x01\0\x01\0\0");
        let com = seg(0xFE, b"taken at home");
        let clean = jpeg(640, 480, &[]);
        let mut input = jpeg(640, 480, &[jfif, exif(), com]);
        // A second image after the first one's end (multi-picture files).
        input.extend_from_slice(&jpeg(64, 64, &[exif()]));
        let p = prepare(&input).unwrap();
        assert_eq!(p.jpeg, clean);
        assert_eq!((p.width, p.height), (640, 480));
        let text = String::from_utf8_lossy(&p.jpeg);
        assert!(!text.contains("GPS") && !text.contains("JFIF") && !text.contains("home"));
        assert!(p.data_url().starts_with("data:image/jpeg;base64,/9j/"));
    }

    #[test]
    fn rejects_what_it_cannot_check() {
        assert_eq!(prepare(b"\x89PNG\r\n"), Err(PhotoError::NotJpeg));
        assert_eq!(
            prepare(&jpeg(4000, 3000, &[])),
            Err(PhotoError::TooWide(4000, 3000))
        );
        let whole = jpeg(640, 480, &[]);
        assert_eq!(
            prepare(&whole[..whole.len() - 4]),
            Err(PhotoError::Truncated)
        );
        assert!(matches!(
            prepare(&vec![0; MAX_BYTES + 1]),
            Err(PhotoError::TooLarge(_))
        ));
        // No frame header at all.
        assert_eq!(prepare(&[0xFF, 0xD8, 0xFF, 0xD9]), Err(PhotoError::NotJpeg));
    }

    #[test]
    fn base64_matches_the_rfc() {
        for (i, o) in [
            ("", ""),
            ("f", "Zg=="),
            ("fo", "Zm8="),
            ("foo", "Zm9v"),
            ("foobar", "Zm9vYmFy"),
        ] {
            let mut s = String::new();
            base64(i.as_bytes(), &mut s);
            assert_eq!(s, o);
        }
    }
}
