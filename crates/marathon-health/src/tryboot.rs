//! Raspberry Pi firmware A/B boot. `autoboot.txt` on partition 1 names the
//! committed boot partition (`[all]`) and the one `reboot '0 tryboot'` tries
//! once (`[tryboot]`). systemd-sysupdate writes a new version into the free
//! slot pair, labelled `marathon_<version>_boot` and `marathon_<version>_root`.

use std::cmp::Ordering;
use std::fs::OpenOptions;
use std::io::{self, Read, Seek, SeekFrom, Write};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const DT_TRYBOOT: &str = "/proc/device-tree/chosen/bootloader/tryboot";
pub const DT_PARTITION: &str = "/proc/device-tree/chosen/bootloader/partition";
pub const STATE: &str = "/var/lib/marathon-health/tryboot";
pub const REBOOT_PARAM: &str = "/run/systemd/reboot-param";
const MOUNT_DIR: &str = "/run/marathon-health/autoboot";
const OS_RELEASE: &str = "/usr/lib/os-release";
const BOOT_ID: &str = "/proc/sys/kernel/random/boot_id";
/// "Erase all content" is pending: the initramfs of this slot erases the
/// data partition at the next boot (docs/FACTORY_RESET.md).
const FACTORY_RESET: &str = "/.marathon-factory-reset";

/// Microsoft basic data: the FAT boot slots.
pub const BOOT_TYPE: &str = "ebd0a0a2-b9e5-4433-87c0-68b6b72699c7";
/// Root, arm64.
pub const ROOT_TYPE: &str = "b921b045-1df0-41c3-af44-4c6f280d3fae";
pub const AUTOBOOT_LABEL: &str = "marathon_autoboot";
/// Trial boots per version before it is left alone.
pub const MAX_TRIES: u32 = 2;

/// A device-tree cell: one big-endian u32.
pub fn be_u32(raw: &[u8]) -> Option<u32> {
    Some(u32::from_be_bytes(raw.get(..4)?.try_into().ok()?))
}

