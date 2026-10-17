//! Rust half of libMarathonCore, called from marathon-core/src through cxx.

pub mod archive;
pub mod manifest;
pub mod permissions;
pub mod signature;

use std::path::Path;

#[cxx::bridge(namespace = "marathon::native")]
mod ffi {
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

    struct PermissionDisclosure {
        /// False when the permission has no wording: refuse the package.
        known: bool,
        label: String,
        detail: String,
        sensitive: bool,
    }

    struct LintFinding {
        error: bool,
        rule: String,
        path: String,
        message: String,
    }

    struct PermissionInfo {
        name: String,
        label: String,
        description: String,
        sensitive: bool,
        restricted: bool,
    }

    extern "Rust" {
        /// Empty on success, else why the archive couldn't be written.
        fn create_package_archive(source_dir: &str, archive: &str) -> String;
        /// Empty on success, else why the archive was refused or failed.
        fn extract_package_archive(archive: &str, dest_dir: &str) -> String;

        /// Checks `<archive>.minisig` against the keys in `trusted_key_dirs`.
        fn verify_package_signature(archive: &str, trusted_key_dirs: &[String]) -> PackageVerdict;
        /// Writes `<archive>.minisig`. Empty on success, else why not.
        fn sign_package(archive: &str, secret_key: &str) -> String;

        /// The install screen's words for one manifest permission.
        fn describe_permission(id: &str) -> PermissionDisclosure;
        /// The permission a name or alias means; empty if none.
        fn canonical_permission(name: &str) -> String;

        /// Lints an app directory or `.marathon` package
        /// (docs/APP_MANIFEST_SCHEMA.md).
        fn lint_app(path: &str, system_app: bool) -> Vec<LintFinding>;

        /// schemas/marathon-permissions-v1.json.
        fn permission_vocabulary() -> Vec<PermissionInfo>;
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

fn describe_permission(id: &str) -> ffi::PermissionDisclosure {
    permissions::describe(id).map_or(
        ffi::PermissionDisclosure {
            known: false,
            label: String::new(),
            detail: String::new(),
            sensitive: false,
        },
        |p| ffi::PermissionDisclosure {
            known: true,
            label: p.label.clone(),
            detail: p.description.clone(),
            sensitive: p.sensitive,
        },
    )
}

fn canonical_permission(name: &str) -> String {
    permissions::canonical(name).unwrap_or_default().to_owned()
}

fn lint_app(path: &str, system_app: bool) -> Vec<ffi::LintFinding> {
    let path = Path::new(path);
    let findings = if path.is_dir() {
        manifest::lint_dir(path, system_app)
    } else {
        manifest::lint_package(path, system_app)
    };
    findings
        .into_iter()
        .map(|f| ffi::LintFinding {
            error: f.error,
            rule: f.rule.to_owned(),
            path: f.path,
            message: f.message,
        })
        .collect()
}

fn permission_vocabulary() -> Vec<ffi::PermissionInfo> {
    permissions::permissions()
        .iter()
        .map(|(name, p)| ffi::PermissionInfo {
            name: name.clone(),
            label: p.label.clone(),
            description: p.description.clone(),
            sensitive: p.sensitive,
            restricted: p.restricted,
        })
        .collect()
}
