//! Open positioning engine for the `MediaTek` CONNSYS GNSS receiver of the
//! MT6789 (docs/hardware/mt6789-gnss.md): the DSP's binary protocol, the
//! GPS navigation message, orbits, single-point positioning and NMEA for
//! `GeoClue`. The DSP's measurement records are not decoded yet, so the
//! daemon only reports epochs for now.

pub mod lnav;
pub mod mtk;
pub mod nmea;
pub mod orbit;
pub mod spp;
