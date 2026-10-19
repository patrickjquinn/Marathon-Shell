//! The shell's I/O thread: one executor for every backend, so D-Bus, sysfs
//! and file work never runs on the GUI thread.

use std::future::Future;
use std::sync::Once;

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
