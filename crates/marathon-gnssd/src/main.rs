//! marathon-gnssd --nav RINEX --approx LAT,LON,HEIGHT [--device DEV | --replay CAPTURE]
//!
//! Opens the GNSS device (which boots the DSP), keeps the DSP searching, and
//! prints NMEA GGA/RMC for each epoch with a GPS fix. Ephemerides come from a
//! RINEX 3 navigation file, the approximate position from the caller.
//! `--replay` runs a `mtk-gnss-capture` recording instead of the device;
//! `--record FILE` writes what the device sends in that format.

use marathon_gnssd::lnav::Ephemeris;
use marathon_gnssd::meas::{self, Channel};
use marathon_gnssd::mtk::{self, Deframer};
use marathon_gnssd::{dsp, nmea, orbit, rinex, spp};
use nalgebra::Vector3;
use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::{self, Read, Write};
use std::time::{SystemTime, UNIX_EPOCH};

const GPS_UNIX_EPOCH: f64 = 315_964_800.0;
const LEAP_SECONDS: f64 = 18.0;
const WEEK: f64 = 604_800.0;
const MIN_CN0: u8 = 20;
const MIN_SATS: usize = 5;
const MAX_RMS: f64 = 15.0;
const MASK: f64 = 10.0;
const MAX_FROM_APPROX: f64 = 5_000.0;

struct Engine {
    ephs: HashMap<u8, Vec<Ephemeris>>,
    approx: Vector3<f64>,
    tag: Option<(u32, f64)>,
    chans: Vec<Channel>,
}

fn ecef(lat: f64, lon: f64, h: f64) -> Vector3<f64> {
    const A: f64 = 6_378_137.0;
    const E2: f64 = 6.694_379_990_14e-3;
    let (la, lo) = (lat.to_radians(), lon.to_radians());
    let n = A / (1.0 - E2 * la.sin().powi(2)).sqrt();
    Vector3::new(
        (n + h) * la.cos() * lo.cos(),
        (n + h) * la.cos() * lo.sin(),
        (n * (1.0 - E2) + h) * la.sin(),
    )
}

/// GPS time of week for a Unix time.
fn tow(unix: f64) -> f64 {
    (unix - GPS_UNIX_EPOCH + LEAP_SECONDS).rem_euclid(WEEK)
}

fn utc(unix: f64) -> nmea::Utc {
    #[allow(clippy::cast_possible_truncation, reason = "Unix seconds fit")]
    let t = chrono::DateTime::from_timestamp(unix.floor() as i64, 0).unwrap_or_default();
    nmea::Utc {
        time: t.format("%H%M%S.00").to_string(),
        date: t.format("%d%m%y").to_string(),
    }
}

impl Engine {
    fn eph(&self, prn: u8, t: f64) -> Option<&Ephemeris> {
        self.ephs
            .get(&prn)
            .and_then(|l| rinex::nearest(l, t))
            .filter(|e| e.health == 0)
    }

    /// GPS PRNs above the horizon at `t` for the approximate position, highest first.
    fn visible(&self, t: f64) -> Vec<u8> {
        let up = self.approx.normalize();
        let mut v: Vec<(f64, u8)> = (1..=32)
            .filter_map(|p| {
                let (s, _) = orbit::position(self.eph(p, t)?, t);
                let el = (s - self.approx).normalize().dot(&up);
                (el > 0.0).then_some((-el, p))
            })
            .collect();
        v.sort_by(|a, b| a.0.total_cmp(&b.0));
        v.into_iter().map(|(_, p)| p).collect()
    }

    fn fix(&self, unix: f64, out: &mut impl Write) -> io::Result<()> {
        let t = tow(unix);
        let good: Vec<Channel> = self
            .chans
            .iter()
            .filter(|c| c.system == meas::GPS && c.cn0 >= MIN_CN0)
            .copied()
            .collect();
        let up = self.approx.normalize();
        let obs: Vec<spp::Observation> =
            meas::transmit_times(&good, |p| self.eph(p, t), t, self.approx)
                .into_iter()
                .filter_map(|(eph, ttx)| {
                    let el = (orbit::position(eph, ttx).0 - self.approx)
                        .normalize()
                        .dot(&up)
                        .asin();
                    // Above 10 degrees, less a mapped standard troposphere.
                    (el > MASK.to_radians()).then(|| spp::Observation {
                        eph,
                        range: orbit::C * orbit::dt(t, ttx) - 2.47 / (el.sin() + 0.0121),
                    })
                })
                .collect();
        let Some(fix) = best_fix(&obs, t, self.approx) else {
            return Ok(());
        };
        let (lat, lon, h) = spp::geodetic(&fix.ecef);
        let u = utc(unix);
        out.write_all(nmea::gga(&u, lat, lon, h, obs.len(), 0.0).as_bytes())?;
        out.write_all(nmea::rmc(&u, lat, lon).as_bytes())?;
        out.flush()
    }

