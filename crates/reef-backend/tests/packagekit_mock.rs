// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! D-Bus contract test: the real zbus `PackageKit` client against a mock
//! `PackageKit` daemon on a private dbus-daemon.
//!
//! The mock implements only what Reef calls, with `PackageKit`'s wire
//! signatures (`Resolve(t, as)`, `InstallPackages(t, as)`, signals
//! `Package(uss)`, `ItemProgress(suu)`, `ErrorCode(us)`, `Finished(uu)`).
//! It checks the client's side of the contract: signature types, that
//! signals emitted before the method reply are not lost, that installs are
//! `ONLY_TRUSTED`, and that failures surface as errors. It says nothing about
//! how Sailfish's real `PackageKit` (zypp backend) behaves; that is Phase 0.
//!
//! Skipped (with a message) when `dbus-daemon` is not installed.

use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};

use futures_lite::future::block_on;
use reef_backend::packagekit::dbus::PackageKitClient;
use reef_backend::packagekit::{
    Error, Exit, Filter, Info, PackageManager, Progress, TRANSACTION_FLAG_ONLY_TRUSTED,
    TRANSACTION_FLAG_SIMULATE,
};
use reef_backend::store::{InstallLedger, Store};
use zbus::object_server::SignalEmitter;
use zbus::zvariant::OwnedObjectPath;
use zbus::{connection, fdo, Connection, ObjectServer};

/// A private bus that dies with the test.
struct Bus {
    child: Child,
    address: String,
    dir: std::path::PathBuf,
}

impl Drop for Bus {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn start_bus(name: &str) -> Option<Bus> {
    let dir = std::env::temp_dir().join(format!("reef-pk-{name}-{}", std::process::id()));
    std::fs::create_dir_all(&dir).ok()?;
    let config = dir.join("bus.conf");
    std::fs::write(
        &config,
        format!(
            r#"<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path={}/bus</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>"#,
            dir.display()
        ),
    )
    .ok()?;
    let mut child = match Command::new("dbus-daemon")
        .arg(format!("--config-file={}", config.display()))
        .args(["--nofork", "--print-address=1"])
        .stdout(Stdio::piped())
        .spawn()
    {
        Ok(child) => child,
        Err(e) => {
            // CI installs dbus-daemon: there a skip would hide that these
            // tests assert nothing.
            assert!(
                std::env::var_os("CI").is_none(),
                "CI is set but dbus-daemon cannot start: {e}"
            );
            eprintln!("skipping: cannot start dbus-daemon: {e}");
            return None;
        }
    };
    let mut line = String::new();
    BufReader::new(child.stdout.take()?)
        .read_line(&mut line)
        .ok()?;
    Some(Bus {
        child,
        address: line.trim().to_string(),
        dir,
    })
}

type Log = Arc<Mutex<Vec<String>>>;

struct MockDaemon {
    next: AtomicU32,
    log: Log,
    /// Another client on the same bus, which forges transaction signals.
    impostor: Connection,
}

#[zbus::interface(name = "org.freedesktop.PackageKit")]
impl MockDaemon {
    fn suggest_daemon_quit(&self) {
        self.log.lock().unwrap().push("SuggestDaemonQuit".into());
    }

