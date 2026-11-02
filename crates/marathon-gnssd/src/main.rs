//! marathon-gnssd [--approx LAT,LON,H | --guess LAT,LON,H] [--state FILE] [--nav RINEX]
//!                [--systems GC] [--device DEV | --replay CAPTURE]
//!                [--record FILE] [--clock-sweep]
//!
//! Opens the GNSS device (which boots the DSP), keeps the DSP searching, and
//! writes NMEA GGA/RMC for each epoch with a fix from GPS (G), BeiDou (C)
//! and, on request, GLONASS (R). GLONASS pseudoranges carry a bias of up to
//! a few hundred metres per frequency slot, so each slot is used only after
//! 30 strong fixes have measured its bias. GPS and BeiDou ephemerides come
//! from the satellites' own navigation messages; GLONASS ones only from a
//! RINEX 3 navigation file (`--nav`), which otherwise just speeds up the
//! first fix.
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

use marathon_gnssd::almanac::{self, Almanac};
use marathon_gnssd::filter::Filter;
use marathon_gnssd::lnav::{Ephemeris, EphemerisBuilder};
use marathon_gnssd::meas::{self, Channel};
use marathon_gnssd::mtk::{self, Deframer};
use marathon_gnssd::rinex::{self, LEAP_SECONDS};
use marathon_gnssd::sat::Sat;
use marathon_gnssd::{clock, d1, dsp, iono, lnav, nmea, orbit, spp, tz};
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
const COARSE_SATS: usize = 3;
/// Doppler residual RMS (m/s) of an accepted coarse position, and how far
/// apart (m) two candidates must be to count as rivals.
const COARSE_DOPPLER: f64 = 0.5;
const COARSE_DISTINCT: f64 = 20e3;
/// Epochs a cell's Doppler fit is averaged over before it can be picked, and
/// how much worse the best rival must fit.
const COARSE_EPOCHS: u32 = 5;
const COARSE_RATIO: f64 = 2.5;
/// Coarse epochs without an answer before the search covers the whole Earth,
/// and how often (in such epochs) that search then runs.
const COARSE_TRIES: u32 = 30;
const GLOBAL_EVERY: u32 = 5;
/// Height prior of the coarse search: sea level, give or take mountains.
const COARSE_HEIGHT_SIGMA: f64 = 500.0;
/// Epochs with that many satellites but no fix before the approximate
/// position is presumed wrong and the coarse search starts again.
const STARVED: u32 = 60;
/// Epochs of residuals before a GLONASS frequency slot's bias is used, and
/// how many are kept.
const SLOT_SAMPLES: usize = 30;
const SLOT_SAMPLES_KEPT: usize = 300;
/// --clock-sweep: seconds per step, first aid, step, number of steps after the first.
const SWEEP_SECONDS: f64 = 45.0;
const SWEEP_FROM: i32 = -600;
const SWEEP_STEP: i32 = 300;
const SWEEP_STEPS: i32 = 12;
/// Seconds between corrections of the crystal model.
const LEARN_EVERY: f64 = 5.0;
/// Thermistor code assumed before the DSP has reported one.
const TSX_DEFAULT: u16 = 29_986;
/// Seconds between progress lines in the journal.
const REPORT_EVERY: f64 = 30.0;
/// An almanac this complete is trusted to name every GPS satellite up, and
/// one older than this (seconds) is not used.
const ALMANAC_FULL: usize = 24;
const ALMANAC_MAX_AGE: f64 = 90.0 * 86_400.0;
/// Saved ephemerides older than this are not used (their fit interval).
const NAV_MAX_AGE: f64 = 4.0 * 3600.0;
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
const SIGMA: [f64; 3] = [10.0, 35.0, 15.0];
/// BeiDou time is GPS time less 14 s and the receiver adds no measurable
/// bias between the two (reference runs: within 25 m), so its clock is tied
/// to the GPS clock; GLONASS keeps a free one.
const BIAS_SIGMA: [Option<f64>; 3] = [None, None, Some(100.0)];

#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn log(msg: &str) {
    eprintln!("{msg}");
}

