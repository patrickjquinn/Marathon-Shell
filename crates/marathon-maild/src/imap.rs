//! IMAP (async-imap): signing in, the folder list, a folder's newest
//! messages into the store, flags and moves.

use std::collections::HashMap;
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::{Arc, LazyLock};
use std::time::Duration;

use async_imap::types::{Flag, NameAttribute};
use async_imap::{Client, Session};
use async_io::Async;
use futures_lite::{AsyncReadExt, AsyncWriteExt, StreamExt};
use futures_rustls::client::TlsStream;
use futures_rustls::rustls::pki_types::ServerName;
use futures_rustls::rustls::{ClientConfig, RootCertStore};
use futures_rustls::TlsConnector;
use futures_util::future::Either;
use marathon_rt::daemon::Shared;

use crate::store::{self, Account, Server, Store};

pub type Stream = Either<Async<TcpStream>, TlsStream<Async<TcpStream>>>;
pub type Imap = Session<Stream>;

/// The newest messages of a folder the phone keeps.
const WINDOW: u32 = 200;
/// Larger messages keep only their headers until opened.
const WHOLE_BELOW: u32 = 8 << 20;

/// Why a connection failed, as `MailService`'s signals name it.
#[derive(Debug)]
pub enum Failure {
    Offline(String),
    Certificate(String),
    Login(String),
    Server(String),
}

impl Failure {
    pub fn reason(&self) -> &'static str {
        match self {
            Self::Offline(_) => "offline",
            Self::Certificate(_) => "certificate",
            Self::Login(_) => "login",
            Self::Server(_) => "server",
        }
    }

    pub fn message(&self) -> &str {
        match self {
            Self::Offline(m) | Self::Certificate(m) | Self::Login(m) | Self::Server(m) => m,
        }
    }
}

impl From<async_imap::error::Error> for Failure {
    fn from(e: async_imap::error::Error) -> Self {
        match e {
            async_imap::error::Error::Io(e) => Self::Offline(e.to_string()),
            other => Self::Server(other.to_string()),
        }
    }
}

impl From<std::io::Error> for Failure {
    fn from(e: std::io::Error) -> Self {
        if e.get_ref()
            .is_some_and(|inner| inner.to_string().contains("certificate"))
        {
            Self::Certificate(e.to_string())
        } else {
            Self::Offline(e.to_string())
        }
    }
}

fn tls() -> TlsConnector {
    static CONFIG: LazyLock<Arc<ClientConfig>> = LazyLock::new(|| {
        let roots = RootCertStore {
            roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
        };
        Arc::new(
            ClientConfig::builder()
                .with_root_certificates(roots)
                .with_no_client_auth(),
        )
    });
    TlsConnector::from(Arc::clone(&CONFIG))
}

async fn tcp(host: &str, port: u16) -> Result<Async<TcpStream>, Failure> {
    let target = format!("{host}:{port}");
    let addrs: Vec<_> =
        blocking::unblock(move || target.to_socket_addrs().map(Iterator::collect)).await?;
    let mut last = Failure::Offline(format!("{host} has no address"));
    for addr in addrs {
        match marathon_rt::io::timeout(Duration::from_secs(15), Async::<TcpStream>::connect(addr))
            .await
        {
            Some(Ok(s)) => return Ok(s),
            Some(Err(e)) => last = e.into(),
            None => last = Failure::Offline(format!("{addr} did not answer")),
        }
    }
    Err(last)
}

async fn wrap(host: &str, plain: Async<TcpStream>) -> Result<Stream, Failure> {
    let name = ServerName::try_from(host.to_owned()).map_err(|e| Failure::Server(e.to_string()))?;
    Ok(Either::Right(tls().connect(name, plain).await?))
}

/// One line from the server, before TLS.
async fn line(s: &mut Async<TcpStream>) -> Result<String, Failure> {
    let mut out = Vec::new();
    let mut byte = [0u8];
    while out.last() != Some(&b'\n') {
        if s.read(&mut byte).await? == 0 {
            return Err(Failure::Offline("the server closed the connection".into()));
        }
        out.push(byte[0]);
    }
    Ok(String::from_utf8_lossy(&out).into_owned())
}