    async fn create_transaction(
        &self,
        #[zbus(object_server)] server: &ObjectServer,
    ) -> fdo::Result<OwnedObjectPath> {
        let n = self.next.fetch_add(1, Ordering::SeqCst);
        let path = format!("/{n}_mock");
        server
            .at(
                path.as_str(),
                MockTransaction {
                    log: self.log.clone(),
                    percentage: AtomicU32::new(101),
                    impostor: self.impostor.clone(),
                },
            )
            .await?;
        Ok(OwnedObjectPath::try_from(path).unwrap())
    }
}

struct MockTransaction {
    log: Log,
    percentage: AtomicU32,
    impostor: Connection,
}

const REPO_PKG: &str = "shipwright-keel-silica;0.1.0-1;aarch64;shipwright-reef";
const INSTALLED_PKG: &str = "shipwright-keel-silica;0.1.0-1;aarch64;installed";
const UPDATE_PKG: &str = "shipwright-keel-silica;0.2.0-1;aarch64;shipwright-reef";
const SYSTEM_UPDATE: &str = "glibc;2.99-1;aarch64;jolla";
const DEPENDENCY: &str = "airpods-service;2.0-1;aarch64;shipwright-reef";

#[zbus::interface(name = "org.freedesktop.PackageKit.Transaction")]
impl MockTransaction {
    async fn resolve(
        &self,
        filter: u64,
        packages: Vec<String>,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.log
            .lock()
            .unwrap()
            .push(format!("Resolve {filter:#x} {packages:?}"));
        // Filter bits: NONE 0x2 lists everything, INSTALLED 0x4 the
        // installed copy (zypp reports plain "installed"), NOT_INSTALLED 0x8
        // the repository's.
        for name in &packages {
            if name == "shipwright-keel-silica" {
                if filter & 0x6 != 0 {
                    Self::package(&e, 1, INSTALLED_PKG, "Silica for Qt6").await?;
                }
                if filter & 0xa != 0 {
                    Self::package(&e, 2, REPO_PKG, "Silica for Qt6").await?;
                }
            }
        }
        Self::finished(&e, 1, 5).await?;
        Ok(())
    }

    async fn install_packages(
        &self,
        flags: u64,
        ids: Vec<String>,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.log
            .lock()
            .unwrap()
            .push(format!("InstallPackages {flags:#x} {ids:?}"));
        if flags & TRANSACTION_FLAG_SIMULATE != 0 {
            // What zypp announces: the package, and a dependency it brings.
            for id in &ids {
                Self::package(&e, 12, id, "").await?;
            }
            Self::package(&e, 12, DEPENDENCY, "Earbuds service").await?;
            Self::finished(&e, 1, 5).await?;
            return Ok(());
        }
        if ids.iter().any(|id| id.contains("stall")) {
            // Accepted, then silence: no progress, no Finished.
            return Ok(());
        }
        if ids.iter().any(|id| id.contains("forged")) {
            // Another bus client claims success on the transaction's path
            // before the daemon reports the real failure.
            let path = e.path().to_owned();
            self.impostor
                .emit_signal(
                    None::<()>,
                    &path,
                    "org.freedesktop.PackageKit.Transaction",
                    "Package",
                    &(12u32, ids[0].as_str(), ""),
                )
                .await?;
            self.impostor
                .emit_signal(
                    None::<()>,
                    &path,
                    "org.freedesktop.PackageKit.Transaction",
                    "Finished",
                    &(1u32, 0u32),
                )
                .await?;
            async_io::Timer::after(std::time::Duration::from_millis(100)).await;
            Self::error_code(&e, 30, "package is not signed").await?;
            Self::finished(&e, 2, 1).await?;
            return Ok(());
        }
        if ids.iter().any(|id| id.contains("unsigned")) {
            // PK_ERROR_ENUM_MISSING_GPG_SIGNATURE is 30 in pk-enum.h.
            Self::error_code(&e, 30, "package is not signed").await?;
            Self::finished(&e, 2, 1).await?;
            return Ok(());
        }
        for id in &ids {
            Self::item_progress(&e, id, 8, 40).await?;
            self.percentage.store(50, Ordering::SeqCst);
            self.percentage_changed(&e).await?;
            Self::item_progress(&e, id, 9, 100).await?;
            Self::package(&e, 12, id, "").await?;
        }
        self.percentage.store(100, Ordering::SeqCst);
        self.percentage_changed(&e).await?;
        Self::finished(&e, 1, 20).await?;
        Ok(())
    }

