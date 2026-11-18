//! An internet station: its stream fetched here (so the in-band "Artist -
//! Title" can be read), decoded by ffmpeg, and played into PipeWire as a
//! Music stream like the FM tuner's audio.

use std::io::{self, Read, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use crate::icy;

pub enum Event {
    /// Audio is reaching PipeWire.
    Playing,
    /// The station's in-band now-playing text.
    Title(String),
    Failed(String),
}

/// Where a stream's events go, with which play they came from: a
/// stream that was replaced still sends until its thread notices.
#[derive(Clone)]
pub struct Tx {
    pub generation: u64,
    pub tx: async_channel::Sender<(u64, Event)>,
}

impl Tx {
    fn send(&self, event: Event) {
        self.tx.send_blocking((self.generation, event)).ok();
    }
}

pub struct Stream {
    stop: Arc<AtomicBool>,
    children: Arc<Mutex<Vec<Child>>>,
}

const TRIES: u32 = 3;

/// pw-cat playing raw 48 kHz stereo from `input` as the Music role, to
/// the default output or, for testing, `MARATHON_RADIO_SINK`.
fn player(input: Stdio) -> io::Result<Child> {
    let mut pw = Command::new("pw-cat");
    if let Some(sink) = std::env::var_os("MARATHON_RADIO_SINK").filter(|s| !s.is_empty()) {
        pw.arg("--target").arg(sink);
    }
    pw.args([
            "--playback",
            "--raw",
            "--format",
            "s16",
            "--rate",
            "48000",
            "--channels",
            "2",
            "--media-role",
            "Music",
            "-P",
            r#"{ "application.name": "Radio", "application.icon-name": "radio", "node.name": "radio", "node.description": "Radio", "media.name": "Radio" }"#,
            "-",
        ])
        .stdin(input)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
}

fn decoder(input: &str) -> io::Result<Child> {
    Command::new("ffmpeg")
        .args([
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-probesize",
            "16384",
            "-analyzeduration",
            "500000",
            "-i",
            input,
            "-vn",
            "-f",
            "s16le",
            "-ar",
            "48000",
            "-ac",
            "2",
            "pipe:1",
        ])
        .stdin(if input == "pipe:0" {
            Stdio::piped()
        } else {
            Stdio::null()
        })
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
}

fn has_extension(url: &str, extensions: &[&str]) -> bool {
    std::path::Path::new(url.split(['?', '#']).next().unwrap_or(url))
        .extension()
        .and_then(|e| e.to_str())
        .is_some_and(|e| extensions.iter().any(|x| e.eq_ignore_ascii_case(x)))
}

/// The first stream address in an M3U or PLS playlist.
fn from_playlist(text: &str) -> Option<String> {
    text.lines()
        .map(str::trim)
        .map(|l| {
            l.split_once('=')
                .filter(|(k, _)| k.starts_with("File"))
                .map_or(l, |(_, v)| v)
        })
        .find(|l| l.starts_with("http://") || l.starts_with("https://"))
        .map(str::to_owned)
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_connect(Some(Duration::from_secs(10)))
        // Only until the answer starts: a live stream's body never ends,
        // and ureq's body timeout is for all of it.
        .timeout_recv_response(Some(Duration::from_secs(15)))
        .user_agent("MarathonRadio/1.0")
        .build()
        .new_agent()
}

impl Stream {
    /// Plays `station`, asking Radio Browser for its current address first.
    pub fn start(station: crate::catalogue::Station, events: Tx) -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let children = Arc::new(Mutex::new(Vec::new()));
        let (s, c) = (Arc::clone(&stop), Arc::clone(&children));
        thread::spawn(move || {
            let hls = station.hls;
            // The directory's address is current; the listen is counted aside.
            let mut url = if station.url.is_empty() {
                crate::catalogue::resolve(&station)
            } else {
                let counted = station.clone();
                thread::spawn(move || crate::catalogue::resolve(&counted));
                station.url.clone()
            };
            let mut tried = 0;
            let mut last = String::new();
            while !s.load(Ordering::SeqCst) && tried < TRIES {
                tried += 1;
                let began = std::time::Instant::now();
                let played = play_once(&url, hls, &s, &c, &events);
                // A connection that played a while and dropped is a station
                // to go back to, not a failed attempt.
                if began.elapsed() > Duration::from_secs(30) {
                    tried = 1;
                }
                match played {
                    Ok(Some(next)) => {
                        url = next;
                        tried -= 1;
                    }
                    Ok(None) => tried = 0,
                    Err(e) => last = e.to_string(),
                }
                kill(&c);
                if !s.load(Ordering::SeqCst) {
                    thread::sleep(Duration::from_secs(u64::from(tried)));
                }
            }
            if !s.load(Ordering::SeqCst) {
                events.send(Event::Failed(last));
            }
        });
        Self { stop, children }
    }
}

