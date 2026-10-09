// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! keel-mcp: serves the Keel Actions of the apps on this device over MCP.
//!
//! ```text
//! keel-mcp [--stdio | --socket [PATH]] [--actions-dir DIR]... [--external] [--probe-seconds N]
//! ```
//!
//! `--stdio` (default): one client on stdin/stdout (a client that spawns
//! keel-mcp). `--socket`: clients connect to a Unix socket (default
//! `$XDG_RUNTIME_DIR/keel-mcp.sock`, mode 0600), as `pilotd` does.
//! `--external`: serving a paired desktop agent (no sensitive results, no
//! context). Manifests come from `/usr/share/keel/actions` unless
//! `--actions-dir` is given, and from running apps every `--probe-seconds`
//! (default 10; 0 turns it off).

use std::path::PathBuf;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

use keel_mcp::backend::{Backend, Bus};
use keel_mcp::KeelMcp;
use rmcp::ServiceExt;

struct Args {
    socket: Option<PathBuf>,
    dirs: Vec<PathBuf>,
    external: bool,
    probe: u64,
}

fn parse() -> Result<Args, String> {
    let mut args = Args {
        socket: None,
        dirs: Vec::new(),
        external: false,
        probe: 10,
    };
    let mut it = std::env::args().skip(1).peekable();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--stdio" => args.socket = None,
            "--socket" => {
                let default = std::env::var_os("XDG_RUNTIME_DIR")
                    .map_or_else(|| PathBuf::from("/tmp"), PathBuf::from)
                    .join("keel-mcp.sock");
                args.socket = Some(match it.peek() {
                    Some(p) if !p.starts_with("--") => PathBuf::from(it.next().unwrap_or_default()),
                    _ => default,
                });
            }
            "--actions-dir" => args
                .dirs
                .push(it.next().ok_or("--actions-dir needs a directory")?.into()),
            "--external" => args.external = true,
            "--probe-seconds" => {
                args.probe = it
                    .next()
                    .and_then(|n| n.parse().ok())
                    .ok_or("--probe-seconds needs a number")?;
            }
            "--help" | "-h" => {
                println!("keel-mcp [--stdio | --socket [PATH]] [--actions-dir DIR]... [--external] [--probe-seconds N]");
                std::process::exit(0);
            }
            other => return Err(format!("unknown argument {other}")),
        }
    }
    if args.dirs.is_empty() {
        args.dirs.push(PathBuf::from("/usr/share/keel/actions"));
    }
    Ok(args)
}

async fn serve_socket(server: KeelMcp, path: PathBuf) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::remove_file(&path);
    let listener = tokio::net::UnixListener::bind(&path)?;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600))?;
    eprintln!("keel-mcp: listening on {}", path.display());
    loop {
        let (stream, _) = listener.accept().await?;
        let server = server.clone();
        tokio::spawn(async move {
            let (read, write) = stream.into_split();
            match server.serve((read, write)).await {
                Ok(running) => {
                    let _ = running.waiting().await;
                }
                Err(e) => eprintln!("keel-mcp: connection: {e}"),
            }
        });
    }
}

#[tokio::main]
async fn main() -> ExitCode {
    let args = match parse() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("keel-mcp: {e}");
            return ExitCode::from(2);
        }
    };
    let bus = match Bus::session().await {
        Ok(bus) => bus,
        Err(e) => {
            eprintln!("keel-mcp: no session bus: {e}");
            return ExitCode::FAILURE;
        }
    };
    let backend: Arc<dyn Backend> = Arc::new(bus);
    let server = KeelMcp::new(Arc::clone(&backend), args.external);
    let probe = if args.probe == 0 {
        Duration::MAX / 4
    } else {
        Duration::from_secs(args.probe)
    };
    // The first catalogue before the first client.
    let first = keel_mcp::catalogue::Catalogue::build(
        keel_mcp::catalogue::load(&keel_mcp::catalogue::scan(&args.dirs)),
        Vec::new(),
    );
    server.set_catalogue(first);
    tokio::spawn(keel_mcp::watch(
        server.clone(),
        backend,
        args.dirs.clone(),
        probe,
    ));

    let result = match args.socket {
        Some(path) => serve_socket(server, path).await.map_err(|e| e.to_string()),
        None => match server.serve(rmcp::transport::stdio()).await {
            Ok(running) => running
                .waiting()
                .await
                .map(|_| ())
                .map_err(|e| e.to_string()),
            Err(e) => Err(e.to_string()),
        },
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("keel-mcp: {e}");
            ExitCode::FAILURE
        }
    }
}
