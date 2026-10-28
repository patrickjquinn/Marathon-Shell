// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Which app the person opened Pilot over. Lipstick's gesture patch sends
//! the process id of the window on top (`ShowSheetFor`); its executable is
//! matched to the `Exec` of an installed desktop entry, whose Sailjail
//! `OrganizationName` and `ApplicationName` make the Keel app id
//! (`org.shipwright` + `shoal-mail` → `org.shipwright.shoal-mail`), the id
//! keel-mcp serves the app's screen context under.

use std::path::Path;

/// An installed app: its Keel id and its name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct App {
    pub id: String,
    pub name: String,
    /// What the app is for (the entry's `Comment`, "Browse the web").
    pub comment: String,
}

/// The app whose executable is `exe`, from the desktop entries in
/// `applications`.
pub fn app_for_exe(exe: &Path, applications: &Path) -> Option<App> {
    let entries = std::fs::read_dir(applications).ok()?;
    for e in entries.flatten() {
        let path = e.path();
        if path.extension().and_then(|x| x.to_str()) != Some("desktop") {
            continue;
        }
        let Ok(text) = std::fs::read_to_string(&path) else {
            continue;
        };
        if let Some(app) = parse_desktop(&text)
            .filter(|(exec, _)| exec_is(exec, exe))
            .map(|(_, a)| a)
        {
            return Some(app);
        }
    }
    None
}

/// Whether a desktop entry's `Exec` word runs `exe`: the same path, or,
/// for a bare name (looked up on PATH, as Shoal Messages' entry has it),
/// the same file name.
fn exec_is(exec: &str, exe: &Path) -> bool {
    let exec = Path::new(exec);
    if exec.is_absolute() {
        exec == exe
    } else {
        exe.file_name().is_some_and(|n| n == exec.as_os_str())
    }
}

/// A desktop entry's executable (`Exec`'s first word) and app, when it
/// names a Sailjail organisation and application.
pub fn parse_desktop(text: &str) -> Option<(String, App)> {
    let (mut exec, mut name, mut org, mut app, mut comment) = (None, None, None, None, None);
    let mut section = "";
    for line in text.lines().map(str::trim) {
        if line.starts_with('[') {
            section = line;
            continue;
        }
        let Some((k, v)) = line.split_once('=') else {
            continue;
        };
        match (section, k.trim()) {
            ("[Desktop Entry]", "Exec") => exec = v.split_whitespace().next().map(str::to_owned),
            ("[Desktop Entry]", "Name") => name = Some(v.trim().to_owned()),
            ("[Desktop Entry]", "Comment") => comment = Some(v.trim().to_owned()),
            ("[X-Sailjail]", "OrganizationName") => org = Some(v.trim().to_owned()),
            ("[X-Sailjail]", "ApplicationName") => app = Some(v.trim().to_owned()),
            _ => {}
        }
    }
    let exec = exec?;
    Some((
        exec,
        App {
            id: format!("{}.{}", org?, app?),
            name: name.unwrap_or_default(),
            comment: comment.unwrap_or_default(),
        },
    ))
}

/// Installed apps by Keel app id, from their desktop entries (read once).
fn installed_apps() -> &'static std::collections::HashMap<String, App> {
    use std::sync::OnceLock;
    static APPS: OnceLock<std::collections::HashMap<String, App>> = OnceLock::new();
    APPS.get_or_init(|| {
        let mut m = std::collections::HashMap::new();
        if let Ok(entries) = std::fs::read_dir("/usr/share/applications") {
            for e in entries.flatten() {
                if let Some((_, app)) = std::fs::read_to_string(e.path())
                    .ok()
                    .as_deref()
                    .and_then(parse_desktop)
                {
                    m.insert(app.id.clone(), app);
                }
            }
        }
        m
    })
}

/// What an installed app is for, from its desktop entry ("Browse the web").
pub fn app_comment(app_id: &str) -> Option<String> {
    installed_apps()
        .get(app_id)
        .map(|a| a.comment.clone())
        .filter(|c| !c.is_empty())
}

