//! Gmail and Outlook sign-in: OAuth 2 with PKCE through the browser and a
//! loopback redirect, then access tokens from the stored refresh token.
//! The client ids are the build's (or the environment's); without one the
//! provider is not offered.

use std::collections::HashMap;
use std::io::Read as _;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock, Mutex, PoisonError};
use std::time::{Duration, Instant};

use oauth2::basic::BasicClient;
use oauth2::url::Url;
use oauth2::{AuthUrl, AuthorizationCode, ClientId, CsrfToken, PkceCodeChallenge, RedirectUrl, RefreshToken, Scope, TokenResponse, TokenUrl};

use crate::store::{Account, Server};

pub struct Provider {
    pub id: &'static str,
    client_env: &'static str,
    client_default: Option<&'static str>,
    auth: &'static str,
    token: &'static str,
    userinfo: &'static str,
    scopes: &'static [&'static str],
    imap: (&'static str, u16, u8),
    smtp: (&'static str, u16, u8),
}

const PROVIDERS: [Provider; 2] = [
    Provider {
        id: "gmail",
        client_env: "MARATHON_OAUTH_GOOGLE_CLIENT_ID",
        client_default: option_env!("MARATHON_DEFAULT_GOOGLE_CLIENT_ID"),
        auth: "https://accounts.google.com/o/oauth2/v2/auth",
        token: "https://oauth2.googleapis.com/token",
        userinfo: "https://www.googleapis.com/oauth2/v3/userinfo",
        scopes: &["https://mail.google.com/", "https://www.googleapis.com/auth/userinfo.email"],
        imap: ("imap.gmail.com", 993, 1),
        smtp: ("smtp.gmail.com", 465, 1),
    },
    Provider {
        id: "outlook",
        client_env: "MARATHON_OAUTH_MICROSOFT_CLIENT_ID",
        client_default: option_env!("MARATHON_DEFAULT_MICROSOFT_CLIENT_ID"),
        auth: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
        token: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
        userinfo: "https://graph.microsoft.com/v1.0/me",
        scopes: &["offline_access", "https://outlook.office.com/IMAP.AccessAsUser.All", "https://outlook.office.com/SMTP.Send", "User.Read"],
        imap: ("outlook.office365.com", 993, 1),
        smtp: ("smtp.office365.com", 587, 2),
    },
];

pub fn provider(name: &str) -> Option<&'static Provider> {
    let id = match name.to_ascii_lowercase().as_str() {
        "gmail" | "google" => "gmail",
        "outlook" | "microsoft" => "outlook",
        _ => return None,
    };
    PROVIDERS.iter().find(|p| p.id == id)
}

impl Provider {
    fn client_id(&self) -> Option<String> {
        std::env::var(self.client_env).ok().filter(|v| !v.is_empty()).or_else(|| self.client_default.filter(|v| !v.is_empty()).map(str::to_owned))
    }
}

/// The providers this build can sign in to.
pub fn configured() -> Vec<String> {
    PROVIDERS.iter().filter(|p| p.client_id().is_some()).map(|p| p.id.to_owned()).collect()
}

fn http(request: oauth2::HttpRequest) -> Result<oauth2::HttpResponse, ureq::Error> {
    let agent = ureq::Agent::config_builder().http_status_as_error(false).build().new_agent();
    let (parts, mut body) = agent.run(request)?.into_parts();
    Ok(oauth2::HttpResponse::from_parts(parts, body.read_to_vec()?))
}

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

static TOKENS: LazyLock<Mutex<HashMap<i64, (String, Instant)>>> = LazyLock::new(Mutex::default);

/// A fresh access token from the refresh token, kept until it expires.
pub async fn access_token(provider: &str, account: i64, refresh: &str) -> Result<String, String> {
    if let Some((token, until)) = TOKENS.lock().unwrap_or_else(PoisonError::into_inner).get(&account) {
        if *until > Instant::now() {
            return Ok(token.clone());
        }
    }
    let p = self::provider(provider).ok_or("unknown provider")?;
    let id = p.client_id().ok_or("oauth_not_configured")?;
    let refresh = refresh.to_owned();
    let (token, lasts) = blocking::unblock(move || {
        let client = BasicClient::new(ClientId::new(id)).set_token_uri(TokenUrl::new(p.token.to_owned()).map_err(err)?);
        let reply = client.exchange_refresh_token(&RefreshToken::new(refresh)).request(&http).map_err(err)?;
        Ok::<_, String>((reply.access_token().secret().clone(), reply.expires_in().unwrap_or(Duration::from_mins(30))))
    })
    .await?;
    let until = Instant::now() + lasts.saturating_sub(Duration::from_secs(120));
    TOKENS.lock().unwrap_or_else(PoisonError::into_inner).insert(account, (token.clone(), until));
    Ok(token)
}

