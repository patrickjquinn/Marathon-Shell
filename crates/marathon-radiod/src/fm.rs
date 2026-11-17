//! MediaTek's FM receiver (`fmradio_drv`, MT6631/MT6635 A-die) through its
//! character device `/dev/fm`. The ioctls are the driver's `fm_ioctl.h`; it
//! declares most arguments as pointers, so those requests encode 8 bytes.
//! The driver has no seek or scan: as MediaTek's HAL does, each channel is
//! probed with a soft-mute tune, whose answer says whether it is a station.
//! Frequencies are in 10 kHz (9800 is 98.0 MHz).

use std::fs::{File, OpenOptions};
use std::io;
use std::os::fd::AsRawFd;

const MAGIC: u64 = 0xF5;

const fn iowr(nr: u64, size: u64) -> u64 {
    (3 << 30) | (size << 16) | (MAGIC << 8) | nr
}

const POWERUP: u64 = iowr(0, 8);
const POWERDOWN: u64 = iowr(1, 8);
const TUNE: u64 = iowr(2, 8);
const GETRSSI: u64 = iowr(7, 8);
const GETMONOSTEREO: u64 = iowr(13, 8);
const PRE_SEARCH: u64 = iowr(45, 4);
const RESTORE_SEARCH: u64 = iowr(46, 4);
const SOFT_MUTE_TUNE: u64 = iowr(63, 8);

/// US/Europe, 87.5 to 108 MHz.
const BAND_UE: u8 = 1;
const SPACE_100K: u8 = 1;
const STEP: u16 = 10;
pub const LOWEST: u16 = 8750;
pub const HIGHEST: u16 = 10800;

pub struct Fm(File);

/// What the station sends over RDS: its identity code, its name (eight
/// characters, as on a car radio) and its text ("Now playing ...").
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Rds {
    pub pi: u16,
    pub ps: String,
    pub rt: String,
}

/// `struct rds_t` (`fm_rds.h`) on arm64: 688 bytes; the PI code at 24, the
/// four PS buffers at 248 (the fourth is the settled name), the four
/// radio text buffers at 290 with the text's length 258 bytes after.
const RDS_LEN: usize = 688;
const RDS_PI: usize = 24;
const RDS_PS: usize = 248 + 3 * 8;
const RDS_RT: usize = 290 + 3 * 64;
const RDS_RT_LEN: usize = 290 + 258;

fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes)
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

/// The station data in a `struct rds_t`, or None when it has none yet.
pub fn parse_rds(b: &[u8]) -> Option<Rds> {
    if b.len() < RDS_LEN {
        return None;
    }
    let pi = u16::from_le_bytes([b[RDS_PI], b[RDS_PI + 1]]);
    let ps = text(&b[RDS_PS..RDS_PS + 8]);
    let rt_len = usize::from(b[RDS_RT_LEN]).min(64);
    let rt = text(&b[RDS_RT..RDS_RT + rt_len]);
    (pi != 0 || !ps.is_empty()).then_some(Rds { pi, ps, rt })
}

impl Fm {
    pub fn open() -> io::Result<Self> {
        OpenOptions::new()
            .read(true)
            .write(true)
            .open("/dev/fm")
            .map(Self)
    }

    fn ioctl(&self, request: u64, arg: &mut [u8]) -> io::Result<()> {
        // SAFETY: `arg` is a live buffer the size of the driver's struct.
        let r = unsafe { libc::ioctl(self.0.as_raw_fd(), request as _, arg.as_mut_ptr()) };
        if r < 0 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }

    /// err, band, space, hilo, deemphasis, (pad), freq: `fm_tune_parm`.
    fn tune_parm(freq: u16) -> [u8; 8] {
        let f = freq.to_le_bytes();
        [0, BAND_UE, SPACE_100K, 0, 0, 0, f[0], f[1]]
    }

    pub fn power_up(&self, freq: u16) -> io::Result<u16> {
        let mut p = Self::tune_parm(freq);
        self.ioctl(POWERUP, &mut p)?;
        Ok(u16::from_le_bytes([p[6], p[7]]))
    }

    pub fn power_down(&self) -> io::Result<()> {
        self.ioctl(POWERDOWN, &mut 0i32.to_le_bytes())
    }

    pub fn tune(&self, freq: u16) -> io::Result<u16> {
        let mut p = Self::tune_parm(freq);
        self.ioctl(TUNE, &mut p)?;
        Ok(u16::from_le_bytes([p[6], p[7]]))
    }

