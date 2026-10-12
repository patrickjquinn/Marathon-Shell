.pragma library

// Encryption values per QMF's imap4/smtp plugins: 0 none, 1 SSL, 2 STARTTLS.
const presets = {
    "fastmail": { imapHost: "imap.fastmail.com", imapPort: 993, imapEnc: 1, smtpHost: "smtp.fastmail.com", smtpPort: 465, smtpEnc: 1 },
    "icloud": { imapHost: "imap.mail.me.com", imapPort: 993, imapEnc: 1, smtpHost: "smtp.mail.me.com", smtpPort: 587, smtpEnc: 2 },
    "yahoo": { imapHost: "imap.mail.yahoo.com", imapPort: 993, imapEnc: 1, smtpHost: "smtp.mail.yahoo.com", smtpPort: 465, smtpEnc: 1 }
};

const providers = ["fastmail", "icloud", "yahoo", "other"];

const domainPresets = {
    "fastmail.com": "fastmail",
    "fastmail.fm": "fastmail",
    "icloud.com": "icloud",
    "me.com": "icloud",
    "mac.com": "icloud",
    "yahoo.com": "yahoo",
    "ymail.com": "yahoo"
};

const encryptions = [1, 2, 0];
const imapPorts = { 0: 143, 1: 993, 2: 143 };
const smtpPorts = { 0: 25, 1: 465, 2: 587 };

function presetForEmail(email) {
    const domain = String(email).split("@")[1] || "";
    return domainPresets[domain.trim().toLowerCase()] || "";
}

function emailValid(email) {
    return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(email).trim());
}

function prefixed(prefix, subject) {
    const s = String(subject || "").trim();
    return new RegExp("^" + prefix + ":", "i").test(s) ? s : prefix + ": " + s;
}

function quote(text) {
    return String(text || "").split("\n").map(l => "> " + l).join("\n");
}

function replyPrefill(msg) {
    return {
        defaultTo: msg.from || "",
        defaultSubject: prefixed("Re", msg.subject),
        defaultBody: "\n\n" + quote(msg.bodyPlain)
    };
}

function forwardPrefill(msg, dateText) {
    const lines = ["", "", "---------- Forwarded message ----------", "From: " + (msg.from || "")];
    if (dateText)
        lines.push("Date: " + dateText);
    lines.push("Subject: " + (msg.subject || ""));
    if ((msg.to || []).length > 0)
        lines.push("To: " + msg.to.join(", "));
    return {
        defaultSubject: prefixed("Fwd", msg.subject),
        defaultBody: lines.join("\n") + "\n\n" + (msg.bodyPlain || "")
    };
}

// The helper's messages are developer diagnostics (env vars, manifest
// keys), so map them to copy a person can act on.
function oauthErrorText(code, message) {
    if (code === "oauth_not_configured")
        return qsTr("Google and Microsoft sign-in isn't enabled in this build. Use Other (IMAP) instead.");
    if (code === "secret_service_unavailable" || /secret[-_ ]service|keyring/i.test(message))
        return qsTr("Mail can't reach the keyring, so it can't store your account securely. Use Other (IMAP) instead.");
    if (/network|timeout|resolve|connect/i.test(message))
        return qsTr("Couldn't reach the sign-in service. Check your connection and try again.");
    return qsTr("Sign-in didn't complete. Try again.");
}

function headerDescription(accountName, unread) {
    if (unread > 0)
        return accountName ? qsTr("%1 · %n unread", "", unread).arg(accountName) : qsTr("%n unread", "", unread);
    return accountName || "";
}

function draft(fields) {
    return String(fields.to + fields.cc + fields.subject + fields.body).trim() === "" ? "" : JSON.stringify(fields);
}

function parseDraft(json) {
    try {
        const d = JSON.parse(json);
        return d && typeof d === "object" ? { to: d.to || "", cc: d.cc || "", subject: d.subject || "", body: d.body || "" } : null;
    } catch (e) {
        return null;
    }
}
