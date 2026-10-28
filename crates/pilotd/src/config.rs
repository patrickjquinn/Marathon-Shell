// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! `pilotd.toml`. Every remote endpoint, the model ids and the routing
//! thresholds are configuration, not code (spec section 6.1: preview
//! models get replaced). A missing file means the built-in defaults: the
//! Pilot relay for the standard backend, no Lighthouse.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::jev::LabelToken;
use crate::llm::EffortValues;
use crate::route::Thresholds;

/// The production Pilot relay (services/pilot-relay, deployed by
/// services/cloudflare-production.sh).
pub const PRODUCTION_RELAY: &str = "https://pilot.reefstore.app";

/// The relay a missing config uses: `$PILOT_RELAY_URL` at build time when
/// set and not empty (a staging phone build points it at the staging
/// relay), else [`PRODUCTION_RELAY`]. Cargo rebuilds the crate when the
/// variable changes.
pub const DEFAULT_RELAY: &str = match option_env!("PILOT_RELAY_URL") {
    Some(v) if !v.is_empty() => v,
    _ => PRODUCTION_RELAY,
};

// A build-time override that is not a plain https origin fails the build.
const _: () = assert!(
    is_valid_relay(DEFAULT_RELAY),
    "PILOT_RELAY_URL must be an https:// URL with a host and no path, spaces, query or fragment"
);

/// Whether `value` can be the built-in relay: `https://`, then a host of
/// `[A-Za-z0-9.-]` with an optional `:port`, nothing after it (the routes
/// `/v1/...` are appended).
pub const fn is_valid_relay(value: &str) -> bool {
    const SCHEME: &[u8] = b"https://";
    let b = value.as_bytes();
    if b.len() <= SCHEME.len() {
        return false;
    }
    let mut i = 0;
    while i < SCHEME.len() {
        if b[i] != SCHEME[i] {
            return false;
        }
        i += 1;
    }
    let mut port = false;
    while i < b.len() {
        let c = b[i];
        let ok = if port {
            c.is_ascii_digit()
        } else {
            c.is_ascii_alphanumeric() || c == b'.' || c == b'-' || c == b':'
        };
        if !ok {
            return false;
        }
        if c == b':' {
            port = true;
        }
        i += 1;
    }
    let first = b[SCHEME.len()];
    first != b'.' && first != b'-' && first != b':'
}

/// Whether a relay URL names a staging or placeholder host, which a
/// release build refuses (`--cfg release_build`).
pub const fn is_non_production_relay(value: &str) -> bool {
    contains(value, "staging") || contains(value, ".example") || contains(value, ".workers.dev")
}

const fn contains(haystack: &str, needle: &str) -> bool {
    let (h, n) = (haystack.as_bytes(), needle.as_bytes());
    if n.len() > h.len() {
        return false;
    }
    let mut i = 0;
    while i + n.len() <= h.len() {
        let mut j = 0;
        while j < n.len() && h[i + j] == n[j] {
            j += 1;
        }
        if j == n.len() {
            return true;
        }
        i += 1;
    }
    false
}

#[cfg(release_build)]
const _: () = assert!(
    !is_non_production_relay(DEFAULT_RELAY),
    "release build with a staging or placeholder Pilot relay: unset PILOT_RELAY_URL"
);

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase", deny_unknown_fields)]
pub enum JevConfig {
    /// The hosted Jev API (section 5.1 request shape).
    Jev {
        url: String,
        #[serde(default = "default_jev_model")]
        model: String,
        #[serde(default = "default_jev_provider")]
        provider: String,
    },
    /// Local mode's stand-in (jev.rs `LocalJev`): embeddings on this
    /// machine at `url`.
    Local { url: String },
    /// SGLang `/v1/score` over an open model (Lighthouse, section 10.1).
    Score {
        url: String,
        model: String,
        #[serde(default = "default_score_provider")]
        provider: String,
        /// Option labels and their token ids, in order.
        labels: Vec<LabelToken>,
        yes: LabelToken,
        no: LabelToken,
    },
}

