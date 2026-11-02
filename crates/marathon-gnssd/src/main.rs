//! marathon-gnssd [--approx LAT,LON,H | --guess LAT,LON,H] [--state FILE] [--nav RINEX]
//!                [--systems GC] [--device DEV | --replay CAPTURE]
//!                [--record FILE]
//!
//! Opens the GNSS device (which boots the DSP), keeps the DSP searching, and
//! writes NMEA GGA/RMC for each epoch with a fix from GPS (G), BeiDou (C)
//! and, on request, GLONASS (R), whose pseudoranges still carry per-satellite
//! errors of hundreds of metres. Ephemerides come from the satellites' own
//! navigation messages; a RINEX 3 navigation file (`--nav`) only speeds up
//! the first fix.
//!
//! The approximate position is `--approx`, else the one saved in `--state`
//! by an earlier run, else `--guess` or the system time zone's; from a guess
//! that coarse the first fix searches up to 2500 km around it.
//!
//! Started by systemd's socket (marathon-gnssd.socket) it serves NMEA to
//! each client of that socket, opens the device only while one is connected
//! and exits when the last one leaves. Otherwise NMEA goes to stdout.
//! `--replay` runs a `mtk-gnss-capture` recording instead of the device;
//! `--record FILE` writes what the device sends in that format.

use marathon_gnssd::filter::Filter;
use marathon_gnssd::lnav::{Ephemeris, EphemerisBuilder};
use marathon_gnssd::meas::{self, Channel};
use marathon_gnssd::mtk::{self, Deframer};
use marathon_gnssd::rinex::{self, LEAP_SECONDS};
use marathon_gnssd::sat::Sat;
use marathon_gnssd::{d1, dsp, iono, lnav, nmea, orbit, spp, tz};
use nalgebra::Vector3;
use std::collections::HashMap;
use std::fs::OpenOptions;
use std::io::{self, Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const GPS_UNIX_EPOCH: f64 = 315_964_800.0;
const WEEK: f64 = 604_800.0;
const MIN_CN0: u8 = 20;
const MASK: f64 = 10.0;
/// Largest normalised residual RMS of an accepted fix.
const MAX_CHI: f64 = 3.0;
const MAX_FROM_APPROX: f64 = 5_000.0;
/// Geometry too weak to trust beyond this.
const MAX_HDOP: f64 = 10.0;
/// Horizontal error at HDOP 1, metres, for the filter.
const UERE: f64 = 10.0;
/// The coarse search: radius and grid step around the guess, metres, and
/// the GPS satellites it needs.
const COARSE_RADIUS: f64 = 2_500e3;
const COARSE_STEP: f64 = 75e3;
const COARSE_SATS: usize = 5;
/// Height prior of the coarse search: sea level, give or take mountains.
const COARSE_HEIGHT_SIGMA: f64 = 500.0;
/// Epochs with that many satellites but no fix before the approximate
/// position is presumed wrong and the coarse search starts again.
const STARVED: u32 = 60;
/// Seconds between saves of the position to `--state`.
const SAVE_EVERY: f64 = 60.0;
/// Seconds without a client before the daemon exits.
const IDLE: f64 = 10.0;
/// Height samples (redundant, strong geometry) before they replace --approx.
const HEIGHT_SAMPLES: usize = 30;
/// Height constraint sigma, metres, once the height is known; while it is
/// only a guess (sea level where the coarse search landed), the looser one.
const HEIGHT_SIGMA: f64 = 10.0;
const GUESSED_HEIGHT_SIGMA: f64 = 50.0;
/// Pseudorange sigma at zenith per system (GPS, GLONASS, BeiDou), metres.
const SIGMA: [f64; 3] = [10.0, 60.0, 15.0];
/// BeiDou time is GPS time less 14 s and the receiver adds no measurable
/// bias between the two (reference runs: within 25 m), so its clock is tied
/// to the GPS clock; GLONASS keeps a free one.
const BIAS_SIGMA: [Option<f64>; 3] = [None, None, Some(100.0)];

#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn log(msg: &str) {
    eprintln!("{msg}");
}

