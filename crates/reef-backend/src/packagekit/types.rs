// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! `PackageKit`'s wire values. Numbers are from `PackageKit`'s `pk-enum.h`
//! (1.x); bitfields put bit `1 << value` for each enum value.

/// `PkFilterEnum` values used by Reef.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum Filter {
    None = 1,
    Installed = 2,
    NotInstalled = 3,
    Newest = 16,
    Arch = 18,
}

/// Builds a filter bitfield.
pub fn filter_bits(filters: &[Filter]) -> u64 {
    filters.iter().fold(0, |acc, f| acc | (1u64 << (*f as u32)))
}

/// `PkTransactionFlagEnum`: `ONLY_TRUSTED` is 1, so its bit is `1 << 1`.
/// Every install and update Reef starts sets it, so `PackageKit` refuses
/// packages whose signature does not verify against an imported key.
pub const TRANSACTION_FLAG_ONLY_TRUSTED: u64 = 1 << 1;

/// `PkTransactionFlagEnum` `SIMULATE` (2): `PackageKit` resolves the
/// transaction and reports every package it would install, update or
/// remove (`Package` signals), and changes nothing. Reef shows that list
/// before the person agrees to an install, update or removal.
pub const TRANSACTION_FLAG_SIMULATE: u64 = 1 << 2;

/// `PkInfoEnum`: what a `Package` signal says about a package.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Info {
    Installed,
    Available,
    Low,
    Enhancement,
    Normal,
    Bugfix,
    Important,
    Security,
    Downloading,
    Updating,
    Installing,
    Removing,
    /// Replaced by a package being installed (an RPM `Obsoletes`).
    Obsoleting,
    Finished,
    Reinstalling,
    Downgrading,
    Other(u32),
}

impl From<u32> for Info {
    fn from(v: u32) -> Self {
        match v {
            1 => Info::Installed,
            2 => Info::Available,
            3 => Info::Low,
            4 => Info::Enhancement,
            5 => Info::Normal,
            6 => Info::Bugfix,
            7 => Info::Important,
            8 => Info::Security,
            10 => Info::Downloading,
            11 => Info::Updating,
            12 => Info::Installing,
            13 => Info::Removing,
            15 => Info::Obsoleting,
            18 => Info::Finished,
            19 => Info::Reinstalling,
            20 => Info::Downgrading,
            other => Info::Other(other),
        }
    }
}

/// `PkStatusEnum`: the transaction's current phase, for progress text.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Wait,
    Setup,
    Running,
    Query,
    Remove,
    RefreshCache,
    Download,
    Install,
    Update,
    Cleanup,
    DepResolve,
    SigCheck,
    Commit,
    Finished,
    Other(u32),
}

impl From<u32> for Status {
    fn from(v: u32) -> Self {
        match v {
            1 => Status::Wait,
            2 => Status::Setup,
            3 => Status::Running,
            4 => Status::Query,
            6 => Status::Remove,
            7 => Status::RefreshCache,
            8 => Status::Download,
            9 => Status::Install,
            10 => Status::Update,
            11 => Status::Cleanup,
            13 => Status::DepResolve,
            14 => Status::SigCheck,
            16 => Status::Commit,
            18 => Status::Finished,
            other => Status::Other(other),
        }
    }
}

/// `PkExitEnum`: how a transaction ended.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Exit {
    Success,
    Failed,
    Cancelled,
    KeyRequired,
    EulaRequired,
    Killed,
    NeedUntrusted,
    Other(u32),
}

impl From<u32> for Exit {
    fn from(v: u32) -> Self {
        match v {
            1 => Exit::Success,
            2 => Exit::Failed,
            3 => Exit::Cancelled,
            4 => Exit::KeyRequired,
            5 => Exit::EulaRequired,
            6 => Exit::Killed,
            8 => Exit::NeedUntrusted,
            other => Exit::Other(other),
        }
    }
}

/// A `PackageKit` package id, `name;version;arch;data`. For available
/// packages `data` is the repository alias; for installed ones it is
/// `installed` (possibly with the origin repository after a colon).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct PackageId {
    pub raw: String,
    pub name: String,
    pub version: String,
    pub arch: String,
    pub data: String,
}