/// A coarse grid cell, its solution and that solution's Doppler RMS (m/s).
type Cell = ((i32, i32), spp::Fix, f64);

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
    almanac: HashMap<u8, Almanac>,
    /// The crystal's thermistor code, its frequency model, the last Doppler
    /// offset measured with it and when the model was last saved.
    tsx: Option<u16>,
    clock: clock::Model,
    doppler: Option<f64>,
    clock_saved: f64,
    clock_learnt: f64,
    sweep: bool,
    sweep_last: Option<i32>,
    /// The aid last sent (middle point).
    aid: i32,
    /// The head of the last search list, for the journal.
    searching: String,
    /// Residuals per GLONASS frequency slot, for its bias.
    slots: HashMap<i8, Vec<f64>>,
    /// The approximate position is only a guess (time zone, old state).
    coarse: bool,
    starved: u32,
    /// Coarse epochs with satellites to spare but no answer, and whether
    /// the search now covers the whole Earth.
    coarse_tries: u32,
    global: bool,
    /// Per coarse grid cell: summed squared Doppler RMS, epochs, last solution.
    cells: HashMap<(i32, i32), (f64, u32, spp::Fix)>,
    state: Option<String>,
    saved: f64,
    /// Progress for the journal: where the start position came from, what
    /// the last epoch did, when the run started and was last reported.
    seed: String,
    status: String,
    started: Option<f64>,
    reported: f64,
    fixes: u64,
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

/// GPS time, seconds since the GPS epoch, for a Unix time.
fn gps_time(unix: f64) -> f64 {
    unix - GPS_UNIX_EPOCH + LEAP_SECONDS
}

