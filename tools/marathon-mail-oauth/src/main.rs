//! marathon-mail-oauth — OAuth2 + Secret-Service helper for QMF.
//!
//! QMF's IMAP/SMTP plugins authenticate via SASL. For Gmail/Outlook we
//! need XOAUTH2 access tokens, which means a real OAuth2 PKCE flow + a
//! refresh-token cache + a way to mint fresh access tokens on demand.
//!
//! This binary handles all of that and exposes two subcommands the QMF
//! XOAUTH2 SASL plugin invokes as a subprocess:
//!
//!   marathon-mail-oauth add    --provider gmail|outlook --account-id <id>
//!     → opens a loopback browser flow, exchanges code → tokens,
//!       stores refresh token via Secret-Service, prints account_id.
//!
//!   marathon-mail-oauth token  --account-id <id>
//!     → reads the stored refresh token, exchanges for a fresh access
//!       token, prints the access token on stdout (JSON envelope).
//!       Refresh-token rotation is handled automatically.
//!
//! Why a separate binary instead of an in-process Rust shared lib:
//!   • Crash isolation — a panic here doesn't take messageserver down.
//!   • Sandbox simplicity — bwrap can give this binary `network` +
//!     `org.freedesktop.secrets` D-Bus and nothing else.
//!   • Marathon coding rule: lazy-construct heavy clients permission-
//!     gated, not at main() init. A subprocess is the natural shape.
//!
//! No placeholder data: if the user hasn't added an account, `token`
//! returns a structured "no account" error (non-zero exit + JSON body).
//! QMF surfaces that to MailService.syncState = "error" rather than
//! pretending mail is loading.

use anyhow::{anyhow, Context, Result};
use clap::{Parser, Subcommand};
use oauth2::basic::BasicClient;
use oauth2::{
    AuthUrl, AuthorizationCode, ClientId, ClientSecret, CsrfToken, PkceCodeChallenge,
    RedirectUrl, RefreshToken, Scope, TokenResponse, TokenUrl,
};
use secret_service::{EncryptionType, SecretService};
use serde::Serialize;
use std::io::Write;
use std::net::TcpListener;
use std::time::SystemTime;
use url::Url;

// ── Provider definitions ──────────────────────────────────────────────
//
// OAuth2 endpoints come from Google's and Microsoft's public installed-
// app docs. The client_id is NOT a secret for the installed-app flow
// (PKCE replaces the secret).
//
// Client IDs are read at runtime from environment variables so the
// shipping binary can be customised per distribution / channel without
// rebuilding. The production image's marathon-mail-oauth.service sets:
//
//   Environment=MARATHON_OAUTH_GOOGLE_CLIENT_ID=<your-google-id>
//   Environment=MARATHON_OAUTH_MICROSOFT_CLIENT_ID=<your-ms-id>
//
// See docs/MAIL_OAUTH_REGISTRATION.md for how to obtain them from
// Google Cloud Console + Microsoft Azure Portal. If either env var is
// unset (or the placeholder OWN_BEFORE_SHIP… is still present), the
// helper exits with a structured `error` envelope instead of attempting
// a guaranteed-to-fail OAuth flow.

const GOOGLE_AUTH_URL:  &str = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
const GOOGLE_SCOPES:    &[&str] = &[
    "https://mail.google.com/",
    "https://www.googleapis.com/auth/userinfo.email",
];

const MS_AUTH_URL:  &str = "https://login.microsoftonline.com/common/oauth2/v2.0/authorize";
const MS_TOKEN_URL: &str = "https://login.microsoftonline.com/common/oauth2/v2.0/token";
const MS_SCOPES:    &[&str] = &[
    "offline_access",
    "https://outlook.office.com/IMAP.AccessAsUser.All",
    "https://outlook.office.com/SMTP.Send",
    "User.Read",
];

fn resolve_client_id(provider: Provider) -> Result<String> {
    let var = match provider {
        Provider::Gmail   => "MARATHON_OAUTH_GOOGLE_CLIENT_ID",
        Provider::Outlook => "MARATHON_OAUTH_MICROSOFT_CLIENT_ID",
    };
    let raw = std::env::var(var).map_err(|_| {
        anyhow!("{var} not set — see docs/MAIL_OAUTH_REGISTRATION.md to obtain a client id")
    })?;
    if raw.starts_with("OWN_BEFORE_SHIP") || raw.is_empty() {
        return Err(anyhow!(
            "{var} is still the placeholder — register a real client id per \
             docs/MAIL_OAUTH_REGISTRATION.md"
        ));
    }
    Ok(raw)
}

