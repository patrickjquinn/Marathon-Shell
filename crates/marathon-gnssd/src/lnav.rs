//! GPS L1 C/A navigation message (IS-GPS-200, section 20.3): word parity and
//! the ephemeris in subframes 1-3.

const PREAMBLE: u32 = 0x8b;
/// Parity masks over `D29* D30* d1..d30` packed into bits 31..0.
const HAMMING: [u32; 6] = [
    0xbb1f_3480,
    0x5d8f_9a40,
    0xaec7_cd00,
    0x5763_e680,
    0x6bb1_f340,
    0x8b7a_89c0,
];

/// Checks one 30-bit word given the previous word's last two bits and
/// returns its 24 data bits, un-inverted.
pub fn word_data(prev: u32, word: u32) -> Option<u32> {
    let mut w = (prev & 3) << 30 | (word & 0x3fff_ffff);
    if w & 0x4000_0000 != 0 {
        w ^= 0x3fff_ffc0;
    }
    let parity = HAMMING
        .iter()
        .fold(0, |p, &m| p << 1 | (w & m).count_ones() & 1);
    (parity == w & 0x3f).then_some(w >> 6 & 0x00ff_ffff)
}

/// The 240 data bits of a subframe from its ten 30-bit words; `prev` is the
/// last word of the previous subframe (only its parity bits matter).
pub fn subframe_bits(prev: u32, words: &[u32; 10]) -> Option<[u8; 30]> {
    let mut out = [0u8; 30];
    let mut last = prev;
    for (i, &w) in words.iter().enumerate() {
        let d = word_data(last, w)?;
        out[i * 3..i * 3 + 3].copy_from_slice(&d.to_be_bytes()[1..]);
        last = w;
    }
    (u32::from(out[0]) == PREAMBLE).then_some(out)
}

/// The 240 data bits of a subframe from ten 24-bit data words that have
/// already been parity-checked and corrected for polarity, as the DSP
/// reports them.
pub fn subframe_from_data(words: &[u32; 10]) -> Option<[u8; 30]> {
    let mut out = [0u8; 30];
    for (i, w) in words.iter().enumerate() {
        out[i * 3..i * 3 + 3].copy_from_slice(&w.to_be_bytes()[1..]);
    }
    (u32::from(out[0]) == PREAMBLE).then_some(out)
}

/// Klobuchar coefficients (alpha 0-3 in s, s/sc, s/sc², s/sc³; beta 0-3 in
/// s, s/sc, ...) from subframe 4 page 18.
pub fn klobuchar(b: &[u8; 30]) -> Option<[f64; 8]> {
    if header(b).0 != 4 || bits(b, 50, 6) != 56 {
        return None;
    }
    let p = |pos, exp| scaled(sbits(b, pos, 8), exp);
    Some([
        p(56, -30),
        p(64, -27),
        p(72, -24),
        p(80, -24),
        p(88, 11),
        p(96, 14),
        p(104, 16),
        p(112, 16),
    ])
}

fn bits(b: &[u8; 30], pos: usize, len: usize) -> u64 {
    (pos..pos + len).fold(0, |v, i| v << 1 | u64::from(b[i / 8] >> (7 - i % 8) & 1))
}

#[allow(clippy::cast_possible_wrap, reason = "two's complement field")]
fn sbits(b: &[u8; 30], pos: usize, len: usize) -> i64 {
    let v = bits(b, pos, len);
    ((v << (64 - len)) as i64) >> (64 - len)
}

#[allow(clippy::cast_precision_loss, reason = "fields are at most 32 bits")]
fn scaled(v: i64, exp: i32) -> f64 {
    v as f64 * 2f64.powi(exp)
}

/// Subframe id (1-5) and the HOW time of week of the next subframe, in seconds.
pub fn header(b: &[u8; 30]) -> (u8, u32) {
    #[allow(clippy::cast_possible_truncation, reason = "3 and 17 bit fields")]
    (bits(b, 43, 3) as u8, bits(b, 24, 17) as u32 * 6)
}

/// Broadcast ephemeris and clock of one satellite (angles in radians).
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Ephemeris {
    pub week: u16,
    pub health: u8,
    pub iodc: u16,
    pub iode: u8,
    pub tgd: f64,
    pub toc: f64,
    pub af0: f64,
    pub af1: f64,
    pub af2: f64,
    pub crs: f64,
    pub dn: f64,
    pub m0: f64,
    pub cuc: f64,
    pub e: f64,
    pub cus: f64,
    pub sqrt_a: f64,
    pub toe: f64,
    pub cic: f64,
    pub omega0: f64,
    pub cis: f64,
    pub i0: f64,
    pub crc: f64,
    pub omega: f64,
    pub omega_dot: f64,
    pub idot: f64,
}

