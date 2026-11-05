//! One satellite's broadcast ephemeris, whichever the system.

use crate::orbit::{kepler, Model};
use crate::{glonass, lnav};
use nalgebra::Vector3;

/// BDT runs 14 s behind GPS time.
const BDT_OFFSET: f64 = 14.0;

#[derive(Debug, Clone, Copy)]
pub enum Sat<'a> {
    Gps(&'a lnav::Ephemeris),
    Beidou(&'a lnav::Ephemeris, bool),
    Glonass(&'a glonass::Ephemeris),
}

impl Sat<'_> {
    /// A BeiDou satellite; PRNs 1-5 and 59-63 are geostationary.
    pub fn beidou(e: &lnav::Ephemeris, prn: u8) -> Sat<'_> {
        Sat::Beidou(e, matches!(prn, 1..=5 | 59..=63))
    }

    /// ECEF position and clock offset at GPS time of week `t`.
    pub fn position(&self, t: f64) -> (Vector3<f64>, f64) {
        match *self {
            Sat::Gps(e) => kepler(e, t, Model::Gps),
            Sat::Beidou(e, geo) => kepler(e, t - BDT_OFFSET, Model::Beidou { geo }),
            Sat::Glonass(e) => glonass::position(e, t),
        }
    }

    /// 0 GPS, 1 GLONASS, 2 BeiDou: each system has its own receiver clock bias.
    pub fn system(&self) -> usize {
        match self {
            Sat::Gps(_) => 0,
            Sat::Glonass(_) => 1,
            Sat::Beidou(..) => 2,
        }
    }

    pub fn carrier(&self) -> f64 {
        match self {
            Sat::Gps(_) => 1_575.42e6,
            Sat::Beidou(..) => 1_561.098e6,
            Sat::Glonass(e) => e.carrier(),
        }
    }

    /// The transmit-time period the code phase pins down. BeiDou records
    /// jump by half a millisecond against GPS from one epoch to the next
    /// (reference runs), so only their phase within 0.5 ms is used.
    pub fn code_period(&self) -> f64 {
        match self {
            Sat::Beidou(..) => 0.5e-3,
            _ => 1e-3,
        }
    }

    pub fn chip_rate(&self) -> f64 {
        match self {
            Sat::Gps(_) => 1.023e6,
            Sat::Beidou(..) => 2.046e6,
            Sat::Glonass(_) => 0.511e6,
        }
    }
}
