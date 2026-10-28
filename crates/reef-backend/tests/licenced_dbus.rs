// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

//! The licence hand-off over a private dbus-daemon: the service in-process,
//! then the real `shipwright-reef-licenced` binary started by D-Bus
//! activation, with the client from `reef_licence::handoff`.
//!
//! Needs `dbus-daemon` on PATH; the tests are skipped (with a message)
//! when it is missing.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

use reef_backend::licenced::{serve, Activity, LicenceService, BUS_NAME};
use reef_backend::licences::LicenceStore;
use reef_licence::handoff::{fetch_on, HandoffError};
use reef_licence::{Claims, KeySet, Plan, Policy, RevocationList, Signer};

const T0: i64 = 1_790_000_000;

struct Bus {
    child: Child,
    address: String,
    dir: PathBuf,
}

impl Drop for Bus {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("reef-licenced-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// A private session bus with `services` as its activation directory and
/// `data_home` as `XDG_DATA_HOME` for activated services.
fn bus(dir: &Path, data_home: &Path) -> Option<Bus> {
    let services = dir.join("services");
    std::fs::create_dir_all(&services).unwrap();
    let config = dir.join("bus.conf");
    std::fs::write(
        &config,
        format!(
            r#"<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:path={}/bus</listen>
  <servicedir>{}</servicedir>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
"#,
            dir.display(),
            services.display()
        ),
    )
    .unwrap();
    let mut child = match Command::new("dbus-daemon")
        .arg(format!("--config-file={}", config.display()))
        .arg("--nofork")
        .arg("--print-address=1")
        .env("XDG_DATA_HOME", data_home)
        .env("SHIPWRIGHT_REEF_LICENCED_IDLE_SECS", "1")
        .stdout(Stdio::piped())
        .spawn()
    {
        Ok(c) => c,
        Err(e) => {
            // CI installs dbus-daemon: there a skip would hide that these
            // tests assert nothing.
            assert!(
                std::env::var_os("CI").is_none(),
                "CI is set but dbus-daemon cannot start: {e}"
            );
            eprintln!("skipping: dbus-daemon not available ({e})");
            return None;
        }
    };
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    Some(Bus {
        child,
        address: line.trim().to_string(),
        dir: dir.to_path_buf(),
    })
}

fn client(bus: &Bus) -> zbus::blocking::Connection {
    zbus::blocking::connection::Builder::address(bus.address.as_str())
        .unwrap()
        .method_timeout(Duration::from_secs(10))
        .build()
        .unwrap()
}

fn signer() -> Signer {
    Signer::from_seed("k1", [5; 32]).unwrap()
}

fn keys() -> KeySet {
    let mut k = KeySet::new();
    k.insert_text(&signer().public_key_text()).unwrap();
    k
}

fn token(app: &str) -> String {
    signer()
        .issue(&Claims {
            app: app.into(),
            exp: None,
            iat: T0,
            kid: "k1".into(),
            lid: format!("lic_{app}"),
            plan: Plan::OneOff,
        })
        .unwrap()
}

/// `<data_home>/shipwright-reef/licences` with tokens for Mail and Keys,
/// Keys' revoked.
fn licences(data_home: &Path) -> PathBuf {
    let dir = data_home.join("shipwright-reef/licences");
    let store = LicenceStore::new(&dir, keys(), Policy::default());
    store.save(&token("shipwright-shoal-mail"), T0).unwrap();
    store.save(&token("shipwright-shoal-keys"), T0).unwrap();
    let list = RevocationList {
        generated_at: T0 + 1,
        revoked: vec!["lic_shipwright-shoal-keys".into()],
    };
    let body = serde_json::to_vec(&list).unwrap();
    store
        .accept_revocations(&body, &signer().sign_detached(&body))
        .unwrap();
    dir
}

#[test]
fn get_licence_in_process() {
    let dir = scratch("inproc");
    let data_home = dir.join("data");
    let lic_dir = licences(&data_home);
    let Some(bus) = bus(&dir.join("bus"), &data_home) else {
        return;
    };
    let activity = Activity::new();
    let service = LicenceService::new(&lic_dir, keys(), activity.clone());
    let _server =
        futures_lite::future::block_on(serve(service, Some(bus.address.as_str()))).unwrap();
    let conn = client(&bus);

    let got = fetch_on(&conn, "shipwright-shoal-mail").unwrap();
    assert_eq!(
        got.as_deref(),
        Some(token("shipwright-shoal-mail").as_str())
    );
    assert!(
        activity.idle() < Duration::from_secs(5),
        "calls count as activity"
    );
    // Revoked, unknown: no token, not an error.
    assert_eq!(fetch_on(&conn, "shipwright-shoal-keys").unwrap(), None);
    assert_eq!(fetch_on(&conn, "shoal-bridge").unwrap(), None);
    // A bad id is refused by the client before the call ...
    assert!(matches!(
        fetch_on(&conn, "../etc"),
        Err(HandoffError::Failed(_))
    ));
    // ... and by the service when sent raw.
    let raw = conn.call_method(
        Some(BUS_NAME),
        "/org/shipwright/Reef/Licences",
        Some("org.shipwright.Reef.Licences1"),
        "GetLicence",
        &("../../.ssh/id_rsa",),
    );
    match raw {
        Err(zbus::Error::MethodError(name, _, _)) => assert_eq!(
            name.as_str(),
            "org.shipwright.Reef.Licences1.Error.InvalidAppId"
        ),
        other => panic!("expected InvalidAppId, got {other:?}"),
    }
}

#[test]
fn no_service_is_unavailable() {
    let dir = scratch("none");
    let Some(bus) = bus(&dir.join("bus"), &dir.join("data")) else {
        return;
    };
    let conn = client(&bus);
    assert!(matches!(
        fetch_on(&conn, "shipwright-shoal-mail"),
        Err(HandoffError::Unavailable(_))
    ));
}

#[test]
fn activated_binary_answers_then_exits_when_idle() {
    let dir = scratch("activate");
    let data_home = dir.join("data");
    licences(&data_home);
    let Some(bus) = bus(&dir.join("bus"), &data_home) else {
        return;
    };
    // The packaged activation file, pointed at the freshly built binary.
    let packaged = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../packaging/dbus/org.shipwright.Reef.Licences.service"
    ))
    .unwrap();
    assert!(packaged.contains("Exec=/usr/bin/shipwright-reef-licenced\n"));
    std::fs::write(
        dir.join("bus/services/org.shipwright.Reef.Licences.service"),
        packaged.replace(
            "/usr/bin/shipwright-reef-licenced",
            env!("CARGO_BIN_EXE_shipwright-reef-licenced"),
        ),
    )
    .unwrap();
    let conn = client(&bus);
    let got = fetch_on(&conn, "shipwright-shoal-mail").unwrap();
    assert_eq!(
        got.as_deref(),
        Some(token("shipwright-shoal-mail").as_str())
    );

    // Idle timeout is 1 s in this bus's environment: the name goes away.
    let dbus = zbus::blocking::fdo::DBusProxy::new(&conn).unwrap();
    let deadline = Instant::now() + Duration::from_secs(10);
    while dbus.name_has_owner(BUS_NAME.try_into().unwrap()).unwrap() {
        assert!(Instant::now() < deadline, "service did not exit when idle");
        std::thread::sleep(Duration::from_millis(100));
    }
    // And is activated again on the next call.
    assert!(fetch_on(&conn, "shipwright-shoal-mail").unwrap().is_some());
}
