//! A signed JAR's one entry, checked against a pinned signing certificate:
//! F-Droid's `entry.jar`. v1 JAR signing: the PKCS#7 block in
//! `META-INF/*.RSA` signs `*.SF` (RSA, PKCS#1 v1.5, SHA-256, no signed
//! attributes), `*.SF` holds the SHA-256 of `MANIFEST.MF`, and the manifest
//! holds the SHA-256 of each entry.

use std::io::{Cursor, Read};

use base64::Engine;
use sha2::{Digest, Sha256};

/// F-Droid's repository signing certificate (SHA-256 of its DER).
pub const FDROID_CERT_SHA256: &str =
    "43238d512c1e5eb2d6569f4a3afbf5523418b82e0a3ed1552770abb9a9c9ccab";

const OID_SHA256: &[u8] = &[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01];

/// One DER element: its tag, its contents, and what follows it.
fn element(input: &[u8]) -> Result<(u8, &[u8], &[u8]), String> {
    let (&tag, rest) = input.split_first().ok_or("truncated DER")?;
    let (&first, mut rest) = rest.split_first().ok_or("truncated DER")?;
    let len = if first < 0x80 {
        usize::from(first)
    } else {
        let count = usize::from(first & 0x7f);
        if count == 0 || count > 4 || rest.len() < count {
            return Err("bad DER length".into());
        }
        let (bytes, tail) = rest.split_at(count);
        rest = tail;
        bytes.iter().fold(0usize, |n, &b| (n << 8) | usize::from(b))
    };
    if rest.len() < len {
        return Err("truncated DER".into());
    }
    let (contents, tail) = rest.split_at(len);
    Ok((tag, contents, tail))
}

fn expect(input: &[u8], tag: u8) -> Result<(&[u8], &[u8]), String> {
    let (found, contents, tail) = element(input)?;
    if found != tag {
        return Err(format!("expected DER tag {tag:#x}, found {found:#x}"));
    }
    Ok((contents, tail))
}

/// The DER of an element, header included.
fn whole(input: &[u8]) -> Result<(&[u8], &[u8]), String> {
    let (_, _, tail) = element(input)?;
    Ok((&input[..input.len() - tail.len()], tail))
}

/// The certificate and the signature over the `.SF` file.
fn signer(pkcs7: &[u8]) -> Result<(&[u8], &[u8]), String> {
    let (content_info, _) = expect(pkcs7, 0x30)?;
    let (_oid, rest) = expect(content_info, 0x06)?;
    let (explicit, _) = expect(rest, 0xa0)?;
    let (signed_data, _) = expect(explicit, 0x30)?;
    let (_version, rest) = expect(signed_data, 0x02)?;
    let (_digests, rest) = expect(rest, 0x31)?;
    let (_content, rest) = expect(rest, 0x30)?;
    let (certs, rest) = expect(rest, 0xa0)?;
    let (cert, _) = whole(certs)?;
    let rest = match element(rest)? {
        (0xa1, _, tail) => tail,
        _ => rest,
    };
    let (signer_infos, _) = expect(rest, 0x31)?;
    let (info, _) = expect(signer_infos, 0x30)?;
    let (_version, rest) = expect(info, 0x02)?;
    let (_issuer_serial, rest) = expect(rest, 0x30)?;
    let (digest_alg, rest) = expect(rest, 0x30)?;
    let (oid, _) = expect(digest_alg, 0x06)?;
    if oid != OID_SHA256 {
        return Err("signature digest is not SHA-256".into());
    }
    if element(rest)?.0 == 0xa0 {
        return Err("signed attributes are not supported".into());
    }
    let (_sig_alg, rest) = expect(rest, 0x30)?;
    let (signature, _) = expect(rest, 0x04)?;
    Ok((cert, signature))
}

/// The `RSAPublicKey` inside a certificate's `SubjectPublicKeyInfo`.
fn rsa_key(cert: &[u8]) -> Result<&[u8], String> {
    let (certificate, _) = expect(cert, 0x30)?;
    let (tbs, _) = expect(certificate, 0x30)?;
    let rest = match element(tbs)? {
        (0xa0, _, tail) => tail,
        _ => tbs,
    };
    let (_serial, rest) = expect(rest, 0x02)?;
    let (_alg, rest) = expect(rest, 0x30)?;
    let (_issuer, rest) = expect(rest, 0x30)?;
    let (_validity, rest) = expect(rest, 0x30)?;
    let (_subject, rest) = expect(rest, 0x30)?;
    let (spki, _) = expect(rest, 0x30)?;
    let (_alg, rest) = expect(spki, 0x30)?;
    let (bits, _) = expect(rest, 0x03)?;
    match bits.split_first() {
        Some((0, key)) => Ok(key),
        _ => Err("bad public key bit string".into()),
    }
}

fn digest_b64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(Sha256::digest(bytes))
}

