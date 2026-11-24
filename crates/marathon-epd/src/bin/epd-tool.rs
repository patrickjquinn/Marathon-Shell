//! Host tool for the e-paper engine.
//!
//! - `bench [--threads N] [--ticks N]`: engine cost per 85 Hz tick at 800×600 (CPU, and the GPU
//!   with `--features gles`).
//! - `trace W H [--waveform iwf:PATH|v25:A.csv,B.csv]`: drives the engine from stdin for the ink
//!   simulator. Per frame, stdin gives one flags byte (bit 0 allow greys, bit 1 stop) and W·H
//!   target bytes; stdout returns W·H/4 drive bytes and five little-endian u32 stats.
//! - `vectors DIR`: DSI frames from the engine for the bridge RTL testbench, one `$readmemh`
//!   file per frame (800×600 24-bit words, link v2) plus `frames.txt` describing each.
#![allow(
    clippy::print_stdout,
    clippy::print_stderr,
    reason = "a command-line tool"
)]

use std::fmt::Write as _;
use std::io::{Read, Write};
use std::path::Path;
use std::time::Instant;

use marathon_epd::engine::{drive_len, target, CpuEngine, Params, Stats, CLASS_AUTO, CLASS_MONO};
use marathon_epd::link::{pack_frame, Sequencer, DSI_W, FRAME_BYTES, PANEL_H, PANEL_W};
use marathon_epd::waveform::{parse_v25, EngineWaveform, V25Axes, Waveform};

type Res<T> = Result<T, Box<dyn std::error::Error>>;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let r = match args.first().map(String::as_str) {
        Some("bench") => bench(&args[1..]),
        Some("trace") => trace(&args[1..]),
        Some("vectors") => vectors(&args[1..]),
        _ => Err("usage: epd-tool bench|trace|vectors ...".into()),
    };
    if let Err(e) = r {
        eprintln!("epd-tool: {e}");
        std::process::exit(1);
    }
}

fn flag(args: &[String], name: &str) -> Option<String> {
    args.iter()
        .position(|a| a == name)
        .and_then(|i| args.get(i + 1).cloned())
}

fn waveform(spec: Option<String>) -> Res<EngineWaveform> {
    let Some(spec) = spec else {
        return Ok(EngineWaveform::reference());
    };
    if let Some(path) = spec.strip_prefix("iwf:") {
        let wf = Waveform::load_iwf(Path::new(path))?;
        let pick = |names: &[&str]| names.iter().find_map(|n| wf.mode(n));
        let bin = pick(&["A2", "DU", "BIN"]).ok_or("no binary mode (A2/DU) in the IWF")?;
        let grey = pick(&["GL16", "GC16", "GREY"]).ok_or("no grey mode (GL16/GC16) in the IWF")?;
        return Ok(EngineWaveform::new(&wf, bin, grey));
    }
    if let Some(files) = spec.strip_prefix("v25:") {
        let (grey, bin) = files.split_once(',').ok_or("v25:GREY.csv,BIN.csv")?;
        let axes = V25Axes {
            c_is_src: true,
            p_is_white: false,
            reverse_time: false,
        };
        let load = |f: &str| -> Res<_> { Ok(parse_v25(&std::fs::read_to_string(f)?, f, axes)?) };
        let mut wf = Waveform::reference();
        wf.tables = vec![load(bin)?, load(grey)?];
        return Ok(EngineWaveform::new(&wf, 0, 1));
    }
    Err(format!("unknown waveform {spec:?}").into())
}

struct Scenario {
    name: &'static str,
    /// Updates the target before tick `t`.
    step: fn(usize, &mut [u8]),
}

fn full_flip(t: usize, tg: &mut [u8]) {
    // Every pixel reverses every 6 frames, mid-transition: the whole panel cancels and rewinds.
    if t.is_multiple_of(6) {
        let white = (t / 6).is_multiple_of(2);
        tg.fill(target(if white { 15 } else { 0 }, white, CLASS_MONO));
    }
}

