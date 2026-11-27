//! The process's I/O thread: one executor for every backend, so D-Bus, sysfs
//! and file work never runs on the GUI thread.

use std::future::Future;
use std::io;
use std::path::Path;
use std::str::FromStr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use async_channel::{Receiver, RecvError};
use async_io::Timer;

use async_executor::Executor;

static EXECUTOR: Executor<'static> = Executor::new();
static THREAD_STARTED: Mutex<bool> = Mutex::new(false);

fn spawn_with(
    executor: &'static Executor<'static>,
    thread_started: &Mutex<bool>,
    task: impl Future<Output = ()> + Send + 'static,
    start_thread: impl FnOnce() -> io::Result<()>,
) -> io::Result<()> {
    let mut started = thread_started.lock().map_err(|error| {
        io::Error::other(format!("I/O thread startup state is poisoned: {error}"))
    })?;
    if !*started {
        start_thread()?;
        *started = true;
    }
    drop(started);

    executor.spawn(task).detach();
    Ok(())
}

/// Runs `task` on the I/O thread, starting it on first use.
///
/// If creating the thread fails, `task` is dropped and the next call retries
/// thread creation. The failure is written to the process log.
pub fn spawn(task: impl Future<Output = ()> + Send + 'static) {
    let spawned = spawn_with(&EXECUTOR, &THREAD_STARTED, task, || {
        std::thread::Builder::new()
            .name("marathon-io".into())
            .spawn(|| async_io::block_on(EXECUTOR.run(futures_lite::future::pending::<()>())))
            .map(drop)
    });
    if let Err(error) = spawned {
        crate::log::warn("io", format_args!("cannot start the I/O thread: {error}"));
    }
}

/// A file's trimmed contents, parsed: how sysfs and procfs report a value.
pub fn read<T: FromStr>(path: impl AsRef<Path>) -> Option<T> {
    std::fs::read_to_string(path).ok()?.trim().parse().ok()
}

/// The next message, or `None` if `within` passes first; with no `within`,
/// waits for it.
pub async fn recv_within<T>(
    rx: &Receiver<T>,
    within: Option<Duration>,
) -> Option<Result<T, RecvError>> {
    match within {
        Some(within) => timeout(within, rx.recv()).await,
        None => Some(rx.recv().await),
    }
}

/// [`timeout`] for a D-Bus call: one still running when `within` passes runs
/// on to the end. A message dropped halfway out leaves the bus reading the
/// next one as its rest, and it then drops the connection.
pub async fn call_within<T: Send + 'static>(
    within: Duration,
    call: impl Future<Output = T> + Send + 'static,
) -> Option<T> {
    let (tx, rx) = async_channel::bounded(1);
    spawn(async move {
        tx.send(call.await).await.ok();
    });
    timeout(within, rx.recv()).await?.ok()
}

/// `task`'s output, or `None` if `within` passes first.
pub async fn timeout<T>(within: Duration, task: impl Future<Output = T>) -> Option<T> {
    futures_lite::future::or(async { Some(task.await) }, async {
        Timer::after(within).await;
        None
    })
    .await
}

static SYSTEM: Bus = Bus::new("system");
static SESSION: Bus = Bus::new("session");

/// The process's system bus connection. A failed connect is retried on the
/// next call, and a connection the bus closed is replaced.
pub async fn system_bus() -> zbus::Result<zbus::Connection> {
    SYSTEM.get(zbus::Connection::system).await
}

/// The process's session bus connection. A failed connect is retried on the
/// next call, and a connection the bus closed is replaced.
pub async fn session_bus() -> zbus::Result<zbus::Connection> {
    SESSION.get(zbus::Connection::session).await
}