/// The `SHA-256-Digest` the manifest (or `.SF`) gives `name`'s section.
fn section_digest<'a>(text: &'a str, name: &str) -> Option<&'a str> {
    let mut in_section = false;
    for line in text.lines() {
        if let Some(n) = line.strip_prefix("Name: ") {
            in_section = n.trim() == name;
        } else if in_section {
            if let Some(d) = line.strip_prefix("SHA-256-Digest: ") {
                return Some(d.trim());
            }
        }
    }
    None
}

/// `entry`'s bytes, if `jar` is signed by the certificate whose SHA-256 is
/// `pinned` and every digest on the way matches.
pub fn verified_entry(jar: &[u8], entry: &str, pinned: &str) -> Result<Vec<u8>, String> {
    let mut archive = zip::ZipArchive::new(Cursor::new(jar)).map_err(|e| e.to_string())?;
    let mut read = |name: &str| -> Result<Vec<u8>, String> {
        let mut file = archive.by_name(name).map_err(|e| format!("{name}: {e}"))?;
        let mut out = Vec::new();
        file.read_to_end(&mut out)
            .map_err(|e| format!("{name}: {e}"))?;
        Ok(out)
    };
    let names: Vec<String> = zip::ZipArchive::new(Cursor::new(jar))
        .map_err(|e| e.to_string())?
        .file_names()
        .filter_map(Result::ok)
        .map(std::borrow::Cow::into_owned)
        .collect();
    let block = names
        .iter()
        .find(|n| {
            n.starts_with("META-INF/")
                && std::path::Path::new(n)
                    .extension()
                    .is_some_and(|e| e.eq_ignore_ascii_case("rsa"))
        })
        .ok_or("no signature block")?;
    let sf_name = format!("{}.SF", block.trim_end_matches(".RSA"));

    let pkcs7 = read(block)?;
    let sf = read(&sf_name)?;
    let manifest = read("META-INF/MANIFEST.MF")?;
    let content = read(entry)?;

    let (cert, signature) = signer(&pkcs7)?;
    if hex(&Sha256::digest(cert)) != pinned {
        return Err("signed by an unexpected certificate".into());
    }
    ring::signature::UnparsedPublicKey::new(
        &ring::signature::RSA_PKCS1_2048_8192_SHA256,
        rsa_key(cert)?,
    )
    .verify(&sf, signature)
    .map_err(|e| format!("bad signature: {e}"))?;

    let sf = String::from_utf8_lossy(&sf);
    let manifest_digest = sf
        .lines()
        .find_map(|l| l.strip_prefix("SHA-256-Digest-Manifest: "))
        .map(str::trim)
        .ok_or("no manifest digest")?;
    if manifest_digest != digest_b64(&manifest) {
        return Err("manifest digest mismatch".into());
    }
    let manifest = String::from_utf8_lossy(&manifest);
    if section_digest(&manifest, entry) != Some(digest_b64(&content).as_str()) {
        return Err(format!("{entry} digest mismatch"));
    }
    Ok(content)
}

pub fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    bytes
        .iter()
        .flat_map(|b| [DIGITS[usize::from(b >> 4)], DIGITS[usize::from(b & 0xf)]])
        .map(char::from)
        .collect()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    // entry.jar as f-droid.org served it on 2026-10-17.
    const ENTRY_JAR: &[u8] = include_bytes!("../tests/fdroid-entry.jar");

    #[test]
    fn verifies_fdroid_entry_jar() {
        let entry = verified_entry(ENTRY_JAR, "entry.json", FDROID_CERT_SHA256).unwrap();
        let json: serde_json::Value = serde_json::from_slice(&entry).unwrap();
        assert_eq!(json["index"]["name"], "/index-v2.json");
    }

    #[test]
    fn rejects_another_certificate() {
        let wrong = "00".repeat(32);
        assert!(verified_entry(ENTRY_JAR, "entry.json", &wrong).is_err());
    }

    #[test]
    fn rejects_a_changed_entry() {
        // Rewrite entry.json inside the zip; its digest no longer matches.
        let mut archive = zip::ZipArchive::new(Cursor::new(ENTRY_JAR)).unwrap();
        let mut out = zip::ZipWriter::new(Cursor::new(Vec::new()));
        for i in 0..archive.len() {
            let mut file = archive.by_index(i).unwrap();
            let name = file.name().unwrap().into_owned();
            let mut bytes = Vec::new();
            file.read_to_end(&mut bytes).unwrap();
            if name == "entry.json" {
                bytes = bytes.to_ascii_uppercase();
            }
            out.start_file(name, zip::write::SimpleFileOptions::default())
                .unwrap();
            std::io::Write::write_all(&mut out, &bytes).unwrap();
        }
        let tampered = out.finish().unwrap().into_inner();
        let err = verified_entry(&tampered, "entry.json", FDROID_CERT_SHA256).unwrap_err();
        assert!(err.contains("digest mismatch"), "{err}");
    }
}