/// A connection, encrypted as the account says: from the start (1) or
/// after STARTTLS (2) for IMAP; SMTP's are lettre's.
pub async fn connect(server: &Server) -> Result<Client<Stream>, Failure> {
    let mut plain = tcp(&server.host, server.port).await?;
    let stream = match server.security {
        1 => wrap(&server.host, plain).await?,
        2 => {
            line(&mut plain).await?;
            plain.write_all(b"a0 STARTTLS\r\n").await?;
            loop {
                let reply = line(&mut plain).await?;
                if let Some(status) = reply.strip_prefix("a0 ") {
                    if !status.starts_with("OK") {
                        return Err(Failure::Server(format!(
                            "STARTTLS refused: {}",
                            reply.trim()
                        )));
                    }
                    break;
                }
            }
            let client = Client::new(wrap(&server.host, plain).await?);
            return Ok(client);
        }
        _ => Either::Left(plain),
    };
    let mut client = Client::new(stream);
    client.read_response().await?;
    Ok(client)
}

struct XOAuth2(String);

impl async_imap::Authenticator for XOAuth2 {
    type Response = String;
    fn process(&mut self, _: &[u8]) -> String {
        self.0.clone()
    }
}

/// `user=… auth=Bearer …`, XOAUTH2's initial response for IMAP and SMTP.
pub fn xoauth2(user: &str, token: &str) -> String {
    format!("user={user}\x01auth=Bearer {token}\x01\x01")
}

/// Signed in with the account's password or OAuth token.
pub async fn session(account: &Account) -> Result<Imap, Failure> {
    let client = connect(&account.imap).await?;
    let secret = crate::secrets::credential(account)
        .await
        .map_err(Failure::Login)?;
    let signed = if account.provider.is_empty() {
        client.login(&account.username, &secret).await
    } else {
        client
            .authenticate("XOAUTH2", XOAuth2(xoauth2(&account.username, &secret)))
            .await
    };
    signed.map_err(|(e, _)| Failure::Login(e.to_string()))
}

/// The server's folders into the store.
pub async fn folders(s: &mut Imap, store: &Shared<Store>, account: i64) -> Result<(), Failure> {
    let mut found = Vec::new();
    {
        let mut names = s.list(Some(""), Some("*")).await?;
        while let Some(name) = names.next().await {
            let name = name?;
            let attrs = name.attributes();
            if attrs.iter().any(|a| matches!(a, NameAttribute::NoSelect)) {
                continue;
            }
            let special = attrs.iter().find_map(|a| match a {
                NameAttribute::Sent => Some("\\Sent"),
                NameAttribute::Drafts => Some("\\Drafts"),
                NameAttribute::Trash => Some("\\Trash"),
                NameAttribute::Junk => Some("\\Junk"),
                NameAttribute::Archive => Some("\\Archive"),
                NameAttribute::All => Some("\\All"),
                _ => None,
            });
            found.push((name.name().to_owned(), store::kind(name.name(), special)));
        }
    }
    store
        .with(move |st| st.set_folders(account, &found))
        .await
        .map_err(|e| Failure::Server(e.to_string()))
}

