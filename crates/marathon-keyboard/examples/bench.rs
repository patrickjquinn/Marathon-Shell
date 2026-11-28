//! How long the keyboard takes on this machine: `bench <file.lex>`.
#![allow(
    clippy::print_stdout,
    clippy::unwrap_used,
    clippy::cast_precision_loss,
    reason = "a benchmark"
)]

use std::time::Instant;

use marathon_keyboard::history::History;
use marathon_keyboard::layout::Layout;
use marathon_keyboard::lexicon::Lexicon;
use marathon_keyboard::Engine;

fn main() {
    let path = std::env::args().nth(1).unwrap();
    let start = Instant::now();
    let text = std::fs::read_to_string(path).unwrap();
    let lexicon = Lexicon::parse(&text);
    println!("load: {} words in {:?}", lexicon.len(), start.elapsed());
    let layout = Layout::qwerty();
    let engine = Engine::new(lexicon, layout.clone(), History::default());
    let words = [
        "the",
        "hello",
        "keyboard",
        "tomorrow",
        "something",
        "because",
        "really",
        "thanks",
    ];
    let start = Instant::now();
    let mut n = 0;
    for w in words {
        for i in 1..=w.len() {
            engine.suggest(&w[..i], &[], Some("I"));
            n += 1;
        }
    }
    println!(
        "suggest: {:.2} ms a letter",
        start.elapsed().as_secs_f64() * 1000.0 / f64::from(n)
    );
    let start = Instant::now();
    for w in words {
        let corners: Vec<(f32, f32)> = w.chars().map(|c| layout.centre(c).unwrap()).collect();
        let mut path = Vec::new();
        for c in corners.windows(2) {
            for s in 0..10 {
                let t = s as f32 / 10.0;
                path.push((
                    c[0].0 + t * (c[1].0 - c[0].0),
                    c[0].1 + t * (c[1].1 - c[0].1),
                ));
            }
        }
        std::hint::black_box(engine.swipe(&path, None));
    }
    println!(
        "swipe: {:.2} ms a word",
        start.elapsed().as_secs_f64() * 1000.0 / words.len() as f64
    );
}