#[derive(Clone, Copy, Debug)]
enum Provider {
    Gmail,
    Outlook,
}

impl std::str::FromStr for Provider {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self> {
        match s.to_ascii_lowercase().as_str() {
            "gmail" | "google"            => Ok(Provider::Gmail),
            "outlook" | "microsoft" | "ms" => Ok(Provider::Outlook),
            _ => Err(anyhow!("unknown provider {s:?}; expected gmail | outlook")),
        }
    }
}

impl Provider {
    fn auth_url(self) -> &'static str {
        match self { Provider::Gmail => GOOGLE_AUTH_URL, Provider::Outlook => MS_AUTH_URL }
    }
    fn token_url(self) -> &'static str {
        match self { Provider::Gmail => GOOGLE_TOKEN_URL, Provider::Outlook => MS_TOKEN_URL }
    }
    fn scopes(self) -> &'static [&'static str] {
        match self { Provider::Gmail => GOOGLE_SCOPES, Provider::Outlook => MS_SCOPES }
    }
    fn id(self) -> &'static str {
        match self { Provider::Gmail => "gmail", Provider::Outlook => "outlook" }
    }
}

// ── CLI ───────────────────────────────────────────────────────────────

#[derive(Parser)]
#[command(version, about = "Marathon Mail OAuth helper", long_about = None)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Run the loopback PKCE flow, store the refresh token, print a
    /// machine-readable account record on stdout.
    Add {
        #[arg(long)]
        provider: Provider,
        /// Logical id for this account. Used as the Secret-Service item
        /// label and the QMF account configuration handle.
        #[arg(long)]
        account_id: String,
    },
    /// Print a fresh access token for an existing account (JSON envelope
    /// on stdout, non-zero exit on error).
    Token {
        #[arg(long)]
        account_id: String,
    },
    /// Store username + password for a classic IMAP/SMTP account. Password
    /// is read from stdin (so it never appears in a process listing).
    /// Used by MailService.addImapAccount for Fastmail / iCloud / self-
    /// hosted IMAP — the auth method MarathonAccountSetupPage exposes.
    ClassicAdd {
        #[arg(long)]
        account_id: String,
        #[arg(long)]
        username: String,
    },
    /// Print the stored username + password for a classic account on
    /// stdout (JSON envelope). Called by the marathonclassic QMF
    /// credentials plugin on every IMAP/SMTP authentication attempt.
    ClassicGet {
        #[arg(long)]
        account_id: String,
    },
    /// Forget an account — wipes its secret. Works for both OAuth and
    /// classic-password entries (same account_id, separate namespaces).
    Remove {
        #[arg(long)]
        account_id: String,
    },
}

// ── JSON envelope for IPC with the SASL plugin ────────────────────────

