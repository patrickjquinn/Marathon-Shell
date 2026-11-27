//! Booting the DSP of a receiver whose image the secure monitor holds.
//!
//! On the MT6858 the L1 DSP image is not the host's: `MediaTek`'s `gps_drv`
//! (`/dev/gpsdl0`) asks TF-A for its size, addresses, cipher key and
//! fragment count, and has TF-A load each fragment when the host names it.
//! The handshake around it is the boot ROM's, as on the MT6789: the boot
//! parameters (`0xFE08`, acknowledged with `0xFE31`), then each fragment,
//! acknowledged with `0xFE32` and its sequence number.

use crate::mtk::{encode, Deframer};
use std::fs::File;
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::time::{Duration, Instant};

const HOST_CTRL: u16 = 0xfe05;
const BOOT_PARAMS: u16 = 0xfe08;
const BOOT_PARAMS_ACK: u16 = 0xfe31;
const BOOT_CODE_ACK: u16 = 0xfe32;

/// `gps_drv`'s ioctls: plain numbers, not `_IOC` encoded.
const GET_DSP_BOOTUP_INFO: libc::Ioctl = 23;
const DSP_MVCD_FRAGMENT: libc::Ioctl = 25;

const TRIES: u32 = 5;
const MAX_FRAGMENTS: u32 = 256;

/// The boot parameters the stock engine sends for the MT6789 with its 26 MHz
/// co-clock and GPS, GLONASS, Galileo and `BeiDou`; bytes 14-23 come from
/// the image. The MT6858's own are not decoded yet.
const PARAMS: [u8; 106] = [
    0x1a, 0x00, 0x00, 0x00, 0x00, 0x01, 0xc3, 0x01, 0xa5, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x9d, 0x00,
    0x6f, 0x3c, 0x88, 0x89, 0xa2, 0x04, 0x02, 0x00, 0xdc, 0x00, 0xc1, 0x00, 0x28, 0x00, 0x5c, 0x4a,
    0x1e, 0x00, 0xc5, 0x37, 0x28, 0x00, 0x5c, 0x4a, 0x8f, 0x65, 0x07, 0x00, 0x01, 0x00, 0x28, 0x00,
    0xff, 0x00, 0x80, 0x00, 0x47, 0x00, 0x64, 0x00, 0x50, 0x00, 0xd8, 0x00, 0x50, 0x00, 0xbb, 0x00,
    0x03, 0x00, 0x3c, 0x00, 0x6f, 0x00, 0x89, 0x00, 0x88, 0x00, 0x02, 0x00, 0xfb, 0x00, 0x01, 0x00,
    0x89, 0x67, 0xff, 0x0a, 0x00, 0x00, 0x01, 0x00, 0x4e, 0x4f,
];

/// TF-A's description of the image, as `gps_drv` copies it out.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Image {
    pub code_size: u16,
    pub start: u16,
    pub exec: u16,
    pub cipher_key: u16,
    pub fragments: u16,
}

impl Image {
    fn from_words(w: [u32; 5]) -> Self {
        #[allow(
            clippy::cast_possible_truncation,
            reason = "TF-A reports 16-bit fields"
        )]
        Self {
            code_size: w[0] as u16,
            start: w[1] as u16,
            exec: w[2] as u16,
            cipher_key: w[3] as u16,
            fragments: w[4] as u16,
        }
    }
}

/// The boot-parameter payload for `image`.
pub fn params(image: &Image) -> [u8; 106] {
    let mut p = PARAMS;
    for (i, v) in [
        image.code_size,
        image.start,
        image.exec,
        image.cipher_key,
        image.fragments,
    ]
    .into_iter()
    .enumerate()
    {
        p[14 + 2 * i..16 + 2 * i].copy_from_slice(&v.to_le_bytes());
    }
    p
}

/// The sequence number an acknowledgement carries. The boot ROM's frames are
/// not scrambled like the running DSP's, so `Deframer`'s unscrambled payload
/// is scrambled back.
fn ack_seq(payload: &[u8]) -> Option<u16> {
    let raw: Vec<u8> = payload
        .get(..2)?
        .iter()
        .map(|b| (b ^ 0x59).rotate_left(3))
        .collect();
    Some(u16::from_le_bytes([raw[0], raw[1]]))
}