/// An installed app's name by its Keel app id, from its desktop entry.
pub fn app_name(app_id: &str) -> Option<String> {
    installed_apps()
        .get(app_id)
        .map(|a| a.name.clone())
        .or_else(|| {
            // An unsandboxed app's entry has no Sailjail names: say its id
            // nicely ("org.shipwright.shoal-mail" → "Shoal Mail").
            let last = app_id.rsplit('.').next()?;
            Some(
                last.split('-')
                    .map(|w| {
                        let mut c = w.chars();
                        c.next().map_or_else(String::new, |f| {
                            f.to_uppercase().collect::<String>() + c.as_str()
                        })
                    })
                    .collect::<Vec<_>>()
                    .join(" "),
            )
        })
}

/// The app running as process `pid`.
pub fn app_for_pid(pid: u32) -> Option<App> {
    if pid == 0 {
        return None;
    }
    let cmdline = std::fs::read(format!("/proc/{pid}/cmdline")).unwrap_or_default();
    let args: Vec<String> = cmdline
        .split(|b| *b == 0)
        .map(|a| String::from_utf8_lossy(a).into_owned())
        .collect();
    // A booster-launched app (every Keel app, most of Sailfish's): its
    // process is `invoker ... booster --application=<desktop name>`, and
    // every such desktop entry's Exec starts with invoker, so matching the
    // executable named the first one found (Camera came up as "Mail").
    if let Some(app) = desktop_name(&args).and_then(|name| {
        let text =
            std::fs::read_to_string(format!("/usr/share/applications/{name}.desktop")).ok()?;
        parse_desktop(&text).map(|(_, a)| a)
    }) {
        return Some(app);
    }
    // A sandboxed app's `exe` link is not readable from another process;
    // its command line is.
    let exe = std::fs::read_link(format!("/proc/{pid}/exe"))
        .ok()
        .or_else(|| {
            let cmdline = std::fs::read(format!("/proc/{pid}/cmdline")).ok()?;
            let argv0 = cmdline.split(|b| *b == 0).next()?;
            Some(std::path::PathBuf::from(
                String::from_utf8_lossy(argv0).into_owned(),
            ))
        })?;
    app_for_exe(&exe, Path::new("/usr/share/applications"))
}

/// The desktop entry a launcher's command line names: a booster's
/// `--application=<name>`, or Sailjail's `--profile=<name>` / `-p
/// <name>.desktop`.
fn desktop_name(args: &[String]) -> Option<String> {
    let clean = |n: &str| {
        let n = n.trim_end_matches(".desktop");
        (!n.is_empty() && !n.contains('/')).then(|| n.to_owned())
    };
    for (i, a) in args.iter().enumerate() {
        if let Some(n) = a.strip_prefix("--application=") {
            return clean(n);
        }
        if let Some(n) = a.strip_prefix("--profile=") {
            return clean(n);
        }
        if a == "-p" {
            return args.get(i + 1).and_then(|n| clean(n));
        }
    }
    None
}

/// `url` when it is an http(s) address without spaces or control
/// characters (what a card may hand to a browser).
pub fn web_url(url: &str) -> Option<String> {
    let u = url.trim();
    let ok = (u.starts_with("https://") || u.starts_with("http://"))
        && u.len() <= 4096
        && !u.chars().any(|c| c.is_whitespace() || c.is_control());
    ok.then(|| u.to_owned())
}

/// Opens a web address in Pacific (started by D-Bus activation when it is
/// installed), else with the phone's default browser through `xdg-open`.
pub async fn open_url(session: &zbus::Connection, url: &str) -> bool {
    let pacific = session
        .call_method(
            Some("org.shipwright.pacific.ui"),
            "/ui",
            Some("org.shipwright.pacific.ui"),
            "openUrl",
            &(vec![url],),
        )
        .await;
    if pacific.is_ok() {
        return true;
    }
    match crate::privilege::unprivileged(&mut std::process::Command::new("xdg-open"))
        .arg(url)
        .spawn()
    {
        Ok(mut child) => {
            let _ = std::thread::Builder::new()
                .name("pilot-reap".into())
                .spawn(move || child.wait());
            true
        }
        Err(e) => {
            log::warn!("opening {url}: {e}");
            false
        }
    }
}