pub struct SignIn {
    pub account: Account,
    pub refresh: String,
}

/// The browser flow: `url` gets the page to open; the redirect comes back
/// to a loopback listener. `cancelled` stops the wait.
pub fn sign_in(p: &'static Provider, url: impl FnOnce(String), cancelled: &Arc<AtomicBool>) -> Result<SignIn, (&'static str, String)> {
    let id = p.client_id().ok_or_else(|| ("oauth_not_configured", format!("{} sign-in is not set up in this build", p.id)))?;
    let server = tiny_http::Server::http("127.0.0.1:0").map_err(|e| ("server", e.to_string()))?;
    let port = server.server_addr().to_ip().map_or(0, |a| a.port());
    let redirect = format!("http://127.0.0.1:{port}/cb");
    let fail = |e: String| ("server", e);
    let client = BasicClient::new(ClientId::new(id))
        .set_auth_uri(AuthUrl::new(p.auth.to_owned()).map_err(|e| fail(e.to_string()))?)
        .set_token_uri(TokenUrl::new(p.token.to_owned()).map_err(|e| fail(e.to_string()))?)
        .set_redirect_uri(RedirectUrl::new(redirect).map_err(|e| fail(e.to_string()))?);
    let (challenge, verifier) = PkceCodeChallenge::new_random_sha256();
    let mut ask = client.authorize_url(CsrfToken::new_random).set_pkce_challenge(challenge);
    for scope in p.scopes {
        ask = ask.add_scope(Scope::new((*scope).to_owned()));
    }
    if p.id == "gmail" {
        ask = ask.add_extra_param("access_type", "offline").add_extra_param("prompt", "consent");
    }
    let (auth_url, csrf) = ask.url();
    url(auth_url.to_string());
    let request = loop {
        if cancelled.load(Ordering::Relaxed) {
            return Err(("cancelled", "Sign-in cancelled".into()));
        }
        if let Ok(Some(r)) = server.recv_timeout(Duration::from_millis(500)) {
            break r;
        }
    };
    let query: HashMap<String, String> = Url::parse(&format!("http://localhost{}", request.url())).map(|u| u.query_pairs().into_owned().collect()).unwrap_or_default();
    request.respond(tiny_http::Response::from_string("Marathon Mail is signed in. You can close this page.")).ok();
    if query.get("state") != Some(csrf.secret()) {
        return Err(("server", "The sign-in answer did not match its request".into()));
    }
    let code = query.get("code").ok_or_else(|| ("cancelled", "Sign-in was not allowed".to_owned()))?;
    let reply = client.exchange_code(AuthorizationCode::new(code.clone())).set_pkce_verifier(verifier).request(&http).map_err(|e| ("server", e.to_string()))?;
    let refresh = reply.refresh_token().ok_or_else(|| ("server", "The provider gave no refresh token".to_owned()))?.secret().clone();
    let address = email(p, reply.access_token().secret()).unwrap_or_default();
    let server = |(host, port, security): (&str, u16, u8)| Server { host: host.to_owned(), port, security };
    let account = Account { id: 0, name: address.clone(), address: address.clone(), username: address, imap: server(p.imap), smtp: server(p.smtp), provider: p.id.to_owned() };
    Ok(SignIn { account, refresh })
}

fn email(p: &Provider, access: &str) -> Option<String> {
    let mut reply = ureq::get(p.userinfo).header("Authorization", &format!("Bearer {access}")).call().ok()?;
    let mut body = String::new();
    reply.body_mut().as_reader().read_to_string(&mut body).ok()?;
    let json: serde_json::Value = serde_json::from_str(&body).ok()?;
    ["email", "mail", "userPrincipalName"].iter().find_map(|k| json[k].as_str().map(str::to_owned))
}