fn ioctl_info(dev: &File) -> io::Result<Image> {
    let mut words = [0u32; 5];
    // SAFETY: gps_drv copies five u32s to the pointer.
    let r = unsafe { libc::ioctl(dev.as_raw_fd(), GET_DSP_BOOTUP_INFO, words.as_mut_ptr()) };
    if r < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(Image::from_words(words))
}

fn ioctl_fragment(dev: &File, index: u32) -> io::Result<()> {
    // SAFETY: the argument is a plain integer.
    let r = unsafe {
        libc::ioctl(
            dev.as_raw_fd(),
            DSP_MVCD_FRAGMENT,
            libc::c_ulong::from(index),
        )
    };
    if r < 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

/// Reads until a frame `id` with sequence number `seq` arrives or `timeout`
/// passes.
fn wait_ack(
    dev: &mut File,
    deframer: &mut Deframer,
    id: u16,
    seq: u16,
    timeout: Duration,
) -> io::Result<bool> {
    let end = Instant::now() + timeout;
    let mut buf = [0u8; 512];
    loop {
        let left = end.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Ok(false);
        }
        let mut pfd = libc::pollfd {
            fd: dev.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let ms = i32::try_from(left.as_millis()).unwrap_or(i32::MAX).max(1);
        // SAFETY: one pollfd.
        if unsafe { libc::poll(&raw mut pfd, 1, ms) } <= 0 {
            continue;
        }
        let n = dev.read(&mut buf)?;
        for f in buf[..n].iter().filter_map(|&b| deframer.push(b)) {
            if f.id == id && ack_seq(&f.payload) == Some(seq) {
                return Ok(true);
            }
        }
    }
}

/// Boots the DSP through TF-A; afterwards it runs as on the MT6789.
pub fn tfa(dev: &mut File) -> io::Result<()> {
    let image = ioctl_info(dev)?;
    let frags = u32::from(image.fragments);
    if frags == 0 || frags > MAX_FRAGMENTS {
        return Err(io::Error::other(format!("bad DSP image: {image:?}")));
    }
    let mut deframer = Deframer::default();

    let params = params(&image);
    let mut acked = false;
    for r in 0..TRIES {
        dev.write_all(&encode(BOOT_PARAMS, &params))?;
        if wait_ack(
            dev,
            &mut deframer,
            BOOT_PARAMS_ACK,
            0,
            Duration::from_millis(200 << r),
        )? {
            acked = true;
            break;
        }
        // Kick the boot ROM as the stock engine does, then retry.
        for _ in 0..3 {
            dev.write_all(&encode(HOST_CTRL, &[0x04, 0x00]))?;
        }
        std::thread::sleep(Duration::from_millis(500 * u64::from(r + 1)));
    }
    if !acked {
        return Err(io::Error::new(
            io::ErrorKind::TimedOut,
            "the DSP boot ROM did not answer",
        ));
    }

    for seq in 1..=frags {
        #[allow(clippy::cast_possible_truncation, reason = "at most 256 fragments")]
        let want = seq as u16;
        let mut taken = false;
        for r in 0..TRIES {
            ioctl_fragment(dev, seq - 1)?;
            if wait_ack(
                dev,
                &mut deframer,
                BOOT_CODE_ACK,
                want,
                Duration::from_millis(200 << r),
            )? {
                taken = true;
                break;
            }
        }
        if !taken {
            return Err(io::Error::new(
                io::ErrorKind::TimedOut,
                format!("the DSP did not take fragment {seq} of {frags}"),
            ));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_image_fields_land_at_bytes_14_to_23() {
        let p = params(&Image {
            code_size: 0x1234,
            start: 0x5678,
            exec: 0x9abc,
            cipher_key: 0xdef0,
            fragments: 42,
        });
        assert_eq!(
            &p[14..24],
            &[0x34, 0x12, 0x78, 0x56, 0xbc, 0x9a, 0xf0, 0xde, 42, 0]
        );
        assert_eq!(&p[..14], &PARAMS[..14]);
        assert_eq!(&p[24..], &PARAMS[24..]);
    }

    #[allow(clippy::expect_used, reason = "tests")]
    #[test]
    fn an_ack_reads_its_sequence_number_unscrambled_back() {
        let mut d = Deframer::default();
        let frame = encode(BOOT_CODE_ACK, &[7, 0]);
        let f = frame.iter().find_map(|&b| d.push(b)).expect("frame");
        assert_eq!(f.id, BOOT_CODE_ACK);
        assert_eq!(ack_seq(&f.payload), Some(7));
    }
}