/// The folder's newest messages into the store; the ids of those new to
/// the phone and unread.
pub async fn sync(
    s: &mut Imap,
    store: &Shared<Store>,
    account: i64,
    folder: &str,
) -> Result<Vec<i64>, Failure> {
    let mailbox = s.select(folder).await?;
    let validity = mailbox.uid_validity.unwrap_or(0);
    let path = folder.to_owned();
    let failed = |e: rusqlite::Error| Failure::Server(e.to_string());
    store
        .with(move |st| st.validate(account, &path, validity))
        .await
        .map_err(failed)?;
    let mut server: HashMap<u32, (bool, u32)> = HashMap::new();
    if mailbox.exists > 0 {
        let from = mailbox.exists.saturating_sub(WINDOW - 1).max(1);
        let mut fetches = s
            .fetch(format!("{from}:*"), "(UID FLAGS RFC822.SIZE)")
            .await?;
        while let Some(f) = fetches.next().await {
            let f = f?;
            if let Some(uid) = f.uid {
                server.insert(
                    uid,
                    (
                        f.flags().any(|x| matches!(x, Flag::Seen)),
                        f.size.unwrap_or(0),
                    ),
                );
            }
        }
    }
    let seen: HashMap<u32, bool> = server.iter().map(|(u, (s, _))| (*u, *s)).collect();
    let path = folder.to_owned();
    let known = store
        .with(move |st| {
            st.reconcile(account, &path, &seen)?;
            st.uids(account, &path)
        })
        .await
        .map_err(failed)?;
    // A folder's first sync brings its mail in; none of it is news.
    let primed = !known.is_empty();
    let mut added = Vec::new();
    let new: Vec<(u32, bool, u32)> = server
        .iter()
        .filter(|(u, _)| !known.contains_key(u))
        .map(|(u, (s, z))| (*u, *s, *z))
        .collect();
    for whole in [true, false] {
        let set: Vec<String> = new
            .iter()
            .filter(|(_, _, size)| (*size < WHOLE_BELOW) == whole)
            .map(|(u, _, _)| u.to_string())
            .collect();
        if set.is_empty() {
            continue;
        }
        let item = if whole {
            "(UID FLAGS BODY.PEEK[])"
        } else {
            "(UID FLAGS BODY.PEEK[HEADER])"
        };
        let mut got = Vec::new();
        {
            let mut fetches = s.uid_fetch(set.join(","), item).await?;
            while let Some(f) = fetches.next().await {
                let f = f?;
                let raw = f.body().or_else(|| f.header()).unwrap_or_default().to_vec();
                if let Some(uid) = f.uid {
                    got.push((uid, f.flags().any(|x| matches!(x, Flag::Seen)), raw));
                }
            }
        }
        let path = folder.to_owned();
        let ids = store
            .with(move |st| {
                let mut ids = Vec::new();
                for (uid, seen, raw) in got {
                    if let Some(id) = st.insert(account, &path, uid, seen, &raw)? {
                        if !seen {
                            ids.push(id);
                        }
                    }
                }
                Ok::<_, rusqlite::Error>(ids)
            })
            .await
            .map_err(failed)?;
        added.extend(ids);
    }
    let unread = u32::try_from(s.uid_search("UNSEEN").await?.len()).unwrap_or(u32::MAX);
    let path = folder.to_owned();
    let total = mailbox.exists;
    store
        .with(move |st| st.set_counts(account, &path, unread, total))
        .await
        .map_err(failed)?;
    Ok(if primed { added } else { Vec::new() })
}

/// The whole message, for one kept only by its headers.
pub async fn whole(s: &mut Imap, folder: &str, uid: u32) -> Result<Vec<u8>, Failure> {
    s.select(folder).await?;
    let mut fetches = s.uid_fetch(uid.to_string(), "(UID BODY.PEEK[])").await?;
    let mut raw = Vec::new();
    while let Some(f) = fetches.next().await {
        raw = f?.body().unwrap_or_default().to_vec();
    }
    Ok(raw)
}

pub async fn set_seen(s: &mut Imap, folder: &str, uid: u32, seen: bool) -> Result<(), Failure> {
    s.select(folder).await?;
    let change = if seen {
        "+FLAGS (\\Seen)"
    } else {
        "-FLAGS (\\Seen)"
    };
    s.uid_store(uid.to_string(), change)
        .await?
        .collect::<Vec<_>>()
        .await;
    Ok(())
}

/// MOVE where the server has it, else COPY then expunge.
pub async fn move_to(s: &mut Imap, folder: &str, uid: u32, to: &str) -> Result<(), Failure> {
    s.select(folder).await?;
    let caps = s.capabilities().await?;
    if caps.has_str("MOVE") {
        s.uid_mv(uid.to_string(), to).await?;
    } else {
        s.uid_copy(uid.to_string(), to).await?;
        s.uid_store(uid.to_string(), "+FLAGS (\\Deleted)")
            .await?
            .collect::<Vec<_>>()
            .await;
        s.expunge().await?.collect::<Vec<_>>().await;
    }
    Ok(())
}

pub async fn append(s: &mut Imap, folder: &str, raw: &[u8]) -> Result<(), Failure> {
    Ok(s.append(folder, Some("(\\Seen)"), None, raw).await?)
}
