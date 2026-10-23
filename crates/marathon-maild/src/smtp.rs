//! SMTP (lettre): composing a message and sending it.

use lettre::address::Envelope;
use lettre::message::header::ContentType;
use lettre::message::{Attachment, Mailbox, MultiPart, SinglePart};
use lettre::transport::smtp::authentication::{Credentials, Mechanism};
use lettre::{Address, Message, SmtpTransport, Transport};

use crate::store::Account;

fn mailboxes(list: &str) -> Result<Vec<Mailbox>, String> {
    list.split([',', ';'])
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| s.parse::<Mailbox>().map_err(|e| format!("{s}: {e}")))
        .collect()
}

pub struct Draft<'a> {
    pub to: &'a str,
    pub cc: &'a str,
    pub bcc: &'a str,
    pub subject: &'a str,
    pub body: &'a str,
    /// Name, MIME type and bytes.
    pub attachments: Vec<(String, String, Vec<u8>)>,
}

/// The message as sent and its envelope's recipients; Err names a bad
/// address.
pub fn compose(account: &Account, d: Draft<'_>) -> Result<(Vec<u8>, String), String> {
    let from: Mailbox = format!("{} <{}>", account.name, account.address)
        .parse()
        .or_else(|_: lettre::address::AddressError| account.address.parse())
        .map_err(|e| format!("{}: {e}", account.address))?;
    let mut b = Message::builder().from(from).subject(d.subject);
    for m in mailboxes(d.to)? {
        b = b.to(m);
    }
    for m in mailboxes(d.cc)? {
        b = b.cc(m);
    }
    for m in mailboxes(d.bcc)? {
        b = b.bcc(m);
    }
    let text = SinglePart::plain(d.body.to_owned());
    let message = if d.attachments.is_empty() {
        b.singlepart(text)
    } else {
        let mut parts = MultiPart::mixed().singlepart(text);
        for (name, mime, bytes) in d.attachments {
            let kind = ContentType::parse(&mime).unwrap_or(ContentType::TEXT_PLAIN);
            parts = parts.singlepart(Attachment::new(name).body(bytes, kind));
        }
        b.multipart(parts)
    }
    .map_err(|e| e.to_string())?;
    let recipients = message
        .envelope()
        .to()
        .iter()
        .map(Address::to_string)
        .collect::<Vec<_>>()
        .join(",");
    Ok((message.formatted(), recipients))
}

/// Why a send failed: offline, login, certificate, address or server.
fn reason(e: &lettre::transport::smtp::Error) -> &'static str {
    let code = e.status().map(|c| c.to_string()).unwrap_or_default();
    if e.is_tls() {
        "certificate"
    } else if code.starts_with("535") || code.starts_with("534") {
        "login"
    } else if code.starts_with("55") {
        "address"
    } else if e.is_response() {
        "server"
    } else {
        "offline"
    }
}

pub fn send(
    account: &Account,
    credential: &str,
    raw: &[u8],
    recipients: &str,
) -> Result<(), &'static str> {
    let s = &account.smtp;
    let builder = match s.security {
        1 => SmtpTransport::relay(&s.host),
        2 => SmtpTransport::starttls_relay(&s.host),
        _ => Ok(SmtpTransport::builder_dangerous(&s.host)),
    }
    .map_err(|e| {
        marathon_rt::log::warn("Mail", format_args!("SMTP {}: {e}", s.host));
        "server"
    })?;
    let mechanisms = if account.provider.is_empty() {
        vec![Mechanism::Plain, Mechanism::Login]
    } else {
        vec![Mechanism::Xoauth2]
    };
    let transport = builder
        .port(s.port)
        .credentials(Credentials::new(
            account.username.clone(),
            credential.to_owned(),
        ))
        .authentication(mechanisms)
        .build();
    let to: Vec<Address> = recipients
        .split(',')
        .filter_map(|a| a.parse().ok())
        .collect();
    let envelope = Envelope::new(account.address.parse().ok(), to).map_err(|e| {
        marathon_rt::log::warn("Mail", format_args!("envelope: {e}"));
        "address"
    })?;
    transport
        .send_raw(&envelope, raw)
        .map(drop)
        .map_err(|e| reason(&e))
}
