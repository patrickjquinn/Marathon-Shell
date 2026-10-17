//! systemd-boot's boot counting, as the boot loader interface exposes it:
//! `LoaderBootCountPath` names the counted entry, whose file name carries
//! `+LEFT[-DONE]`.

use std::path::{Path, PathBuf};

pub const COUNT_PATH_VAR: &str =
    "/sys/firmware/efi/efivars/LoaderBootCountPath-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f";
const ESP_MOUNTS: [&str; 3] = ["/efi", "/boot", "/boot/efi"];

/// The ESP-relative path in an efivarfs file: four attribute bytes, then
/// NUL-terminated UTF-16LE with backslashes.
pub fn decode_path(raw: &[u8]) -> Option<String> {
    let units: Vec<u16> = raw
        .get(4..)?
        .as_chunks::<2>()
        .0
        .iter()
        .map(|&pair| u16::from_le_bytes(pair))
        .take_while(|&u| u != 0)
        .collect();
    String::from_utf16(&units)
        .ok()
        .map(|s| s.replace('\\', "/"))
}

/// Tries left in a counted entry's file name; `None` when it is uncounted.
pub fn tries_left(file_name: &str) -> Option<u32> {
    let stem = file_name.rsplit_once('.').map_or(file_name, |(s, _)| s);
    let (_, counter) = stem.rsplit_once('+')?;
    counter
        .split_once('-')
        .map_or(counter, |(left, _)| left)
        .parse()
        .ok()
}

/// The counted entry on the mounted ESP, if this boot is counted.
pub fn counted_entry(var: &Path) -> Option<PathBuf> {
    let path = decode_path(&std::fs::read(var).ok()?)?;
    let relative = path.trim_start_matches('/');
    ESP_MOUNTS
        .iter()
        .map(|mount| Path::new(mount).join(relative))
        .find(|candidate| candidate.is_file())
}

/// Whether a reboot can do better than this failed boot: the entry has tries
/// left, or another entry beside it is good (uncounted) or still has tries.
/// An entry already at zero is booted again only when nothing else is
/// left, and rebooting into it again would never end.
pub fn reboot_helps(entry: &Path) -> bool {
    let Some(name) = entry.file_name().and_then(|n| n.to_str()) else {
        return false;
    };
    if tries_left(name).is_some_and(|left| left > 0) {
        return true;
    }
    let ext = entry.extension();
    let Some(dir) = entry.parent() else {
        return false;
    };
    std::fs::read_dir(dir).is_ok_and(|entries| {
        entries.flatten().any(|e| {
            let path = e.path();
            let other = e.file_name();
            let other = other.to_string_lossy();
            other != name
                && path.extension() == ext
                && tries_left(&other).is_none_or(|left| left > 0)
        })
    })
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn efivar(path: &str) -> Vec<u8> {
        let mut raw = vec![7, 0, 0, 0];
        for unit in path.encode_utf16().chain(std::iter::once(0)) {
            raw.extend_from_slice(&unit.to_le_bytes());
        }
        raw
    }

    #[test]
    fn decodes_the_efivar() {
        assert_eq!(
            decode_path(&efivar("\\EFI\\Linux\\os_26101801+2-1.efi")).as_deref(),
            Some("/EFI/Linux/os_26101801+2-1.efi")
        );
        assert_eq!(decode_path(&[7, 0, 0, 0]), Some(String::new()));
        assert_eq!(decode_path(&[7, 0]), None);
    }

    #[test]
    fn reads_tries_left_from_the_name() {
        assert_eq!(tries_left("os_26101801+3.efi"), Some(3));
        assert_eq!(tries_left("os_26101801+2-1.efi"), Some(2));
        assert_eq!(tries_left("os_26101801+0-3.efi"), Some(0));
        assert_eq!(tries_left("os_26101801.efi"), None);
        assert_eq!(tries_left("entry+1-2.conf"), Some(1));
    }

    fn esp(names: &[&str]) -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        for name in names {
            std::fs::write(dir.path().join(name), b"").unwrap();
        }
        dir
    }

    #[test]
    fn reboots_while_the_entry_has_tries() {
        let dir = esp(&["os_2+1-2.efi"]);
        assert!(reboot_helps(&dir.path().join("os_2+1-2.efi")));
    }

    #[test]
    fn reboots_into_a_good_entry_once_tries_run_out() {
        let dir = esp(&["os_1.efi", "os_2+0-3.efi"]);
        assert!(reboot_helps(&dir.path().join("os_2+0-3.efi")));
    }

    #[test]
    fn stays_up_when_nothing_better_is_left() {
        let dir = esp(&["os_1+0-3.efi", "os_2+0-3.efi", "notes.txt"]);
        assert!(!reboot_helps(&dir.path().join("os_2+0-3.efi")));
        let alone = esp(&["os_2+0-3.efi"]);
        assert!(!reboot_helps(&alone.path().join("os_2+0-3.efi")));
    }

    #[test]
    fn finds_no_entry_on_an_uncounted_boot() {
        let dir = tempfile::tempdir().unwrap();
        assert_eq!(counted_entry(&dir.path().join("LoaderBootCountPath")), None);
    }
}
