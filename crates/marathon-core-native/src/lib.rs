//! Rust half of libMarathonCore, called from marathon-core/src through cxx.

pub mod archive;
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
