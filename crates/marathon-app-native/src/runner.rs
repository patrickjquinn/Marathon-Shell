//! What marathon-app-runner does outside QML: how it was started, a pool
//! spare's adoption, the shell's calls to it (`Lifecycle1`), where its QML
//! comes from, and the spare's keepalive.

use std::collections::HashMap;
use std::fs;
use std::hash::{Hash, Hasher};
use std::io::Write as _;
use std::path::{Path, PathBuf};
use std::pin::Pin;

use clap::Parser;
use cxx_qt::{CxxQtThread, CxxQtType, Threading};
use cxx_qt_lib::{QByteArray, QList, QString, QStringList};
use marathon_keel::{caller_is_shell, runner_name, RUNNER_PATH};
use marathon_rt::{io, log};
use zbus::fdo;
use zbus::message::Header;

#[cxx_qt::bridge(namespace = "marathon::runner")]
pub mod ffi {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
        include!("cxx-qt-lib/qbytearray.h");
        type QByteArray = cxx_qt_lib::QByteArray;
    }

    /// How the runner was started: a spare (`pool`), or for an app, at a
    /// route with its JSON parameters.
    struct Launch {
        pool: bool,
        app_id: QString,
        route: QString,
        route_params: QString,
    }

    extern "Rust" {
        /// The command line, and `MARATHON_APP_ROUTE*` for what it leaves
        /// out. Read before Qt starts; prints usage and exits on `--help`.
        fn launch() -> Launch;
        /// A spare's adoption: one JSON line on stdin (its app, route and
        /// environment, which it exports). An empty app id for a bad line.
        fn adopt(line: &QByteArray) -> Launch;
        /// One line of `$XDG_RUNTIME_DIR/marathon-startup.log`.
        fn log_startup(app_id: &QString, phase: &str, ms: i64);
        /// MarathonOS.Shell's import roots, dev builds first; where a qmldir
        /// says `prefer :/qt/qml/`, a copy without it (the runner's own
        /// resources hold only the shell's singletons).
        fn shell_import_roots(binary_dir: &QString) -> QStringList;
        /// QML that makes `component` from the app's module, for an app
        /// whose entry file is compiled in; empty when it has no module.
        fn entry_wrapper(app_path: &QString, app_id: &QString, component: &QString) -> QString;
        /// Reads every page of the resident private working set: a spare's
        /// keepalive when it cannot lock its memory.
        fn touch_resident_pages();
    }

    extern "RustQt" {
        /// The shell's calls (`org.marathonos.AppRunner.<id>`, `Lifecycle1`).
        /// Back and Forward go to the app's root through main.cpp, which
        /// answers with `answer`.
        #[qobject]
        type RunnerLifecycle = super::RunnerLifecycleRust;

        #[qsignal]
        #[cxx_name = "backRequested"]
        fn back_requested(self: Pin<&mut Self>);
        #[qsignal]
        #[cxx_name = "forwardRequested"]
        fn forward_requested(self: Pin<&mut Self>);
        /// Frozen, the app holds no bus name: a call for it then
        /// bus-activates and the shell thaws it.
        #[qsignal]
        #[cxx_name = "prepareFreezeRequested"]
        fn prepare_freeze_requested(self: Pin<&mut Self>);
        #[qsignal]
        fn thawed(self: Pin<&mut Self>);

        fn serve(self: Pin<&mut RunnerLifecycle>, app_id: &QString);
        fn answer(self: Pin<&mut RunnerLifecycle>, handled: bool);
        /// The root's `minimizeRequested`: an app with nothing to go back
        /// to, which the shell then sends home.
        #[qinvokable]
        #[cxx_name = "minimizeRequested"]
        fn minimize_requested(self: Pin<&mut RunnerLifecycle>);
    }

    impl cxx_qt::Threading for RunnerLifecycle {}
}

use ffi::{Launch, RunnerLifecycle};

