//! The process's I/O thread: one executor for every backend, so D-Bus, sysfs
//! and file work never runs on the GUI thread.

use std::future::Future;
use std::io;
use std::path::Path;
use std::str::FromStr;
use std::sync::Mutex;
use std::time::Duration;

use async_channel::{Receiver, RecvError};
use async_io::Timer;

use async_executor::Executor;
use async_lock::OnceCell;

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

/// `task`'s output, or `None` if `within` passes first.
pub async fn timeout<T>(within: Duration, task: impl Future<Output = T>) -> Option<T> {
    futures_lite::future::or(async { Some(task.await) }, async {
        Timer::after(within).await;
        None
    })
    .await
}

/// The process's one system bus connection; a failed connect is retried on
/// the next call.
pub async fn system_bus() -> zbus::Result<zbus::Connection> {
    static BUS: OnceCell<zbus::Connection> = OnceCell::new();
    BUS.get_or_try_init(zbus::Connection::system).await.cloned()
}

/// The process's one session bus connection.
pub async fn session_bus() -> zbus::Result<zbus::Connection> {
    static BUS: OnceCell<zbus::Connection> = OnceCell::new();
    BUS.get_or_try_init(zbus::Connection::session)
        .await
        .cloned()
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
}
