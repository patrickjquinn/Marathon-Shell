//! `marathon-store://<verb>/<arg>` URLs, validated before anything runs.

use std::sync::LazyLock;

use regex::Regex;

/// Flathub's app-id shape.
pub static REF_RE: LazyLock<Regex> = LazyLock::new(|| {
    #[allow(clippy::unwrap_used, reason = "constant pattern")]
    Regex::new(r"^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9][A-Za-z0-9_-]*)+$").unwrap()
});

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verb {
    Install,
    Update,
    Uninstall,
    Cancel,
    Open,
    RefreshState,
    UpdateAll,
}

impl Verb {
    pub fn as_str(self) -> &'static str {
        match self {
            Verb::Install => "install",
            Verb::Update => "update",
            Verb::Uninstall => "uninstall",
            Verb::Cancel => "cancel",
            Verb::Open => "open",
            Verb::RefreshState => "refresh-state",
            Verb::UpdateAll => "update-all",
        }
    }

    /// Install, update and uninstall each run in their own named unit.
    pub fn is_job(self) -> bool {
        matches!(self, Verb::Install | Verb::Update | Verb::Uninstall)
    }
}

#[derive(Debug, PartialEq, Eq)]
pub struct Request {
    pub verb: Verb,
    pub arg: String,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Rejection {
    BadUrl,
    UnknownVerb(String),
    Traversal(String),
    BadRef(String),
}

impl Rejection {
    pub fn exit_code(&self) -> u8 {
        match self {
            Rejection::BadUrl | Rejection::UnknownVerb(_) => 2,
            Rejection::Traversal(_) | Rejection::BadRef(_) => 3,
        }
    }

    pub fn message(&self, url: &str) -> String {
        match self {
            Rejection::BadUrl => format!("bad url: {url}"),
            Rejection::UnknownVerb(verb) => format!("unknown verb: {verb}"),
            Rejection::Traversal(arg) => format!("rejecting traversal: {arg}"),
            Rejection::BadRef(arg) => format!("rejecting ref: {arg}"),
        }
    }
}

pub fn parse(url: &str) -> Result<Request, Rejection> {
    let (verb, arg) = url
        .strip_prefix("marathon-store://")
        .and_then(|rest| rest.split_once('/'))
        .filter(|(verb, _)| !verb.is_empty())
        .ok_or(Rejection::BadUrl)?;
    let verb = match verb {
        "install" => Verb::Install,
        "update" => Verb::Update,
        "uninstall" => Verb::Uninstall,
        "cancel" => Verb::Cancel,
        "open" => Verb::Open,
        "refresh-state" => Verb::RefreshState,
        "update-all" => Verb::UpdateAll,
        other => return Err(Rejection::UnknownVerb(other.to_owned())),
    };
    if !matches!(verb, Verb::RefreshState | Verb::UpdateAll) {
        if arg.contains("..") {
            return Err(Rejection::Traversal(arg.to_owned()));
        }
        if !REF_RE.is_match(arg) {
            return Err(Rejection::BadRef(arg.to_owned()));
        }
    }
    Ok(Request {
        verb,
        arg: arg.to_owned(),
    })
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn accepts_each_verb() {
        let r = parse("marathon-store://install/org.gnome.Maps").unwrap();
        assert_eq!(r.verb, Verb::Install);
        assert_eq!(r.arg, "org.gnome.Maps");
        assert_eq!(
            parse("marathon-store://cancel/io.github.App_x-1")
                .unwrap()
                .verb,
            Verb::Cancel
        );
        assert_eq!(
            parse("marathon-store://refresh-state/all").unwrap().verb,
            Verb::RefreshState
        );
        assert_eq!(
            parse("marathon-store://update-all/").unwrap().verb,
            Verb::UpdateAll
        );
    }

    #[test]
    fn rejects_malformed_urls() {
        for url in [
            "",
            "marathon-store://",
            "marathon-store://install",
            "marathon-store:///org.a.b",
            "https://install/org.a.b",
        ] {
            assert_eq!(parse(url), Err(Rejection::BadUrl), "{url}");
        }
        assert_eq!(
            parse("marathon-store://rm/org.a.b"),
            Err(Rejection::UnknownVerb("rm".into()))
        );
    }

    #[test]
    fn rejects_refs_that_are_not_app_ids() {
        assert!(matches!(
            parse("marathon-store://install/org..evil"),
            Err(Rejection::Traversal(_))
        ));
        for arg in [
            "org",
            "1org.a",
            "org.a/b",
            "org.a;rm -rf",
            "org.a b",
            "org.a\nevil",
            "-org.a",
        ] {
            let err = parse(&format!("marathon-store://install/{arg}")).unwrap_err();
            assert_eq!(err.exit_code(), 3, "{arg}");
        }
    }

    #[test]
    fn listing_verbs_take_any_argument() {
        assert!(parse("marathon-store://refresh-state/../x").is_ok());
    }
}