#[derive(Parser)]
#[command(about = "Runs a Marathon QML app out of process", ignore_errors = true)]
struct Args {
    /// Marathon app id (e.g. phone, calculator).
    #[arg(short, long)]
    app_id: Option<String>,
    /// In-app route to open (e.g. /emergency).
    #[arg(short, long)]
    route: Option<String>,
    /// A warm spare, adopted later through stdin.
    #[arg(long)]
    pool: bool,
}

fn launch() -> Launch {
    // From /proc: on musl, std::env::args is empty when Rust's main is not
    // the program's.
    let cmdline = fs::read("/proc/self/cmdline").unwrap_or_default();
    let cmdline = cmdline.strip_suffix(&[0]).unwrap_or(&cmdline);
    let args = Args::parse_from(
        cmdline
            .split(|b| *b == 0)
            .map(|a| String::from_utf8_lossy(a).into_owned()),
    );
    let env = |name| std::env::var(name).unwrap_or_default();
    Launch {
        pool: args.pool,
        app_id: QString::from(args.app_id.unwrap_or_default().trim()),
        route: QString::from(
            &args
                .route
                .filter(|r| !r.trim().is_empty())
                .unwrap_or_else(|| env("MARATHON_APP_ROUTE")),
        ),
        route_params: QString::from(&env("MARATHON_APP_ROUTE_PARAMS")),
    }
}

#[derive(serde::Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct Adopt {
    app_id: String,
    route: String,
    route_params: String,
    env: HashMap<String, String>,
}

fn adopt(line: &QByteArray) -> Launch {
    let message: Adopt = serde_json::from_slice(line.as_slice()).unwrap_or_default();
    for (key, value) in &message.env {
        std::env::set_var(key, value);
    }
    Launch {
        pool: true,
        app_id: QString::from(message.app_id.trim()),
        route: QString::from(&message.route),
        route_params: QString::from(&message.route_params),
    }
}

fn log_startup(app_id: &QString, phase: &str, ms: i64) {
    let Some(dir) = std::env::var_os("XDG_RUNTIME_DIR") else {
        return;
    };
    if let Ok(mut log) = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(Path::new(&dir).join("marathon-startup.log"))
    {
        log.write_all(format!("{app_id} {phase} {ms} ms\n").as_bytes())
            .ok();
    }
}

fn shell_import_roots(binary_dir: &QString) -> QStringList {
    let bin = PathBuf::from(binary_dir.to_string());
    let candidates = std::env::var_os("MARATHON_SHELL_QML_IMPORT_PATH")
        .map(PathBuf::from)
        .into_iter()
        .chain([
            bin.join("../../shell/qml"),
            bin.join("../shell/qml"),
            bin.join("shell/qml"),
        ])
        .chain(
            [
                "/usr/local/lib/qt6/qml",
                "/usr/lib/qt6/qml",
                "/usr/lib64/qt6/qml",
            ]
            .map(PathBuf::from),
        );
    let mut roots = QList::<QString>::default();
    for root in candidates.filter(|r| r.join("MarathonOS/Shell").is_dir()) {
        let root = without_prefer(&root).unwrap_or(root);
        roots.append(QString::from(&*root.to_string_lossy()));
    }
    QStringList::from(&roots)
}

/// A copy of `root`'s MarathonOS.Shell whose qmldir has no `prefer` line and
/// declares only types whose files exist (a stale install's orphans make
/// Qt's resolver fail on `Type X unavailable`).
fn without_prefer(root: &Path) -> Option<PathBuf> {
    const MODULE: &str = "MarathonOS/Shell";
    const NOT_TYPES: [&str; 7] = [
        "module ",
        "plugin ",
        "classname ",
        "typeinfo ",
        "depends ",
        "import ",
        "linktarget ",
    ];
    let source = root.join(MODULE);
    let qmldir = fs::read_to_string(source.join("qmldir")).ok()?;
    if !qmldir.contains("prefer :/qt/qml/") {
        return None;
    }
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    root.hash(&mut hasher);
    let copy = std::env::temp_dir()
        .join("marathon-app-runner")
        .join(format!(
            "shell-qmldir-{}-{:016x}",
            std::process::id(),
            hasher.finish()
        ));
    let target = copy.join(MODULE);
    fs::create_dir_all(&target).ok()?;
    let kept: String = qmldir
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#') && !l.starts_with("prefer "))
        .filter(|l| {
            let file = l.split_whitespace().last().unwrap_or_default();
            let qml = Path::new(file).extension().is_some_and(|e| e == "qml");
            let declares = l.split_whitespace().count() >= 3
                && qml
                && !NOT_TYPES.iter().any(|p| l.starts_with(p));
            !declares || source.join(file).exists()
        })
        .fold(String::new(), |mut kept, l| {
            kept.push_str(l);
            kept.push('\n');
            kept
        });
    fs::write(target.join("qmldir"), kept).ok()?;
    if !target.join("qml").exists() {
        copy_dir(&source.join("qml"), &target.join("qml"))?;
    }
    let types = "marathon-shell.qmltypes";
    if source.join(types).exists() && !target.join(types).exists() {
        fs::copy(source.join(types), target.join(types)).ok();
    }
    Some(copy)
}

