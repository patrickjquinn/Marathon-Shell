//! MediaTek's FM receiver (`fmradio_drv`, MT6631/MT6635 A-die) through its
//! character device `/dev/fm`. The ioctls are the driver's `fm_ioctl.h`; it
//! declares every argument as a pointer, so each request encodes 8 bytes.
//! Frequencies are in 10 kHz (9800 is 98.0 MHz).

use std::fs::{File, OpenOptions};
use std::io;
use std::os::fd::AsRawFd;

const MAGIC: u64 = 0xF5;

const fn iowr(nr: u64) -> u64 {
    (3 << 30) | (8 << 16) | (MAGIC << 8) | nr
}

const POWERUP: u64 = iowr(0);
const POWERDOWN: u64 = iowr(1);
const TUNE: u64 = iowr(2);
const SEEK: u64 = iowr(3);
const GETRSSI: u64 = iowr(7);
const SCAN: u64 = iowr(8);
const GETMONOSTEREO: u64 = iowr(13);

/// US/Europe, 87.5 to 108 MHz.
const BAND_UE: u8 = 1;
const SPACE_100K: u8 = 1;
/// The driver's default seek threshold.
const SEEK_THRESHOLD: u8 = 4;
pub const LOWEST: u16 = 8750;
pub const HIGHEST: u16 = 10800;

pub struct Fm(File);

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

    /// The next station up or down from `freq`: `fm_seek_parm`.
    pub fn seek(&self, freq: u16, up: bool) -> io::Result<u16> {
        let f = freq.to_le_bytes();
        let mut p = [0, BAND_UE, SPACE_100K, 0, u8::from(!up), SEEK_THRESHOLD, f[0], f[1]];
        self.ioctl(SEEK, &mut p)?;
        Ok(u16::from_le_bytes([p[6], p[7]]))
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

    /// The stations a band scan finds, from `fm_scan_parm`'s bitmap of
    /// 100 kHz channels from the bottom of the band.
    pub fn scan(&self) -> io::Result<Vec<u16>> {
        // err, band, space, hilo, freq, ScanTBL[26], ScanTBLSize
        let mut p = [0u8; 60];
        p[1] = BAND_UE;
        p[2] = SPACE_100K;
        p[58..60].copy_from_slice(&26u16.to_le_bytes());
        self.ioctl(SCAN, &mut p)?;
        Ok(stations(&p[6..58]))
    }
}

/// Frequencies of the set bits of a scan table (26 little-endian words).
pub fn stations(table: &[u8]) -> Vec<u16> {
    let mut found = Vec::new();
    for (w, word) in table.as_chunks::<2>().0.iter().enumerate() {
        let bits = u16::from_le_bytes(*word);
        for b in 0..16u16 {
            if bits & (1 << b) != 0 {
                let channel = u16::try_from(w).unwrap_or(0) * 16 + b;
                let freq = LOWEST + channel * 10;
                if freq <= HIGHEST {
                    found.push(freq);
                }
            }
        }
    }
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scan_bits_are_100_khz_channels_from_87_5() {
        let mut table = [0u8; 52];
        table[0] = 0b1; // channel 0: 87.5
        table[2] = 0b100; // channel 18: 89.3
        assert_eq!(stations(&table), vec![8750, 8930]);
    }

    #[test]
    fn requests_match_the_driver() {
        // _IOWR(0xf5, 0, struct fm_tune_parm *) on a 64-bit kernel.
        assert_eq!(POWERUP, 0xC008_F500);
        assert_eq!(SCAN, 0xC008_F508);
    }
}