fn default_jev_model() -> String {
    "jev-latest".into()
}
fn default_jev_provider() -> String {
    "jev".into()
}
fn default_score_provider() -> String {
    "lighthouse-score".into()
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LlmConfig {
    /// Full chat completions URL.
    pub url: String,
    #[serde(default = "default_llm_model")]
    pub model: String,
    #[serde(default = "default_llm_provider")]
    pub provider: String,
    #[serde(default = "default_region_header")]
    pub region_header: String,
    #[serde(default = "default_regions")]
    pub allowed_regions: Vec<String>,
    #[serde(default)]
    pub effort: EffortValuesConfig,
    #[serde(default = "default_max_tokens")]
    pub max_completion_tokens: u32,
}

/// `[backends.*.llm.effort]`; an empty string leaves the parameter out.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct EffortValuesConfig {
    pub off: String,
    pub low: String,
    pub medium: String,
}

impl Default for EffortValuesConfig {
    fn default() -> Self {
        let d = EffortValues::default();
        EffortValuesConfig {
            off: d.off.unwrap_or_default(),
            low: d.low.unwrap_or_default(),
            medium: d.medium.unwrap_or_default(),
        }
    }
}

impl From<&EffortValuesConfig> for EffortValues {
    fn from(c: &EffortValuesConfig) -> Self {
        let o = |s: &String| (!s.is_empty()).then(|| s.clone());
        EffortValues {
            off: o(&c.off),
            low: o(&c.low),
            medium: o(&c.medium),
        }
    }
}

