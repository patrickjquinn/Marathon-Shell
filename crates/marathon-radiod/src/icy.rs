//! Shoutcast/Icecast in-band metadata ("ICY"): asked for with
//! `Icy-MetaData: 1`, a server that has it sends `icy-metaint: N`, then
//! after every N bytes of audio one length byte L and L * 16 bytes of
//! `StreamTitle='Artist - Title';...`.

/// Splits a stream into its audio and its metadata blocks.
pub struct Demux {
    interval: usize,
    /// Audio bytes left before the next length byte.
    audio_left: usize,
    /// Metadata bytes still to come, and those read so far.
    meta_left: usize,
    meta: Vec<u8>,
    in_meta: bool,
}

impl Demux {
    pub fn new(interval: usize) -> Self {
        Self {
            interval,
            audio_left: interval,
            meta_left: 0,
            meta: Vec::new(),
            in_meta: false,
        }
    }

    /// Feeds `chunk`; appends its audio to `audio` and returns the stream
    /// titles completed in it.
    pub fn feed(&mut self, mut chunk: &[u8], audio: &mut Vec<u8>) -> Vec<String> {
        let mut titles = Vec::new();
        while !chunk.is_empty() {
            if self.in_meta {
                let take = self.meta_left.min(chunk.len());
                self.meta.extend_from_slice(&chunk[..take]);
                self.meta_left -= take;
                chunk = &chunk[take..];
                if self.meta_left == 0 {
                    if let Some(t) = stream_title(&self.meta) {
                        titles.push(t);
                    }
                    self.meta.clear();
                    self.in_meta = false;
                    self.audio_left = self.interval;
                }
            } else if self.audio_left == 0 {
                self.meta_left = usize::from(chunk[0]) * 16;
                chunk = &chunk[1..];
                if self.meta_left == 0 {
                    self.audio_left = self.interval;
                } else {
                    self.in_meta = true;
                }
            } else {
                let take = self.audio_left.min(chunk.len());
                audio.extend_from_slice(&chunk[..take]);
                self.audio_left -= take;
                chunk = &chunk[take..];
            }
        }
        titles
    }
}

/// `StreamTitle='...';` from a metadata block, without its padding.
pub fn stream_title(block: &[u8]) -> Option<String> {
    let text = String::from_utf8_lossy(block);
    let text = text.trim_end_matches('\0');
    let start = text.find("StreamTitle='")? + "StreamTitle='".len();
    let rest = &text[start..];
    let end = rest.find("';").unwrap_or(rest.len());
    Some(rest[..end].trim().to_owned())
}

/// "Artist - Title" as (artist, title); a title alone when there is no dash.
pub fn split(title: &str) -> (Option<String>, String) {
    match title.split_once(" - ") {
        Some((artist, song)) if !artist.trim().is_empty() && !song.trim().is_empty() => {
            (Some(artist.trim().to_owned()), song.trim().to_owned())
        }
        _ => (None, title.trim().to_owned()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn block(text: &str) -> Vec<u8> {
        let mut b = text.as_bytes().to_vec();
        let len = b.len().div_ceil(16);
        b.resize(len * 16, 0);
        let mut out = vec![u8::try_from(len).unwrap_or(0)];
        out.extend(b);
        out
    }

    #[test]
    fn audio_passes_and_titles_come_out_across_chunk_edges() {
        let mut stream = b"abcd".to_vec();
        stream.extend(block("StreamTitle='Muse - Uprising';StreamUrl='';"));
        stream.extend(b"efgh");
        stream.push(0); // an empty block: no change
        stream.extend(b"ij");
        let mut demux = Demux::new(4);
        let (mut audio, mut titles) = (Vec::new(), Vec::new());
        for piece in stream.chunks(3) {
            titles.extend(demux.feed(piece, &mut audio));
        }
        assert_eq!(audio, b"abcdefghij");
        assert_eq!(titles, vec!["Muse - Uprising"]);
    }

    #[test]
    fn a_title_splits_into_artist_and_song() {
        assert_eq!(
            split("Muse - Uprising"),
            (Some("Muse".into()), "Uprising".into())
        );
        assert_eq!(split("News at nine"), (None, "News at nine".into()));
        assert_eq!(split(" - "), (None, "-".into()));
    }
}