    async fn update_packages(
        &self,
        flags: u64,
        ids: Vec<String>,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.log
            .lock()
            .unwrap()
            .push(format!("UpdatePackages {flags:#x} {ids:?}"));
        if flags & TRANSACTION_FLAG_SIMULATE != 0 {
            for id in &ids {
                Self::package(&e, 11, id, "").await?;
            }
        }
        Self::finished(&e, 1, 5).await?;
        Ok(())
    }

    /// Sizes the new way (`a{sv}`), as `PackageKit` 1.1 and later send them.
    async fn get_details(
        &self,
        ids: Vec<String>,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.log.lock().unwrap().push(format!("GetDetails {ids:?}"));
        for id in &ids {
            let mut details: std::collections::HashMap<&str, zbus::zvariant::Value<'_>> =
                std::collections::HashMap::new();
            details.insert("package-id", id.as_str().into());
            details.insert("size", 2_000_000u64.into());
            Self::details(&e, details).await?;
        }
        Self::finished(&e, 1, 5).await?;
        Ok(())
    }

    async fn remove_packages(
        &self,
        flags: u64,
        ids: Vec<String>,
        allow_deps: bool,
        autoremove: bool,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.log.lock().unwrap().push(format!(
            "RemovePackages {flags:#x} {ids:?} {allow_deps} {autoremove}"
        ));
        if flags & TRANSACTION_FLAG_SIMULATE != 0 {
            for id in &ids {
                Self::package(&e, 13, id, "").await?;
            }
        }
        Self::finished(&e, 1, 5).await?;
        Ok(())
    }

    async fn get_updates(
        &self,
        filter: u64,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.log
            .lock()
            .unwrap()
            .push(format!("GetUpdates {filter:#x}"));
        Self::package(&e, 5, UPDATE_PKG, "").await?;
        Self::package(&e, 8, SYSTEM_UPDATE, "").await?;
        Self::finished(&e, 1, 5).await?;
        Ok(())
    }

    /// Nothing named like the package: removals find no parts.
    async fn search_names(
        &self,
        filter: u64,
        values: Vec<String>,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.log
            .lock()
            .unwrap()
            .push(format!("SearchNames {filter:#x} {values:?}"));
        Self::finished(&e, 1, 5).await?;
        Ok(())
    }

    /// Keel needs nothing of Reef's.
    async fn depends_on(
        &self,
        filter: u64,
        ids: Vec<String>,
        recursive: bool,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.log
            .lock()
            .unwrap()
            .push(format!("DependsOn {filter:#x} {ids:?} {recursive}"));
        Self::finished(&e, 1, 5).await?;
        Ok(())
    }

    /// Nothing installed needs Keel.
    async fn required_by(
        &self,
        filter: u64,
        ids: Vec<String>,
        recursive: bool,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.log
            .lock()
            .unwrap()
            .push(format!("RequiredBy {filter:#x} {ids:?} {recursive}"));
        Self::finished(&e, 1, 5).await?;
        Ok(())
    }

    async fn repo_set_data(
        &self,
        repo_id: String,
        parameter: String,
        value: String,
        #[zbus(signal_emitter)] e: SignalEmitter<'_>,
    ) -> fdo::Result<()> {
        self.log
            .lock()
            .unwrap()
            .push(format!("RepoSetData {repo_id} {parameter} {value}"));
        Self::finished(&e, 1, 5).await?;
        Ok(())
    }

    #[zbus(property)]
    fn percentage(&self) -> u32 {
        self.percentage.load(Ordering::SeqCst)
    }