/// Runs `task` on the I/O thread with the system bus connection, and again
/// with each one that replaces it. A task still running when its connection
/// closes is dropped.
pub fn each_system_bus<T>(task: impl FnMut(zbus::Connection) -> T + Send + 'static)
where
    T: Future<Output = ()> + Send + 'static,
{
    spawn(each(system_bus, task));
}

/// [`each_system_bus`] for the session bus: for what owns a name, exports an
/// object or follows signals there, none of which a new connection has.
pub fn each_session_bus<T>(task: impl FnMut(zbus::Connection) -> T + Send + 'static)
where
    T: Future<Output = ()> + Send + 'static,
{
    spawn(each(session_bus, task));
}

/// A connection the bus closes this soon after it opened makes the next
/// connect wait, twice as long each time: a message the bus refuses at every
/// start must not spin the process.
const SHORT_LIVED: Duration = Duration::from_secs(10);
const RECONNECT_MAX: Duration = Duration::from_secs(32);

struct Bus {
    name: &'static str,
    slot: async_lock::Mutex<Slot>,
}

struct Slot {
    connection: Option<zbus::Connection>,
    opened: Option<Instant>,
    delay: Duration,
}

impl Bus {
    const fn new(name: &'static str) -> Self {
        Self {
            name,
            slot: async_lock::Mutex::new(Slot {
                connection: None,
                opened: None,
                delay: Duration::ZERO,
            }),
        }
    }

    async fn get<C>(&self, connect: impl FnOnce() -> C) -> zbus::Result<zbus::Connection>
    where
        C: Future<Output = zbus::Result<zbus::Connection>>,
    {
        let mut slot = self.slot.lock().await;
        if let Some(open) = slot.connection.as_ref().filter(|c| !c.is_closed()) {
            return Ok(open.clone());
        }
        if let Some(lost) = slot.connection.take() {
            let name = lost.unique_name().map_or_default(ToString::to_string);
            crate::log::warn(
                "io",
                format_args!(
                    "LOST the {} bus connection {name}: the bus closed it; reconnecting",
                    self.name
                ),
            );
            slot.delay = if slot.opened.is_some_and(|t| t.elapsed() < SHORT_LIVED) {
                (slot.delay * 2).clamp(Duration::from_secs(1), RECONNECT_MAX)
            } else {
                Duration::ZERO
            };
        }
        if !slot.delay.is_zero() {
            Timer::after(slot.delay).await;
        }
        let connection = connect().await?;
        if slot.opened.is_some() {
            let name = connection.unique_name().map_or_default(ToString::to_string);
            crate::log::warn(
                "io",
                format_args!("{} bus: reconnected as {name}", self.name),
            );
        }
        slot.opened = Some(Instant::now());
        slot.connection = Some(connection.clone());
        Ok(connection)
    }
}

async fn each<B, T>(bus: impl Fn() -> B, mut task: impl FnMut(zbus::Connection) -> T)
where
    B: Future<Output = zbus::Result<zbus::Connection>>,
    T: Future<Output = ()>,
{
    let mut retry = Duration::from_secs(1);
    loop {
        match bus().await {
            Ok(connection) => {
                retry = Duration::from_secs(1);
                let run = task(connection.clone());
                futures_lite::future::or(
                    async {
                        run.await;
                        futures_lite::future::pending::<()>().await;
                    },
                    connection.closed(),
                )
                .await;
            }
            Err(e) => {
                crate::log::warn("io", format_args!("no bus connection: {e}"));
                Timer::after(retry).await;
                retry = (retry * 2).min(RECONNECT_MAX);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use std::pin::Pin;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::sync::Arc;
    use std::task::{Context, Poll};

    use super::*;

    struct PendingUntilDropped(Arc<AtomicBool>);

    impl Future for PendingUntilDropped {
        type Output = ();

        fn poll(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<Self::Output> {
            Poll::Pending
        }
    }

    impl Drop for PendingUntilDropped {
        fn drop(&mut self) {
            self.0.store(true, Ordering::Relaxed);
        }
    }

    #[test]
    fn failed_thread_start_drops_task_and_can_be_retried() {
        static TEST_EXECUTOR: Executor<'static> = Executor::new();

        let thread_started = Mutex::new(false);
        let starts = AtomicUsize::new(0);
        let dropped = Arc::new(AtomicBool::new(false));

        let failed = spawn_with(
            &TEST_EXECUTOR,
            &thread_started,
            PendingUntilDropped(Arc::clone(&dropped)),
            || {
                starts.fetch_add(1, Ordering::Relaxed);
                Err(io::Error::other("injected thread creation failure"))
            },
        );
        assert!(failed.is_err());
        assert!(dropped.load(Ordering::Relaxed));
        assert!(!TEST_EXECUTOR.try_tick());

        let retried = spawn_with(&TEST_EXECUTOR, &thread_started, async {}, || {
            starts.fetch_add(1, Ordering::Relaxed);
            Ok(())
        });
        assert!(retried.is_ok());
        assert_eq!(starts.load(Ordering::Relaxed), 2);
        assert!(TEST_EXECUTOR.try_tick());
    }

    #[cfg(feature = "testing")]
    #[allow(clippy::unwrap_used, clippy::expect_used, reason = "tests")]
    mod buses {
        use std::collections::HashMap;

        use zbus::{fdo, OwnedVariant};

        use super::super::*;
        use crate::testing::PrivateBus;

        const PROBE: &str = "org.marathonos.Probe";

        fn connect(address: &str) -> impl Future<Output = zbus::Result<zbus::Connection>> {
            let address = address.to_owned();
            async move {
                zbus::connection::Builder::address(address.as_str())
                    .build()
                    .await
            }
        }

        /// What dbus-broker cut the shell off for on the Jolla: a body that
        /// does not hold to D-Bus, here a string with a NUL in it.
        async fn send_invalid_body(connection: &zbus::Connection) {
            let state = HashMap::from([(
                "ssid".to_owned(),
                OwnedVariant::try_from(zbus::Variant::from("Cafe\0\0")).unwrap(),
            )]);
            connection
                .emit_signal(
                    None::<&str>,
                    "/probe",
                    "org.marathonos.Probe1",
                    "StateChanged",
                    &(state,),
                )
                .await
                .ok();
            let closed = timeout(Duration::from_secs(5), connection.closed()).await;
            assert!(
                closed.is_some(),
                "the bus kept a connection that sent an invalid body"
            );
        }

        async fn owner(observer: &fdo::DBusProxy<'_>) -> Option<String> {
            observer
                .get_name_owner(PROBE.try_into().unwrap())
                .await
                .ok()
                .map(|o| o.to_string())
        }

        #[test]
        fn a_connection_the_bus_closed_is_replaced() {
            let Some(private) = PrivateBus::start() else {
                return;
            };
            let bus = Bus::new("test");
            async_io::block_on(async {
                let first = bus.get(|| connect(&private.address)).await.unwrap();
                assert_eq!(
                    bus.get(|| connect(&private.address))
                        .await
                        .unwrap()
                        .unique_name(),
                    first.unique_name()
                );
                send_invalid_body(&first).await;
                let second = bus.get(|| connect(&private.address)).await.unwrap();
                assert_ne!(second.unique_name(), first.unique_name());
                let id = fdo::DBusProxy::new(&second).await.unwrap().get_id().await;
                assert!(id.is_ok(), "the new connection does not work: {id:?}");
            });
        }

        #[test]
        fn each_runs_again_on_the_new_connection() {
            let Some(private) = PrivateBus::start() else {
                return;
            };
            let bus = Bus::new("test");
            let (tx, rx) = async_channel::unbounded();
            let each = each(
                || bus.get(|| connect(&private.address)),
                move |connection: zbus::Connection| {
                    let tx = tx.clone();
                    async move {
                        connection.request_name(PROBE).await.unwrap();
                        tx.send(connection).await.ok();
                    }
                },
            );
            let checks = async {
                let observer = connect(&private.address).await.unwrap();
                let observer = fdo::DBusProxy::new(&observer).await.unwrap();
                let first = rx.recv().await.unwrap();
                let first_name = first.unique_name().map(ToString::to_string);
                assert_eq!(owner(&observer).await, first_name);
                send_invalid_body(&first).await;
                let second = timeout(Duration::from_secs(10), rx.recv())
                    .await
                    .expect("the task never ran on a new connection")
                    .unwrap();
                assert_ne!(second.unique_name(), first.unique_name());
                assert_eq!(
                    owner(&observer).await,
                    second.unique_name().map(ToString::to_string)
                );
            };
            async_io::block_on(futures_lite::future::or(
                async {
                    each.await;
                },
                checks,
            ));
        }
    }
}
