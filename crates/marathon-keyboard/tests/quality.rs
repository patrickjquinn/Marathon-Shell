//! The keyboard against the real word list, with typing simulated: run with
//! `MARATHON_LEXICON=/path/en_GB.lex cargo test --release -p marathon-keyboard
//! --test quality -- --nocapture`. Skipped without a lexicon.
#![allow(
    clippy::print_stdout,
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::unwrap_used,
    reason = "a report"
)]

use std::time::Instant;

use marathon_keyboard::history::History;
use marathon_keyboard::layout::Layout;
use marathon_keyboard::lexicon::Lexicon;
use marathon_keyboard::Engine;

fn engine() -> Option<Engine> {
    let path = std::env::var("MARATHON_LEXICON").ok()?;
    let lexicon = Lexicon::parse(&std::fs::read_to_string(path).ok()?);
    Some(Engine::new(lexicon, Layout::qwerty(), History::default()))
}

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> f32 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        (self.0 >> 40) as f32 / (1u64 << 24) as f32
    }
    fn gauss(&mut self) -> f32 {
        let (u, v) = (self.next().max(1e-7), self.next());
        (-2.0 * u.ln()).sqrt() * (std::f32::consts::TAU * v).cos()
    }
}

fn common(engine: &Engine, n: usize) -> Vec<String> {
    let lex = &engine.lexicon;
    let mut ids: Vec<u32> = (0..u32::try_from(lex.len()).unwrap())
        .filter(|&id| {
            let w = lex.word(id);
            w.chars().all(|c| c.is_ascii_lowercase()) && w.len() >= 2 && !lex.offensive(id)
        })
        .collect();
    ids.sort_by_key(|&id| std::cmp::Reverse(lex.freq(id)));
    ids.into_iter()
        .take(n)
        .map(|id| lex.word(id).to_owned())
        .collect()
}

#[test]
fn typos_are_corrected_and_words_are_left_alone() {
    let Some(engine) = engine() else { return };
    let cases = [
        ("teh", "the"),
        ("thw", "the"),
        ("hte", "the"),
        ("dont", "don't"),
        ("im", "I'm"),
        ("i", "I"),
        ("helo", "hello"),
        ("recieve", "receive"),
        ("becuase", "because"),
        ("waht", "what"),
        ("yuo", "you"),
        ("adn", "and"),
        ("tomorow", "tomorrow"),
        ("realy", "really"),
        ("goign", "going"),
        ("thnaks", "thanks"),
        ("plese", "please"),
        ("its", "its"),
        ("were", "were"),
        ("well", "well"),
        ("colour", "colour"),
        ("Dublin", "Dublin"),
        ("asdf", "asdf"),
        ("ok", "ok"),
        ("Teh", "The"),
        ("wierd", "weird"),
        ("aboit", "about"),
        ("somthing", "something"),
        ("whwre", "where"),
        ("hpw", "how"),
        ("cant", "can't"),
        ("Marathon", "Marathon"),
        ("jolla", "Jolla"),
        ("gonna", "gonna"),
    ];
    let mut wrong = Vec::new();
    for (typed, want) in cases {
        let got = engine.suggest(typed, &[], None);
        let commit = got.correction.clone().unwrap_or_else(|| typed.to_owned());
        println!("{typed:>10} -> {commit:<10} {:?}", got.words);
        if commit != want {
            wrong.push(format!("{typed} -> {commit}, wanted {want}"));
        }
    }
    println!("{} of {} wrong: {wrong:#?}", wrong.len(), cases.len());
}

#[test]
fn noisy_taps_are_read_as_their_words() {
    let Some(engine) = engine() else { return };
    let layout = Layout::qwerty();
    let words = common(&engine, 3000);
    for sigma in [0.25_f32, 0.35, 0.45] {
        let mut rng = Rng(0x9e37_79b9_7f4a_7c15);
        let (mut literal_ok, mut engine_ok, mut broken, mut fixed) = (0, 0, 0, 0);
        let start = Instant::now();
        for word in &words {
            let taps: Vec<(f32, f32)> = word
                .chars()
                .map(|c| {
                    let (x, y) = layout.centre(c).unwrap();
                    (x + sigma * rng.gauss(), y + sigma * rng.gauss())
                })
                .collect();
            let typed: String = taps.iter().map(|&t| layout.near(t, 9.0)[0]).collect();
            let got = engine.suggest(&typed, &taps, None);
            let commit = got.correction.unwrap_or_else(|| typed.clone());
            let lit = typed == *word;
            let ok = commit == *word;
            literal_ok += usize::from(lit);
            engine_ok += usize::from(ok);
            broken += usize::from(lit && !ok);
            fixed += usize::from(!lit && ok);
        }
        let n = words.len() as f32;
        println!(
            "taps sigma {sigma}: as tapped {:.1}%, after the keyboard {:.1}% (fixed {fixed}, broke {broken}), {:.2} ms a word",
            100.0 * literal_ok as f32 / n,
            100.0 * engine_ok as f32 / n,
            start.elapsed().as_secs_f32() * 1000.0 / n
        );
    }
}

#[test]
fn noisy_swipes_are_read_as_their_words() {
    let Some(engine) = engine() else { return };
    let layout = Layout::qwerty();
    let words = common(&engine, 2000);
    let mut rng = Rng(0x2545_f491_4f6c_dd1d);
    let (mut top1, mut top3) = (0, 0);
    let mut misses = Vec::new();
    let start = Instant::now();
    for word in &words {
        // Corners through each key with the finger's error, cut every tenth of a key.
        let corners: Vec<(f32, f32)> = word
            .chars()
            .map(|c| {
                let (x, y) = layout.centre(c).unwrap();
                (x + 0.25 * rng.gauss(), y + 0.25 * rng.gauss())
            })
            .collect();
        let mut path = Vec::new();
        for w in corners.windows(2) {
            let d = (w[1].0 - w[0].0).hypot(w[1].1 - w[0].1);
            let steps = (d / 0.1).ceil().max(1.0) as usize;
            for s in 0..steps {
                let t = s as f32 / steps as f32;
                path.push((
                    w[0].0 + t * (w[1].0 - w[0].0),
                    w[0].1 + t * (w[1].1 - w[0].1),
                ));
            }
        }
        path.push(*corners.last().unwrap());
        let got = engine.swipe(&path, None);
        if got.first() == Some(word) {
            top1 += 1;
        } else if misses.len() < 25 {
            misses.push(format!("{word}: {:?}", &got[..got.len().min(3)]));
        }
        top3 += usize::from(got.iter().take(3).any(|w| w == word));
    }
    let n = words.len() as f32;
    println!(
        "swipes: top 1 {:.1}%, top 3 {:.1}%, {:.2} ms a word\nmisses: {misses:#?}",
        100.0 * top1 as f32 / n,
        100.0 * top3 as f32 / n,
        start.elapsed().as_secs_f32() * 1000.0 / n
    );
}
