//! Rust half of libMarathonCore, called from marathon-core/src through cxx.

pub mod archive;
pub mod signature;
pub mod verify;

use std::path::Path;

#[cxx::bridge(namespace = "marathon::native")]
mod ffi {
    enum SignatureCheck {
        Valid,
        InvalidSignature,
        UntrustedKey,
        NoTrustedKeys,
        Failed,
    }

    struct SignatureVerdict {
        check: SignatureCheck,
        detail: String,
    }

    enum PackageCheck {
        Valid,
        Unsigned,
        InvalidSignature,
        UntrustedKey,
        RevokedKey,
        Failed,
    }

    struct PackageVerdict {
        check: PackageCheck,
        /// The signing key's id, when the signature names one.
        key_id: String,
        detail: String,
    }

    extern "Rust" {
        /// Empty on success, else why the archive couldn't be written.
        fn create_package_archive(source_dir: &str, archive: &str) -> String;
        /// Empty on success, else why the archive was refused or failed.
        fn extract_package_archive(archive: &str, dest_dir: &str) -> String;

        fn verify_manifest_signature(
            manifest: &str,
            signature: &str,
            trusted_keys_dir: &str,
        ) -> SignatureVerdict;

        /// Checks `<archive>.minisig` against the keys in `trusted_key_dirs`.
        fn verify_package_signature(archive: &str, trusted_key_dirs: &[String]) -> PackageVerdict;
        /// Writes `<archive>.minisig`. Empty on success, else why not.
        fn sign_package(archive: &str, secret_key: &str) -> String;
    }
}

fn create_package_archive(source_dir: &str, archive: &str) -> String {
    archive::create(Path::new(source_dir), Path::new(archive))
        .err()
        .unwrap_or_default()
}

fn extract_package_archive(archive: &str, dest_dir: &str) -> String {
    archive::extract(Path::new(archive), Path::new(dest_dir))
        .err()
        .unwrap_or_default()
}

fn verify_manifest_signature(
    manifest: &str,
    signature: &str,
    trusted_keys_dir: &str,
) -> ffi::SignatureVerdict {
    use ffi::{SignatureCheck, SignatureVerdict};
    use verify::Verdict;
    let verdict = verify::verify_file(
        Path::new(manifest),
        Path::new(signature),
        Path::new(trusted_keys_dir),
    );
    let (check, detail) = match verdict {
        Verdict::Valid => (SignatureCheck::Valid, String::new()),
        Verdict::InvalidSignature(detail) => (SignatureCheck::InvalidSignature, detail),
        Verdict::UntrustedKey => (SignatureCheck::UntrustedKey, String::new()),
        Verdict::NoTrustedKeys => (SignatureCheck::NoTrustedKeys, String::new()),
        Verdict::Failed(detail) => (SignatureCheck::Failed, detail),
    };
    SignatureVerdict { check, detail }
}

fn verify_package_signature(archive: &str, trusted_key_dirs: &[String]) -> ffi::PackageVerdict {
    use ffi::{PackageCheck, PackageVerdict};
    use signature::Verdict;
    let dirs: Vec<&Path> = trusted_key_dirs.iter().map(Path::new).collect();
    let verdict = match signature::TrustStore::load(&dirs) {
        Ok(store) => signature::verify(Path::new(archive), &store),
        Err(e) => Verdict::Failed(format!("Failed to load trusted keys: {e}")),
    };
    let (check, key_id, detail) = match verdict {
        Verdict::Valid(id) => (PackageCheck::Valid, id, String::new()),
        Verdict::Unsigned => (PackageCheck::Unsigned, String::new(), String::new()),
        Verdict::InvalidSignature(detail) => {
            (PackageCheck::InvalidSignature, String::new(), detail)
        }
        Verdict::UntrustedKey(id) => (PackageCheck::UntrustedKey, id, String::new()),
        Verdict::RevokedKey(id) => (PackageCheck::RevokedKey, id, String::new()),
        Verdict::Failed(detail) => (PackageCheck::Failed, String::new(), detail),
    };
    PackageVerdict {
        check,
        key_id,
        detail,
    }
}

fn sign_package(archive: &str, secret_key: &str) -> String {
    signature::sign(Path::new(archive), Path::new(secret_key))
        .err()
        .unwrap_or_default()
}