impl PackageId {
    pub fn parse(raw: &str) -> Option<Self> {
        let mut it = raw.split(';');
        let (name, version, arch, data) = (it.next()?, it.next()?, it.next()?, it.next()?);
        if name.is_empty() || it.next().is_some() {
            return None;
        }
        Some(Self {
            raw: raw.to_string(),
            name: name.into(),
            version: version.into(),
            arch: arch.into(),
            data: data.into(),
        })
    }

    pub fn is_installed(&self) -> bool {
        self.data == "installed" || self.data.starts_with("installed:")
    }

    /// Whether this package comes from repository `alias`.
    pub fn from_repo(&self, alias: &str) -> bool {
        self.data == alias || self.data.strip_prefix("installed:") == Some(alias)
    }
}

/// One `Package` signal.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PackageInfo {
    pub info: Info,
    pub id: PackageId,
    pub summary: String,
}

/// Progress of a running transaction, for the UI.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Progress {
    /// 0 to 100, or `None` when `PackageKit` does not know (it sends 101).
    pub percentage: Option<u32>,
    pub status: Status,
    /// The package id `ItemProgress` refers to, if any.
    pub item: Option<String>,
}

pub(crate) fn percentage(raw: u32) -> Option<u32> {
    (raw <= 100).then_some(raw)
}

/// One transaction's progress as a single 0 to 100, from what `PackageKit`'s
/// zypp backend actually reports: its own `Percentage` restarts for every
/// preparation step (refresh, dependency resolution) and stays at 0 while
/// packages download, and each package's `ItemProgress` runs 0 to 100 once
/// to download it and once more to install it. So: nothing known while
/// preparing (the bar is busy), downloading is the first half and
/// installing the second (or all of it, with nothing to download), each
/// spread across the packages announced for that step.
#[derive(Debug, Default)]
pub struct Overall {
    downloads: Vec<String>,
    applies: Vec<String>,
    downloaded_any: bool,
    value: Option<u32>,
}

impl Overall {
    /// A `Package` signal: `info` says which step `id` is in.
    pub fn package(&mut self, info: Info, id: &str) {
        let list = match info {
            Info::Downloading => &mut self.downloads,
            Info::Installing | Info::Updating | Info::Removing => &mut self.applies,
            _ => return,
        };
        if !list.iter().any(|x| x == id) {
            list.push(id.to_owned());
        }
    }

    /// An `ItemProgress` signal; returns the overall percentage so far.
    pub fn item(&mut self, id: &str, status: Status, pct: Option<u32>) -> Option<u32> {
        let Some(pct) = pct else { return self.value };
        let download = status == Status::Download;
        let list = if download {
            self.downloaded_any = true;
            &mut self.downloads
        } else {
            &mut self.applies
        };
        let i = list.iter().position(|x| x == id).unwrap_or_else(|| {
            list.push(id.to_owned());
            list.len() - 1
        });
        let n = list.len();
        let (base, width) = match (download, self.downloaded_any) {
            (true, _) => (0, 50),
            (false, true) => (50, 50),
            (false, false) => (0, 100),
        };
        // Within the step the packages before this one are done: the step
        // is (i + pct / 100) / n of the way through, rounded to nearest.
        let done = u64::try_from(i).unwrap_or(u64::MAX) * 100 + u64::from(pct.min(100));
        let all = u64::try_from(n).unwrap_or(u64::MAX).max(1) * 100;
        let v = base + (done * width + all / 2) / all;
        self.value = Some(u32::try_from(v.min(100)).unwrap_or(100));
        self.value
    }

    /// The overall percentage so far (`None` while preparing).
    pub fn value(&self) -> Option<u32> {
        self.value
    }
}

/// What one operation's progress bar shows: `PackageKit`'s overall
/// percentage, which can step back between its download and install
/// phases, held so that it only ever moves forward, and only the changes
/// (`PackageKit` repeats itself a lot). Make one per operation.
#[derive(Debug, Default)]
pub struct SteadyProgress {
    shown: Option<u32>,
    last: Option<(Option<u32>, Status)>,
}