impl Ephemeris {
    /// The ephemeris as one line of numbers, for the state directory.
    pub fn to_line(&self) -> String {
        let f = [
            self.tgd,
            self.toc,
            self.af0,
            self.af1,
            self.af2,
            self.crs,
            self.dn,
            self.m0,
            self.cuc,
            self.e,
            self.cus,
            self.sqrt_a,
            self.toe,
            self.cic,
            self.omega0,
            self.cis,
            self.i0,
            self.crc,
            self.omega,
            self.omega_dot,
            self.idot,
        ];
        let head = format!("{} {} {} {}", self.week, self.health, self.iodc, self.iode);
        std::iter::once(head)
            .chain(f.iter().map(|v| format!("{v:e}")))
            .collect::<Vec<_>>()
            .join(" ")
    }

    /// Reads back [`Ephemeris::to_line`].
    pub fn from_line(s: &str) -> Option<Self> {
        let w: Vec<&str> = s.split_whitespace().collect();
        let f: Vec<f64> = w
            .get(4..)?
            .iter()
            .map(|x| x.parse().ok())
            .collect::<Option<_>>()?;
        let [tgd, toc, af0, af1, af2, crs, dn, m0, cuc, e, cus, sqrt_a, toe, cic, omega0, cis, i0, crc, omega, omega_dot, idot] =
            f[..]
        else {
            return None;
        };
        Some(Self {
            week: w[0].parse().ok()?,
            health: w[1].parse().ok()?,
            iodc: w[2].parse().ok()?,
            iode: w[3].parse().ok()?,
            tgd,
            toc,
            af0,
            af1,
            af2,
            crs,
            dn,
            m0,
            cuc,
            e,
            cus,
            sqrt_a,
            toe,
            cic,
            omega0,
            cis,
            i0,
            crc,
            omega,
            omega_dot,
            idot,
        })
    }
}

/// Collects subframes 1-3 of one satellite into an ephemeris.
#[derive(Default)]
pub struct EphemerisBuilder {
    sf: [Option<[u8; 30]>; 3],
}

impl EphemerisBuilder {
    /// Adds a checked subframe; returns the ephemeris once 1-3 agree on IODE/IODC.
    pub fn add(&mut self, b: [u8; 30]) -> Option<Ephemeris> {
        let (id, _) = header(&b);
        if !(1..=3).contains(&id) {
            return None;
        }
        self.sf[usize::from(id) - 1] = Some(b);
        let [Some(s1), Some(s2), Some(s3)] = self.sf else {
            return None;
        };
        let e = decode(&s1, &s2, &s3);
        #[allow(clippy::cast_possible_truncation, reason = "8-bit field")]
        let iode3 = bits(&s3, 216, 8) as u8;
        (e.iode == iode3 && (e.iodc & 0xff) == u16::from(e.iode)).then_some(e)
    }
}