fn read_be_u32(path: &str) -> Option<u32> {
    be_u32(&std::fs::read(path).ok()?)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Autoboot {
    pub all: u32,
    pub tryboot: u32,
}

impl Autoboot {
    /// `boot_partition` under `[all]` and `[tryboot]`, with `tryboot_a_b=1`.
    pub fn parse(text: &str) -> Option<Self> {
        let (mut section, mut a_b) = ("all", false);
        let (mut all, mut tryboot) = (None, None);
        for line in text.lines().map(str::trim) {
            if let Some(name) = line.strip_prefix('[').and_then(|l| l.strip_suffix(']')) {
                section = if name == "tryboot" { "tryboot" } else { "all" };
                continue;
            }
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            match (section, key.trim()) {
                ("all", "tryboot_a_b") => a_b = value.trim() == "1",
                ("all", "boot_partition") => all = value.trim().parse().ok(),
                ("tryboot", "boot_partition") => tryboot = value.trim().parse().ok(),
                _ => {}
            }
        }
        a_b.then_some(Self {
            all: all?,
            tryboot: tryboot?,
        })
    }

    pub fn render(self) -> String {
        format!(
            "[all]\ntryboot_a_b=1\nboot_partition={}\n[tryboot]\nboot_partition={}\n",
            self.all, self.tryboot
        )
    }

    /// The trial boot on `booted` succeeded: boot it from now on, and keep
    /// the previous one as the slot to try. `None` when it already is.
    pub fn committed(self, booted: u32) -> Option<Self> {
        (self.all != booted).then_some(Self {
            all: booted,
            tryboot: self.all,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Partition {
    pub path: PathBuf,
    pub number: u32,
    /// First sector, in 512-byte sectors as sysfs counts them.
    pub start: u64,
    pub ptype: String,
    pub label: String,
}

/// A GPT GUID as text: the first three fields are little-endian.
fn guid(raw: &[u8; 16]) -> String {
    format!(
        "{:08x}-{:04x}-{:04x}-{:02x}{:02x}-{:012x}",
        u32::from_le_bytes([raw[0], raw[1], raw[2], raw[3]]),
        u16::from_le_bytes([raw[4], raw[5]]),
        u16::from_le_bytes([raw[6], raw[7]]),
        raw[8],
        raw[9],
        raw[10..]
            .iter()
            .fold(0u64, |node, &b| (node << 8) | u64::from(b))
    )
}

/// The used entries of the primary GPT on `dev`, named as partitions of
/// `disk` (`/dev/mmcblk0` has `/dev/mmcblk0p1`, `/dev/sda` has `/dev/sda1`).
pub fn read_gpt<D: Read + Seek>(
    dev: &mut D,
    sector: u64,
    disk: &Path,
) -> io::Result<Vec<Partition>> {
    let bad = |what: &str| io::Error::new(io::ErrorKind::InvalidData, what.to_owned());
    let mut header = [0u8; 92];
    dev.seek(SeekFrom::Start(sector))?;
    dev.read_exact(&mut header)?;
    if &header[..8] != b"EFI PART" {
        return Err(bad("no GPT"));
    }
    let entries_lba = u64::from_le_bytes(
        header[0x48..0x50]
            .try_into()
            .map_err(|_e| bad("GPT header"))?,
    );
    let count = u32::from_le_bytes(
        header[0x50..0x54]
            .try_into()
            .map_err(|_e| bad("GPT header"))?,
    );
    let size = u32::from_le_bytes(
        header[0x54..0x58]
            .try_into()
            .map_err(|_e| bad("GPT header"))?,
    );
    if size < 128 || count > 1024 {
        return Err(bad("GPT entry table"));
    }
    let disk_name = disk.to_string_lossy();
    let sep = if disk_name.ends_with(|c: char| c.is_ascii_digit()) {
        "p"
    } else {
        ""
    };
    let mut table = vec![0u8; count as usize * size as usize];
    dev.seek(SeekFrom::Start(entries_lba * sector))?;
    dev.read_exact(&mut table)?;
    let mut parts = Vec::new();
    for (index, entry) in table.chunks_exact(size as usize).enumerate() {
        let ptype: [u8; 16] = entry[..16].try_into().map_err(|_e| bad("GPT entry"))?;
        if ptype == [0; 16] {
            continue;
        }
        let units: Vec<u16> = entry[56..128]
            .as_chunks::<2>()
            .0
            .iter()
            .map(|&pair| u16::from_le_bytes(pair))
            .take_while(|&u| u != 0)
            .collect();
        let number = u32::try_from(index + 1).map_err(|_e| bad("GPT entry"))?;
        parts.push(Partition {
            path: PathBuf::from(format!("{disk_name}{sep}{number}")),
            number,
            start: u64::from_le_bytes(entry[32..40].try_into().map_err(|_e| bad("GPT entry"))?)
                * sector
                / 512,
            ptype: guid(&ptype),
            label: String::from_utf16_lossy(&units),
        });
    }
    Ok(parts)
}

/// The version in `marathon_<version>_<kind>`.
pub fn slot_version<'a>(label: &'a str, kind: &str) -> Option<&'a str> {
    let version = label
        .strip_prefix("marathon_")?
        .strip_suffix(kind)?
        .strip_suffix('_')?;
    (!version.is_empty() && !version.contains('_')).then_some(version)
}

/// Digit runs compare as numbers, the rest as text.
pub fn version_cmp(a: &str, b: &str) -> Ordering {
    fn parts(s: &str) -> Vec<(bool, &str)> {
        let mut out = Vec::new();
        let mut rest = s;
        while let Some(first) = rest.chars().next() {
            let digit = first.is_ascii_digit();
            let end = rest
                .find(|c: char| c.is_ascii_digit() != digit)
                .unwrap_or(rest.len());
            out.push((digit, &rest[..end]));
            rest = &rest[end..];
        }
        out
    }
    let (pa, pb) = (parts(a), parts(b));
    for ((da, sa), (db, sb)) in pa.iter().zip(&pb) {
        let ord = if *da && *db {
            let (ta, tb) = (sa.trim_start_matches('0'), sb.trim_start_matches('0'));
            ta.len().cmp(&tb.len()).then_with(|| ta.cmp(tb))
        } else {
            sa.cmp(sb)
        };
        if ord != Ordering::Equal {
            return ord;
        }
    }
    pa.len().cmp(&pb.len())
}

/// The newest version newer than `running` that has both its boot and its
/// root slot written, and that boot slot.
pub fn candidate<'a>(parts: &'a [Partition], running: &str) -> Option<(&'a str, &'a Partition)> {
    let has_root = |version: &str| {
        parts
            .iter()
            .any(|p| p.ptype == ROOT_TYPE && slot_version(&p.label, "root") == Some(version))
    };
    parts
        .iter()
        .filter(|p| p.ptype == BOOT_TYPE)
        .filter_map(|p| Some((slot_version(&p.label, "boot")?, p)))
        .filter(|(v, _)| version_cmp(v, running) == Ordering::Greater && has_root(v))
        .max_by(|(a, _), (b, _)| version_cmp(a, b))
}

/// Trial boots of one version, counted once per boot.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Attempts {
    pub version: String,
    pub count: u32,
    pub boot_id: String,
}

impl Attempts {
    pub fn parse(text: &str) -> Self {
        let mut words = text.split_whitespace();
        Self {
            version: words.next().unwrap_or_default().to_owned(),
            count: words.next().and_then(|c| c.parse().ok()).unwrap_or(0),
            boot_id: words.next().unwrap_or_default().to_owned(),
        }
    }

    pub fn render(&self) -> String {
        format!("{} {} {}\n", self.version, self.count, self.boot_id)
    }

    /// Counts a trial of `version` armed in boot `boot_id`. False once the
    /// version has had `MAX_TRIES`; arming twice in one boot counts once.
    pub fn record(&mut self, version: &str, boot_id: &str) -> bool {
        if self.version != version {
            *self = Self {
                version: version.to_owned(),
                ..Self::default()
            };
        }
        if self.boot_id == boot_id {
            return true;
        }
        if self.count >= MAX_TRIES {
            return false;
        }
        self.count += 1;
        boot_id.clone_into(&mut self.boot_id);
        true
    }

    pub fn exhausted(&self, version: &str) -> bool {
        self.version == version && self.count >= MAX_TRIES
    }
}

/// Records a FAT32 file system's partition start (in 512-byte sectors) in
/// the BPB's hidden sectors and the backup boot sector's, as the Pi's boot
/// partition has them. False, and nothing written, if it is not FAT32.
pub fn set_fat32_hidden_sectors<D: Read + Write + Seek>(
    dev: &mut D,
    start: u64,
) -> io::Result<bool> {
    let mut boot = [0u8; 512];
    dev.seek(SeekFrom::Start(0))?;
    dev.read_exact(&mut boot)?;
    if boot.get(0x52..0x5a) != Some(b"FAT32   ".as_slice()) {
        return Ok(false);
    }
    let sector = u64::from(u16::from_le_bytes([boot[0x0b], boot[0x0c]]));
    if sector == 0 || !(start * 512).is_multiple_of(sector) {
        return Ok(false);
    }
    let hidden = u32::try_from(start * 512 / sector)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidInput, e))?;
    for copy in [0, 6] {
        dev.seek(SeekFrom::Start(copy * sector + 0x1c))?;
        dev.write_all(&hidden.to_le_bytes())?;
    }
    dev.flush()?;
    Ok(true)
}

