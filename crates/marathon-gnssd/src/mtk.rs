//! `MediaTek` CONNSYS GNSS framing (`docs/hardware/mt6789-gnss.md`).

const SYNC: u8 = 0xaa;
const START: u8 = 0xf0;
const END: u8 = 0x0f;
const ESC: u8 = 0xde;

/// DSP-to-host payloads are rotated left by three and then XOR-ed with `0x59`.
pub fn unscramble(payload: &mut [u8]) {
    for b in payload {
        *b = b.rotate_right(3) ^ 0x59;
    }
}

/// One host frame: `AA F0 | len | id | payload | sum | AA 0F`, escaped.
pub fn encode(id: u16, payload: &[u8]) -> Vec<u8> {
    let len = u16::try_from(payload.len() + 4).unwrap_or(u16::MAX);
    let mut body = Vec::with_capacity(payload.len() + 6);
    body.extend_from_slice(&len.to_le_bytes());
    body.extend_from_slice(&id.to_le_bytes());
    body.extend_from_slice(payload);
    let sum = body.iter().fold(0u16, |s, &b| s.wrapping_add(u16::from(b)));
    body.extend_from_slice(&sum.to_le_bytes());
    let mut out = vec![SYNC, START];
    for b in body {
        match b {
            SYNC => out.extend_from_slice(&[ESC, 0xdf]),
            ESC => out.extend_from_slice(&[ESC, 0xe0]),
            _ => out.push(b),
        }
    }
    out.extend_from_slice(&[SYNC, END]);
    out
}

/// A checked DSP frame with its payload unscrambled.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frame {
    pub id: u16,
    pub payload: Vec<u8>,
}

#[derive(Default)]
enum State {
    #[default]
    Hunt,
    Start,
    Body,
    Esc,
    End,
}

/// Byte-at-a-time deframer; frames with a bad length or checksum are dropped.
#[derive(Default)]
pub struct Deframer {
    state: State,
    body: Vec<u8>,
}

impl Deframer {
    pub fn push(&mut self, b: u8) -> Option<Frame> {
        match self.state {
            State::Hunt => {
                if b == SYNC {
                    self.state = State::Start;
                }
            }
            State::Start => {
                self.state = match b {
                    START => {
                        self.body.clear();
                        State::Body
                    }
                    SYNC => State::Start,
                    _ => State::Hunt,
                };
            }
            State::Body => match b {
                SYNC => self.state = State::End,
                ESC => self.state = State::Esc,
                _ => self.body.push(b),
            },
            State::Esc => {
                self.state = State::Body;
                match b {
                    0xdf => self.body.push(SYNC),
                    0xe0 => self.body.push(ESC),
                    _ => self.state = State::Hunt,
                }
            }
            State::End => {
                self.state = State::Hunt;
                match b {
                    END => return self.finish(),
                    START => {
                        self.body.clear();
                        self.state = State::Body;
                    }
                    _ => {}
                }
            }
        }
        None
    }

    fn finish(&self) -> Option<Frame> {
        let b = &self.body;
        if b.len() < 6 || usize::from(u16::from_le_bytes([b[0], b[1]]) & 0xfff) + 2 != b.len() {
            return None;
        }
        let (data, sum) = b.split_at(b.len() - 2);
        let calc = data.iter().fold(0u16, |s, &x| s.wrapping_add(u16::from(x)));
        if calc != u16::from_le_bytes([sum[0], sum[1]]) {
            return None;
        }
        let mut payload = data[4..].to_vec();
        unscramble(&mut payload);
        Some(Frame {
            id: u16::from_le_bytes([data[2], data[3]]),
            payload,
        })
    }
}

/// Message ids, `0xFE00 | n`.
pub mod id {
    pub const QUERY: u16 = 0xfe08;
    pub const REPLY: u16 = 0xfe14;
    pub const TIME_TAG: u16 = 0xfe28;
    pub const CHANNEL: u16 = 0xfe29;
    pub const EPOCH_END: u16 = 0xfe2c;
    /// The last message of each epoch.
    pub const EPOCH_LAST: u16 = 0xfe4e;
}

/// The DSP's word order for 32-bit values: high 16-bit word first.
pub fn be_words_u32(p: &[u8], at: usize) -> Option<u32> {
    let w = p.get(at..at + 4)?;
    Some(
        u32::from(u16::from_le_bytes([w[0], w[1]])) << 16
            | u32::from(u16::from_le_bytes([w[2], w[3]])),
    )
}

/// msg 0x28: the DSP's millisecond clock for the epoch.
pub fn time_tag_ms(f: &Frame) -> Option<u32> {
    (f.id == id::TIME_TAG)
        .then(|| be_words_u32(&f.payload, 1))
        .flatten()
}

/// The version query the stock engine sends (msg 0x08, word 0x0018).
pub fn version_query() -> Vec<u8> {
    encode(id::QUERY, &0x18u16.to_le_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scramble(p: &[u8]) -> Vec<u8> {
        p.iter().map(|b| (b ^ 0x59).rotate_left(3)).collect()
    }

    fn feed(d: &mut Deframer, bytes: &[u8]) -> Vec<Frame> {
        bytes.iter().filter_map(|&b| d.push(b)).collect()
    }

    #[test]
    fn version_query_matches_stock_bytes() {
        assert_eq!(
            version_query(),
            [0xaa, 0xf0, 0x06, 0x00, 0x08, 0xfe, 0x18, 0x00, 0x24, 0x01, 0xaa, 0x0f]
        );
    }

    #[test]
    fn round_trip_with_escapes_and_noise() {
        let payload = [0xaa, 0xde, 0x00, 0x42];
        let mut bytes = vec![0x13, 0xaa, 0xf0, 0x05];
        bytes.extend(encode(0xfe2c, &scramble(&payload)));
        let frames = feed(&mut Deframer::default(), &bytes);
        assert_eq!(
            frames,
            [Frame {
                id: 0xfe2c,
                payload: payload.to_vec()
            }]
        );
    }

    #[test]
    fn bad_checksum_is_dropped() {
        let mut bytes = encode(0xfe62, &[1, 2, 3]);
        let n = bytes.len();
        bytes[n - 4] ^= 1;
        assert!(feed(&mut Deframer::default(), &bytes).is_empty());
    }

    #[test]
    fn time_tag_from_phone_capture() {
        // msg 0x28 as the Q25 DSP sent it one second after boot (indoor capture).
        let mut payload = vec![0xc2, 0xca, 0xca, 0x65, 0xd2, 0x09, 0x81, 0xca, 0x48];
        unscramble(&mut payload);
        assert_eq!(payload, [0x01, 0, 0, 0xf5, 0x03, 0x78, 0x69, 0, 0x50]);
        let f = Frame {
            id: id::TIME_TAG,
            payload,
        };
        assert_eq!(time_tag_ms(&f), Some(1013));
    }
}
