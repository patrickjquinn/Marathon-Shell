// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! pilotd: the Pilot assistant daemon. Owns `org.shipwright.Pilot` on the
//! session bus; see ../README.md.

use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;

use pilotd::config::{self, Config};
use pilotd::daemon::{self, Options, StartError};
use pilotd::{localtime, logger, privacy};

const USAGE: &str = "\
usage: pilotd [--config FILE] [--data-dir DIR] [--ask TEXT | --calibrate]

  --config FILE   configuration (default $XDG_CONFIG_HOME/shoal-pilot/pilotd.toml)
  --data-dir DIR  egress log, settings, device token (default $XDG_DATA_HOME/shoal-pilot)
  --ask TEXT      run one turn without D-Bus and print the result as JSON
  --calibrate     print the routing calibration report from the decision log

Log level: SHOAL_PILOT_LOG=error|warn|info|debug (default info).";

#[derive(Debug, Default, PartialEq)]
struct Args {
    config: Option<PathBuf>,
    data_dir: Option<PathBuf>,
    ask: Option<String>,
    calibrate: bool,
    help: bool,
}

fn parse_args(args: impl IntoIterator<Item = String>) -> Result<Args, String> {
    let mut out = Args::default();
    let mut it = args.into_iter();
    while let Some(a) = it.next() {
        let mut val = |what: &str| it.next().ok_or_else(|| format!("{a} needs {what}"));
        match a.as_str() {
            "--config" => out.config = Some(val("a file")?.into()),
            "--data-dir" => out.data_dir = Some(val("a directory")?.into()),
            "--ask" => out.ask = Some(val("text")?),
            "--calibrate" => out.calibrate = true,
            "-h" | "--help" => out.help = true,
            other => return Err(format!("unknown argument {other}")),
        }
    }
    Ok(out)
}

fn main() -> ExitCode {
    // Before anything else, and before any thread: the privileged group is
    // held back except for the calendar and contacts reads (privilege.rs).
    let dropped = pilotd::privilege::drop_at_start();
    let args = match parse_args(std::env::args().skip(1)) {
        Ok(a) if a.help => {
            println!("{USAGE}");
            return ExitCode::SUCCESS;
        }
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}\n{USAGE}");
            return ExitCode::from(2);
        }
    };
    logger::init();
    if dropped {
        log::info!("running as the person's group; privileged only for the calendar and contacts");
    }
    let rt = match tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
    {
        Ok(rt) => rt,
        Err(e) => {
            log::error!("runtime: {e}");
            return ExitCode::FAILURE;
        }
    };
    match rt.block_on(run(args)) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            log::error!("{e}");
            ExitCode::FAILURE
        }
    }
}

async fn run(args: Args) -> Result<(), Box<dyn std::error::Error>> {
    let config_path = args
        .config
        .or_else(config::default_config_path)
        .ok_or("no HOME or XDG_CONFIG_HOME")?;
    let config = Config::load(&config_path)?;
    let data_dir = args
        .data_dir
        .or_else(config::default_data_dir)
        .ok_or("no HOME or XDG_DATA_HOME")?;
    if args.calibrate {
        // Local only: the decision log and the configured thresholds.
        let store = pilotd::store::Store::open(&data_dir.join("pilot.db"))?;
        let report = pilotd::calibrate::report(&store.decisions(0)?, &config.thresholds);
        println!("{}", serde_json::to_string_pretty(&report)?);
        return Ok(());
    }
    let session = zbus::Connection::session().await.ok();
    let system = zbus::Connection::system().await.ok();
    let privacy_source = config.privacy.source.clone();
    let mcp = config.mcp.clone();
    let d = Arc::new(daemon::build(Options {
        config,
        data_dir: Some(data_dir),
        session: session.clone(),
        system,
        adapters: None,
        credential: None,
        licence: None,
        now: localtime::now,
    })?);
    // Keel Actions through keel-mcp (spec section 9), if installed.
    if mcp
        .command
        .first()
        .is_some_and(|p| std::path::Path::new(p).exists())
    {
        d.pipeline
            .attach_mcp_command(
                &mcp.command,
                std::time::Duration::from_secs(mcp.timeout_secs),
            )
            .await;
    }
    let switch = privacy::from_config(&privacy_source, session.clone());
    log::info!("privacy switch source: {}", switch.describe());

    if let Some(text) = args.ask {
        let engaged = switch.current().await.unwrap_or(true);
        d.apply_privacy(engaged, None).await;
        let r = d.pipeline.ask(&text, false).await;
        println!("{}", serde_json::to_string_pretty(&r)?);
        return Ok(());
    }

    let conn = session.ok_or(StartError::Bus(zbus::Error::Failure(
        "no session bus".into(),
    )))?;
    daemon::serve_on(&d, &conn).await?;
    log::info!(
        "{} ready (backend {})",
        pilotd::dbus::BUS_NAME,
        d.pipeline.backend_name()
    );
    tokio::spawn(d.clone().follow_switch(switch, Some(conn.clone())));
    tokio::spawn(d.clone().follow_wake(conn.clone()));
    // Proactive triage (spec section 5.3): the notification monitor needs
    // a connection of its own, as a monitor can do nothing else.
    let monitor = zbus::Connection::session().await.ok();
    d.start_triage(monitor, Some(conn.clone()));

    let mut term = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
    tokio::select! {
        _ = tokio::signal::ctrl_c() => {}
        _ = term.recv() => {}
    }
    log::info!("stopping");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn a(s: &[&str]) -> Vec<String> {
        s.iter().map(ToString::to_string).collect()
    }

    #[test]
    fn args() {
        assert_eq!(parse_args(a(&[])).unwrap(), Args::default());
        let p = parse_args(a(&["--config", "/c", "--ask", "set a timer"])).unwrap();
        assert_eq!(p.config, Some("/c".into()));
        assert_eq!(p.ask.as_deref(), Some("set a timer"));
        assert!(parse_args(a(&["--data-dir"])).is_err());
        assert!(parse_args(a(&["--nope"])).is_err());
        assert!(parse_args(a(&["-h"])).unwrap().help);
        assert!(parse_args(a(&["--calibrate"])).unwrap().calibrate);
    }
}