    /// Whether `freq` is a station: `fm_softmute_tune_t` (rssi, freq, valid).
    fn probe(&self, freq: u16) -> io::Result<bool> {
        let mut p = [0u8; 12];
        p[4..6].copy_from_slice(&freq.to_le_bytes());
        self.ioctl(SOFT_MUTE_TUNE, &mut p)?;
        Ok(i32::from_le_bytes([p[8], p[9], p[10], p[11]]) != 0)
    }

    /// Probes `channels` between the driver's search setup and its undoing.
    fn search(&self, channels: impl Iterator<Item = u16>, all: bool) -> io::Result<Vec<u16>> {
        self.ioctl(PRE_SEARCH, &mut [0u8; 4])?;
        let mut found = Vec::new();
        let mut probed = Ok(());
        for freq in channels {
            match self.probe(freq) {
                Ok(true) => {
                    found.push(freq);
                    if !all {
                        break;
                    }
                }
                Ok(false) => {}
                Err(e) => {
                    probed = Err(e);
                    break;
                }
            }
        }
        self.ioctl(RESTORE_SEARCH, &mut [0u8; 4])?;
        probed.map(|()| found)
    }

    /// The next station up or down from `freq`, round the band; tunes to it.
    pub fn seek(&self, freq: u16, up: bool) -> io::Result<u16> {
        let next = self
            .search(around(freq, up), false)?
            .first()
            .copied()
            .unwrap_or(freq);
        self.tune(next)
    }

    /// The RDS data received since the last call; None when nothing new.
    pub fn rds(&self) -> Option<Rds> {
        use std::io::Read;
        let mut b = [0u8; RDS_LEN];
        let n = (&self.0).read(&mut b).ok()?;
        parse_rds(&b[..n])
    }

    pub fn rssi(&self) -> io::Result<i32> {
        let mut r = [0u8; 4];
        self.ioctl(GETRSSI, &mut r)?;
        Ok(i32::from_le_bytes(r))
    }

    pub fn stereo(&self) -> io::Result<bool> {
        let mut s = [0u8; 2];
        self.ioctl(GETMONOSTEREO, &mut s)?;
        Ok(u16::from_le_bytes(s) == 1)
    }

    /// The band's stations.
    pub fn scan(&self) -> io::Result<Vec<u16>> {
        self.search((LOWEST..=HIGHEST).step_by(STEP.into()), true)
    }
}

/// Every channel after `freq` going up or down, wrapping round the band.
fn around(freq: u16, up: bool) -> impl Iterator<Item = u16> {
    let count = (HIGHEST - LOWEST) / STEP + 1;
    let at = freq.clamp(LOWEST, HIGHEST).saturating_sub(LOWEST) / STEP;
    (1..count).map(move |i| {
        let k = if up {
            (at + i) % count
        } else {
            (at + count - i) % count
        };
        LOWEST + k * STEP
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seeking_wraps_round_the_band() {
        assert_eq!(around(10800, true).next(), Some(8750));
        assert_eq!(around(8750, false).next(), Some(10800));
        assert_eq!(around(9800, true).next(), Some(9810));
        assert_eq!(around(9800, true).count(), 205);
    }

    #[test]
    fn rds_gives_the_settled_name_and_the_text() {
        let mut b = [0u8; RDS_LEN];
        b[RDS_PI..RDS_PI + 2].copy_from_slice(&0x2434u16.to_le_bytes());
        b[RDS_PS..RDS_PS + 8].copy_from_slice(b"  NOVA  ");
        let rt = b"Radio Nova, Three Rock";
        b[RDS_RT..RDS_RT + rt.len()].copy_from_slice(rt);
        b[RDS_RT_LEN] = u8::try_from(rt.len()).unwrap_or(0);
        let r = parse_rds(&b).unwrap_or_default();
        assert_eq!(
            (r.pi, r.ps.as_str(), r.rt.as_str()),
            (0x2434, "NOVA", "Radio Nova, Three Rock")
        );
        assert_eq!(parse_rds(&b[..10]), None);
    }

    #[test]
    fn requests_match_the_driver() {
        // _IOWR(0xf5, 0, struct fm_tune_parm *) and _IOWR(0xf5, 45, int32_t).
        assert_eq!(POWERUP, 0xC008_F500);
        assert_eq!(PRE_SEARCH, 0xC004_F52D);
        assert_eq!(SOFT_MUTE_TUNE, 0xC008_F53F);
    }
}
