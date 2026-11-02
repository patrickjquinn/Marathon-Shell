//! marathon-gnssd --nav RINEX --approx LAT,LON,HEIGHT [--systems GC]
//!                [--device DEV | --replay CAPTURE] [--record FILE]
//!
//! Opens the GNSS device (which boots the DSP), keeps the DSP searching, and
//! prints NMEA GGA/RMC for each epoch with a fix from GPS (G), BeiDou (C)
//! and, on request, GLONASS (R), whose pseudoranges still carry unexplained
//! per-satellite errors of hundreds of metres. Ephemerides come from a RINEX 3 navigation file, the
//! approximate position and ellipsoidal height from the caller.
//! `--replay` runs a `mtk-gnss-capture` recording instead of the device;
//! `--record FILE` writes what the device sends in that format.

use marathon_gnssd::lnav::Ephemeris;
use marathon_gnssd::meas::{self, Channel};
use marathon_gnssd::mtk::{self, Deframer};
use marathon_gnssd::rinex::{self, LEAP_SECONDS};
use marathon_gnssd::sat::Sat;
use marathon_gnssd::{dsp, nmea, orbit, spp};
use nalgebra::Vector3;
use std::fs::OpenOptions;
use std::io::{self, Read, Write};
use std::time::{SystemTime, UNIX_EPOCH};

const GPS_UNIX_EPOCH: f64 = 315_964_800.0;
const WEEK: f64 = 604_800.0;
const MIN_CN0: u8 = 20;
const MASK: f64 = 10.0;
/// Largest normalised residual RMS of an accepted fix.
const MAX_CHI: f64 = 3.0;
const MAX_FROM_APPROX: f64 = 5_000.0;
/// Geometry too weak to trust beyond this.
const MAX_HDOP: f64 = 10.0;
/// Height constraint sigma, metres.
const HEIGHT_SIGMA: f64 = 10.0;
/// Pseudorange sigma at zenith per system (GPS, GLONASS, BeiDou), metres.
const SIGMA: [f64; 3] = [10.0, 60.0, 15.0];
/// BeiDou time is GPS time less 14 s and the receiver adds no measurable
/// bias between the two (reference runs: within 25 m), so its clock is tied
/// to the GPS clock; GLONASS keeps a free one.
const BIAS_SIGMA: [Option<f64>; 3] = [None, None, Some(30.0)];

struct Engine {
    nav: rinex::Nav,
    systems: [bool; 3],
    approx: Vector3<f64>,
    height: f64,
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
    #[allow(clippy::cast_possible_truncation, reason = "Unix centiseconds fit")]
    let cs = (unix * 100.0).round() as i64;
    let t = chrono::DateTime::from_timestamp(cs.div_euclid(100), 0).unwrap_or_default();
    nmea::Utc {
        time: format!("{}.{:02}", t.format("%H%M%S"), cs.rem_euclid(100)),
        date: t.format("%d%m%y").to_string(),
    }
}

impl Engine {
    fn kepler(list: Option<&Vec<Ephemeris>>, t: f64) -> Option<&Ephemeris> {
        list.and_then(|l| rinex::nearest(l, t))
            .filter(|e| e.health == 0)
    }

    fn elevation(&self, sat: &Sat, t: f64) -> f64 {
        let up = self.approx.normalize();
        (sat.position(t).0 - self.approx)
            .normalize()
            .dot(&up)
            .asin()
    }