#[derive(Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum Reply<'a> {
    AccessToken { access_token: &'a str, expires_in_secs: u64, email: Option<&'a str> },
    Password    { username: &'a str, password: &'a str },
    Added       { account_id: &'a str, provider: &'a str, email: Option<&'a str> },
    ClassicAdded { account_id: &'a str, username: &'a str },
    Removed     { account_id: &'a str },
    Error       { code: &'a str, message: String },
}

fn emit<T: Serialize>(value: &T) {
    let s = serde_json::to_string(value).unwrap_or_default();
    let mut out = std::io::stdout().lock();
    let _ = out.write_all(s.as_bytes());
    let _ = out.write_all(b"\n");
}

fn fail(code: &str, message: impl Into<String>) -> ! {
    emit(&Reply::Error { code, message: message.into() });
    std::process::exit(1);
}

// ── Secret-Service bridge ─────────────────────────────────────────────
//
// Items are stored under the collection "default" with attributes:
//   { service: "marathon-mail-oauth",
//     account_id: <id>,
//     provider:   "gmail" | "outlook" }
// The secret payload is the OAuth refresh token verbatim (UTF-8 string,
// no JSON wrapping — we store ONLY the refresh token; access tokens are
// re-minted per call).

async fn ss_store_refresh(account_id: &str, provider: Provider, refresh: &str) -> Result<()> {
    let ss = SecretService::connect(EncryptionType::Dh).await
        .context("connecting to org.freedesktop.secrets")?;
    let coll = ss.get_default_collection().await
        .context("opening default Secret-Service collection")?;
    if coll.is_locked().await.unwrap_or(false) {
        coll.unlock().await.context("unlocking Secret-Service collection")?;
    }
    let attrs: std::collections::HashMap<&str, &str> = [
        ("service",    "marathon-mail-oauth"),
        ("account_id", account_id),
        ("provider",   provider.id()),
    ].into_iter().collect();
    coll.create_item(
        &format!("Marathon Mail · {account_id}"),
        attrs,
        refresh.as_bytes(),
        true,   // replace_existing
        "text/plain",
    ).await.context("writing refresh token to Secret-Service")?;
    Ok(())
}

async fn ss_load_refresh(account_id: &str) -> Result<(Provider, String)> {
    let ss = SecretService::connect(EncryptionType::Dh).await
        .context("connecting to org.freedesktop.secrets")?;
    let attrs: std::collections::HashMap<&str, &str> = [
        ("service",    "marathon-mail-oauth"),
        ("account_id", account_id),
    ].into_iter().collect();
    let items = ss.search_items(attrs).await
        .context("searching Secret-Service for account")?;
    let item = items.unlocked.into_iter().chain(items.locked).next()
        .ok_or_else(|| anyhow!("no account named {account_id:?}"))?;
    if item.is_locked().await.unwrap_or(false) {
        item.unlock().await.context("unlocking secret item")?;
    }
    let attrs = item.get_attributes().await.unwrap_or_default();
    let provider: Provider = attrs.get("provider")
        .ok_or_else(|| anyhow!("stored item missing provider attribute"))?
        .parse()?;
    let bytes = item.get_secret().await.context("reading secret payload")?;
    let refresh = String::from_utf8(bytes).context("refresh token is not UTF-8")?;
    Ok((provider, refresh))
}

async fn ss_remove(account_id: &str) -> Result<()> {
    // Wipe BOTH namespaces so a Remove on an account_id that switched auth
    // method (rare but possible) doesn't leave a dangling stale secret.
    let ss = SecretService::connect(EncryptionType::Dh).await
        .context("connecting to org.freedesktop.secrets")?;
    for service in ["marathon-mail-oauth", "marathon-mail-classic"] {
        let attrs: std::collections::HashMap<&str, &str> = [
            ("service",    service),
            ("account_id", account_id),
        ].into_iter().collect();
        let items = ss.search_items(attrs).await?;
        for item in items.unlocked.into_iter().chain(items.locked) {
            let _ = item.delete().await;
        }
    }
    Ok(())
}

// Classic-password storage. Username lives in the item attributes (not
// secret); password is the secret payload. Separate namespace from OAuth
// to avoid the attribute search picking up the wrong item kind.

async fn ss_store_classic(account_id: &str, username: &str, password: &str) -> Result<()> {
    let ss = SecretService::connect(EncryptionType::Dh).await
        .context("connecting to org.freedesktop.secrets")?;
    let coll = ss.get_default_collection().await
        .context("opening default Secret-Service collection")?;
    if coll.is_locked().await.unwrap_or(false) {
        coll.unlock().await.context("unlocking Secret-Service collection")?;
    }
    let attrs: std::collections::HashMap<&str, &str> = [
        ("service",    "marathon-mail-classic"),
        ("account_id", account_id),
        ("username",   username),
    ].into_iter().collect();
    coll.create_item(
        &format!("Marathon Mail · {account_id} (IMAP)"),
        attrs,
        password.as_bytes(),
        true,   // replace_existing
        "text/plain",
    ).await.context("writing classic credentials to Secret-Service")?;
    Ok(())
}

async fn ss_load_classic(account_id: &str) -> Result<(String, String)> {
    let ss = SecretService::connect(EncryptionType::Dh).await
        .context("connecting to org.freedesktop.secrets")?;
    let attrs: std::collections::HashMap<&str, &str> = [
        ("service",    "marathon-mail-classic"),
        ("account_id", account_id),
    ].into_iter().collect();
    let items = ss.search_items(attrs).await
        .context("searching Secret-Service for classic account")?;
    let item = items.unlocked.into_iter().chain(items.locked).next()
        .ok_or_else(|| anyhow!("no classic-password account named {account_id:?}"))?;
    if item.is_locked().await.unwrap_or(false) {
        item.unlock().await.context("unlocking secret item")?;
    }
    let attrs = item.get_attributes().await.unwrap_or_default();
    let username = attrs.get("username")
        .ok_or_else(|| anyhow!("stored item missing username attribute"))?
        .clone();
    let bytes = item.get_secret().await.context("reading secret payload")?;
    let password = String::from_utf8(bytes).context("password is not UTF-8")?;
    Ok((username, password))
}

// ── OAuth flows ───────────────────────────────────────────────────────

fn build_client(provider: Provider, redirect: &Url) -> Result<BasicClient> {
    let client_id = resolve_client_id(provider)?;
    Ok(BasicClient::new(
        ClientId::new(client_id),
        // No client_secret — installed apps use PKCE. For Microsoft's
        // common endpoint we technically *can* use an empty secret too.
        Some(ClientSecret::new(String::new())),
        AuthUrl::new(provider.auth_url().to_string())?,
        Some(TokenUrl::new(provider.token_url().to_string())?),
    )
    .set_redirect_uri(RedirectUrl::new(redirect.to_string())?))
}

async fn run_pkce_flow(provider: Provider) -> Result<(String /*refresh*/, Option<String> /*email*/)> {
    // Loopback server picks a random port so multiple Marathon
    // installs on one machine don't collide.
    let listener = TcpListener::bind("127.0.0.1:0").context("binding loopback port")?;
    let port = listener.local_addr()?.port();
    let redirect = Url::parse(&format!("http://127.0.0.1:{port}/cb"))?;
    let client = build_client(provider, &redirect)?;

    let (pkce_challenge, pkce_verifier) = PkceCodeChallenge::new_random_sha256();

    let (auth_url, csrf) = {
        let mut req = client.authorize_url(CsrfToken::new_random)
            .set_pkce_challenge(pkce_challenge);
        for scope in provider.scopes() {
            req = req.add_scope(Scope::new((*scope).to_string()));
        }
        // Google needs offline access + consent prompt to issue a
        // refresh token; Microsoft's offline_access scope handles its
        // side already.
        if matches!(provider, Provider::Gmail) {
            req = req.add_extra_param("access_type", "offline")
                     .add_extra_param("prompt",      "consent");
        }
        req.url()
    };

    eprintln!("Open this URL in your browser to authorise Marathon Mail:");
    eprintln!("{}", auth_url);

    // Accept exactly one inbound request — that's the redirect.
    let server = tiny_http::Server::from_listener(listener, None)
        .map_err(|e| anyhow!("tiny_http: {e}"))?;
    let request = server.recv().context("waiting for OAuth redirect")?;

    let url = format!("http://localhost{}", request.url());
    let parsed = Url::parse(&url).context("parsing redirect URL")?;
    let qs: std::collections::HashMap<_, _> = parsed.query_pairs().into_owned().collect();

    let code = qs.get("code").cloned()
        .ok_or_else(|| anyhow!("redirect missing `code` query param: {url}"))?;
    let state = qs.get("state").cloned()
        .ok_or_else(|| anyhow!("redirect missing `state` query param"))?;
    if state != *csrf.secret() {
        return Err(anyhow!("CSRF state mismatch — possible attack"));
    }

    let _ = request.respond(tiny_http::Response::from_string(
        "Marathon Mail authorised. You can close this tab."
    ));

    // Exchange the code for tokens. We use the blocking variant because
    // tiny_http's recv is also blocking; both happen on the runtime's
    // main thread.
    let token_res = client
        .exchange_code(AuthorizationCode::new(code))
        .set_pkce_verifier(pkce_verifier)
        .request_async(oauth2::reqwest::async_http_client)
        .await
        .map_err(|e| anyhow!("token exchange failed: {e}"))?;

    let refresh = token_res.refresh_token()
        .ok_or_else(|| anyhow!("provider returned no refresh_token — flow incomplete"))?
        .secret()
        .clone();

    // We don't bother decoding the id_token; for surfacing the email in
    // the UI we'll ask the provider's userinfo endpoint on first
    // successful access-token mint. Keep this function focused.
    Ok((refresh, None))
}

async fn mint_access_token(account_id: &str) -> Result<(String, u64, Option<String>)> {
    let (provider, refresh) = ss_load_refresh(account_id).await?;
    // No redirect needed for the refresh flow, but the BasicClient
    // type requires one. Use a dummy.
    let dummy = Url::parse("http://127.0.0.1/")?;
    let client = build_client(provider, &dummy)?;
    let resp = client
        .exchange_refresh_token(&RefreshToken::new(refresh.clone()))
        .request_async(oauth2::reqwest::async_http_client)
        .await
        .map_err(|e| anyhow!("refresh token exchange failed: {e}"))?;

    let access = resp.access_token().secret().clone();
    let expires_in = resp.expires_in()
        .map(|d| d.as_secs())
        .unwrap_or(3300);   // Google default is ~3600s; subtract margin

    // Refresh-token rotation: Microsoft rotates these, Google does not.
    // If a new refresh comes back, persist it so the next call uses it.
    if let Some(new_refresh) = resp.refresh_token() {
        if new_refresh.secret() != &refresh {
            ss_store_refresh(account_id, provider, new_refresh.secret()).await?;
        }
    }
    Ok((access, expires_in, None))
}

// ── Entrypoint ────────────────────────────────────────────────────────

fn main() {
    let cli = Cli::parse();

    // Permission gate. AppLaunchService sets MARATHON_PERM_SECRET_SERVICE=1
    // for apps whose manifest declares the `secret-service` permission.
    // We require it for every code path here (Add stores a refresh token,
    // Token reads one, Remove deletes one) — without it we refuse to touch
    // the keyring even though the session-bus socket is technically
    // reachable inside the sandbox. This is the policy enforcement point.
    if std::env::var("MARATHON_PERM_SECRET_SERVICE").as_deref() != Ok("1") {
        fail(
            "permission_denied",
            "MARATHON_PERM_SECRET_SERVICE not granted — \
             app manifest must declare \"secret-service\" permission",
        );
    }

    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("build tokio runtime");

    let result: Result<()> = rt.block_on(async move {
        match cli.cmd {
            Cmd::Add { provider, account_id } => {
                let (refresh, email) = run_pkce_flow(provider).await?;
                ss_store_refresh(&account_id, provider, &refresh).await?;
                emit(&Reply::Added {
                    account_id: &account_id,
                    provider:   provider.id(),
                    email:      email.as_deref(),
                });
                Ok(())
            }
            Cmd::Token { account_id } => {
                let (access, expires, email) = mint_access_token(&account_id).await?;
                emit(&Reply::AccessToken {
                    access_token:    &access,
                    expires_in_secs: expires,
                    email:           email.as_deref(),
                });
                // We exit cleanly even after stdout write; the SASL
                // plugin treats exit 0 + non-error JSON as success.
                let _ = SystemTime::now();
                Ok(())
            }
            Cmd::ClassicAdd { account_id, username } => {
                // Password from stdin (NOT a CLI arg) so it stays out of
                // /proc/<pid>/cmdline and any ps listing.
                let mut buf = String::new();
                std::io::stdin().read_line(&mut buf)
                    .context("reading password from stdin")?;
                let password = buf.trim_end_matches('\n').trim_end_matches('\r');
                if password.is_empty() {
                    return Err(anyhow!("empty password on stdin"));
                }
                ss_store_classic(&account_id, &username, password).await?;
                emit(&Reply::ClassicAdded {
                    account_id: &account_id,
                    username:   &username,
                });
                Ok(())
            }
            Cmd::ClassicGet { account_id } => {
                let (username, password) = ss_load_classic(&account_id).await?;
                emit(&Reply::Password {
                    username: &username,
                    password: &password,
                });
                Ok(())
            }
            Cmd::Remove { account_id } => {
                ss_remove(&account_id).await?;
                emit(&Reply::Removed { account_id: &account_id });
                Ok(())
            }
        }
    });

    if let Err(e) = result {
        // Walk the error chain so the SASL plugin sees the actual root
        // cause, not "an error occurred."
        let chain = e.chain().map(|c| c.to_string()).collect::<Vec<_>>().join(": ");
        fail("io", chain);
    }
}