fn system_letter(sys: u8) -> char {
    match sys {
        dsp::GPS => 'G',
        dsp::GLONASS => 'R',
        dsp::BEIDOU => 'C',
        dsp::QZSS => 'J',
        _ => '?',
    }
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

    /// GPS PRNs expected above the horizon at Unix time `unix`, highest
    /// first, from the ephemerides or else the almanac. From a coarse guess
    /// the horizon is lowered by its possible error.
    fn visible(&self, unix: f64) -> Vec<u8> {
        let t = tow(unix);
        let horizon = if self.coarse { -25f64 } else { -5f64 }.to_radians();
        let mut v: Vec<(f64, u8)> = (1..=32)
            .filter_map(|p| {
                let alm;
                let e = if let Some(e) = Self::kepler(self.nav.gps.get(&p), t) {
                    e
                } else {
                    alm = self.almanac.get(&p)?.ephemeris(gps_time(unix));
                    if alm.health != 0 {
                        return None;
                    }
                    &alm
                };
                let el = self.elevation(&Sat::Gps(e), t);
                (el > horizon).then_some((-el, p))
            })
            .collect();
        v.sort_by(|a, b| a.0.total_cmp(&b.0));
        v.into_iter().map(|(_, p)| p).collect()
    }

    /// The search list for the epoch at `unix`: satellites in lock first
    /// (strongest first, as the stock engine does), then those expected up.
    /// With a whole almanac and a position that is not a world-wide guess,
    /// GPS satellites below the horizon are left out.
    fn search(&self, unix: f64) -> Vec<(u8, u8)> {
        let mut locked: Vec<&Channel> = self
            .chans
            .iter()
            .filter(|c| c.locked && c.cn0 >= MIN_CN0)
            .collect();
        locked.sort_by_key(|c| std::cmp::Reverse(c.cn0));
        let of = |sys| -> Vec<u8> {
            let mut v: Vec<u8> = locked
                .iter()
                .filter(|c| c.system == sys)
                .map(|c| c.sv)
                .collect();
            v.dedup();
            v
        };
        let mut gps = of(meas::GPS);
        for p in self.visible(unix) {
            if !gps.contains(&p) {
                gps.push(p);
            }
        }
        let known_sky = self.almanac.len() >= ALMANAC_FULL && !self.global;
        dsp::search_order(&gps, known_sky, &of(meas::GLONASS), &of(meas::BEIDOU))
    }

    /// Corrects the crystal model from the measured Doppler offset (not while
    /// sweeping), saving it now and then.
    fn learn_clock(&mut self, unix: f64, offset: Option<f64>) {
        let (Some(r), Some(code)) = (offset, self.tsx) else {
            return;
        };
        self.doppler = Some(r);
        // The DSP takes a few epochs to answer a new aid.
        if self.sweep_last.is_some() || unix - self.clock_learnt < LEARN_EVERY {
            return;
        }
        self.clock_learnt = unix;
        self.clock.learn(code, r);
        if unix - self.clock_saved > SAVE_EVERY {
            self.clock_saved = unix;
            if let Some(path) = &self.state {
                write_atomic(&format!("{path}.clk"), &self.clock.to_lines());
            }
        }
    }

    /// With --clock-sweep, the clock aid's middle point is stepped through
    /// absolute values, 45 s each, from -600 to 3000 in steps of 300, then
    /// handed back to the model: on a hot phone, to see at which aid
    /// satellites lock and how the Doppler offset the DSP reports answers.
    /// Returns the shift to add to the model's points.
    fn sweep_shift(&mut self, unix: f64, model: i32) -> i32 {
        if !self.sweep {
            return 0;
        }
        let elapsed = unix - self.started.unwrap_or(unix);
        #[allow(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "a few dozen steps"
        )]
        let step = (elapsed / SWEEP_SECONDS) as i32;
        let target = (step <= SWEEP_STEPS).then_some(SWEEP_FROM + step * SWEEP_STEP);
        if target != self.sweep_last {
            match target {
                Some(a) => log(&format!("clock sweep: aid {a}")),
                None => log("clock sweep: done, aid from the model"),
            }
            self.sweep_last = target;
        }
        target.map_or(0, |a| a - model)
    }

    /// Takes the median of heights measured without the constraint as the
    /// constraint, once there are enough of them.
    fn learn_height(&mut self, free_height: Option<f64>) {
        if let Some(h) = free_height {
            self.heights.push(h);
            if self.heights.len() >= HEIGHT_SAMPLES {
                let mut sorted = self.heights.split_off(0);
                sorted.sort_by(f64::total_cmp);
                self.height = (sorted[sorted.len() / 2], HEIGHT_SIGMA);
                log(&format!(
                    "height {:.0} m above the ellipsoid, from {} fixes",
                    self.height.0, HEIGHT_SAMPLES
                ));
            }
        }
    }

    /// Keeps an almanac page and saves the almanac when it changes.
    fn learn_almanac(&mut self, sf: &[u8; 30], unix: f64) {
        let Some(a) = almanac::decode(sf, gps_time(unix)) else {
            return;
        };
        if self.almanac.insert(a.prn, a).is_some_and(|old| old == a) {
            return;
        }
        if self.almanac.len() == ALMANAC_FULL {
            log(&format!("almanac: {ALMANAC_FULL} GPS satellites"));
        }
        let Some(path) = &self.state else {
            return;
        };
        let lines: Vec<String> = self.almanac.values().map(Almanac::to_line).collect();
        write_atomic(&format!("{path}.alm"), &(lines.join("\n") + "\n"));
    }

    fn fix(&mut self, unix: f64, out: &mut impl Write) -> io::Result<()> {
        let t = tow(unix);
        let (fix, used, gps, coarse, samples, (free_height, offset)) = {
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
                // The whole-Earth search takes a while: not every epoch.
                let due = !self.global || self.coarse_tries.is_multiple_of(GLOBAL_EVERY);
                let found = (gps >= COARSE_SATS && due).then(|| self.coarse_fix(&tracked, t));
                (None, 0, gps, Some(found), Vec::new(), (None, None))
            } else {
                let mut ordered = tracked.clone();
                ordered.sort_by_key(|(_, s)| s.system());
                let obs = self.observations(&ordered, t);
                // GLONASS only once its satellite's bias is known.
                let used: Vec<spp::Observation> = obs
                    .iter()
                    .filter_map(|o| match o.sat {
                        Sat::Glonass(e) => self.slot_bias(e.k).map(|b| spp::Observation {
                            range: o.range - b,
                            ..*o
                        }),
                        _ => Some(*o),
                    })
                    .collect();
                let fix = best_fix(&used, t, self.approx, self.height);
                let samples = fix
                    .as_ref()
                    .filter(|f| f.hdop < 2.0 && f.redundancy >= 2)
                    .map(|f| self.slot_samples(&obs, t, &f.ecef))
                    .unwrap_or_default();
                // The height measured without the height constraint.
                let free = fix
                    .as_ref()
                    .and_then(|f| spp::solve(&used, t, f.ecef, None, BIAS_SIGMA))
                    .filter(|g| g.chi < MAX_CHI && g.hdop < 3.0)
                    .map(|g| spp::geodetic(&g.ecef).2);
                // Known well enough without a fix: the clock error moves the
                // Doppler by hundreds of hertz, the position error by less than one.
                let at = fix.as_ref().map_or(self.approx, |f| f.ecef);
                let offset = meas::doppler_offset(&tracked, t, at);
                (fix, used.len(), gps, None, samples, (free, offset))
            }
        };
        self.learn_slots(samples);
        self.learn_clock(unix, offset);
        if let Some(found) = coarse {
            let found = found.and_then(|f| self.coarse_pick(f, gps));
            self.coarse_result(found, gps);
            return Ok(());
        }
        let Some(fix) = fix else {
            self.status = format!("no fix from {used} usable satellites");
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
            self.status = "fix refused by the filter".into();
            return Ok(());
        };
        if self.fixes == 0 {
            let after = unix - self.started.unwrap_or(unix);
            log(&format!("first fix after {after:.0} s"));
        }
        self.fixes += 1;
        self.status = format!("fixing, HDOP {:.1}, {used} satellites", fix.hdop);
        self.learn_height(free_height);
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
    /// may be far off: whole code periods are resolved anew from each. A
    /// still receiver's Doppler then picks the right one, which works from
    /// three satellites; with five or more the code residuals alone can.
    fn coarse_fix(&self, tracked: &[(Channel, Sat)], t: f64) -> Vec<Cell> {
        let gps: Vec<(Channel, Sat)> = tracked
            .iter()
            .filter(|(_, s)| s.system() == 0)
            .copied()
            .collect();
        let mut found = Vec::new();
        for (cell, lat, lon) in self.coarse_grid() {
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
            let Some(f) = spp::solve(&obs, t, start, Some((0.0, COARSE_HEIGHT_SIGMA)), BIAS_SIGMA)
            else {
                continue;
            };
            if f.hdop < MAX_HDOP && (f.ecef - start).norm() < COARSE_STEP {
                let rms = meas::doppler_rms(&gps, t, f.ecef);
                found.push((cell, f, rms));
            }
        }
        found
    }

    /// Accumulates each cell's Doppler fit over epochs and picks the cell
    /// that fits clearly better than any other more than 20 km from it; with
    /// five or more satellites, the code residuals of one epoch can decide.
    fn coarse_pick(&mut self, found: Vec<Cell>, gps: usize) -> Option<spp::Fix> {
        let by_chi = found
            .iter()
            .map(|c| c.1)
            .filter(|f| gps >= 5 && f.redundancy >= 2 && f.hdop < 5.0)
            .min_by(|a, b| a.chi.total_cmp(&b.chi))
            .filter(|f| f.chi < MAX_CHI);
        for (cell, f, rms) in found {
            let e = self.cells.entry(cell).or_insert((0.0, 0, f));
            *e = (e.0 + rms * rms, e.1 + 1, f);
        }
        #[allow(clippy::cast_precision_loss, reason = "a few hundred epochs")]
        let fits: Vec<(f64, spp::Fix)> = self
            .cells
            .values()
            .filter(|c| c.1 >= COARSE_EPOCHS)
            .map(|c| ((c.0 / f64::from(c.1)).sqrt(), c.2))
            .collect();
        let best = fits.iter().min_by(|a, b| a.0.total_cmp(&b.0));
        let picked = best.and_then(|&(rms, f)| {
            let rival = fits
                .iter()
                .filter(|c| (c.1.ecef - f.ecef).norm() > COARSE_DISTINCT)
                .map(|c| c.0)
                .fold(f64::INFINITY, f64::min);
            (rms < COARSE_DOPPLER && rival > COARSE_RATIO * rms).then_some(f)
        });
        picked.or(by_chi)
    }

    /// Pseudoranges, less the troposphere and broadcast ionosphere, for the
    /// tracked channels (GPS first: its clock is the one reported).
    fn observations<'a>(
        &'a self,
        ordered: &[(Channel, Sat<'a>)],
        t: f64,
    ) -> Vec<spp::Observation<'a>> {
        meas::transmit_times(ordered, t, self.approx)
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
            .collect()
    }

    /// The pseudorange bias of a GLONASS frequency slot relative to the
    /// others, once enough epochs have measured it.
    fn slot_bias(&self, k: i8) -> Option<f64> {
        let v = self.slots.get(&k).filter(|v| v.len() >= SLOT_SAMPLES)?;
        let mut s = v.clone();
        s.sort_by(f64::total_cmp);
        Some(s[s.len() / 2])
    }

    /// Each GLONASS satellite's residual against a fix made without the
    /// uncalibrated ones, less the epoch's common GLONASS offset (its clock).
    fn slot_samples(&self, obs: &[spp::Observation], t: f64, pos: &Vector3<f64>) -> Vec<(i8, f64)> {
        let glo: Vec<(i8, f64)> = obs
            .iter()
            .filter_map(|o| match o.sat {
                Sat::Glonass(e) => Some((e.k, o.range - spp::geometry(o, t, pos).1)),
                _ => None,
            })
            .collect();
        if glo.len() < 2 {
            return Vec::new();
        }
        let known: Vec<f64> = glo
            .iter()
            .filter_map(|&(k, r)| Some(r - self.slot_bias(k)?))
            .collect();
        #[allow(clippy::cast_precision_loss, reason = "a handful")]
        let common = if known.is_empty() {
            glo.iter().map(|g| g.1).sum::<f64>() / glo.len() as f64
        } else {
            known.iter().sum::<f64>() / known.len() as f64
        };
        glo.into_iter().map(|(k, r)| (k, r - common)).collect()
    }

    fn learn_slots(&mut self, samples: Vec<(i8, f64)>) {
        for (k, s) in samples {
            let v = self.slots.entry(k).or_default();
            if v.len() >= SLOT_SAMPLES_KEPT {
                v.remove(0);
            }
            v.push(s);
        }
    }

    /// Starting points of the coarse search: around the guess, or once that
    /// has failed for long enough, the whole Earth.
    fn coarse_grid(&self) -> Vec<((i32, i32), f64, f64)> {
        let deg = COARSE_STEP / 111_320.0;
        let (lat0, lon0) = if self.global {
            (0.0, 0.0)
        } else {
            let (lat, lon, _) = spp::geodetic(&self.approx);
            (lat, lon)
        };
        let radius = if self.global {
            90.0
        } else {
            COARSE_RADIUS / 111_320.0
        };
        #[allow(clippy::cast_possible_truncation, reason = "a few hundred steps")]
        let n = (radius / deg).ceil() as i32;
        let mut grid = Vec::new();
        for i in -n..=n {
            let dlat = f64::from(i) * deg;
            let lat = lat0 + dlat;
            if !(-89.0..=89.0).contains(&lat) {
                continue;
            }
            let cos = lat.to_radians().cos();
            let span = if self.global {
                180.0
            } else {
                (radius * radius - dlat * dlat).max(0.0).sqrt() / cos
            };
            #[allow(clippy::cast_possible_truncation, reason = "a few hundred steps")]
            let m = (span * cos / deg).floor() as i32;
            for j in -m..=m {
                grid.push(((i, j), lat, lon0 + f64::from(j) * deg / cos));
            }
        }
        grid
    }

    fn coarse_result(&mut self, found: Option<spp::Fix>, gps: usize) {
        if found.is_none() && gps >= COARSE_SATS {
            self.coarse_tries += 1;
            if self.coarse_tries == COARSE_TRIES && !self.global {
                log(&format!(
                    "nothing near {}; searching the whole Earth",
                    self.seed
                ));
                self.global = true;
                self.cells.clear();
            }
        }
        let area = if self.global {
            "the whole Earth".to_owned()
        } else {
            format!("around {}", self.seed)
        };
        self.status = if gps < COARSE_SATS {
            format!("searching {area}: {gps}/{COARSE_SATS} GPS in lock with an ephemeris")
        } else {
            format!("searching {area}: no clear position yet from {gps} GPS")
        };
        if let Some(f) = found {
            let (lat, lon, _) = spp::geodetic(&f.ecef);
            log(&format!(
                "coarse fix {lat:.3},{lon:.3} from {gps} satellites"
            ));
            self.approx = f.ecef;
            self.height = (geoid(lat, lon), GUESSED_HEIGHT_SIGMA);
            self.coarse = false;
            self.cells.clear();
        }
    }

    /// Logs where the receiver is, at most every `REPORT_EVERY` seconds.
    fn report(&mut self, unix: f64) {
        let started = *self.started.get_or_insert(unix);
        if self.reported > 0.0 && unix - self.reported < REPORT_EVERY {
            return;
        }
        self.reported = unix;
        let mut locked = [0; 3];
        for c in self.chans.iter().filter(|c| c.locked && c.cn0 >= MIN_CN0) {
            match c.system {
                meas::GPS => locked[0] += 1,
                meas::GLONASS => locked[1] += 1,
                meas::BEIDOU => locked[2] += 1,
                _ => {}
            }
        }
        let list = |m: &HashMap<u8, Vec<Ephemeris>>, p: char| {
            let mut v: Vec<u8> = m.keys().copied().collect();
            v.sort_unstable();
            v.iter()
                .map(|n| format!("{p}{n:02}"))
                .collect::<Vec<_>>()
                .join(" ")
        };
        log(&format!(
            "{:.0} s: locked GPS {} GLONASS {} BeiDou {}; ephemerides [{}] [{}]; almanac {}; crystal code {} aid {} Doppler offset {}; searching {} ...; {}",
            unix - started,
            locked[0],
            locked[1],
            locked[2],
            list(&self.nav.gps, 'G'),
            list(&self.nav.beidou, 'C'),
            self.almanac.len(),
            self.tsx.map_or_else(|| "-".into(), |c| c.to_string()),
            self.aid,
            self.doppler.map_or_else(|| "-".into(), |d| format!("{d:.0} Hz")),
            self.searching,
            self.status
        ));
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
        let (lat, lon, _) = spp::geodetic(&self.approx);
        let (h, sigma) = self.height;
        write_atomic(path, &format!("{lat:.5},{lon:.5},{h:.0},{sigma:.0}\n"));
    }

    /// Saves the ephemerides read from the sky next to the position, for a
    /// warm start within the next few hours.
    fn save_nav(&self, unix: f64) {
        let Some(path) = &self.state else {
            return;
        };
        let lines: Vec<String> = [('G', &self.nav.gps), ('C', &self.nav.beidou)]
            .into_iter()
            .flat_map(|(p, map)| {
                map.iter()
                    .filter_map(move |(prn, e)| Some(format!("{p} {prn} {}", e.first()?.to_line())))
            })
            .collect();
        write_atomic(
            &format!("{path}.nav"),
            &format!("saved {unix:.0}\n{}\n", lines.join("\n")),
        );
    }

    /// Handles one frame received at Unix time `unix`; returns commands to send.
    fn frame(&mut self, f: &mtk::Frame, unix: f64, out: &mut impl Write) -> io::Result<Vec<u8>> {
        if let Some(ms) = mtk::time_tag_ms(f) {
            self.tag = Some((ms, unix));
            self.chans.clear();
        } else if f.id == mtk::id::EPOCH_FIRST {
            if let Some(b) = f.payload.get(12..14) {
                self.tsx = Some(u16::from_le_bytes([b[0], b[1]]));
            }
        } else if f.id == mtk::id::CHANNEL {
            self.chans.extend(meas::channel(&f.payload));
        } else if f.id == mtk::id::GPS_SUBFRAME {
            if let Some((prn, sf)) = meas::gps_subframe(&f.payload) {
                self.iono = lnav::klobuchar(&sf).or(self.iono);
                self.learn_almanac(&sf, unix);
                if let Some(e) = self.subframes.entry(prn).or_default().add(sf) {
                    match self.nav.gps.insert(prn, vec![e]) {
                        None => log(&format!("ephemeris G{prn:02}: {} GPS", self.nav.gps.len())),
                        Some(old) if old.first() == Some(&e) => return Ok(Vec::new()),
                        Some(_) => {}
                    }
                    self.save_nav(unix);
                }
            }
        } else if f.id == mtk::id::BEIDOU_SUBFRAME {
            if let Some((prn, sf)) = meas::beidou_subframe(&f.payload) {
                if let Some(e) = self.d1.entry(prn).or_default().add(sf) {
                    match self.nav.beidou.insert(prn, vec![e]) {
                        None => log(&format!(
                            "ephemeris C{prn:02}: {} BeiDou",
                            self.nav.beidou.len()
                        )),
                        Some(old) if old.first() == Some(&e) => return Ok(Vec::new()),
                        Some(_) => {}
                    }
                    self.save_nav(unix);
                }
            }
        } else if f.id == mtk::id::EPOCH_LAST {
            if let Some((ms, at)) = self.tag {
                self.fix(at, out)?;
                self.report(at);
                let list = self.search(at + 1.0);
                self.searching = list
                    .iter()
                    .take(12)
                    .map(|&(sv, sys)| format!("{}{sv}", system_letter(sys)))
                    .collect::<Vec<_>>()
                    .join(" ");
                let mut clock = self.clock.aid(self.tsx.unwrap_or(TSX_DEFAULT));
                let shift = self.sweep_shift(at, clock[1].1);
                for p in &mut clock {
                    p.1 += shift;
                }
                self.aid = clock[1].1;
                return Ok(dsp::epoch(ms, tow(at + 1.0), &clock, &list));
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

fn write_atomic(path: &str, text: &str) {
    let tmp = format!("{path}.new");
    if let Err(e) = std::fs::write(&tmp, text).and_then(|()| std::fs::rename(&tmp, path)) {
        log(&format!("{path}: {e}"));
    }
}

/// Ephemerides saved by an earlier run, if they are recent enough.
fn load_nav(path: &str, unix: f64, nav: &mut rinex::Nav) {
    let Ok(text) = std::fs::read_to_string(format!("{path}.nav")) else {
        return;
    };
    let mut lines = text.lines();
    let saved: Option<f64> = lines
        .next()
        .and_then(|l| l.strip_prefix("saved "))
        .and_then(|s| s.parse().ok());
    if saved.is_none_or(|s| unix - s > NAV_MAX_AGE) {
        return;
    }
    for l in lines {
        let mut w = l.splitn(3, ' ');
        let (Some(sys), Some(prn), Some(rest)) = (w.next(), w.next(), w.next()) else {
            continue;
        };
        let (Ok(prn), Some(e)) = (prn.parse(), Ephemeris::from_line(rest)) else {
            continue;
        };
        match sys {
            "G" => nav.gps.insert(prn, vec![e]),
            "C" => nav.beidou.insert(prn, vec![e]),
            _ => None,
        };
    }
    log(&format!(
        "{} GPS and {} BeiDou ephemerides from the last run",
        nav.gps.len(),
        nav.beidou.len()
    ));
}

/// The almanac saved by an earlier run, unless it is too old to help.
fn load_almanac(path: &str) -> HashMap<u8, Almanac> {
    let now = gps_time(now());
    let alm: HashMap<u8, Almanac> = std::fs::read_to_string(format!("{path}.alm"))
        .unwrap_or_default()
        .lines()
        .filter_map(Almanac::from_line)
        .filter(|a| (now - a.toa).abs() < ALMANAC_MAX_AGE)
        .map(|a| (a.prn, a))
        .collect();
    if !alm.is_empty() {
        log(&format!(
            "almanac of {} GPS satellites from an earlier run",
            alm.len()
        ));
    }
    alm
}

/// The height sigma saved with a position, if any.
fn parse_height_sigma(s: &str) -> Option<f64> {
    s.trim().split(',').nth(3)?.parse().ok()
}

fn parse_position(s: &str) -> Option<(f64, f64, f64)> {
    let v: Vec<f64> = s.trim().split(',').filter_map(|x| x.parse().ok()).collect();
    match v[..] {
        [lat, lon, h] | [lat, lon, h, _] => Some((lat, lon, h)),
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

/// Where to start: the first of `--approx`, the saved position, `--guess` and
/// the time zone, with a description for the journal.
/// Description, position, height sigma, and whether it is only a guess.
type Start = (String, (f64, f64, f64), f64, bool);

/// Also the height sigma, and whether the position is only a guess.
fn start_position(args: &[String], state: Option<&str>) -> io::Result<Start> {
    let given = arg(args, "--approx").and_then(|s| parse_position(&s));
    let saved_text = state.and_then(|p| std::fs::read_to_string(p).ok());
    let saved = saved_text.as_deref().and_then(parse_position);
    // A saved height is trusted only as far as it was when saved.
    let sigma = saved_text
        .as_deref()
        .and_then(parse_height_sigma)
        .filter(|_| given.is_none())
        .unwrap_or(HEIGHT_SIGMA);
    let guess = arg(args, "--guess").and_then(|s| parse_position(&s));
    let tz = time_zone_position();
    let (from, (lat, lon, h)) = [
        ("--approx", given),
        ("the saved position", saved),
        ("--guess", guess),
        ("the time zone", tz),
    ]
    .into_iter()
    .find_map(|(name, p)| Some((name, p?)))
    .ok_or_else(|| io::Error::other("no --approx, --state or time zone to start from"))?;
    let seed = format!("{lat:.2},{lon:.2} ({from})");
    log(&format!("starting from {seed}"));
    Ok((
        seed,
        (lat, lon, h),
        sigma,
        given.is_none() && saved.is_none(),
    ))
}

fn new_engine(
    args: &[String],
    nav: rinex::Nav,
    state: Option<String>,
    seed: String,
    (lat, lon, h): (f64, f64, f64),
    sigma: f64,
    coarse: bool,
) -> Engine {
    let systems = arg(args, "--systems").unwrap_or_else(|| "GC".into());
    Engine {
        nav,
        systems: ['G', 'R', 'C'].map(|c| systems.contains(c)),
        approx: ecef(lat, lon, h),
        height: (h, sigma),
        heights: Vec::new(),
        tag: None,
        chans: Vec::new(),
        subframes: HashMap::new(),
        d1: HashMap::new(),
        iono: None,
        filter: Filter::default(),
        almanac: state.as_deref().map(load_almanac).unwrap_or_default(),
        searching: String::new(),
        tsx: None,
        clock: state
            .as_deref()
            .and_then(|p| std::fs::read_to_string(format!("{p}.clk")).ok())
            .map(|s| clock::Model::from_lines(&s))
            .unwrap_or_default(),
        clock_saved: 0.0,
        clock_learnt: 0.0,
        doppler: None,
        sweep: args.iter().any(|a| a == "--clock-sweep"),
        sweep_last: None,
        aid: 0,
        slots: HashMap::new(),
        coarse,
        starved: 0,
        coarse_tries: 0,
        global: false,
        cells: HashMap::new(),
        state,
        saved: 0.0,
        seed,
        status: "starting".into(),
        started: None,
        reported: 0.0,
        fixes: 0,
    }
}

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let nav = arg(&args, "--nav")
        .map(std::fs::read_to_string)
        .transpose()?
        .unwrap_or_default();
    let state = arg(&args, "--state");
    let (seed, (lat, lon, h), sigma, coarse) = start_position(&args, state.as_deref())?;
    let mut nav = rinex::parse(&nav);
    if let Some(p) = &state {
        load_nav(p, now(), &mut nav);
    }
    let mut engine = new_engine(&args, nav, state, seed, (lat, lon, h), sigma, coarse);
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