fn default_llm_model() -> String {
    "qwen/qwen3.8-27b".into()
}
fn default_llm_provider() -> String {
    "groq".into()
}
fn default_region_header() -> String {
    "x-pilot-processing-region".into()
}
/// The regions a reply may be stamped with. The relay's Groq upstream is
/// its public endpoint, processed in the US (decided 4 October 2026); EU
/// stays allowed for an EU upstream or Lighthouse.
fn default_regions() -> Vec<String> {
    vec!["eu".into(), "us".into()]
}
fn default_max_tokens() -> u32 {
    1024
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Backend {
    pub jev: JevConfig,
    pub llm: LlmConfig,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct PrivacyConfig {
    /// "sailfish" (the session-bus service), "none", or `file:PATH`.
    pub source: String,
}

impl Default for PrivacyConfig {
    fn default() -> Self {
        PrivacyConfig {
            source: "sailfish".into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct AdaptersConfig {
    /// Overrides for the mkcal and qtcontacts-sqlite database paths.
    pub calendar_db: Option<PathBuf>,
    pub contacts_db: Option<PathBuf>,
    /// The voice unit stopped by the privacy switch.
    pub voice_unit: String,
}

impl Default for AdaptersConfig {
    fn default() -> Self {
        AdaptersConfig {
            calendar_db: None,
            contacts_db: None,
            voice_unit: crate::adapters::voice::VOICE_UNIT.into(),
        }
    }
}

/// `[mcp]`: the MCP server whose tools Pilot offers (keel-mcp, spec
/// section 9). Skipped when the program is not installed.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct McpConfig {
    pub command: Vec<String>,
    pub timeout_secs: u64,
}

impl Default for McpConfig {
    fn default() -> Self {
        McpConfig {
            command: vec!["/usr/bin/keel-mcp".into(), "--stdio".into()],
            timeout_secs: 60,
        }
    }
}

/// `[events]`: Pilot's entry in the Events view (`events.rs`).
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct EventsConfig {
    /// Also keep a notification in the Events view's notification list.
    /// Off: the Pilot widget (shoal/pilot/lipstick/eventswidget) shows the
    /// same summary there; this is the fallback if a release drops
    /// Lipstick's widget registry.
    pub notification: bool,
    /// Run when the entry is tapped, to bring up the app's events page.
    /// `invoker --single-instance` raises a running app instead (which
    /// then follows `EventsRequested`). Empty: nothing is started.
    pub open_command: Vec<String>,
}

impl Default for EventsConfig {
    fn default() -> Self {
        EventsConfig {
            notification: false,
            open_command: [
                "/usr/bin/invoker",
                "--type=keel",
                "--single-instance",
                "/usr/bin/shoal-pilot",
            ]
            .map(String::from)
            .to_vec(),
        }
    }
}

/// `[sheet]`: the system-wide bottom-edge gesture (the gesture patch
/// in shoal/pilot/lipstick/patch) calls `ShowSheet`, which runs this.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct SheetConfig {
    /// Brings up the app; empty: nothing is started (a running app still
    /// follows `SheetRequested`). No arguments: Sailjail refuses a command
    /// line its desktop entry does not template, so the app learns why it
    /// started from `TakeLaunchRequest`.
    pub open_command: Vec<String>,
}

impl Default for SheetConfig {
    fn default() -> Self {
        SheetConfig {
            open_command: [
                "/usr/bin/invoker",
                "--type=keel",
                "--single-instance",
                "/usr/bin/shoal-pilot",
            ]
            .map(String::from)
            .to_vec(),
        }
    }
}

/// `[direct]`: the owner's Groq and Jev keys on the phone instead of the
/// relay (direct.rs). Used only when `enabled` and the key file exists.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct DirectConfig {
    pub enabled: bool,
    /// Default `$XDG_CONFIG_HOME/shoal-pilot/keys.env`.
    pub key_file: Option<PathBuf>,
    /// The relay's upstreams (services/cloudflare-production.sh).
    pub jev_url: String,
    pub llm_url: String,
    /// Where `llm_url` processes requests: Groq's public endpoint, `us`.
    pub llm_region: String,
    pub max_completion_tokens: u64,
}

impl Default for DirectConfig {
    fn default() -> Self {
        DirectConfig {
            enabled: false,
            key_file: None,
            jev_url: "https://api.typesafe.ai/v1/systemone".into(),
            llm_url: "https://api.groq.com/openai/v1/chat/completions".into(),
            llm_region: "us".into(),
            max_completion_tokens: 4096,
        }
    }
}

impl DirectConfig {
    pub fn key_path(&self) -> Option<PathBuf> {
        self.key_file
            .clone()
            .or_else(|| xdg("XDG_CONFIG_HOME", ".config").map(|d| d.join("shoal-pilot/keys.env")))
    }
}

/// `[local]`: the model runs on the phone (llama.cpp's llama-server): no
/// relay, no licence, no keys. Wins over
/// `[direct]`.
#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct LocalConfig {
    pub enabled: bool,
    /// OpenAI-compatible chat completions on this machine.
    pub llm_url: String,
    pub model: String,
    pub max_completion_tokens: u64,
    /// A phone's CPU answers slower than a hosted model.
    pub timeout_secs: u64,
    /// The `web.search` tool, the relay's contract, on this machine.
    /// Empty: not offered.
    pub web_search_url: String,
    /// OpenAI-compatible embeddings on this machine, which pick the tools.
    pub embed_url: String,
}

impl Default for LocalConfig {
    fn default() -> Self {
        LocalConfig {
            enabled: false,
            llm_url: "http://127.0.0.1:8088/v1/chat/completions".into(),
            model: "local".into(),
            max_completion_tokens: 1024,
            timeout_secs: 120,
            web_search_url: "http://127.0.0.1:8089/v1/search".into(),
            embed_url: "http://127.0.0.1:8087/v1/embeddings".into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    /// The relay's device token. Default `$XDG_DATA_HOME/shoal-pilot/device-token`.
    pub token_file: Option<PathBuf>,
    /// The relay's `POST /v1/search` for the `web.search` tool. Empty: the
    /// tool is not offered.
    pub web_search_url: String,
    /// Per-request timeout.
    pub timeout_secs: u64,
    /// Model rounds per turn before giving up.
    pub max_tool_rounds: u32,
    pub thresholds: Thresholds,
    pub privacy: PrivacyConfig,
    pub adapters: AdaptersConfig,
    pub mcp: McpConfig,
    pub triage: crate::triage::TriageConfig,
    pub events: EventsConfig,
    pub sheet: SheetConfig,
    pub direct: DirectConfig,
    pub local: LocalConfig,
    pub backends: BTreeMap<String, Backend>,
}

impl Default for Config {
    fn default() -> Self {
        let mut backends = BTreeMap::new();
        backends.insert(
            "standard".to_owned(),
            Backend {
                jev: JevConfig::Jev {
                    url: format!("{DEFAULT_RELAY}/v1/jev"),
                    model: default_jev_model(),
                    provider: default_jev_provider(),
                },
                llm: LlmConfig {
                    url: format!("{DEFAULT_RELAY}/v1/llm/chat/completions"),
                    model: default_llm_model(),
                    provider: default_llm_provider(),
                    region_header: default_region_header(),
                    allowed_regions: default_regions(),
                    effort: EffortValuesConfig::default(),
                    max_completion_tokens: default_max_tokens(),
                },
            },
        );
        Config {
            token_file: None,
            web_search_url: format!("{DEFAULT_RELAY}/v1/search"),
            timeout_secs: 20,
            max_tool_rounds: 5,
            thresholds: Thresholds::default(),
            privacy: PrivacyConfig::default(),
            adapters: AdaptersConfig::default(),
            mcp: McpConfig::default(),
            triage: crate::triage::TriageConfig::default(),
            events: EventsConfig::default(),
            sheet: SheetConfig::default(),
            direct: DirectConfig::default(),
            local: LocalConfig::default(),
            backends,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("{}: {source}", path.display())]
    Read {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("{}: {source}", path.display())]
    Parse {
        path: PathBuf,
        source: toml::de::Error,
    },
    #[error("{0}")]
    Invalid(String),
}

impl Config {
    /// Loads `path`; a missing file gives the defaults.
    pub fn load(path: &Path) -> Result<Config, ConfigError> {
        let text = match std::fs::read_to_string(path) {
            Ok(t) => t,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Config::default()),
            Err(source) => {
                return Err(ConfigError::Read {
                    path: path.to_owned(),
                    source,
                })
            }
        };
        Self::parse(&text).map_err(|e| match e {
            ConfigError::Parse { source, .. } => ConfigError::Parse {
                path: path.to_owned(),
                source,
            },
            other => other,
        })
    }

    pub fn parse(text: &str) -> Result<Config, ConfigError> {
        let mut c: Config = toml::from_str(text).map_err(|source| ConfigError::Parse {
            path: PathBuf::new(),
            source,
        })?;
        if c.backends.is_empty() {
            c.backends = Config::default().backends;
        }
        c.validate()?;
        Ok(c)
    }

    fn validate(&self) -> Result<(), ConfigError> {
        for (name, b) in &self.backends {
            let urls = [
                match &b.jev {
                    JevConfig::Jev { url, .. }
                    | JevConfig::Score { url, .. }
                    | JevConfig::Local { url } => url.as_str(),
                },
                b.llm.url.as_str(),
            ];
            for u in urls.into_iter().filter(|u| !u.is_empty()) {
                // Plain HTTP only to this machine (tests, a local relay).
                if !u.starts_with("https://") && !is_local(u) {
                    return Err(ConfigError::Invalid(format!(
                        "backend {name}: {u} is not https"
                    )));
                }
            }
            if b.llm.allowed_regions.is_empty() {
                return Err(ConfigError::Invalid(format!(
                    "backend {name}: allowed_regions is empty"
                )));
            }
            if let JevConfig::Score { labels, .. } = &b.jev {
                if labels.len() < 2 {
                    return Err(ConfigError::Invalid(format!(
                        "backend {name}: fewer than two labels"
                    )));
                }
            }
        }
        for (name, x) in [
            ("web_search_url", &self.web_search_url),
            ("direct.jev_url", &self.direct.jev_url),
            ("direct.llm_url", &self.direct.llm_url),
        ] {
            if !x.is_empty() && !x.starts_with("https://") && !is_local(x) {
                return Err(ConfigError::Invalid(format!("{name} {x} is not https")));
            }
        }
        for (name, x) in [
            ("local.llm_url", &self.local.llm_url),
            ("local.web_search_url", &self.local.web_search_url),
            ("local.embed_url", &self.local.embed_url),
        ] {
            if self.local.enabled && !x.is_empty() && !is_local(x) {
                return Err(ConfigError::Invalid(format!(
                    "{name} {x} is not on this machine"
                )));
            }
        }
        if !self.backends.contains_key("standard") {
            return Err(ConfigError::Invalid("no [backends.standard]".into()));
        }
        Ok(())
    }
}

/// Plain HTTP is allowed only to this machine (tests, a local relay).
fn is_local(u: &str) -> bool {
    u.starts_with("http://127.0.0.1")
        || u.starts_with("http://localhost")
        || u.starts_with("http://[::1]")
}

/// The distribution's configuration, read when the person has none.
pub const SYSTEM_CONFIG: &str = "/etc/shoal-pilot/pilotd.toml";

/// `$XDG_CONFIG_HOME/shoal-pilot/pilotd.toml`, else [`SYSTEM_CONFIG`] if
/// that exists.
pub fn default_config_path() -> Option<PathBuf> {
    let own = xdg("XDG_CONFIG_HOME", ".config").map(|d| d.join("shoal-pilot/pilotd.toml"));
    match own {
        Some(p) if !p.exists() && Path::new(SYSTEM_CONFIG).exists() => Some(SYSTEM_CONFIG.into()),
        other => other,
    }
}

/// `$XDG_DATA_HOME/shoal-pilot`.
pub fn default_data_dir() -> Option<PathBuf> {
    xdg("XDG_DATA_HOME", ".local/share").map(|d| d.join("shoal-pilot"))
}

fn xdg(var: &str, fallback: &str) -> Option<PathBuf> {
    std::env::var_os(var)
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(fallback)))
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn defaults_point_at_the_relay() {
        let c = Config::parse("").unwrap();
        let s = &c.backends["standard"];
        assert_eq!(s.llm.model, "qwen/qwen3.8-27b");
        assert_eq!(s.llm.allowed_regions, ["eu", "us"]);
        assert_eq!(s.llm.provider, "groq");
        assert_eq!(
            s.llm.url,
            format!("{DEFAULT_RELAY}/v1/llm/chat/completions")
        );
        assert_eq!(c.web_search_url, format!("{DEFAULT_RELAY}/v1/search"));
        assert!(matches!(&s.jev, JevConfig::Jev { url, .. } if url.ends_with("/v1/jev")));
        assert!((c.thresholds.intent_confidence - 0.85).abs() < f64::EPSILON);
    }

    #[test]
    fn full_file() {
        let c = Config::parse(
            r#"
            max_tool_rounds = 3
            [privacy]
            source = "file:/tmp/switch"
            [thresholds]
            intent_confidence = 0.9
            [backends.standard.jev]
            kind = "jev"
            url = "http://127.0.0.1:9/decide"
            [backends.standard.llm]
            url = "http://127.0.0.1:9/chat"
            effort = { off = "", low = "low", medium = "medium" }
            [backends.lighthouse.jev]
            kind = "score"
            url = "https://score.lighthouse.example/v1/score"
            model = "scorer"
            labels = [{ text = "A", token_id = 32 }, { text = "B", token_id = 33 }]
            yes = { text = "yes", token_id = 9891 }
            no = { text = "no", token_id = 2201 }
            [backends.lighthouse.llm]
            url = "https://llm.lighthouse.example/v1/chat/completions"
            model = "Qwen/Qwen3.8-27B"
            provider = "lighthouse-llm"
            "#,
        )
        .unwrap();
        assert_eq!(c.max_tool_rounds, 3);
        assert!((c.thresholds.ambiguity - 1.0).abs() < f64::EPSILON);
        assert_eq!(
            EffortValues::from(&c.backends["standard"].llm.effort).off,
            None
        );
        assert!(matches!(
            c.backends["lighthouse"].jev,
            JevConfig::Score { .. }
        ));
    }

    #[test]
    fn example_file_parses() {
        let c = Config::parse(include_str!("../pilotd.example.toml")).unwrap();
        let s = &c.backends["standard"];
        assert_eq!(s.llm.provider, "groq");
        assert_eq!(s.llm.allowed_regions, ["eu", "us"]);
        assert!(s.llm.url.starts_with(PRODUCTION_RELAY));
    }

    #[test]
    fn refuses_plain_http_and_unknown_keys() {
        assert!(Config::parse(
            "[backends.standard.jev]\nkind = \"jev\"\nurl = \"http://jev.example\"\n[backends.standard.llm]\nurl = \"https://x\"\n"
        )
        .is_err());
        assert!(Config::parse("bogus = 1").is_err());
        assert!(Config::parse("[backends.other.jev]\nkind=\"jev\"\nurl=\"https://a\"\n[backends.other.llm]\nurl=\"https://b\"\n").is_err());
    }

    #[test]
    fn default_relay_follows_the_build() {
        match option_env!("PILOT_RELAY_URL") {
            Some(v) if !v.is_empty() => assert_eq!(DEFAULT_RELAY, v),
            _ => {
                assert_eq!(DEFAULT_RELAY, "https://pilot.reefstore.app");
                assert!(!is_non_production_relay(DEFAULT_RELAY));
            }
        }
    }

    #[test]
    fn relay_urls() {
        for ok in [
            "https://pilot.reefstore.app",
            "https://shipwright-pilot-relay-staging.someone.workers.dev",
            "https://localhost:8787",
        ] {
            assert!(is_valid_relay(ok), "{ok:?}");
        }
        for bad in [
            "",
            "https://",
            "http://pilot.reefstore.app",
            "https://pilot.reefstore.app/",
            "https://pilot.reefstore.app/v1",
            "https://pilot.reefstore.app?x=1",
            "https://pilot reefstore.app",
            "https://.reefstore.app",
            "https://pilot.reefstore.app:80a",
        ] {
            assert!(!is_valid_relay(bad), "{bad:?}");
        }
        assert!(is_non_production_relay(
            "https://shipwright-pilot-relay-staging.someone.workers.dev"
        ));
        assert!(is_non_production_relay("https://pilot.shipwright.example"));
        assert!(is_non_production_relay(
            "https://pilot-staging.reefstore.app"
        ));
        assert!(!is_non_production_relay("https://pilot.reefstore.app"));
    }

    #[test]
    fn allowed_regions_are_config() {
        let eu_only = Config::parse(
            "[backends.standard.jev]\nkind = \"jev\"\nurl = \"https://a\"\n\
             [backends.standard.llm]\nurl = \"https://b\"\nallowed_regions = [\"eu\"]\n",
        )
        .unwrap();
        assert_eq!(eu_only.backends["standard"].llm.allowed_regions, ["eu"]);
        assert!(Config::parse(
            "[backends.standard.jev]\nkind = \"jev\"\nurl = \"https://a\"\n\
             [backends.standard.llm]\nurl = \"https://b\"\nallowed_regions = []\n",
        )
        .is_err());
    }
}