#[allow(clippy::cast_possible_truncation, reason = "field widths fit")]
fn decode(s1: &[u8; 30], s2: &[u8; 30], s3: &[u8; 30]) -> Ephemeris {
    use std::f64::consts::PI;
    let sc = |v: i64, exp| scaled(v, exp) * PI;
    let u = |b: &[u8; 30], p, l| bits(b, p, l).cast_signed();
    Ephemeris {
        week: bits(s1, 48, 10) as u16,
        health: bits(s1, 64, 6) as u8,
        iodc: (bits(s1, 70, 2) << 8 | bits(s1, 168, 8)) as u16,
        tgd: scaled(sbits(s1, 160, 8), -31),
        toc: scaled(u(s1, 176, 16), 4),
        af2: scaled(sbits(s1, 192, 8), -55),
        af1: scaled(sbits(s1, 200, 16), -43),
        af0: scaled(sbits(s1, 216, 22), -31),
        iode: bits(s2, 48, 8) as u8,
        crs: scaled(sbits(s2, 56, 16), -5),
        dn: sc(sbits(s2, 72, 16), -43),
        m0: sc(sbits(s2, 88, 32), -31),
        cuc: scaled(sbits(s2, 120, 16), -29),
        e: scaled(u(s2, 136, 32), -33),
        cus: scaled(sbits(s2, 168, 16), -29),
        sqrt_a: scaled(u(s2, 184, 32), -19),
        toe: scaled(u(s2, 216, 16), 4),
        cic: scaled(sbits(s3, 48, 16), -29),
        omega0: sc(sbits(s3, 64, 32), -31),
        cis: scaled(sbits(s3, 96, 16), -29),
        i0: sc(sbits(s3, 112, 32), -31),
        crc: scaled(sbits(s3, 144, 16), -5),
        omega: sc(sbits(s3, 160, 32), -31),
        omega_dot: sc(sbits(s3, 192, 24), -43),
        idot: sc(sbits(s3, 224, 14), -43),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
pub(crate) mod tests {
    use super::*;

    /// Adds parity to 24 data bits (inverting them when D30* is set).
    pub fn encode_word(prev: u32, data: u32) -> u32 {
        let d = if prev & 1 != 0 {
            !data & 0xff_ffff
        } else {
            data
        };
        let w = (prev & 3) << 30 | d << 6;
        let w0 = if w & 0x4000_0000 != 0 {
            w ^ 0x3fff_ffc0
        } else {
            w
        };
        let parity = HAMMING
            .iter()
            .fold(0, |p, &m| p << 1 | (w0 & m).count_ones() & 1);
        (w | parity) & 0x3fff_ffff
    }

    pub fn put(b: &mut [u8; 30], pos: usize, len: usize, v: i64) {
        for i in 0..len {
            let bit = (v >> (len - 1 - i)) & 1;
            let p = pos + i;
            b[p / 8] = b[p / 8] & !(0x80 >> (p % 8)) | u8::try_from(bit << (7 - p % 8)).unwrap();
        }
    }

    pub fn words(b: &[u8; 30], prev: u32) -> [u32; 10] {
        let mut out = [0; 10];
        let mut last = prev;
        for (i, w) in out.iter_mut().enumerate() {
            let data =
                u32::from(b[i * 3]) << 16 | u32::from(b[i * 3 + 1]) << 8 | u32::from(b[i * 3 + 2]);
            *w = encode_word(last, data);
            last = *w;
        }
        out
    }

    pub fn subframe(id: i64, fill: impl Fn(&mut [u8; 30])) -> [u8; 30] {
        let mut b = [0u8; 30];
        put(&mut b, 0, 8, i64::from(PREAMBLE));
        put(&mut b, 24, 17, 100);
        put(&mut b, 43, 3, id);
        fill(&mut b);
        b
    }

    #[test]
    fn parity_round_trip_and_inversion() {
        for prev in [0, 1, 2, 3] {
            let w = encode_word(prev, 0x8b_1234);
            assert_eq!(word_data(prev, w), Some(0x8b_1234));
            assert_eq!(word_data(prev, w ^ 0x100), None);
        }
    }

    #[test]
    fn line_round_trip() {
        let e = Ephemeris {
            week: 2390,
            iodc: 77,
            iode: 77,
            toc: 122_400.0,
            af0: -1.234_567_890_123e-4,
            sqrt_a: 5_153.654_321,
            omega: -2.1,
            idot: 3.0e-10,
            ..Ephemeris::default()
        };
        assert_eq!(Ephemeris::from_line(&e.to_line()), Some(e));
        assert_eq!(Ephemeris::from_line("1 2 3"), None);
    }

    #[test]
    fn page_18_ionosphere() {
        let sf = subframe(4, |b| {
            put(b, 50, 6, 56);
            put(b, 56, 8, 0x0c);
            put(b, 88, 8, 0x4b);
            put(b, 112, 8, -2);
        });
        let k = klobuchar(&sf).unwrap();
        assert!((k[0] - 12.0 * 2f64.powi(-30)).abs() < 1e-20);
        assert!((k[4] - 75.0 * 2048.0).abs() < 1e-9 && (k[7] + 2.0 * 65536.0).abs() < 1e-9);
        let words: Vec<u32> = sf
            .chunks(3)
            .map(|c| u32::from_be_bytes([0, c[0], c[1], c[2]]))
            .collect();
        assert_eq!(subframe_from_data(&words.try_into().unwrap()), Some(sf));
    }

    #[test]
    fn ephemeris_fields() {
        let s1 = subframe(1, |b| {
            put(b, 48, 10, 300);
            put(b, 70, 2, 0);
            put(b, 168, 8, 77);
            put(b, 216, 22, -12345);
        });
        let s2 = subframe(2, |b| {
            put(b, 48, 8, 77);
            put(b, 136, 32, 0x0040_0000);
            put(b, 184, 32, 0xa10d_0000);
            put(b, 216, 16, 450);
        });
        let s3 = subframe(3, |b| {
            put(b, 192, 24, -100);
            put(b, 216, 8, 77);
            put(b, 224, 14, -5);
        });
        let mut eb = EphemerisBuilder::default();
        let mut prev = 0;
        let mut eph = None;
        for sf in [s1, s2, s3] {
            let w = words(&sf, prev);
            eph = eb.add(subframe_bits(prev, &w).unwrap()).or(eph);
            prev = w[9];
        }
        let e = eph.unwrap();
        assert_eq!((e.week, e.iode, e.iodc), (300, 77, 77));
        assert!((e.af0 - -12345.0 * 2f64.powi(-31)).abs() < 1e-18);
        assert!((e.e - f64::from(0x0040_0000u32) * 2f64.powi(-33)).abs() < 1e-15);
        assert!((e.toe - 7200.0).abs() < 1e-9);
        assert!(e.omega_dot < 0.0 && e.idot < 0.0);
    }
}
