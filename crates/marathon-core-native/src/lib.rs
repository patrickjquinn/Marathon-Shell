//! Rust half of libMarathonCore, called from marathon-core/src through cxx.

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
        fn verify_manifest_signature(
            manifest: &str,
            signature: &str,
            trusted_keys_dir: &str,
        ) -> SignatureVerdict;
    }
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
