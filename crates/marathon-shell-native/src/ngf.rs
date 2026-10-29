//! `Ngf`: the ngfd D-Bus API (`com.nokia.NonGraphicFeedback1` on the system
//! bus) that Nemo.Ngf, and so Silica's pulley menus, call. Its events become
//! vibration patterns for the haptics.

use std::collections::HashMap;
use std::pin::Pin;
use std::time::Duration;

use async_channel::Sender;
use async_io::Timer;
use cxx_qt::{CxxQtThread, Threading};
use cxx_qt_lib::QList;
use futures_lite::future;
use zbus::object_server::SignalEmitter;
use zbus::OwnedVariant as OwnedValue;

use crate::{io, log};

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qlist.h");
        type QList_i32 = cxx_qt_lib::QList<i32>;
    }

    extern "RustQt" {
        #[qobject]
        type Ngf = super::NgfRust;

        /// Vibrate, pause, vibrate, … in ms.
        #[qsignal]
        fn vibrate(self: Pin<&mut Self>, pattern: &QList_i32);
        #[qsignal]
        #[cxx_name = "stopVibration"]
        fn stop_vibration(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for Ngf {}
    impl cxx_qt::Initialize for Ngf {}
}

use qobject::Ngf;

type Qt = CxxQtThread<Ngf>;

const NAME: &str = "com.nokia.NonGraphicFeedback1.Backend";
const PATH: &str = "/com/nokia/NonGraphicFeedback1";

const FAILED: u32 = 0;
const COMPLETED: u32 = 1;
const PLAYING: u32 = 2;
const PAUSED: u32 = 3;

/// What Silica and Sailfish apps ask ngfd to play.
const EFFECTS: &[(&str, &[i32], bool)] = &[
    ("pulldown_highlight", &[10], false),
    ("pulldown_lock", &[25], false),
    ("feedback_press", &[15], false),
    ("feedback_press_weak", &[8], false),
    ("feedback_release", &[8], false),
    ("feedback_lock", &[30], false),
    ("keypad_press", &[10], false),
    ("keyboard_press", &[8], false),
    ("sms", &[200, 100, 200], false),
    ("chat", &[200, 100, 200], false),
    ("email", &[150], false),
    ("im", &[200, 100, 200], false),
    ("notice", &[150], false),
    ("general_warning", &[300], false),
    ("battery_low", &[300, 150, 300], false),
    ("ringtone", &[800, 1200], true),
    ("alarm", &[500, 500], true),
    ("clock", &[500, 500], true),
    ("calendar", &[300, 200, 300], false),
];

#[derive(Default)]
pub struct NgfRust;

impl cxx_qt::Initialize for Ngf {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let served = async {
                let conn = io::system_bus().await?;
                conn.object_server()
                    .at(
                        PATH,
                        Server {
                            qt,
                            next: 1,
                            playing: HashMap::new(),
                        },
                    )
                    .await?;
                conn.request_name(NAME).await
            };
            if let Err(e) = served.await {
                log::warn("ngf", format_args!("Nemo.Ngf backend not registered: {e}"));
            }
        });
    }
}

/// The pattern, and whether it repeats until stopped.
type Effect = (&'static [i32], bool);

struct Playing {
    effect: Effect,
    // Dropped to stop the effect's timer.
    timer: Option<Sender<()>>,
}

struct Server {
    qt: Qt,
    next: u32,
    playing: HashMap<u32, Playing>,
}

fn effect(event: &str) -> Option<Effect> {
    EFFECTS
        .iter()
        .find(|(name, _, _)| *name == event)
        .map(|&(_, pattern, repeat)| (pattern, repeat))
}

/// After the call's reply, so the caller knows the id.
fn status(emitter: &SignalEmitter<'_>, id: u32, state: u32) {
    let emitter = emitter.to_owned();
    io::spawn(async move {
        Timer::after(Duration::from_millis(1)).await;
        Server::status(&emitter, id, state).await.ok();
    });
}

#[zbus::interface(name = "com.nokia.NonGraphicFeedback1")]
#[allow(
    clippy::needless_pass_by_value,
    reason = "the arguments zbus hands over"
)]
impl Server {
    #[allow(unused_variables, reason = "no event takes properties")]
    fn play(
        &mut self,
        event: &str,
        properties: HashMap<String, OwnedValue>,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> u32 {
        let id = self.next;
        self.next = self.next.wrapping_add(1).max(1);
        let Some(effect) = effect(event) else {
            status(&emitter, id, FAILED);
            return id;
        };
        self.vibrate(effect.0);
        status(&emitter, id, PLAYING);
        let timer = Self::start(id, effect, &emitter);
        self.playing.insert(
            id,
            Playing {
                effect,
                timer: Some(timer),
            },
        );
        id
    }

    fn pause(
        &mut self,
        id: u32,
        pause: bool,
        #[zbus(signal_emitter)] emitter: SignalEmitter<'_>,
    ) -> bool {
        let Some(playing) = self.playing.get_mut(&id) else {
            return false;
        };
        if pause {
            playing.timer = None;
            self.qt.queue(Ngf::stop_vibration).ok();
            status(&emitter, id, PAUSED);
        } else {
            let effect = playing.effect;
            let timer = Self::start(id, effect, &emitter);
            self.playing.entry(id).and_modify(|p| p.timer = Some(timer));
            status(&emitter, id, PLAYING);
        }
        true
    }

    fn stop(&mut self, id: u32, #[zbus(signal_emitter)] emitter: SignalEmitter<'_>) -> bool {
        if self.playing.remove(&id).is_none() {
            return false;
        }
        self.qt.queue(Ngf::stop_vibration).ok();
        status(&emitter, id, COMPLETED);
        true
    }

    #[zbus(signal)]
    async fn status(emitter: &SignalEmitter<'_>, id: u32, state: u32) -> zbus::Result<()>;
}

impl Server {
    fn vibrate(&self, pattern: &'static [i32]) {
        self.qt
            .queue(move |obj| obj.vibrate(&pattern.iter().copied().collect::<QList<i32>>()))
            .ok();
    }

    /// Every pattern's length: a repeating effect vibrates again, any other
    /// completes. Ends when its sender is dropped.
    fn start(id: u32, (pattern, repeat): Effect, emitter: &SignalEmitter<'_>) -> Sender<()> {
        let (timer, stopped) = async_channel::bounded::<()>(1);
        let emitter = emitter.to_owned();
        let period = Duration::from_millis(u64::try_from(pattern.iter().sum::<i32>()).unwrap_or(0));
        io::spawn(async move {
            loop {
                let ended = future::or(
                    async {
                        Timer::after(period).await;
                        false
                    },
                    async { stopped.recv().await.is_err() },
                );
                if ended.await {
                    return;
                }
                let Ok(iface) = emitter
                    .connection()
                    .object_server()
                    .interface::<_, Server>(PATH)
                    .await
                else {
                    return;
                };
                let mut server = iface.get_mut().await;
                if stopped.is_closed() {
                    return;
                }
                if repeat {
                    server.vibrate(pattern);
                    continue;
                }
                server.playing.remove(&id);
                Server::status(&emitter, id, COMPLETED).await.ok();
                return;
            }
        });
        timer
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn events_are_patterns() {
        assert_eq!(effect("alarm"), Some((&[500, 500][..], true)));
        assert!(effect("pulldown_highlight").is_some_and(|(_, repeat)| !repeat));
        assert_eq!(effect("no_such_event"), None);
    }
}