fn copy_dir(from: &Path, to: &Path) -> Option<()> {
    for entry in walkdir::WalkDir::new(from)
        .into_iter()
        .filter_map(Result::ok)
    {
        let dest = to.join(entry.path().strip_prefix(from).ok()?);
        if entry.file_type().is_dir() {
            fs::create_dir_all(&dest).ok()?;
        } else {
            fs::copy(entry.path(), &dest).ok()?;
        }
    }
    Some(())
}

fn entry_wrapper(app_path: &QString, app_id: &QString, component: &QString) -> QString {
    let modules = PathBuf::from(app_path.to_string()).join("MarathonApp");
    let id = app_id.to_string();
    let named: String = id
        .chars()
        .take(1)
        .flat_map(char::to_uppercase)
        .chain(id.chars().skip(1))
        .collect();
    let qmldir = std::iter::once(modules.join(&named).join("qmldir"))
        .chain(
            fs::read_dir(&modules)
                .into_iter()
                .flatten()
                .filter_map(Result::ok)
                .map(|e| e.path().join("qmldir")),
        )
        .find(|p| p.is_file());
    let Some(text) = qmldir.and_then(|p| fs::read_to_string(p).ok()) else {
        return QString::default();
    };
    let component = component.to_string();
    let lines = text.lines().map(str::trim);
    let Some(module) = lines
        .clone()
        .find_map(|l| l.strip_prefix("module "))
        .map(str::trim)
    else {
        return QString::default();
    };
    let version = lines
        .filter_map(|l| l.strip_prefix(&format!("{component} ")))
        .find_map(|rest| rest.split_whitespace().next())
        .unwrap_or_default();
    QString::from(&format!(
        "import QtQuick\nimport {module} {version}\n{component} {{ }}\n"
    ))
}

fn touch_resident_pages() {
    const PAGE: usize = 4096;
    const BATCH: usize = 512;
    let maps = fs::read_to_string("/proc/self/maps").unwrap_or_default();
    let mut sink = [0u8; BATCH];
    let mut remote: Vec<libc::iovec> = Vec::with_capacity(BATCH);
    // process_vm_readv rather than a read through a pointer: a page another
    // thread unmaps meanwhile fails the read (EFAULT), not the process.
    let mut flush = |remote: &mut Vec<libc::iovec>| {
        let mut i = 0;
        while i < remote.len() {
            let left = remote.len() - i;
            let local = libc::iovec {
                iov_base: sink.as_mut_ptr().cast(),
                iov_len: left,
            };
            // SAFETY: `local` is `sink`, `left` bytes long; `remote` holds
            // `left` one-byte ranges of this process, and the call only reads.
            let n = unsafe {
                libc::process_vm_readv(
                    libc::getpid(),
                    &raw const local,
                    1,
                    remote.as_ptr().add(i),
                    left as libc::c_ulong,
                    0,
                )
            };
            match usize::try_from(n) {
                Ok(n) => i += n.max(1),
                Err(_) if std::io::Error::last_os_error().raw_os_error() == Some(libc::EFAULT) => {
                    i += 1;
                }
                Err(_) => break,
            }
        }
        remote.clear();
    };
    for line in maps.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        let (Some(range), Some(perms)) = (fields.first(), fields.get(1)) else {
            continue;
        };
        let path = fields.get(5).copied().unwrap_or_default();
        if !perms.starts_with('r')
            || !perms.ends_with('p')
            || path.starts_with("/dev")
            || path.starts_with("[vsyscall]")
            || path.starts_with("[vvar]")
        {
            continue;
        }
        let Some((start, end)) = range.split_once('-') else {
            continue;
        };
        let (Ok(start), Ok(end)) = (
            usize::from_str_radix(start, 16),
            usize::from_str_radix(end, 16),
        ) else {
            continue;
        };
        for at in (start..end).step_by(PAGE) {
            remote.push(libc::iovec {
                iov_base: at as *mut libc::c_void,
                iov_len: 1,
            });
            if remote.len() == BATCH {
                flush(&mut remote);
            }
        }
    }
    flush(&mut remote);
}