fn page_turn(t: usize, tg: &mut [u8]) {
    // New grey content over the whole panel every 60 frames: MONO, HOLD, then GREY everywhere.
    if t.is_multiple_of(60) {
        for (i, v) in tg.iter_mut().enumerate() {
            let g = u32::try_from((i * 7 + t * 13 + i / PANEL_W * 3) % 16).unwrap_or(0);
            *v = target(g, g >= 8, CLASS_AUTO);
        }
    }
}

fn typing(t: usize, tg: &mut [u8]) {
    // A 64×32 block of the panel changes every 8 frames, the rest is still.
    if t.is_multiple_of(8) {
        let white = (t / 8).is_multiple_of(2);
        for y in 300..332 {
            for x in 100..164 {
                tg[y * PANEL_W + x] = target(if white { 15 } else { 0 }, white, CLASS_MONO);
            }
        }
    }
}

fn idle(_: usize, _: &mut [u8]) {}

#[allow(clippy::cast_precision_loss, reason = "small counts")]
fn report(name: &str, mut ms: Vec<f64>) {
    ms.sort_by(f64::total_cmp);
    let mean = ms.iter().sum::<f64>() / ms.len() as f64;
    let p99 = ms[(ms.len() * 99 / 100).min(ms.len() - 1)];
    let mpix = (PANEL_W * PANEL_H) as f64 / mean / 1e3;
    println!(
        "{name:<26} mean {mean:6.3} ms  p99 {p99:6.3} ms  {mpix:7.1} Mpix/s  {:5.1}% of an 85 Hz frame",
        mean / (1000.0 / 85.0) * 100.0
    );
}

fn bench(args: &[String]) -> Res<()> {
    let ticks: usize = flag(args, "--ticks").map_or(Ok(600), |s| s.parse())?;
    let wf = waveform(flag(args, "--waveform"))?;
    let p = Params::new(&wf, 0);
    let scenarios = [
        Scenario {
            name: "full-panel flip/cancel",
            step: full_flip,
        },
        Scenario {
            name: "full-panel page turn",
            step: page_turn,
        },
        Scenario {
            name: "typing 64x32",
            step: typing,
        },
        Scenario {
            name: "idle panel",
            step: idle,
        },
    ];
    let threads: Vec<usize> = match flag(args, "--threads") {
        Some(t) => t.split(',').map(str::parse).collect::<Result<_, _>>()?,
        None => vec![1, 2, 4],
    };
    let mut drive = vec![0u8; drive_len(PANEL_W, PANEL_H)];
    for &n in &threads {
        println!("CPU, {n} thread(s), {ticks} ticks, 800x600:");
        for sc in &scenarios {
            let mut e = CpuEngine::new(PANEL_W, PANEL_H, 15, &p);
            e.threads = n;
            let mut tg = vec![target(15, true, CLASS_AUTO); PANEL_W * PANEL_H];
            let mut ms = Vec::with_capacity(ticks);
            for t in 0..ticks {
                (sc.step)(t, &mut tg);
                let t0 = Instant::now();
                std::hint::black_box(e.tick(&tg, &p, &wf.lut, &mut drive));
                ms.push(t0.elapsed().as_secs_f64() * 1e3);
            }
            report(sc.name, ms);
        }
    }
    #[cfg(feature = "gles")]
    gpu_bench(&scenarios, ticks, &wf, &p)?;
    Ok(())
}

#[cfg(feature = "gles")]
fn gpu_bench(scenarios: &[Scenario], ticks: usize, wf: &EngineWaveform, p: &Params) -> Res<()> {
    use marathon_epd::engine::idle_state;
    use marathon_epd::gpu::GpuEngine;
    let g = GpuEngine::new(PANEL_W, PANEL_H, &wf.lut)?;
    println!(
        "GPU ({}), {ticks} ticks, 800x600; dispatch = upload target + compute + wait:",
        g.renderer
    );
    let mut drive = vec![0u8; drive_len(PANEL_W, PANEL_H)];
    for sc in scenarios {
        g.upload_state(
            &vec![idle_state(15); PANEL_W * PANEL_H],
            &vec![p.rest_dc(15); PANEL_W * PANEL_H],
        );
        let mut tg = vec![target(15, true, CLASS_AUTO); PANEL_W * PANEL_H];
        let (mut d, mut full) = (Vec::new(), Vec::new());
        for t in 0..ticks {
            (sc.step)(t, &mut tg);
            let t0 = Instant::now();
            if t % 2 == 0 {
                g.dispatch(&tg, p);
                d.push(t0.elapsed().as_secs_f64() * 1e3);
            } else {
                std::hint::black_box(g.tick(&tg, p, &mut drive));
                full.push(t0.elapsed().as_secs_f64() * 1e3);
            }
        }
        report(&format!("{} (dispatch)", sc.name), d);
        report(&format!("{} (+readback)", sc.name), full);
    }
    Ok(())
}