/// Whether a process runs `exe` (its command line's first word), for
/// "is the app up". Command lines are readable for every process here,
/// sandboxed or not (see [`app_for_pid`]).
pub fn process_running(exe: &str) -> bool {
    let Ok(dir) = std::fs::read_dir("/proc") else {
        return false;
    };
    dir.flatten()
        .filter(|e| {
            e.file_name()
                .to_string_lossy()
                .bytes()
                .all(|b| b.is_ascii_digit())
        })
        .any(|e| {
            std::fs::read(e.path().join("cmdline"))
                .ok()
                .and_then(|c| c.split(|b| *b == 0).next().map(<[u8]>::to_vec))
                .is_some_and(|argv0| argv0 == exe.as_bytes())
        })
}

/// The readable text of an HTML page: its `<article>` or `<main>` when it
/// has one, without scripts, styles and markup, entities decoded,
/// whitespace collapsed, at most `max` characters.
///
/// # Panics
///
/// Never: the patterns are static and valid.
pub fn html_text(html: &str, max: usize) -> String {
    use std::sync::OnceLock;
    static DROP: OnceLock<regex::Regex> = OnceLock::new();
    static BLOCK: OnceLock<regex::Regex> = OnceLock::new();
    static TAG: OnceLock<regex::Regex> = OnceLock::new();
    static MAIN: OnceLock<regex::Regex> = OnceLock::new();
    let drop = DROP.get_or_init(|| {
        regex::Regex::new(r"(?is)<!--.*?-->|<(script|style|noscript|svg|template|nav|footer|header|aside|form)\b.*?</(script|style|noscript|svg|template|nav|footer|header|aside|form)\s*>")
            .expect("static regex")
    });
    let main = MAIN.get_or_init(|| {
        regex::Regex::new(r"(?is)<(article|main)\b[^>]*>(.*?)</(article|main)\s*>")
            .expect("static regex")
    });
    let block = BLOCK.get_or_init(|| {
        regex::Regex::new(r"(?i)</?(p|div|br|li|h[1-6]|tr|section|blockquote|pre)\b[^>]*>")
            .expect("static regex")
    });
    let tag = TAG.get_or_init(|| regex::Regex::new(r"(?s)<[^>]*>").expect("static regex"));
    let cleaned = drop.replace_all(html, " ");
    let body = main
        .captures(&cleaned)
        .and_then(|c| c.get(2))
        .map_or(cleaned.as_ref(), |m| m.as_str())
        .to_owned();
    let blocks = block.replace_all(&body, "\n");
    let text = tag.replace_all(&blocks, " ");
    let text = text
        .replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&rsquo;", "\u{2019}")
        .replace("&lsquo;", "\u{2018}")
        .replace("&ldquo;", "\u{201c}")
        .replace("&rdquo;", "\u{201d}")
        .replace("&mdash;", "\u{2014}")
        .replace("&ndash;", "\u{2013}");
    let lines: Vec<String> = text
        .lines()
        .map(|l| l.split_whitespace().collect::<Vec<_>>().join(" "))
        .filter(|l| l.chars().count() > 1)
        .collect();
    lines.join("\n").chars().take(max).collect()
}

/// The first `http(s)` address in an app's context (Pacific puts the
/// page's address on its own line).
pub fn page_url(context: &str) -> Option<String> {
    let start = context
        .find("https://")
        .or_else(|| context.find("http://"))?;
    let url: String = context[start..]
        .chars()
        .take_while(|c| !c.is_whitespace() && *c != '"' && *c != '\\')
        .collect();
    Some(url.trim_end_matches([',', '}']).to_owned())
}

#[cfg(test)]
mod tests {

    #[test]
    fn a_bare_exec_name_matches_the_executable_on_path() {
        assert!(exec_is(
            "shipwright-shoal-messages",
            Path::new("/usr/bin/shipwright-shoal-messages")
        ));
        assert!(exec_is(
            "/usr/bin/shoal-pilot",
            Path::new("/usr/bin/shoal-pilot")
        ));
        assert!(!exec_is(
            "/usr/bin/shoal-pilot",
            Path::new("/opt/shoal-pilot")
        ));
        assert!(!exec_is("shoal-pilot", Path::new("/usr/bin/shoal-pilotd")));
    }