struct Engine {
    nav: rinex::Nav,
    systems: [bool; 3],
    approx: Vector3<f64>,
    /// Ellipsoidal height for the constraint, and its sigma.
    height: (f64, f64),
    /// Heights of well-determined fixes, for the height constraint.
    heights: Vec<f64>,
    tag: Option<(u32, f64)>,
    chans: Vec<Channel>,
    subframes: HashMap<u8, EphemerisBuilder>,
    d1: HashMap<u8, d1::EphemerisBuilder>,
    iono: Option<[f64; 8]>,
    filter: Filter,
    /// The approximate position is only a guess (time zone, old state).
    coarse: bool,
    starved: u32,
    state: Option<String>,
    saved: f64,
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

/// Geoid height (EGM2008) above the ellipsoid, metres.
fn geoid(lat: f64, lon: f64) -> f64 {
    #[allow(clippy::cast_possible_truncation, reason = "degrees")]
    f64::from(egm2008::geoid_height(lat as f32, lon as f32).unwrap_or(0.0))
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

    /// Azimuth and elevation (radians) from the approximate position.
    fn az_el(&self, sat: &Sat, t: f64) -> (f64, f64) {
        let (lat, lon, _) = spp::geodetic(&self.approx);
        let (la, lo) = (lat.to_radians(), lon.to_radians());
        let d = (sat.position(t).0 - self.approx).normalize();
        let east = Vector3::new(-lo.sin(), lo.cos(), 0.0);
        let north = Vector3::new(-la.sin() * lo.cos(), -la.sin() * lo.sin(), la.cos());
        let up = Vector3::new(la.cos() * lo.cos(), la.cos() * lo.sin(), la.sin());
        (d.dot(&east).atan2(d.dot(&north)), d.dot(&up).asin())
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
        let (fix, used, gps, coarse) = {
            let tracked: Vec<(Channel, Sat)> = self
                .chans
                .iter()
                .filter(|c| c.locked && c.cn0 >= MIN_CN0)
                .filter_map(|c| Some((*c, self.sat(c, t)?)))
                .filter(|(_, s)| self.coarse || self.elevation(s, t) > MASK.to_radians())
                .collect();
            // From a coarse guess the geometric Doppler is too far off to check.
            let tracked = if self.coarse {
                tracked
            } else {
                meas::doppler_consistent(&tracked, t, self.approx)
            };
            let gps = tracked.iter().filter(|(_, s)| s.system() == 0).count();
            if self.coarse {
                let found = (gps >= COARSE_SATS)
                    .then(|| self.coarse_fix(&tracked, t))
                    .flatten();
                (None, 0, gps, Some(found))
            } else {
                // GPS first: its clock is the one reported.
                let mut ordered = tracked.clone();
                ordered.sort_by_key(|(_, s)| s.system());
                let obs: Vec<spp::Observation> = meas::transmit_times(&ordered, t, self.approx)
                    .into_iter()
                    .map(|(sat, ttx)| {
                        let (az, el) = self.az_el(&sat, ttx);
                        // less a mapped standard troposphere and the broadcast ionosphere
                        let tropo = 2.47 / (el.sin() + 0.0121);
                        let iono = self.iono.map_or(0.0, |k| {
                            let (lat, lon, _) = spp::geodetic(&self.approx);
                            let l1 = 1_575.42e6 / sat.carrier();
                            orbit::C
                                * iono::delay(&k, lat.to_radians(), lon.to_radians(), az, el, t)
                                * l1
                                * l1
                        });
                        spp::Observation {
                            sat,
                            range: orbit::C * orbit::dt(t, ttx) - tropo - iono,
                            sigma: SIGMA[sat.system()] / el.sin(),
                        }
                    })
                    .collect();
                (
                    best_fix(&obs, t, self.approx, self.height),
                    obs.len(),
                    gps,
                    None,
                )
            }
        };
        if let Some(found) = coarse {
            if let Some(f) = found {
                let (lat, lon, _) = spp::geodetic(&f.ecef);
                log(&format!(
                    "coarse fix {lat:.3},{lon:.3} from {gps} satellites"
                ));
                self.approx = f.ecef;
                self.height = (geoid(lat, lon), GUESSED_HEIGHT_SIGMA);
                self.coarse = false;
            }
            return Ok(());
        }
        let Some(fix) = fix else {
            if gps >= COARSE_SATS {
                self.starved += 1;
                if self.starved >= STARVED {
                    log("no fix near the approximate position, searching wider");
                    self.coarse = true;
                    self.starved = 0;
                }
            }
            return Ok(());
        };
        self.starved = 0;
        let Some(pos) = self.filter.update(unix, fix.ecef, UERE * fix.hdop.max(1.0)) else {
            return Ok(());
        };
        let (_, _, h) = spp::geodetic(&fix.ecef);
        if fix.redundancy >= 3 && fix.hdop < 2.0 {
            self.heights.push(h);
            if self.heights.len() >= HEIGHT_SAMPLES {
                let mut sorted = self.heights.split_off(0);
                sorted.sort_by(f64::total_cmp);
                self.height = (sorted[sorted.len() / 2], HEIGHT_SIGMA);
            }
        }
        if fix.hdop < 3.0 {
            self.approx = pos;
            self.save(unix);
        }
        let (lat, lon, h) = spp::geodetic(&pos);
        let geoid = geoid(lat, lon);
        // The receiver clock bias puts the epoch on GPS time.
        let u = utc(unix - fix.clock);
        out.write_all(nmea::gga(&u, lat, lon, h - geoid, geoid, used, fix.hdop).as_bytes())?;
        out.write_all(nmea::rmc(&u, lat, lon).as_bytes())?;
        out.flush()
    }

    /// A GPS-only solution from a grid of starting points around a guess that
    /// may be far off: whole code periods are resolved anew from each, and
    /// the consistent solution with the smallest residuals wins.
    fn coarse_fix(&self, tracked: &[(Channel, Sat)], t: f64) -> Option<spp::Fix> {
        let gps: Vec<(Channel, Sat)> = tracked
            .iter()
            .filter(|(_, s)| s.system() == 0)
            .copied()
            .collect();
        let (lat0, lon0, _) = spp::geodetic(&self.approx);
        #[allow(clippy::cast_possible_truncation, reason = "a few dozen steps")]
        let n = (COARSE_RADIUS / COARSE_STEP) as i32;
        let mut best: Option<spp::Fix> = None;
        for i in -n..=n {
            for j in -n..=n {
                let (north, east) = (f64::from(i) * COARSE_STEP, f64::from(j) * COARSE_STEP);
                if north.hypot(east) > COARSE_RADIUS {
                    continue;
                }
                let lat = (lat0 + north / 111_320.0).clamp(-89.0, 89.0);
                let lon = lon0 + east / (111_320.0 * lat.to_radians().cos());
                let start = ecef(lat, lon, 0.0);
                let up = start.normalize();
                // Every satellite tracked is above this horizon.
                if gps
                    .iter()
                    .any(|(_, s)| (s.position(t).0 - start).dot(&up) < 0.0)
                {
                    continue;
                }
                let obs: Vec<spp::Observation> = meas::transmit_times(&gps, t, start)
                    .into_iter()
                    .map(|(sat, ttx)| spp::Observation {
                        sat,
                        range: orbit::C * orbit::dt(t, ttx),
                        sigma: SIGMA[0],
                    })
                    .collect();
                let Some(f) =
                    spp::solve(&obs, t, start, Some((0.0, COARSE_HEIGHT_SIGMA)), BIAS_SIGMA)
                else {
                    continue;
                };
                if f.redundancy >= 2
                    && f.hdop < 5.0
                    && (f.ecef - start).norm() < COARSE_STEP
                    && best.as_ref().is_none_or(|b| f.chi < b.chi)
                {
                    best = Some(f);
                }
            }
        }
        best.filter(|f| f.chi < MAX_CHI)
    }

    /// Saves the approximate position for the next start, now and then.
    fn save(&mut self, unix: f64) {
        let Some(path) = &self.state else {
            return;
        };
        if unix - self.saved < SAVE_EVERY {
            return;
        }
        self.saved = unix;
        let (lat, lon, h) = spp::geodetic(&self.approx);
        let tmp = format!("{path}.new");
        let saved = std::fs::write(&tmp, format!("{lat:.5},{lon:.5},{h:.0}\n"))
            .and_then(|()| std::fs::rename(&tmp, path));
        if let Err(e) = saved {
            log(&format!("{path}: {e}"));
        }
    }

    /// Handles one frame received at Unix time `unix`; returns commands to send.
    fn frame(&mut self, f: &mtk::Frame, unix: f64, out: &mut impl Write) -> io::Result<Vec<u8>> {
        if let Some(ms) = mtk::time_tag_ms(f) {
            self.tag = Some((ms, unix));
            self.chans.clear();
        } else if f.id == mtk::id::CHANNEL {
            self.chans.extend(meas::channel(&f.payload));
        } else if f.id == mtk::id::GPS_SUBFRAME {
            if let Some((prn, sf)) = meas::gps_subframe(&f.payload) {
                self.iono = lnav::klobuchar(&sf).or(self.iono);
                if let Some(e) = self.subframes.entry(prn).or_default().add(sf) {
                    self.nav.gps.insert(prn, vec![e]);
                }
            }
        } else if f.id == mtk::id::BEIDOU_SUBFRAME {
            if let Some((prn, sf)) = meas::beidou_subframe(&f.payload) {
                if let Some(e) = self.d1.entry(prn).or_default().add(sf) {
                    self.nav.beidou.insert(prn, vec![e]);
                }
            }
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
    height: (f64, f64),
) -> Option<spp::Fix> {
    let constraint = Some(height);
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

/// The NMEA clients of the listening socket. Each has a thread that waits
/// for it to hang up; one that cannot keep up is dropped.
#[derive(Clone, Default)]
struct Clients(Arc<Mutex<Vec<(u64, UnixStream)>>>);

impl Clients {
    fn len(&self) -> usize {
        self.0.lock().map_or(0, |c| c.len())
    }

    fn add(&self, id: u64, s: UnixStream) {
        s.set_write_timeout(Some(Duration::from_secs(1))).ok();
        let Ok(mut reader) = s.try_clone() else {
            return;
        };
        if let Ok(mut c) = self.0.lock() {
            c.push((id, s));
        }
        let clients = self.clone();
        std::thread::spawn(move || {
            io::copy(&mut reader, &mut io::sink()).ok();
            if let Ok(mut c) = clients.0.lock() {
                c.retain(|(i, _)| *i != id);
            }
        });
    }

    /// Takes the first client now and the rest as they come.
    fn serve(listener: UnixListener) -> io::Result<Self> {
        let clients = Self::default();
        clients.add(0, listener.accept()?.0);
        let more = clients.clone();
        std::thread::spawn(move || {
            for (id, s) in (1..).zip(listener.incoming().flatten()) {
                more.add(id, s);
            }
        });
        Ok(clients)
    }
}

impl Write for Clients {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        if let Ok(mut c) = self.0.lock() {
            c.retain_mut(|(_, s)| s.write_all(buf).is_ok());
        }
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

/// systemd's socket (marathon-gnssd.socket), if this process was given one.
fn activation_socket() -> Option<UnixListener> {
    use std::os::fd::FromRawFd as _;
    if std::env::var("LISTEN_PID").ok() != Some(std::process::id().to_string())
        || std::env::var("LISTEN_FDS").ok().as_deref() != Some("1")
    {
        return None;
    }
    // SAFETY: systemd passed exactly one socket, as fd 3, to this process.
    Some(unsafe { UnixListener::from_raw_fd(3) })
}

fn parse_position(s: &str) -> Option<(f64, f64, f64)> {
    let v: Vec<f64> = s.trim().split(',').filter_map(|x| x.parse().ok()).collect();
    match v[..] {
        [lat, lon, h] => Some((lat, lon, h)),
        _ => None,
    }
}

/// The system time zone's location, at sea level.
fn time_zone_position() -> Option<(f64, f64, f64)> {
    let zone = std::fs::read_link("/etc/localtime").ok()?;
    let zone = zone.to_str()?.split("zoneinfo/").nth(1)?.to_owned();
    let table = std::fs::read_to_string("/usr/share/zoneinfo/zone1970.tab").ok()?;
    let (lat, lon) = tz::position(&table, &zone)?;
    Some((lat, lon, 0.0))
}

/// Runs a `mtk-gnss-capture` recording through the engine.
fn replay(engine: &mut Engine, path: &str) -> io::Result<()> {
    let mut out = io::stdout().lock();
    let mut deframer = Deframer::default();
    let data = std::fs::read(path)?;
    let mut i = 0;
    while i + 20 <= data.len() {
        let ns = u64::from_le_bytes(data[i..i + 8].try_into().map_err(io::Error::other)?);
        let len = u32::from_le_bytes(data[i + 16..i + 20].try_into().map_err(io::Error::other)?);
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
    Ok(())
}

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let nav = arg(&args, "--nav")
        .map(std::fs::read_to_string)
        .transpose()?
        .unwrap_or_default();
    let state = arg(&args, "--state");
    let given = arg(&args, "--approx").and_then(|s| parse_position(&s));
    let saved = state
        .as_ref()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|s| parse_position(&s));
    let (lat, lon, h) = given
        .or(saved)
        .or_else(|| arg(&args, "--guess").and_then(|s| parse_position(&s)))
        .or_else(time_zone_position)
        .ok_or_else(|| io::Error::other("no --approx, --state or time zone to start from"))?;
    let systems = arg(&args, "--systems").unwrap_or_else(|| "GC".into());
    let mut engine = Engine {
        nav: rinex::parse(&nav),
        systems: ['G', 'R', 'C'].map(|c| systems.contains(c)),
        approx: ecef(lat, lon, h),
        height: (h, HEIGHT_SIGMA),
        heights: Vec::new(),
        tag: None,
        chans: Vec::new(),
        subframes: HashMap::new(),
        d1: HashMap::new(),
        iono: None,
        filter: Filter::default(),
        coarse: given.is_none() && saved.is_none(),
        starved: 0,
        state,
        saved: 0.0,
    };
    if let Some(path) = arg(&args, "--replay") {
        return replay(&mut engine, &path);
    }

    let clients = activation_socket().map(Clients::serve).transpose()?;
    let mut out: Box<dyn Write> = match &clients {
        Some(c) => Box::new(c.clone()),
        None => Box::new(io::stdout().lock()),
    };
    let path = arg(&args, "--device").unwrap_or_else(|| "/dev/gnss0".into());
    let mut dev = OpenOptions::new().read(true).write(true).open(path)?;
    let mut record = arg(&args, "--record")
        .map(std::fs::File::create)
        .transpose()?;
    dev.write_all(&dsp::start())?;
    let mut deframer = Deframer::default();
    let mut buf = [0u8; 4096];
    let mut alone_since = None;
    loop {
        let n = dev.read(&mut buf)?;
        if n == 0 {
            return Ok(());
        }
        let unix = now();
        if let Some(c) = &clients {
            if c.len() > 0 {
                alone_since = None;
            } else if unix - *alone_since.get_or_insert(unix) > IDLE {
                return Ok(());
            }
        }
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