/// Overwrites the file without truncating it first, so a same-length
/// rewrite of a one-sector `autoboot.txt` is one data-sector write.
pub fn write_in_place(path: &Path, text: &str) -> io::Result<()> {
    let mut file = OpenOptions::new().write(true).open(path)?;
    file.write_all(text.as_bytes())?;
    file.set_len(text.len() as u64)?;
    file.sync_all()
}

/// `IMAGE_VERSION` from os-release text.
pub fn image_version(os_release: &str) -> Option<String> {
    os_release.lines().find_map(|line| {
        let value = line.strip_prefix("IMAGE_VERSION=")?.trim();
        let value = value
            .strip_prefix('"')
            .and_then(|v| v.strip_suffix('"'))
            .unwrap_or(value);
        (!value.is_empty()).then(|| value.to_owned())
    })
}

#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn log(message: &str) {
    eprintln!("marathon-health: {message}");
}

fn run(program: &str, args: &[&str]) -> io::Result<String> {
    let out = Command::new(program).args(args).output()?;
    if !out.status.success() {
        return Err(io::Error::other(format!(
            "{program} {}: {}",
            args.join(" "),
            String::from_utf8_lossy(&out.stderr).trim()
        )));
    }
    Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// The whole disk `/` is on.
fn root_disk() -> io::Result<PathBuf> {
    let dev = std::fs::metadata("/")?.dev();
    let (major, minor) = (
        ((dev >> 32) & 0xffff_f000) | ((dev >> 8) & 0xfff),
        ((dev >> 12) & 0xffff_ff00) | (dev & 0xff),
    );
    let part = std::fs::canonicalize(format!("/sys/dev/block/{major}:{minor}"))?;
    let disk = part
        .parent()
        .and_then(Path::file_name)
        .ok_or_else(|| io::Error::other("root is not on a partition"))?;
    Ok(Path::new("/dev").join(disk))
}

fn partitions() -> io::Result<Vec<Partition>> {
    let disk = root_disk()?;
    let name = disk.file_name().unwrap_or_default();
    let sector: u64 = std::fs::read_to_string(
        Path::new("/sys/block")
            .join(name)
            .join("queue/logical_block_size"),
    )
    .ok()
    .and_then(|s| s.trim().parse().ok())
    .unwrap_or(512);
    read_gpt(&mut std::fs::File::open(&disk)?, sector, &disk)
}

fn running_version() -> io::Result<String> {
    image_version(&std::fs::read_to_string(OS_RELEASE)?)
        .ok_or_else(|| io::Error::other("no IMAGE_VERSION in os-release"))
}

/// Rewrites `autoboot.txt` on partition 1 with `change`, which returns
/// `None` to leave it alone. Returns what it wrote.
fn update_autoboot(
    parts: &[Partition],
    change: impl FnOnce(Autoboot) -> Option<Autoboot>,
) -> io::Result<Option<Autoboot>> {
    let dev = parts
        .iter()
        .find(|p| p.label == AUTOBOOT_LABEL)
        .ok_or_else(|| io::Error::other("no marathon_autoboot partition"))?;
    std::fs::create_dir_all(MOUNT_DIR)?;
    run(
        "mount",
        &[
            "-t",
            "vfat",
            "-o",
            "rw,sync,noatime",
            &dev.path.to_string_lossy(),
            MOUNT_DIR,
        ],
    )?;
    let file = Path::new(MOUNT_DIR).join("autoboot.txt");
    let result = std::fs::read_to_string(&file).and_then(|text| {
        let current =
            Autoboot::parse(&text).ok_or_else(|| io::Error::other("autoboot.txt is not A/B"))?;
        let next = change(current);
        if let Some(next) = next {
            write_in_place(&file, &next.render())?;
        }
        Ok(next)
    });
    let unmounted = run("umount", &[MOUNT_DIR]);
    let next = result?;
    unmounted?;
    Ok(next)
}

fn fix_hidden_sectors(boot: &Partition) -> io::Result<()> {
    let mut dev = OpenOptions::new().read(true).write(true).open(&boot.path)?;
    set_fat32_hidden_sectors(&mut dev, boot.start)?;
    dev.sync_all()
}

/// Points `[tryboot]` at a newer installed version and makes the next
/// reboot a tryboot. Returns the version armed.
pub fn arm() -> io::Result<Option<String>> {
    if read_be_u32(DT_TRYBOOT) == Some(1) {
        // A trial is running: it commits itself or falls back.
        return Ok(None);
    }
    if Path::new(FACTORY_RESET).exists() {
        // Only this slot's initramfs knows to erase; the trial waits.
        return Ok(None);
    }
    let parts = partitions()?;
    let running = running_version()?;
    let Some((version, boot)) = candidate(&parts, &running) else {
        return Ok(None);
    };
    let boot_id = std::fs::read_to_string(BOOT_ID)?.trim().to_owned();
    let mut attempts = Attempts::parse(&std::fs::read_to_string(STATE).unwrap_or_default());
    if !attempts.record(version, &boot_id) {
        return Ok(None);
    }
    fix_hidden_sectors(boot)?;
    let target = boot.number;
    update_autoboot(&parts, |current| {
        (current.tryboot != target).then_some(Autoboot {
            tryboot: target,
            ..current
        })
    })?;
    if let Some(dir) = Path::new(STATE).parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(STATE, attempts.render())?;
    std::fs::write(REBOOT_PARAM, "0 tryboot")?;
    Ok(Some(version.to_owned()))
}

/// At shutdown: arm a newly installed version for the reboot.
pub fn on_shutdown() {
    match arm() {
        Ok(Some(version)) => log(&format!("next reboot tries {version}")),
        Ok(None) => {}
        Err(e) => log(&format!("could not arm a trial boot: {e}")),
    }
}

/// Early boot: a version installed before a power-off, power loss or forced
/// reboot is tried now.
pub fn on_boot() {
    match arm() {
        Ok(Some(version)) => {
            log(&format!("rebooting to try {version}"));
            reboot();
        }
        Ok(None) => {
            let attempts = Attempts::parse(&std::fs::read_to_string(STATE).unwrap_or_default());
            if let (Ok(parts), Ok(running)) = (partitions(), running_version()) {
                if let Some((version, _)) = candidate(&parts, &running) {
                    if attempts.exhausted(version) {
                        log(&format!(
                            "{version} failed its trial boots; staying on {running}"
                        ));
                    }
                }
            }
        }
        Err(e) => log(&format!("could not arm a trial boot: {e}")),
    }
}

/// After the shell's first frame on a trial boot: make it the committed slot.
pub fn commit() -> io::Result<Option<Autoboot>> {
    let booted = read_be_u32(DT_PARTITION)
        .ok_or_else(|| io::Error::other("no booted partition in the device tree"))?;
    update_autoboot(&partitions()?, |current| current.committed(booted))
}

pub fn is_trial_boot() -> bool {
    read_be_u32(DT_TRYBOOT) == Some(1)
}

/// A plain reboot: the firmware has already cleared the tryboot flag, so it
/// boots the committed slot.
pub fn reboot() {
    match Command::new("systemctl")
        .args(["--no-block", "reboot"])
        .status()
    {
        Ok(status) if status.success() => {}
        Ok(status) => log(&format!("systemctl reboot: {status}")),
        Err(e) => log(&format!("systemctl reboot: {e}")),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;
    use std::io::Cursor;

    const INITIAL: &str = "[all]\ntryboot_a_b=1\nboot_partition=2\n[tryboot]\nboot_partition=3\n";

    #[test]
    fn reads_device_tree_cells() {
        assert_eq!(be_u32(&[0, 0, 0, 1]), Some(1));
        assert_eq!(be_u32(&[0, 0, 0, 3, 0]), Some(3));
        assert_eq!(be_u32(&[0, 1]), None);
    }

    #[test]
    fn autoboot_round_trips() {
        let a = Autoboot::parse(INITIAL).unwrap();
        assert_eq!(a, Autoboot { all: 2, tryboot: 3 });
        assert_eq!(a.render(), INITIAL);
        let b = Autoboot { all: 3, tryboot: 2 };
        assert_eq!(Autoboot::parse(&b.render()), Some(b));
        assert_eq!(a.render().len(), b.render().len());
    }

    #[test]
    fn parses_the_autoboot_txt_the_image_ships() {
        let shipped = include_str!("../../../packaging/ota/pi/autoboot.txt");
        assert_eq!(
            Autoboot::parse(shipped),
            Some(Autoboot { all: 2, tryboot: 3 })
        );
        assert_eq!(shipped, INITIAL);
    }

    #[test]
    fn autoboot_tolerates_spacing_and_comments() {
        let text =
            "# A/B\n[all]\n tryboot_a_b = 1\nboot_partition = 3\n\n[tryboot]\nboot_partition=2\n";
        assert_eq!(Autoboot::parse(text), Some(Autoboot { all: 3, tryboot: 2 }));
    }

    #[test]
    fn autoboot_needs_both_slots_and_a_b_mode() {
        assert_eq!(
            Autoboot::parse("[all]\ntryboot_a_b=1\nboot_partition=2\n"),
            None
        );
        assert_eq!(
            Autoboot::parse("[all]\nboot_partition=2\n[tryboot]\nboot_partition=3\n"),
            None
        );
        assert_eq!(Autoboot::parse(""), None);
    }

    #[test]
    fn commits_the_booted_slot_and_keeps_the_old_one_to_try() {
        let a = Autoboot { all: 2, tryboot: 3 };
        assert_eq!(a.committed(3), Some(Autoboot { all: 3, tryboot: 2 }));
        assert_eq!(a.committed(2), None);
    }

    #[test]
    fn rewrites_in_place() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("autoboot.txt");
        std::fs::write(&path, INITIAL).unwrap();
        let next = Autoboot { all: 3, tryboot: 2 }.render();
        write_in_place(&path, &next).unwrap();
        assert_eq!(std::fs::read_to_string(&path).unwrap(), next);
        write_in_place(&path, "[all]\n").unwrap();
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "[all]\n");
        assert!(write_in_place(&dir.path().join("missing"), INITIAL).is_err());
    }

    fn guid_bytes(text: &str) -> [u8; 16] {
        let hex: String = text.chars().filter(char::is_ascii_hexdigit).collect();
        let mut b: Vec<u8> = (0..16)
            .map(|i| u8::from_str_radix(&hex[i * 2..i * 2 + 2], 16).unwrap())
            .collect();
        b[..4].reverse();
        b[4..6].reverse();
        b[6..8].reverse();
        b.try_into().unwrap()
    }

    /// A disk with a primary GPT holding `parts` (type, label) at LBA 2048,
    /// 2048 + 4096, and so on, in `sector`-byte sectors.
    fn gpt(sector: usize, parts: &[(&str, &str)]) -> Vec<u8> {
        let mut disk = vec![0u8; sector * 2 + 128 * 128];
        disk[sector..sector + 8].copy_from_slice(b"EFI PART");
        disk[sector + 0x48..sector + 0x50].copy_from_slice(&2u64.to_le_bytes());
        disk[sector + 0x50..sector + 0x54].copy_from_slice(&128u32.to_le_bytes());
        disk[sector + 0x54..sector + 0x58].copy_from_slice(&128u32.to_le_bytes());
        for (i, (ptype, label)) in parts.iter().enumerate() {
            let e = sector * 2 + i * 128;
            if ptype.is_empty() {
                continue;
            }
            disk[e..e + 16].copy_from_slice(&guid_bytes(ptype));
            let start = 2048 + 4096 * i as u64;
            disk[e + 32..e + 40].copy_from_slice(&start.to_le_bytes());
            for (k, unit) in label.encode_utf16().enumerate() {
                disk[e + 56 + k * 2..e + 58 + k * 2].copy_from_slice(&unit.to_le_bytes());
            }
        }
        disk
    }

    const ESP: &str = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b";
    const VAR: &str = "4d21b016-b534-45c2-a9fb-5c16e091fd2d";

    fn card() -> Vec<Partition> {
        let disk = gpt(
            512,
            &[
                (ESP, "marathon_autoboot"),
                (BOOT_TYPE, "marathon_26101801_boot"),
                (BOOT_TYPE, "marathon_26101902_boot"),
                (ROOT_TYPE, "marathon_26101801_root"),
                (ROOT_TYPE, "marathon_26101902_root"),
                (VAR, "marathon_data"),
            ],
        );
        read_gpt(&mut Cursor::new(disk), 512, Path::new("/dev/mmcblk0")).unwrap()
    }

    #[test]
    fn reads_the_gpt() {
        let parts = card();
        assert_eq!(parts.len(), 6);
        assert_eq!(
            parts[2],
            Partition {
                path: PathBuf::from("/dev/mmcblk0p3"),
                number: 3,
                start: 2048 + 2 * 4096,
                ptype: BOOT_TYPE.to_owned(),
                label: "marathon_26101902_boot".to_owned(),
            }
        );
        assert_eq!(parts[0].label, AUTOBOOT_LABEL);
        assert_eq!(parts[0].ptype, ESP);
    }

    #[test]
    fn reads_a_gpt_sfdisk_wrote() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("disk.raw");
        std::fs::File::create(&path)
            .unwrap()
            .set_len(8 << 20)
            .unwrap();
        let layout = format!(
            "label: gpt\nstart=2048, size=2048, type={ESP}, name=marathon_autoboot\n\
             size=2048, type={BOOT_TYPE}, name=marathon_26101801_boot\n"
        );
        let Ok(mut sfdisk) = Command::new("sfdisk")
            .args(["-q", &path.to_string_lossy()])
            .stdin(std::process::Stdio::piped())
            .spawn()
        else {
            return; // no sfdisk on this host
        };
        sfdisk
            .stdin
            .take()
            .unwrap()
            .write_all(layout.as_bytes())
            .unwrap();
        assert!(sfdisk.wait().unwrap().success());
        let parts = read_gpt(
            &mut std::fs::File::open(&path).unwrap(),
            512,
            Path::new("/dev/mmcblk0"),
        )
        .unwrap();
        assert_eq!(parts.len(), 2);
        assert_eq!((parts[0].ptype.as_str(), parts[0].start), (ESP, 2048));
        assert_eq!(
            (
                parts[1].ptype.as_str(),
                parts[1].label.as_str(),
                parts[1].start
            ),
            (BOOT_TYPE, "marathon_26101801_boot", 4096)
        );
    }

    #[test]
    fn skips_unused_entries_and_names_sd_style_disks() {
        let disk = gpt(512, &[("", ""), (ROOT_TYPE, "_empty")]);
        let parts = read_gpt(&mut Cursor::new(disk), 512, Path::new("/dev/sda")).unwrap();
        assert_eq!(parts.len(), 1);
        assert_eq!(
            (parts[0].number, parts[0].path.as_path()),
            (2, Path::new("/dev/sda2"))
        );
    }

    #[test]
    fn counts_starts_in_512_byte_sectors() {
        let disk = gpt(4096, &[(BOOT_TYPE, "marathon_1_boot")]);
        let parts = read_gpt(&mut Cursor::new(disk), 4096, Path::new("/dev/nvme0n1")).unwrap();
        assert_eq!(parts[0].start, 2048 * 8);
        assert_eq!(parts[0].path, PathBuf::from("/dev/nvme0n1p1"));
    }

    #[test]
    fn refuses_a_disk_without_a_gpt() {
        let mut disk = gpt(512, &[]);
        disk[512..520].copy_from_slice(b"NOT PART");
        assert!(read_gpt(&mut Cursor::new(disk), 512, Path::new("/dev/mmcblk0")).is_err());
    }

    #[test]
    fn reads_versions_from_slot_labels() {
        assert_eq!(
            slot_version("marathon_26101801_boot", "boot"),
            Some("26101801")
        );
        assert_eq!(
            slot_version("marathon_26101801_root", "root"),
            Some("26101801")
        );
        assert_eq!(slot_version("marathon_26101801_root", "boot"), None);
        assert_eq!(slot_version("marathon_autoboot", "boot"), None);
        assert_eq!(slot_version("marathon__boot", "boot"), None);
        assert_eq!(slot_version("_empty", "boot"), None);
    }

    #[test]
    fn compares_versions_numerically() {
        assert_eq!(version_cmp("26101902", "26101801"), Ordering::Greater);
        assert_eq!(version_cmp("9", "10"), Ordering::Less);
        assert_eq!(version_cmp("1.10", "1.9"), Ordering::Greater);
        assert_eq!(version_cmp("007", "7"), Ordering::Equal);
        assert_eq!(version_cmp("1", "1a"), Ordering::Less);
    }

    #[test]
    fn picks_the_newer_complete_slot() {
        let parts = card();
        let (version, boot) = candidate(&parts, "26101801").unwrap();
        assert_eq!((version, boot.number), ("26101902", 3));
        assert!(candidate(&parts, "26101902").is_none());
    }

    #[test]
    fn skips_a_slot_whose_root_is_missing_or_pending() {
        let mut parts = card();
        // sysupdate marks a slot it is still writing with a derived type.
        parts[4].ptype = "0d4a0d32-0000-4000-8000-000000000000".to_owned();
        assert!(candidate(&parts, "26101801").is_none());
        parts.remove(4);
        assert!(candidate(&parts, "26101801").is_none());
    }

    #[test]
    fn counts_trials_once_per_boot() {
        let mut a = Attempts::default();
        assert!(a.record("2", "boot-a"));
        assert!(a.record("2", "boot-a"));
        assert_eq!(a.count, 1);
        assert!(a.record("2", "boot-b"));
        assert_eq!(a.count, 2);
        assert!(a.exhausted("2"));
        assert!(!a.record("2", "boot-c"));
        assert!(a.record("3", "boot-c"));
        assert_eq!((a.version.as_str(), a.count), ("3", 1));
        assert!(!a.exhausted("2"));
    }

    #[test]
    fn attempts_round_trip() {
        let a = Attempts {
            version: "26101902".to_owned(),
            count: 2,
            boot_id: "f00".to_owned(),
        };
        assert_eq!(Attempts::parse(&a.render()), a);
        assert_eq!(Attempts::parse(""), Attempts::default());
        assert_eq!(Attempts::parse("garbage").count, 0);
    }

    fn fat32(sector: u16) -> Vec<u8> {
        let mut disk = vec![0u8; usize::from(sector) * 8];
        disk[0x0b..0x0d].copy_from_slice(&sector.to_le_bytes());
        disk[0x52..0x5a].copy_from_slice(b"FAT32   ");
        disk
    }

    fn hidden(disk: &[u8], sector: usize) -> u32 {
        u32::from_le_bytes(disk[sector + 0x1c..sector + 0x20].try_into().unwrap())
    }

    #[test]
    fn records_the_partition_start_in_both_boot_sectors() {
        let mut dev = Cursor::new(fat32(512));
        assert!(set_fat32_hidden_sectors(&mut dev, 1_050_624).unwrap());
        let disk = dev.into_inner();
        assert_eq!(hidden(&disk, 0), 1_050_624);
        assert_eq!(hidden(&disk, 6 * 512), 1_050_624);
    }

    #[test]
    fn counts_hidden_sectors_in_the_file_systems_sector_size() {
        let mut dev = Cursor::new(fat32(4096));
        assert!(set_fat32_hidden_sectors(&mut dev, 2048).unwrap());
        let disk = dev.into_inner();
        assert_eq!(hidden(&disk, 0), 256);
        assert_eq!(hidden(&disk, 6 * 4096), 256);
    }

    #[test]
    fn leaves_anything_but_fat32_alone() {
        let mut disk = fat32(512);
        disk[0x52..0x5a].copy_from_slice(b"FAT16   ");
        let mut dev = Cursor::new(disk.clone());
        assert!(!set_fat32_hidden_sectors(&mut dev, 2048).unwrap());
        assert_eq!(dev.into_inner(), disk);
    }

    #[test]
    fn reads_image_version() {
        assert_eq!(
            image_version("ID=postmarketos\nIMAGE_VERSION=26101801\n").as_deref(),
            Some("26101801")
        );
        assert_eq!(
            image_version("IMAGE_VERSION=\"26101801\"\n").as_deref(),
            Some("26101801")
        );
        assert_eq!(image_version("ID=x\n"), None);
        assert_eq!(image_version("IMAGE_VERSION=\n"), None);
    }
}