impl SteadyProgress {
    /// The progress to show for `p`, or `None` when nothing visible changed.
    pub fn next(&mut self, mut p: Progress) -> Option<Progress> {
        self.shown = match (self.shown, p.percentage) {
            (Some(a), Some(b)) => Some(a.max(b)),
            (a, b) => a.or(b),
        };
        p.percentage = self.shown;
        let key = (p.percentage, p.status);
        if self.last == Some(key) {
            return None;
        }
        self.last = Some(key);
        Some(p)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filter_bitfields_match_packagekit_qt() {
        // PackageKit-Qt: FilterInstalled = 0x4, FilterNotInstalled = 0x8,
        // FilterNewest = 0x10000.
        assert_eq!(filter_bits(&[Filter::Installed]), 0x4);
        assert_eq!(filter_bits(&[Filter::NotInstalled]), 0x8);
        assert_eq!(filter_bits(&[Filter::Newest]), 0x10000);
        assert_eq!(filter_bits(&[Filter::None]), 0x2);
        assert_eq!(TRANSACTION_FLAG_ONLY_TRUSTED, 0x2);
        // PackageKit-Qt: TransactionFlagSimulate = 1 << 2.
        assert_eq!(TRANSACTION_FLAG_SIMULATE, 0x4);
    }

    #[test]
    fn parses_package_ids() {
        let id =
            PackageId::parse("shipwright-keel-silica;0.1.0-1;aarch64;shipwright-reef").unwrap();
        assert_eq!(id.name, "shipwright-keel-silica");
        assert!(id.from_repo("shipwright-reef"));
        assert!(!id.is_installed());
        let inst = PackageId::parse("bash;5.0-1;aarch64;installed").unwrap();
        assert!(inst.is_installed());
        assert!(!inst.from_repo("shipwright-reef"));
        let origin = PackageId::parse("x;1;noarch;installed:shipwright-reef").unwrap();
        assert!(origin.is_installed() && origin.from_repo("shipwright-reef"));
        assert!(PackageId::parse("a;b;c").is_none());
        assert!(PackageId::parse(";1;a;d").is_none());
        assert!(PackageId::parse("a;1;a;d;e").is_none());
    }

    #[test]
    fn enums_map_unknowns() {
        assert_eq!(Exit::from(1), Exit::Success);
        assert_eq!(Exit::from(99), Exit::Other(99));
        assert_eq!(Info::from(8), Info::Security);
        assert_eq!(Info::from(15), Info::Obsoleting);
        assert_eq!(Info::from(20), Info::Downgrading);
        assert_eq!(Status::from(14), Status::SigCheck);
        assert_eq!(percentage(101), None);
        assert_eq!(percentage(42), Some(42));
    }

    #[test]
    fn overall_is_download_then_install() {
        let mut o = Overall::default();
        assert_eq!(o.value(), None);
        o.package(Info::Downloading, "a");
        o.package(Info::Downloading, "b");
        assert_eq!(o.item("a", Status::Download, Some(50)), Some(13));
        assert_eq!(o.item("a", Status::Download, Some(100)), Some(25));
        assert_eq!(o.item("b", Status::Download, Some(100)), Some(50));
        assert_eq!(o.item("a", Status::Install, Some(1)), Some(51));
        o.package(Info::Installing, "b");
        assert_eq!(o.item("a", Status::Install, Some(100)), Some(75));
        assert_eq!(o.item("b", Status::Install, Some(100)), Some(100));
        // Unknown (101) changes nothing.
        assert_eq!(o.item("b", Status::Install, None), Some(100));
    }

    #[test]
    fn overall_without_downloads_is_all_install() {
        let mut o = Overall::default();
        o.package(Info::Removing, "a");
        assert_eq!(o.item("a", Status::Remove, Some(40)), Some(40));
    }

    #[test]
    fn steady_progress_only_moves_forward() {
        let p = |pct: Option<u32>, status: u32| Progress {
            percentage: pct,
            status: status.into(),
            item: None,
        };
        let mut s = SteadyProgress::default();
        let shown = |s: &mut SteadyProgress, pct, st| s.next(p(pct, st)).map(|x| x.percentage);
        assert_eq!(shown(&mut s, None, 8), Some(None));
        assert_eq!(shown(&mut s, Some(10), 8), Some(Some(10)));
        assert_eq!(shown(&mut s, Some(40), 8), Some(Some(40)));
        // Back to 5 when installing starts: the bar stays, the status moves.
        assert_eq!(shown(&mut s, Some(5), 9), Some(Some(40)));
        // Unknown for a moment, or the same again: nothing new to show.
        assert_eq!(shown(&mut s, None, 9), None);
        assert_eq!(shown(&mut s, Some(30), 9), None);
        assert_eq!(shown(&mut s, Some(70), 9), Some(Some(70)));
    }
}