#[derive(Default)]
pub struct RunnerLifecycleRust {
    handled: bool,
    minimized: bool,
}

impl RunnerLifecycle {
    fn serve(self: Pin<&mut Self>, app_id: &QString) {
        let qt = self.qt_thread();
        let name = runner_name(&app_id.to_string());
        io::spawn(async move {
            let served = async {
                let bus = io::session_bus().await?;
                bus.object_server()
                    .at(RUNNER_PATH, Lifecycle1 { qt })
                    .await?;
                bus.request_name(name.as_str()).await
            };
            if let Err(e) = served.await {
                log::warn(
                    "marathon-app-runner",
                    format_args!("cannot register {name}: {e}"),
                );
            }
        });
    }

    fn answer(mut self: Pin<&mut Self>, handled: bool) {
        self.as_mut().rust_mut().handled = handled;
    }

    fn minimize_requested(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().minimized = true;
    }
}

struct Lifecycle1 {
    qt: CxxQtThread<RunnerLifecycle>,
}

impl Lifecycle1 {
    /// `f`'s answer, on the GUI thread.
    async fn gui<R: Send + 'static>(
        &self,
        f: impl FnOnce(Pin<&mut RunnerLifecycle>) -> R + Send + 'static,
    ) -> fdo::Result<R> {
        let (tx, rx) = async_channel::bounded(1);
        self.qt
            .queue(move |obj| {
                tx.try_send(f(obj)).ok();
            })
            .map_err(|_stopping| fdo::Error::Failed("the app is stopping".into()))?;
        rx.recv()
            .await
            .map_err(|_stopping| fdo::Error::Failed("the app is stopping".into()))
    }
}

#[zbus::interface(name = "org.marathonos.AppRunner.Lifecycle1")]
impl Lifecycle1 {
    async fn back(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        caller_is_shell(&h).await?;
        self.gui(|mut obj| {
            let mut rust = obj.as_mut().rust_mut();
            rust.handled = false;
            rust.minimized = false;
            obj.as_mut().back_requested();
            obj.handled && !obj.minimized
        })
        .await
    }

    async fn forward(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<bool> {
        caller_is_shell(&h).await?;
        self.gui(|mut obj| {
            obj.as_mut().rust_mut().handled = false;
            obj.as_mut().forward_requested();
            obj.handled
        })
        .await
    }

    /// 1 while the app's cover is on screen in the task switcher.
    async fn set_cover_status(
        &self,
        status: i32,
        #[zbus(header)] h: Header<'_>,
    ) -> fdo::Result<()> {
        caller_is_shell(&h).await?;
        if let Some(host) = crate::keel::host() {
            host.set_cover_status(status);
        }
        Ok(())
    }

    async fn prepare_freeze(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        caller_is_shell(&h).await?;
        self.gui(ffi::RunnerLifecycle::prepare_freeze_requested)
            .await
    }

    async fn thawed(&self, #[zbus(header)] h: Header<'_>) -> fdo::Result<()> {
        caller_is_shell(&h).await?;
        self.gui(ffi::RunnerLifecycle::thawed).await
    }
}