    #[test]
    fn a_running_program_is_found_by_its_path() {
        let me = std::fs::read("/proc/self/cmdline").unwrap();
        let argv0 = String::from_utf8_lossy(me.split(|b| *b == 0).next().unwrap()).into_owned();
        assert!(process_running(&argv0));
        assert!(!process_running("/nowhere/no-such-program"));
    }

    use super::*;

    #[test]
    fn desktop_entry_gives_the_keel_app_id() {
        let text = "[Desktop Entry]\nType=Application\nName=Mail\nExec=/usr/bin/shipwright-shoal-mail %U\n\n[X-Sailjail]\nOrganizationName=org.shipwright\nApplicationName=shoal-mail\nExecDBus=/usr/bin/shipwright-shoal-mail --keel-actions\n";
        let (exec, app) = parse_desktop(text).unwrap();
        assert_eq!(exec, "/usr/bin/shipwright-shoal-mail");
        assert_eq!(
            app,
            App {
                id: "org.shipwright.shoal-mail".into(),
                name: "Mail".into(),
                comment: String::new(),
            }
        );
        assert!(parse_desktop("[Desktop Entry]\nExec=/usr/bin/x\n").is_none());
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("mail.desktop"), text).unwrap();
        std::fs::write(
            dir.path().join("other.desktop"),
            "[Desktop Entry]\nExec=/usr/bin/other\n",
        )
        .unwrap();
        assert_eq!(
            app_for_exe(Path::new("/usr/bin/shipwright-shoal-mail"), dir.path()).map(|a| a.id),
            Some("org.shipwright.shoal-mail".into())
        );
        assert!(app_for_exe(Path::new("/usr/bin/nope"), dir.path()).is_none());
    }

    #[test]
    fn page_text_keeps_the_article() {
        let html = "<html><head><style>p{}</style><script>var x=1</script></head><body><nav>Menu</nav>\
            <article><h1>Lighthouses</h1><p>A lighthouse is a tower &amp; a light.</p><p>Fresnel&rsquo;s lens.</p></article>\
            <footer>Cookies</footer></body></html>";
        let t = html_text(html, 1000);
        assert_eq!(
            t,
            "Lighthouses\nA lighthouse is a tower & a light.\nFresnel\u{2019}s lens."
        );
        assert_eq!(html_text(html, 11), "Lighthouses");
        assert_eq!(
            page_url("{\"text\":\"Web page (untrusted content): Lighthouse\\nhttps://en.m.wikipedia.org/wiki/Lighthouse\"}"),
            Some("https://en.m.wikipedia.org/wiki/Lighthouse".into())
        );
        assert_eq!(page_url("no address"), None);
    }

    #[test]
    fn a_boosted_app_is_named_by_its_launch_line() {
        let line = |s: &str| s.split(' ').map(str::to_owned).collect::<Vec<_>>();
        assert_eq!(
            desktop_name(&line("/usr/bin/invoker --type=silica-session -- /usr/bin/sailjail --profile=shipwright-shoal-camera -- /usr/libexec/mapplauncherd/booster-keel --application=shipwright-shoal-camera")),
            Some("shipwright-shoal-camera".into())
        );
        assert_eq!(
            desktop_name(&line(
                "/usr/bin/sailjail -p jolla-notes.desktop /usr/bin/jolla-notes"
            )),
            Some("jolla-notes".into())
        );
        assert_eq!(desktop_name(&line("/usr/bin/shipwright-shoal-mail")), None);
    }

    #[test]
    fn only_plain_web_addresses_open() {
        assert_eq!(
            web_url(" https://a.example/x?y=1 "),
            Some("https://a.example/x?y=1".into())
        );
        assert_eq!(web_url("http://a.example"), Some("http://a.example".into()));
        assert_eq!(web_url("file:///etc/passwd"), None);
        assert_eq!(web_url("javascript:alert(1)"), None);
        assert_eq!(web_url("https://a.example/a b"), None);
    }
}