    #[zbus(signal)]
    async fn package(
        e: &SignalEmitter<'_>,
        info: u32,
        package_id: &str,
        summary: &str,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn item_progress(
        e: &SignalEmitter<'_>,
        id: &str,
        status: u32,
        percentage: u32,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn details(
        e: &SignalEmitter<'_>,
        data: std::collections::HashMap<&str, zbus::zvariant::Value<'_>>,
    ) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn error_code(e: &SignalEmitter<'_>, code: u32, details: &str) -> zbus::Result<()>;

    #[zbus(signal)]
    async fn finished(e: &SignalEmitter<'_>, exit: u32, runtime: u32) -> zbus::Result<()>;
}

struct Harness {
    _bus: Bus,
    _server: Connection,
    client: PackageKitClient,
    log: Log,
}

fn harness(name: &str) -> Option<Harness> {
    let bus = start_bus(name)?;
    let log: Log = Arc::default();
    block_on(async {
        let impostor = connection::Builder::address(bus.address.as_str())
            .unwrap()
            .build()
            .await
            .unwrap();
        let server = connection::Builder::address(bus.address.as_str())
            .unwrap()
            .name("org.freedesktop.PackageKit")
            .unwrap()
            .serve_at(
                "/org/freedesktop/PackageKit",
                MockDaemon {
                    next: AtomicU32::new(1),
                    log: log.clone(),
                    impostor,
                },
            )
            .unwrap()
            .build()
            .await
            .unwrap();
        let client_conn = connection::Builder::address(bus.address.as_str())
            .unwrap()
            .build()
            .await
            .unwrap();
        Some(Harness {
            _bus: bus,
            _server: server,
            client: PackageKitClient::new(client_conn),
            log,
        })
    })
}

#[test]
fn resolve_and_install_with_progress() {
    let Some(h) = harness("install") else { return };
    block_on(async {
        let found = h
            .client
            .resolve(&["shipwright-keel-silica", "nope"], &[Filter::NotInstalled])
            .await
            .unwrap();
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].info, Info::Available);
        assert_eq!(found[0].summary, "Silica for Qt6");

        let mut seen: Vec<Progress> = Vec::new();
        h.client
            .install(&[REPO_PKG], &mut |p| seen.push(p))
            .await
            .unwrap();
        // Downloading is the first half: the package 40% downloaded is 20%
        // overall. The transaction's own Percentage (50) is not used: the
        // zypp backend restarts it for every preparation step.
        assert!(seen
            .iter()
            .any(|p| p.item.as_deref() == Some(REPO_PKG) && p.percentage == Some(20)));
        assert!(seen.iter().all(|p| p.percentage != Some(50)));
        assert!(seen.iter().any(|p| p.percentage == Some(100)));
    });
    let log = h.log.lock().unwrap();
    assert_eq!(log[0], r#"Resolve 0x8 ["shipwright-keel-silica", "nope"]"#);
    assert_eq!(
        log[1],
        format!("InstallPackages {TRANSACTION_FLAG_ONLY_TRUSTED:#x} [\"{REPO_PKG}\"]")
    );
}

#[test]
fn failed_transaction_reports_error() {
    let Some(h) = harness("fail") else { return };
    let err = block_on(h.client.install(&["x;1;noarch;unsigned"], &mut |_| {})).unwrap_err();
    match err {
        Error::Transaction {
            exit: Exit::Failed,
            error: Some((30, details)),
        } => assert_eq!(details, "package is not signed"),
        other => panic!("unexpected {other:?}"),
    }
}

#[test]
fn signals_from_other_bus_clients_are_ignored() {
    // B-01: a forged Finished(success) from another connection on the
    // transaction's path must not end the transaction.
    let Some(h) = harness("forged") else { return };
    let err = block_on(h.client.install(&["x;1;noarch;forged"], &mut |_| {})).unwrap_err();
    match err {
        Error::Transaction {
            exit: Exit::Failed,
            error: Some((30, _)),
        } => {}
        other => panic!("a forged signal was believed: {other:?}"),
    }
}

#[test]
fn a_silent_transaction_times_out() {
    // B-02: PackageKit accepts the call and then says nothing.
    let Some(h) = harness("stall") else { return };
    let client = h
        .client
        .clone()
        .with_idle_timeout(std::time::Duration::from_millis(300));
    let start = std::time::Instant::now();
    let err = block_on(client.install(&["x;1;noarch;stall"], &mut |_| {})).unwrap_err();
    assert!(err.to_string().contains("giving up"), "{err}");
    assert!(start.elapsed() < std::time::Duration::from_secs(10));
}

#[test]
fn store_updates_only_reef_packages_and_refreshes_one_repo() {
    let Some(h) = harness("update") else { return };
    // Keel is installed with zypp's plain "installed": Reef's to remove
    // only because the ledger says Reef installed it.
    let dir = std::env::temp_dir().join(format!("reef-pk-ledger-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let ledger = InstallLedger::new(dir.join("installed.json"));
    ledger.record("shipwright-keel-silica").unwrap();
    let store = Store::new(h.client.clone(), "shipwright-reef").with_ledger(Some(ledger));
    block_on(async {
        let all = store.preview_update_all(None).await.unwrap();
        assert_eq!(store.update_all(&all, &mut |_| {}).await.unwrap(), 1);
        store.pm.refresh_repo("shipwright-reef").await.unwrap();
        let plan = store
            .preview_remove("shipwright-keel-silica", None)
            .await
            .unwrap();
        store
            .remove("shipwright-keel-silica", &plan, &mut |_| {})
            .await
            .unwrap();
    });
    std::fs::remove_dir_all(dir).unwrap();
    let log = h.log.lock().unwrap();
    let simulate = TRANSACTION_FLAG_ONLY_TRUSTED | TRANSACTION_FLAG_SIMULATE;
    let real: Vec<&String> = log
        .iter()
        .filter(|l| !l.starts_with("Resolve") && !l.starts_with("GetDetails"))
        .collect();
    assert_eq!(real[0], "GetUpdates 0x2");
    assert_eq!(
        real[1],
        &format!("UpdatePackages {simulate:#x} [\"{UPDATE_PKG}\"]")
    );
    // Update all looks again, simulates again, then updates for real.
    assert_eq!(
        real[4],
        &format!("UpdatePackages {TRANSACTION_FLAG_ONLY_TRUSTED:#x} [\"{UPDATE_PKG}\"]")
    );
    assert_eq!(real[5], "RepoSetData shipwright-reef refresh-now true");
    // After the lookups the removal makes (how many is the store's business).
    let removes: Vec<&&String> = real
        .iter()
        .filter(|l| l.starts_with("RemovePackages"))
        .collect();
    assert_eq!(removes.len(), 2, "{log:?}");
    assert!(
        removes[0].starts_with("RemovePackages 0x4"),
        "simulated first"
    );
    let remove = removes[1];
    assert!(remove.starts_with("RemovePackages 0x0"), "{remove}");
    // The installed copy.
    assert!(remove.contains(INSTALLED_PKG), "{remove}");
    assert!(remove.ends_with("false false"), "{remove}");
}

#[test]
fn a_simulated_install_lists_what_comes_with_it_and_its_size() {
    let Some(h) = harness("simulate") else { return };
    let store = Store::new(h.client.clone(), "shipwright-reef");
    let plan = block_on(store.preview_install("shipwright-keel-silica", None)).unwrap();
    let names: Vec<&str> = plan.items.iter().map(|i| i.name.as_str()).collect();
    assert_eq!(names, ["shipwright-keel-silica", "airpods-service"]);
    assert!(plan.items[0].requested && !plan.items[1].requested);
    assert_eq!(plan.download_size, Some(4_000_000));
    let log = h.log.lock().unwrap();
    let simulate = TRANSACTION_FLAG_ONLY_TRUSTED | TRANSACTION_FLAG_SIMULATE;
    assert!(log.contains(&format!("InstallPackages {simulate:#x} [\"{REPO_PKG}\"]")));
    assert!(
        !log.iter().any(|l| l.starts_with(&format!(
            "InstallPackages {TRANSACTION_FLAG_ONLY_TRUSTED:#x}"
        ))),
        "a preview installs nothing: {log:?}"
    );
}
