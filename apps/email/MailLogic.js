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

function headerDescription(accountName, unread, outbox) {
    const parts = accountName ? [accountName] : [];
    if (unread > 0)
        parts.push(qsTr("%n unread", "", unread));
    if (outbox > 0)
        parts.push(qsTr("%n in Outbox", "", outbox));
    return parts.join(" · ");
}

// Splits on commas and semicolons (and spaces between bare addresses),
// accepts "Name <addr>", and stops at the first token that isn't an address.
function parseRecipients(text) {
    const recipients = [];
    const parts = String(text || "").match(/"[^"]*"\s*<[^>]*>|[^,;]+/g) || [];
    for (const raw of parts) {
        const part = raw.trim();
        if (part === "")
            continue;
        const named = /^(.*?)\s*<([^<>]+)>$/.exec(part);
        if (named) {
            const addr = named[2].trim();
            if (!emailValid(addr))
                return { recipients: recipients, invalid: part };
            recipients.push(named[1].trim() !== "" ? named[1].trim() + " <" + addr + ">" : addr);
            continue;
        }
        for (const token of part.split(/\s+/)) {
            if (!emailValid(token))
                return { recipients: recipients, invalid: token };
            recipients.push(token);
        }
    }
    return { recipients: recipients, invalid: "" };
}

function sendFailureText(reason) {
    if (reason === "offline")
        return qsTr("Not sent — you're offline. It'll stay in Outbox; pull down in Inbox to retry.");
    if (reason === "login")
        return qsTr("Not sent — the mail server didn't accept your password. It'll stay in Outbox.");
    if (reason === "certificate")
        return qsTr("Not sent — the mail server's security certificate couldn't be verified. It'll stay in Outbox.");
    if (reason === "address")
        return qsTr("Not sent — the server refused a recipient's address. Delete it from Outbox and send it again with the address fixed.");
    return qsTr("Not sent — couldn't reach the mail server. It'll stay in Outbox; pull down in Inbox to retry.");
}

function setupFailureText(reason) {
    if (reason === "offline")
        return qsTr("You're offline. Connect to the internet, then sign in.");
    if (reason === "login")
        return qsTr("The server didn't accept that email address and password. Many providers need an app password here.");
    if (reason === "certificate")
        return qsTr("The server's security certificate couldn't be verified. Check the server name and encryption, then try again.");
    if (reason === "keyring")
        return qsTr("Mail can't reach the keyring, so it can't store your password. Restart your phone, then try again.");
    return qsTr("Couldn't reach the mail server. Check the server settings and your connection, then try again.");
}

// Drafts are kept per message: "new-<time>" for new mail, "reply-<id>" and
// "forward-<id>" for answers, so one never overwrites another.
function parseDrafts(json) {
    try {
        const d = JSON.parse(json || "{}");
        return d && typeof d === "object" && !Array.isArray(d) ? d : {};
    } catch (e) {
        return {};
    }
}

function withDraft(json, key, fields, savedAt) {
    const drafts = Object.assign({}, parseDrafts(json));
    if (String(fields.to + fields.cc + fields.bcc + fields.subject + fields.body).trim() === "")
        delete drafts[key];
    else
        drafts[key] = Object.assign({}, fields, { savedAt: savedAt });
    return JSON.stringify(drafts);
}

function draftList(drafts) {
    return Object.keys(drafts).map(k => Object.assign({ to: "", cc: "", bcc: "", subject: "", body: "", savedAt: 0 }, drafts[k], { key: k })).sort((a, b) => b.savedAt - a.savedAt);
}

// Search matches the sender, subject or preview, ignoring case.
function matchesMessage(message, query) {
    const q = String(query || "").trim().toLowerCase();
    return q === "" || [message.from, message.subject, message.snippet].some(v => String(v || "").toLowerCase().indexOf(q) !== -1);
}

function draftKind(key) {
    return String(key).split("-")[0];
}

const folderIcons = {
    "inbox": "image://theme/icon-m-mail",
    "drafts": "image://theme/icon-m-edit",
    "sent": "image://theme/icon-m-send",
    "outbox": "image://theme/icon-m-cloud-upload",
    "junk": "image://theme/icon-m-warning",
    "trash": "image://theme/icon-m-delete",
    "other": "image://theme/icon-m-folder"
};

function folderIcon(kind) {
    return folderIcons[kind] || folderIcons.other;
}