    /// Handles one frame received at Unix time `unix`; returns commands to send.
    fn frame(&mut self, f: &mtk::Frame, unix: f64, out: &mut impl Write) -> io::Result<Vec<u8>> {
        if let Some(ms) = mtk::time_tag_ms(f) {
            self.tag = Some((ms, unix));
            self.chans.clear();
        } else if f.id == mtk::id::CHANNEL {
            self.chans.extend(meas::channel(&f.payload));
        } else if f.id == mtk::id::EPOCH_LAST {
            if let Some((ms, at)) = self.tag {
                self.fix(at, out)?;
                let next = tow(at + 1.0);
                return Ok(dsp::epoch(
                    ms,
                    next,
                    &dsp::search_order(&self.visible(next)),
                ));
            }
        }
        Ok(Vec::new())
    }
}

/// The solution, or with six or more satellites the best one leaving out a
/// single satellite, if its residuals and distance from the approximate
/// position are plausible.
fn best_fix(obs: &[spp::Observation], t: f64, approx: Vector3<f64>) -> Option<spp::Fix> {
    if obs.len() < MIN_SATS {
        return None;
    }
    let mut fix = spp::solve(obs, t, approx)?;
    if fix.rms > MAX_RMS / 2.0 && obs.len() > MIN_SATS {
        for skip in 0..obs.len() {
            let rest: Vec<spp::Observation> = obs
                .iter()
                .enumerate()
                .filter(|&(i, _)| i != skip)
                .map(|(_, o)| o.clone())
                .collect();
            if let Some(f) = spp::solve(&rest, t, approx).filter(|f| f.rms < fix.rms) {
                fix = f;
            }
        }
    }
    (fix.rms < MAX_RMS && (fix.ecef - approx).norm() < MAX_FROM_APPROX).then_some(fix)
}

fn now() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0.0, |d| d.as_secs_f64())
}

fn arg(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1))
        .cloned()
}

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let usage = || {
        io::Error::other(
            "usage: marathon-gnssd --nav RINEX --approx LAT,LON,H [--device DEV | --replay FILE]",
        )
    };
    let nav = std::fs::read_to_string(arg(&args, "--nav").ok_or_else(usage)?)?;
    let approx: Vec<f64> = arg(&args, "--approx")
        .ok_or_else(usage)?
        .split(',')
        .filter_map(|s| s.parse().ok())
        .collect();
    let [lat, lon, h] = approx[..] else {
        return Err(usage());
    };
    let mut engine = Engine {
        ephs: rinex::parse_gps(&nav),
        approx: ecef(lat, lon, h),
        tag: None,
        chans: Vec::new(),
    };
    let mut out = io::stdout().lock();
    let mut deframer = Deframer::default();

    if let Some(path) = arg(&args, "--replay") {
        let data = std::fs::read(path)?;
        let mut i = 0;
        while i + 20 <= data.len() {
            let ns = u64::from_le_bytes(data[i..i + 8].try_into().map_err(io::Error::other)?);
            let len =
                u32::from_le_bytes(data[i + 16..i + 20].try_into().map_err(io::Error::other)?);
            let n = usize::try_from(len).map_err(io::Error::other)?;
            #[allow(clippy::cast_precision_loss, reason = "ms precision is enough")]
            let unix = ns as f64 / 1e9;
            for f in data[i + 20..(i + 20 + n).min(data.len())]
                .iter()
                .filter_map(|&b| deframer.push(b))
            {
                engine.frame(&f, unix, &mut out)?;
            }
            i += 20 + n;
        }
        return Ok(());
    }

    let path = arg(&args, "--device").unwrap_or_else(|| "/dev/gnss0".into());
    let mut dev = OpenOptions::new().read(true).write(true).open(path)?;
    let mut record = arg(&args, "--record")
        .map(std::fs::File::create)
        .transpose()?;
    dev.write_all(&dsp::start())?;
    let mut buf = [0u8; 4096];
    loop {
        let n = dev.read(&mut buf)?;
        if n == 0 {
            return Ok(());
        }
        let unix = now();
        if let Some(r) = record.as_mut() {
            #[allow(
                clippy::cast_possible_truncation,
                clippy::cast_sign_loss,
                reason = "ns since 1970"
            )]
            let ns = (unix * 1e9) as u64;
            let len = u32::try_from(n).map_err(io::Error::other)?;
            r.write_all(
                &[
                    &ns.to_le_bytes()[..],
                    &[0; 8],
                    &len.to_le_bytes(),
                    &buf[..n],
                ]
                .concat(),
            )?;
        }
        for f in buf[..n].iter().filter_map(|&b| deframer.push(b)) {
            let cmds = engine.frame(&f, unix, &mut out)?;
            if !cmds.is_empty() {
                dev.write_all(&cmds)?;
            }
        }
    }
}
