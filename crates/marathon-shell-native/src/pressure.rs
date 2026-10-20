//! `MemoryPressure`: how long tasks stall on memory, from PSI's "some"
//! avg10 in `/proc/pressure/memory`, read every 5 s on the I/O thread.

use std::pin::Pin;
use std::time::Duration;

use async_io::Timer;
use cxx_qt::Threading;

use crate::{io, log};

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    extern "RustQt" {
        #[qobject]
        type MemoryPressure = super::MemoryPressureRust;

        /// Stalls reached 20 % of the time, or changed while above it.
        #[qsignal]
        fn high(self: Pin<&mut Self>);
        /// Stalls reached 40 %: the system is close to OOM.
        #[qsignal]
        fn critical(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for MemoryPressure {}
    impl cxx_qt::Initialize for MemoryPressure {}
}

const PSI: &str = "/proc/pressure/memory";

#[derive(Default)]
pub struct MemoryPressureRust;

#[derive(Clone, Copy, Debug, PartialEq, PartialOrd)]
enum Level {
    Normal,
    Moderate,
    High,
    Critical,
}

fn level(avg10: f64) -> Level {
    match avg10 {
        a if a >= 40.0 => Level::Critical,
        a if a >= 20.0 => Level::High,
        a if a >= 5.0 => Level::Moderate,
        _ => Level::Normal,
    }
}

fn some_avg10(psi: &str) -> Option<f64> {
    psi.lines().find_map(|l| l.strip_prefix("some "))?.split(' ').find_map(|f| f.strip_prefix("avg10="))?.parse().ok()
}

impl cxx_qt::Initialize for qobject::MemoryPressure {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            if let Err(e) = std::fs::read_to_string(PSI) {
                log::warn("pressure", format_args!("no PSI, pressure is not watched: {e}"));
                return;
            }
            let mut last = Level::Normal;
            loop {
                if let Some(avg10) = std::fs::read_to_string(PSI).ok().as_deref().and_then(some_avg10) {
                    let now = level(avg10);
                    if now != last {
                        log::warn("pressure", format_args!("{now:?} (avg10 {avg10} %)"));
                        last = now;
                        qt.queue(move |mut obj| {
                            if now >= Level::High {
                                obj.as_mut().high();
                            }
                            if now == Level::Critical {
                                obj.critical();
                            }
                        })
                        .ok();
                    }
                }
                Timer::after(Duration::from_secs(5)).await;
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_some_line_is_read() {
        let psi = "some avg10=21.50 avg60=3.00 avg300=1.00 total=123\nfull avg10=45.00 avg60=0 avg300=0 total=9\n";
        assert_eq!(some_avg10(psi), Some(21.5));
        assert_eq!(level(21.5), Level::High);
        assert_eq!(some_avg10("full avg10=1.00\n"), None);
    }
}