fn kill(children: &Mutex<Vec<Child>>) {
    let mut c = children
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    for mut child in c.drain(..) {
        child.kill().ok();
        child.wait().ok();
    }
}

/// Copies decoded audio to PipeWire, saying so once it flows.
fn relay(mut from: impl Read + Send + 'static, mut to: ChildStdin, events: Tx) {
    thread::spawn(move || {
        let mut buf = vec![0u8; 16 << 10];
        let mut told = false;
        while let Ok(n) = from.read(&mut buf) {
            if n == 0 || to.write_all(&buf[..n]).is_err() {
                break;
            }
            if !told {
                told = true;
                events.send(Event::Playing);
            }
        }
    });
}

/// Plays `url` until it ends or fails; `Ok(Some(next))` when it was a
/// playlist naming the stream, `Ok(None)` when a stream that played ended.
fn play_once(
    url: &str,
    hls: bool,
    stop: &AtomicBool,
    children: &Mutex<Vec<Child>>,
    events: &Tx,
) -> io::Result<Option<String>> {
    let lower = url.to_ascii_lowercase();
    let mut out = player(Stdio::piped())?;
    let to_player = out.stdin.take();
    let direct = hls || lower.contains(".m3u8");
    let mut dec = decoder(if direct { url } else { "pipe:0" })?;
    if let (Some(from), Some(to)) = (dec.stdout.take(), to_player) {
        relay(from, to, events.clone());
    }
    let mut into_dec = dec.stdin.take();
    {
        let mut c = children
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        c.push(dec);
        c.push(out);
    }
    if direct {
        while !stop.load(Ordering::SeqCst) {
            thread::sleep(Duration::from_millis(250));
            let ended = children
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .first_mut()
                .is_none_or(|d| d.try_wait().ok().flatten().is_some());
            if ended {
                return Err(io::Error::other("the stream ended"));
            }
        }
        return Ok(None);
    }
    let resp = agent()
        .get(url)
        .header("Icy-MetaData", "1")
        .call()
        .map_err(io::Error::other)?;
    let kind = resp
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_ascii_lowercase();
    let interval = resp
        .headers()
        .get("icy-metaint")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.trim().parse::<usize>().ok())
        .filter(|&n| n > 0);
    let mut body = resp.into_body().into_reader();
    if kind.contains("mpegurl") || kind.contains("scpls") || has_extension(&lower, &["m3u", "pls"])
    {
        let mut text = String::new();
        body.take(1 << 16).read_to_string(&mut text)?;
        return from_playlist(&text)
            .map(Some)
            .ok_or_else(|| io::Error::other("an empty playlist"));
    }
    let Some(into) = into_dec.as_mut() else {
        return Err(io::Error::other("ffmpeg took no input"));
    };
    let mut demux = interval.map(icy::Demux::new);
    let mut buf = vec![0u8; 16 << 10];
    let mut audio = Vec::with_capacity(buf.len());
    while !stop.load(Ordering::SeqCst) {
        let n = body.read(&mut buf)?;
        if n == 0 {
            return Err(io::Error::other("the stream ended"));
        }
        let chunk = &buf[..n];
        if let Some(d) = demux.as_mut() {
            audio.clear();
            for title in d.feed(chunk, &mut audio) {
                events.send(Event::Title(title));
            }
            into.write_all(&audio)?;
        } else {
            into.write_all(chunk)?;
        }
    }
    Ok(None)
}

impl Drop for Stream {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::SeqCst);
        kill(&self.children);
    }
}

#[cfg(test)]
mod tests {
    use super::from_playlist;

    #[test]
    fn playlists_name_their_stream() {
        assert_eq!(
            from_playlist("#EXTM3U\n#EXTINF:-1,Nova\nhttps://stream.example/nova.mp3\n").as_deref(),
            Some("https://stream.example/nova.mp3")
        );
        assert_eq!(
            from_playlist("[playlist]\nNumberOfEntries=1\nFile1=http://a.example:8000/live\n")
                .as_deref(),
            Some("http://a.example:8000/live")
        );
        assert_eq!(from_playlist("[playlist]\n"), None);
    }
}