fn trace(args: &[String]) -> Res<()> {
    let width: usize = args.first().ok_or("trace W H")?.parse()?;
    let height: usize = args.get(1).ok_or("trace W H")?.parse()?;
    let wf = waveform(flag(args, "--waveform"))?;
    let mut p = Params::new(&wf, 0);
    if let Some(q) = flag(args, "--quiet") {
        p.quiet_frames = q.parse()?;
    }
    let mut e = CpuEngine::new(width, height, 15, &p);
    let (mut stdin, mut stdout) = (std::io::stdin().lock(), std::io::stdout().lock());
    let mut tg = vec![0u8; width * height];
    let mut drive = vec![0u8; drive_len(width, height)];
    let mut flags = [0u8; 1];
    loop {
        stdin.read_exact(&mut flags)?;
        if flags[0] & 2 != 0 {
            return Ok(());
        }
        stdin.read_exact(&mut tg)?;
        p.allow_grey = flags[0] & 1 != 0;
        let s: Stats = e.tick(&tg, &p, &wf.lut, &mut drive);
        stdout.write_all(&drive)?;
        for v in [s.active, s.pending, s.driven, s.row_min, s.row_max] {
            stdout.write_all(&v.to_le_bytes())?;
        }
        stdout.flush()?;
    }
}

/// A resync, a bar moving down the panel for a few frames (real engine output, scan windows
/// follow the bar), then a drain.
fn vectors(args: &[String]) -> Res<()> {
    let dir = Path::new(args.first().ok_or("vectors DIR")?);
    std::fs::create_dir_all(dir)?;
    let wf = EngineWaveform::reference();
    let p = Params::new(&wf, 0);
    let mut e = CpuEngine::new(PANEL_W, PANEL_H, 15, &p);
    let mut tg = vec![target(15, true, CLASS_MONO); PANEL_W * PANEL_H];
    let mut drive = vec![0u8; drive_len(PANEL_W, PANEL_H)];
    let mut seq = Sequencer::default();
    let mut wire = vec![0u8; FRAME_BYTES];
    let mut list = String::new();
    let mut write = |i: usize, wire: &[u8], what: String| -> Res<()> {
        let mut text = String::with_capacity(wire.len() / 3 * 7);
        for px in wire.as_chunks::<3>().0 {
            writeln!(text, "{:02x}{:02x}{:02x}", px[0], px[1], px[2])?;
        }
        std::fs::write(dir.join(format!("frame_{i:03}.hex")), text)?;
        writeln!(list, "frame_{i:03}.hex {what}")?;
        Ok(())
    };
    pack_frame(&seq.resync(), &drive, &mut wire);
    write(0, &wire, "resync".into())?;
    for i in 1..=4 {
        let y0 = 100 + 37 * i;
        for y in y0..y0 + 30 {
            for x in 40 + 16 * i..360 + 16 * i {
                tg[y * PANEL_W + x] = target(0, false, CLASS_MONO);
            }
        }
        let s = e.tick(&tg, &p, &wf.lut, &mut drive);
        let rows = (s.row_min <= s.row_max).then_some((s.row_min, s.row_max));
        let h = seq.drive(rows);
        pack_frame(&h, &drive, &mut wire);
        write(i, &wire, format!("drive seq {} rows {:?}", h.seq, rows))?;
    }
    pack_frame(&seq.drain(), &drive, &mut wire);
    write(5, &wire, "drain (stale payload, must not drive)".into())?;
    std::fs::write(dir.join("frames.txt"), list)?;
    println!(
        "wrote 6 frames of {}x{} words to {}",
        DSI_W,
        FRAME_BYTES / 3 / DSI_W,
        dir.display()
    );
    Ok(())
}
