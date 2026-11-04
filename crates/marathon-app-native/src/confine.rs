//! The runner's own confinement inside the shell's bwrap, before it starts a
//! thread or loads app code: a seccomp deny list and Landlock. Both are best
//! effort; a kernel without one still runs the app.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use cxx_qt_lib::QString;
use landlock::{
    Access, AccessFs, BitFlags, PathBeneath, PathFd, RestrictionStatus, Ruleset, RulesetAttr,
    RulesetCreatedAttr, RulesetError, RulesetStatus, Scope, ABI,
};
use marathon_rt::log;
use seccompiler::{
    BpfProgram, SeccompAction, SeccompCmpArgLen, SeccompCmpOp, SeccompCondition, SeccompFilter,
    SeccompRule, TargetArch,
};

// The generic ioctl numbers, which all of seccompiler's architectures use.
const TIOCSTI: u64 = 0x5412;
const TIOCLINUX: u64 = 0x541C;

/// Confines the runner of `app_id`, empty for a spare. WebEngine apps keep
/// namespaces and every path: Chromium nests its own namespace sandbox and
/// keeps its profile in the tmpfs home. Camera apps keep namespaces:
/// libcamera runs an IPA module it cannot verify in a user namespace.
pub fn confine(app_id: &QString) {
    // Set only by the shell's bwrap: what the app may write.
    let Some(writable) = std::env::var_os("MARATHON_SANDBOX_WRITABLE") else {
        return;
    };
    let writable: Vec<PathBuf> = std::env::split_paths(&writable).collect();
    let app = marathon_apps::apps::find(&app_id.to_string());
    let webengine = app
        .as_ref()
        .is_some_and(|a| a.requires_qt_modules.iter().any(|m| m == "webengine"));
    let camera = app.is_some_and(|a| a.permissions.iter().any(|p| p == "camera"));
    match landlock(&writable, !webengine) {
        Ok(status) if status.ruleset == RulesetStatus::NotEnforced => {
            log::warn("sandbox", "Landlock not enforced");
        }
        Ok(_) => {}
        Err(e) => log::warn("sandbox", format_args!("no Landlock: {e}")),
    }
    if let Err(e) = seccomp(webengine || camera) {
        log::warn("sandbox", format_args!("no seccomp filter: {e}"));
    }
}

fn landlock(writable: &[PathBuf], files: bool) -> Result<RestrictionStatus, RulesetError> {
    let abi = ABI::V6;
    let mut scopes = BitFlags::from(Scope::Signal);
    // A session bus on an abstract socket is created outside the domain.
    if !std::env::var("DBUS_SESSION_BUS_ADDRESS").is_ok_and(|a| a.contains("abstract=")) {
        scopes |= Scope::AbstractUnixSocket;
    }
    let ruleset = Ruleset::default().scope(scopes)?;
    if !files {
        return ruleset.create()?.restrict_self();
    }
    let read = AccessFs::from_read(abi);
    let special = read | AccessFs::WriteFile | AccessFs::Truncate;
    let rules = [
        (Path::new("/"), read),
        (Path::new("/proc"), special),
        (Path::new("/dev"), special | AccessFs::IoctlDev),
    ]
    .into_iter()
    .chain(
        writable
            .iter()
            .map(|p| (p.as_path(), AccessFs::from_all(abi))),
    );
    let mut ruleset = ruleset.handle_access(AccessFs::from_all(abi))?.create()?;
    for (path, access) in rules {
        // bind-try paths may be missing.
        if let Ok(fd) = PathFd::new(path) {
            ruleset = ruleset.add_rule(PathBeneath::new(fd, access))?;
        }
    }
    ruleset.restrict_self()
}

fn seccomp(namespaces: bool) -> seccompiler::Result<()> {
    let arch = TargetArch::try_from(std::env::consts::ARCH)?;
    let arg = |index, op, value| SeccompCondition::new(index, SeccompCmpArgLen::Dword, op, value);
    let mut denied: BTreeMap<i64, Vec<SeccompRule>> = [
        libc::SYS_syslog,
        libc::SYS_acct,
        libc::SYS_quotactl,
        libc::SYS_add_key,
        libc::SYS_keyctl,
        libc::SYS_request_key,
        libc::SYS_perf_event_open,
        libc::SYS_bpf,
        libc::SYS_userfaultfd,
        libc::SYS_kexec_load,
        libc::SYS_init_module,
        libc::SYS_finit_module,
        libc::SYS_delete_module,
        libc::SYS_mount,
        libc::SYS_umount2,
        libc::SYS_pivot_root,
        libc::SYS_setns,
    ]
    .into_iter()
    .map(|n| (n, Vec::new()))
    .collect();
    // Typing into the controlling terminal (CVE-2017-5226, CVE-2023-28100).
    denied.insert(
        libc::SYS_ioctl,
        vec![
            SeccompRule::new(vec![arg(1, SeccompCmpOp::Eq, TIOCSTI)?])?,
            SeccompRule::new(vec![arg(1, SeccompCmpOp::Eq, TIOCLINUX)?])?,
        ],
    );
    // Anything but PER_LINUX, or a query.
    denied.insert(
        libc::SYS_personality,
        vec![SeccompRule::new(vec![
            arg(0, SeccompCmpOp::Ne, 0)?,
            arg(0, SeccompCmpOp::Ne, 0xffff_ffff)?,
        ])?],
    );
    if !namespaces {
        let newuser = u64::from(libc::CLONE_NEWUSER.unsigned_abs());
        denied.insert(libc::SYS_unshare, Vec::new());
        denied.insert(libc::SYS_chroot, Vec::new());
        denied.insert(
            libc::SYS_clone,
            vec![SeccompRule::new(vec![arg(
                0,
                SeccompCmpOp::MaskedEq(newuser),
                newuser,
            )?])?],
        );
    }
    // ENOSYS, as if the kernel lacked them, so callers fall back; seccomp
    // cannot read clone3's flags.
    let missing: BTreeMap<i64, Vec<SeccompRule>> = [
        libc::SYS_clone3,
        libc::SYS_open_tree,
        libc::SYS_move_mount,
        libc::SYS_fsopen,
        libc::SYS_fsconfig,
        libc::SYS_fsmount,
        libc::SYS_fspick,
        libc::SYS_mount_setattr,
        libc::SYS_io_uring_setup,
    ]
    .into_iter()
    .map(|n| (n, Vec::new()))
    .collect();
    for (rules, errno) in [(denied, libc::EPERM), (missing, libc::ENOSYS)] {
        let program: BpfProgram = SeccompFilter::new(
            rules,
            SeccompAction::Allow,
            SeccompAction::Errno(errno.unsigned_abs()),
            arch,
        )?
        .try_into()?;
        seccompiler::apply_filter(&program)?;
    }
    Ok(())
}
