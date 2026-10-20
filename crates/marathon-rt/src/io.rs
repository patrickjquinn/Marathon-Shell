//! The process's I/O thread: one executor for every backend, so D-Bus, sysfs
//! and file work never runs on the GUI thread.

use std::future::Future;
use std::path::Path;
use std::str::FromStr;
use std::sync::Once;
use std::time::Duration;

use async_channel::{Receiver, RecvError};
use async_io::Timer;

use async_executor::Executor;
use async_lock::OnceCell;

static EXECUTOR: Executor<'static> = Executor::new();
static THREAD: Once = Once::new();

/// Runs `task` on the I/O thread, starting it on first use.
pub fn spawn(task: impl Future<Output = ()> + Send + 'static) {
    THREAD.call_once(|| {
        let started = std::thread::Builder::new()
            .name("marathon-io".into())
            .spawn(|| async_io::block_on(EXECUTOR.run(futures_lite::future::pending::<()>())));
        if let Err(e) = started {
            crate::log::warn("io", format_args!("cannot start the I/O thread: {e}"));
        }
    });
    EXECUTOR.spawn(task).detach();
}

/// A file's trimmed contents, parsed: how sysfs and procfs report a value.
pub fn read<T: FromStr>(path: impl AsRef<Path>) -> Option<T> {
    std::fs::read_to_string(path).ok()?.trim().parse().ok()
}

/// The next message, or `None` if `within` passes first; with no `within`,
/// waits for it.
pub async fn recv_within<T>(rx: &Receiver<T>, within: Option<Duration>) -> Option<Result<T, RecvError>> {
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
    BUS.get_or_try_init(zbus::Connection::session).await.cloned()
}