    /// The satellite a channel tracks. GLONASS channels report a frequency
    /// slot; of the satellites sharing it the one above the horizon is meant.
    fn sat(&self, c: &Channel, t: f64) -> Option<Sat<'_>> {
        match c.system {
            meas::GPS if self.systems[0] => Self::kepler(self.nav.gps.get(&c.sv), t).map(Sat::Gps),
            meas::BEIDOU if self.systems[2] => {
                Self::kepler(self.nav.beidou.get(&c.sv), t - 14.0).map(|e| Sat::beidou(e, c.sv))
            }
            meas::GLONASS if self.systems[1] => self
                .nav
                .glonass
                .values()
                .filter_map(|l| {
                    l.iter().min_by(|a, b| {
                        orbit::dt(t, a.tb)
                            .abs()
                            .total_cmp(&orbit::dt(t, b.tb).abs())
                    })
                })
                .filter(|e| e.health == 0 && i16::from(e.k) + 8 == i16::from(c.sv))
                .map(Sat::Glonass)
                .max_by(|a, b| self.elevation(a, t).total_cmp(&self.elevation(b, t))),
            _ => None,
        }
    }

    /// GPS PRNs above the horizon at `t` for the approximate position, highest first.
    fn visible(&self, t: f64) -> Vec<u8> {
        let mut v: Vec<(f64, u8)> = (1..=32)
            .filter_map(|p| {
                let el = self.elevation(&Sat::Gps(Self::kepler(self.nav.gps.get(&p), t)?), t);
                (el > 0.0).then_some((-el, p))
            })
            .collect();
        v.sort_by(|a, b| a.0.total_cmp(&b.0));
        v.into_iter().map(|(_, p)| p).collect()
    }

    fn fix(&mut self, unix: f64, out: &mut impl Write) -> io::Result<()> {
        let t = tow(unix);
        let (fix, used) = {
            let tracked: Vec<(Channel, Sat)> = self
                .chans
                .iter()
                .filter(|c| c.locked && c.cn0 >= MIN_CN0)
                .filter_map(|c| Some((*c, self.sat(c, t)?)))
                .filter(|(_, s)| self.elevation(s, t) > MASK.to_radians())
                .collect();
            let tracked = meas::doppler_consistent(&tracked, t, self.approx);
            // GPS first: its clock is the one reported.
            let mut ordered = tracked.clone();
            ordered.sort_by_key(|(_, s)| s.system());
            let obs: Vec<spp::Observation> = meas::transmit_times(&ordered, t, self.approx)
                .into_iter()
                .map(|(sat, ttx)| {
                    let el = self.elevation(&sat, ttx);
                    spp::Observation {
                        sat,
                        // less a mapped standard troposphere
                        range: orbit::C * orbit::dt(t, ttx) - 2.47 / (el.sin() + 0.0121),
                        sigma: SIGMA[sat.system()] / el.sin(),
                    }
                })
                .collect();
            (best_fix(&obs, t, self.approx, self.height), obs.len())
        };
        let Some(fix) = fix else {
            return Ok(());
        };
        let (lat, lon, h) = spp::geodetic(&fix.ecef);
        if fix.redundancy >= 2 {
            self.height = h;
        }
        #[allow(clippy::cast_possible_truncation, reason = "degrees")]
        let geoid = f64::from(egm2008::geoid_height(lat as f32, lon as f32).unwrap_or(0.0));
        // The receiver clock bias puts the epoch on GPS time.
        let u = utc(unix - fix.clock);
        out.write_all(nmea::gga(&u, lat, lon, h - geoid, geoid, used, fix.hdop).as_bytes())?;
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

/// The solution, or the best one leaving out a single satellite when there
/// is redundancy to spare, if it is consistent and near the approximate
/// position.
fn best_fix(
    obs: &[spp::Observation],
    t: f64,
    approx: Vector3<f64>,
    height: f64,
) -> Option<spp::Fix> {
    let constraint = Some((height, HEIGHT_SIGMA));
    let full = spp::solve(obs, t, approx, constraint, BIAS_SIGMA);
    let mut fix = full.unwrap_or(spp::Fix {
        ecef: approx,
        clock: 0.0,
        chi: f64::INFINITY,
        hdop: 0.0,
        redundancy: obs.len(),
    });
    if fix.chi > MAX_CHI / 2.0 && fix.redundancy >= 2 {
        for skip in 0..obs.len() {
            let rest: Vec<spp::Observation> = obs
                .iter()
                .enumerate()
                .filter(|&(i, _)| i != skip)
                .map(|(_, o)| *o)
                .collect();
            if let Some(f) =
                spp::solve(&rest, t, approx, constraint, BIAS_SIGMA).filter(|f| f.chi < fix.chi)
            {
                fix = f;
            }
        }
    }
    (fix.chi < MAX_CHI && fix.hdop < MAX_HDOP && (fix.ecef - approx).norm() < MAX_FROM_APPROX)
        .then_some(fix)
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
            "usage: marathon-gnssd --nav RINEX --approx LAT,LON,H [--systems GRC] [--device DEV | --replay FILE]",
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
    let systems = arg(&args, "--systems").unwrap_or_else(|| "GC".into());
    let mut engine = Engine {
        nav: rinex::parse(&nav),
        systems: ['G', 'R', 'C'].map(|c| systems.contains(c)),
        approx: ecef(lat, lon, h),
        height: h,
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
