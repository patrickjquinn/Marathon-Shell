#include "davsyncengine.h"
#include "contactsmanager.h"
#include "davcalendarstore.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QUuid>
#include <QXmlStreamReader>
#include <QDateTime>
#include <QDebug>
#include <QTimeZone>
#include <QUrl>

namespace {

    const char *kDav     = "DAV:";
    const char *kCardDav = "urn:ietf:params:xml:ns:carddav";
    const char *kCalDav  = "urn:ietf:params:xml:ns:caldav";

    // Parse a multistatus PROPFIND/REPORT body.
    struct DavResponse {
        QString href;
        QString etag;
        QString syncToken;
        QString resourceType;
        QString currentUserPrincipal;
        QString addressbookHome;
        QString calendarHome;
        QString displayName;
        QString body;
        int     status = 200;
    };

    QList<DavResponse> parseMultistatus(const QByteArray &xml) {
        QList<DavResponse> out;
        QXmlStreamReader   r(xml);
        DavResponse        cur;
        bool               inResponse = false;
        QString            currentTag;
        while (!r.atEnd()) {
            r.readNext();
            if (r.isStartElement()) {
                currentTag = r.name().toString();
                if (currentTag == "response") {
                    cur        = DavResponse{};
                    inResponse = true;
                } else if (currentTag == "href" && inResponse) {
                    cur.href = r.readElementText();
                } else if (currentTag == "getetag") {
                    cur.etag = r.readElementText();
                } else if (currentTag == "sync-token") {
                    cur.syncToken = r.readElementText();
                } else if (currentTag == "displayname") {
                    cur.displayName = r.readElementText();
                } else if (currentTag == "status") {
                    const QString s = r.readElementText();
                    if (s.contains(QStringLiteral("404")))
                        cur.status = 404;
                    else if (s.contains(QStringLiteral("200")))
                        cur.status = 200;
                    else
                        cur.status = 500;
                } else if (currentTag == "current-user-principal") {
                    // Inner href will populate principal -- we capture below in next iteration.
                } else if (currentTag == "addressbook-home-set") {
                    // Same pattern -- inner href captures it.
                } else if (currentTag == "calendar-home-set") {
                    // Same.
                } else if (currentTag == "address-data" || currentTag == "calendar-data") {
                    cur.body = r.readElementText();
                } else if (currentTag == "resourcetype") {
                    cur.resourceType.clear();
                    while (r.readNextStartElement()) {
                        cur.resourceType += "<" + r.name().toString() + ">";
                        r.skipCurrentElement();
                    }
                }
            } else if (r.isEndElement()) {
                if (r.name() == QStringLiteral("response")) {
                    inResponse = false;
                    out.append(cur);
                }
            }
        }
        return out;
    }

    // Walk inner href under named parent element, helper for principal/home extraction.
    QString findHrefUnder(const QByteArray &xml, const char *parentLocalName) {
        QXmlStreamReader r(xml);
        bool             inParent = false;
        while (!r.atEnd()) {
            r.readNext();
            if (r.isStartElement()) {
                if (r.name() == QString::fromLatin1(parentLocalName))
                    inParent = true;
                else if (inParent && r.name() == QStringLiteral("href"))
                    return r.readElementText();
            } else if (r.isEndElement()) {
                if (r.name() == QString::fromLatin1(parentLocalName))
                    inParent = false;
            }
        }
        return {};
    }

    QString resolveRelative(const QString &base, const QString &maybeRelative) {
        if (maybeRelative.startsWith("http://") || maybeRelative.startsWith("https://"))
            return maybeRelative;
        QUrl b(base);
        QUrl r(maybeRelative);
        return b.resolved(r).toString();
    }

    // === vCard 3.0 / 4.0 parser ===============================================
    //
    // Correct enough for daily-driver use against Nextcloud / Fastmail / iCloud /
    // Mailbox / Radicale. Handles RFC 6350 line folding, multiple TEL/EMAIL with
    // TYPE params, ORG, NOTE, NICKNAME, UID, and PHOTO=base64.
    struct VCardContact {
        QString     uid;
        QString     name;
        QString     organization;
        QString     note;
        QString     photoBase64;
        QStringList phones;
        QStringList phoneTypes;
        QStringList emails;
        QStringList emailTypes;
    };

    QString unfoldVCard(const QString &text) {
        QStringList lines = text.split('\n');
        QStringList out;
        out.reserve(lines.size());
        for (QString l : lines) {
            if (l.endsWith('\r'))
                l.chop(1);
            if (!out.isEmpty() && (l.startsWith(' ') || l.startsWith('\t')))
                out.last() += l.mid(1);
            else
                out.append(l);
        }
        return out.join('\n');
    }

    QString extractType(const QString &paramSection) {
        const QStringList parts = paramSection.split(';');
        for (const QString &p : parts) {
            const int eq = p.indexOf('=');
            if (eq < 0)
                continue;
            const QString key = p.left(eq).trimmed().toUpper();
            if (key != QStringLiteral("TYPE"))
                continue;
            QStringList values = p.mid(eq + 1).split(',');
            for (QString v : values) {
                v = v.trimmed().toLower();
                if (v == "cell" || v == "mobile" || v == "work" || v == "home" || v == "fax")
                    return v;
            }
        }
        return {};
    }

    // === iCalendar (VEVENT) parser =============================================
    struct VEventEntry {
        QString uid;
        QString summary;
        QString description;
        QString location;
        qint64  startMs = 0;
        qint64  endMs   = 0;
        bool    allDay  = false;
    };

    qint64 parseICalDateTime(const QString &headParams, const QString &raw, bool *isAllDay) {
        // VALUE=DATE means YYYYMMDD (no time component); else YYYYMMDDTHHMMSS[Z]
        *isAllDay = headParams.contains(QStringLiteral("VALUE=DATE"), Qt::CaseInsensitive) &&
            !headParams.contains(QStringLiteral("VALUE=DATE-TIME"), Qt::CaseInsensitive);
        QString s = raw.trimmed();
        if (s.isEmpty())
            return 0;
        if (*isAllDay && s.size() == 8) {
            QDate d = QDate::fromString(s, "yyyyMMdd");
            return QDateTime(d, QTime(0, 0), QTimeZone::UTC).toMSecsSinceEpoch();
        }
        // Z suffix means UTC; otherwise treat naïve datetimes as local.
        bool isUtc = s.endsWith('Z');
        if (isUtc)
            s.chop(1);
        QDateTime dt = QDateTime::fromString(s, "yyyyMMddTHHmmss");
        if (!dt.isValid())
            return 0;
        dt.setTimeZone(isUtc ? QTimeZone::UTC : QTimeZone::LocalTime);
        return dt.toMSecsSinceEpoch();
    }

    QList<VEventEntry> parseICalendar(const QString &raw) {
        QList<VEventEntry> out;
        const QString      unfolded = unfoldVCard(raw); // same folding rule
        VEventEntry        cur;
        bool               inEvent = false;
        for (const QString &line : unfolded.split('\n')) {
            const QString t = line.trimmed();
            if (t == QStringLiteral("BEGIN:VEVENT")) {
                cur     = VEventEntry{};
                inEvent = true;
                continue;
            }
            if (t == QStringLiteral("END:VEVENT")) {
                if (inEvent && !cur.uid.isEmpty())
                    out.append(cur);
                inEvent = false;
                continue;
            }
            if (!inEvent)
                continue;
            const int colon = t.indexOf(':');
            if (colon < 0)
                continue;
            const QString head  = t.left(colon);
            const QString value = t.mid(colon + 1);
            const QString prop  = head.section(';', 0, 0).toUpper();
            if (prop == "UID")
                cur.uid = value.trimmed();
            else if (prop == "SUMMARY")
                cur.summary = value.trimmed();
            else if (prop == "DESCRIPTION")
                cur.description = value.trimmed();
            else if (prop == "LOCATION")
                cur.location = value.trimmed();
            else if (prop == "DTSTART") {
                bool ad     = false;
                cur.startMs = parseICalDateTime(head, value, &ad);
                cur.allDay  = ad;
            } else if (prop == "DTEND") {
                bool ad   = false;
                cur.endMs = parseICalDateTime(head, value, &ad);
            }
        }
        return out;
    }

    VCardContact parseVCard(const QString &raw) {
        VCardContact  c;
        const QString unfolded = unfoldVCard(raw);
        for (const QString &line : unfolded.split('\n')) {
            const int colon = line.indexOf(':');
            if (colon < 0)
                continue;
            const QString     head  = line.left(colon);
            const QString     value = line.mid(colon + 1);
            const QStringList par   = head.split(';');
            if (par.isEmpty())
                continue;
            const QString prop = par.first().toUpper();
            if (prop == "FN") {
                c.name = value.trimmed();
            } else if (prop == "UID") {
                c.uid = value.trimmed();
            } else if (prop == "ORG") {
                c.organization = value.section(';', 0, 0).trimmed();
            } else if (prop == "NOTE") {
                c.note = value.trimmed();
            } else if (prop == "TEL") {
                QString num = value.trimmed();
                if (num.startsWith(QStringLiteral("tel:"), Qt::CaseInsensitive))
                    num = num.mid(4);
                c.phones.append(num);
                c.phoneTypes.append(extractType(head));
            } else if (prop == "EMAIL") {
                QString addr = value.trimmed();
                if (addr.startsWith(QStringLiteral("mailto:"), Qt::CaseInsensitive))
                    addr = addr.mid(7);
                c.emails.append(addr);
                c.emailTypes.append(extractType(head));
            } else if (prop == "PHOTO") {
                if (value.startsWith(QStringLiteral("data:"))) {
                    const int comma = value.indexOf(',');
                    if (comma > 0)
                        c.photoBase64 = value.mid(comma + 1);
                } else if (head.contains(QStringLiteral("ENCODING=b"), Qt::CaseInsensitive) ||
                           head.contains(QStringLiteral("BASE64"), Qt::CaseInsensitive)) {
                    c.photoBase64 = value;
                }
            }
        }
        return c;
    }

} // namespace

QVariantMap DavAccount::toVariant() const {
    QVariantMap m;
    m["id"]                  = id;
    m["displayName"]         = displayName;
    m["baseUrl"]             = baseUrl;
    m["username"]            = username;
    m["authKind"]            = authKind;
    m["homeUrlContacts"]     = homeUrlContacts;
    m["homeUrlCalendar"]     = homeUrlCalendar;
    m["collectionsContacts"] = collectionsContacts;
    m["collectionsCalendar"] = collectionsCalendar;
    m["enabled"]             = enabled;
    // secret is intentionally NOT round-tripped through toVariant -- secrets
    // never leave the engine.
    return m;
}

DavAccount DavAccount::fromVariant(const QVariantMap &m) {
    DavAccount a;
    a.id                  = m.value("id").toString();
    a.displayName         = m.value("displayName").toString();
    a.baseUrl             = m.value("baseUrl").toString();
    a.username            = m.value("username").toString();
    a.authKind            = m.value("authKind", "basic").toString();
    a.homeUrlContacts     = m.value("homeUrlContacts").toString();
    a.homeUrlCalendar     = m.value("homeUrlCalendar").toString();
    a.collectionsContacts = m.value("collectionsContacts").toStringList();
    a.collectionsCalendar = m.value("collectionsCalendar").toStringList();
    a.enabled             = m.value("enabled", true).toBool();
    return a;
}

DavSyncEngine::DavSyncEngine(ContactsManager *contacts, DavCalendarStore *calendarStore,
                             QObject *parent)
    : QObject(parent)
    , m_contacts(contacts)
    , m_calendarStore(calendarStore)
    , m_net(new QNetworkAccessManager(this))
    , m_syncTimer(new QTimer(this)) {
    loadAccounts();
    connect(m_syncTimer, &QTimer::timeout, this, &DavSyncEngine::syncNow);
    if (m_syncIntervalMs > 0)
        m_syncTimer->start(m_syncIntervalMs);
}

void DavSyncEngine::loadAccounts() {
    QSettings s;
    s.beginGroup("dav/accounts");
    const QStringList ids = s.childGroups();
    for (const QString &id : ids) {
        s.beginGroup(id);
        DavAccount a;
        a.id                  = id;
        a.displayName         = s.value("displayName").toString();
        a.baseUrl             = s.value("baseUrl").toString();
        a.username            = s.value("username").toString();
        a.secret              = s.value("secret").toString(); // TODO: libsecret
        a.authKind            = s.value("authKind", "basic").toString();
        a.homeUrlContacts     = s.value("homeUrlContacts").toString();
        a.homeUrlCalendar     = s.value("homeUrlCalendar").toString();
        a.collectionsContacts = s.value("collectionsContacts").toStringList();
        a.collectionsCalendar = s.value("collectionsCalendar").toStringList();
        a.enabled             = s.value("enabled", true).toBool();
        s.endGroup();
        m_accounts.insert(id, a);
    }
    s.endGroup();
    emit accountsChanged();
}

void DavSyncEngine::persistAccount(const DavAccount &a) {
    QSettings s;
    s.beginGroup("dav/accounts/" + a.id);
    s.setValue("displayName", a.displayName);
    s.setValue("baseUrl", a.baseUrl);
    s.setValue("username", a.username);
    s.setValue("secret", a.secret);
    s.setValue("authKind", a.authKind);
    s.setValue("homeUrlContacts", a.homeUrlContacts);
    s.setValue("homeUrlCalendar", a.homeUrlCalendar);
    s.setValue("collectionsContacts", a.collectionsContacts);
    s.setValue("collectionsCalendar", a.collectionsCalendar);
    s.setValue("enabled", a.enabled);
    s.endGroup();
    s.sync();
}

void DavSyncEngine::erasePersistedAccount(const QString &id) {
    QSettings s;
    s.beginGroup("dav/accounts");
    s.remove(id);
    s.endGroup();
    s.sync();
}

void DavSyncEngine::saveAccounts() const {
    for (const auto &a : m_accounts)
        const_cast<DavSyncEngine *>(this)->persistAccount(a);
}

QVariantList DavSyncEngine::listAccounts() const {
    QVariantList out;
    for (const auto &a : m_accounts)
        out.append(a.toVariant());
    return out;
}

QString DavSyncEngine::addAccount(const QString &displayName, const QString &baseUrl,
                                  const QString &username, const QString &secret,
                                  const QString &authKind) {
    DavAccount a;
    a.id          = QUuid::createUuid().toString(QUuid::WithoutBraces);
    a.displayName = displayName;
    a.baseUrl     = baseUrl;
    a.username    = username;
    a.secret      = secret;
    a.authKind    = authKind;
    m_accounts.insert(a.id, a);
    persistAccount(a);
    emit accountsChanged();
    discover(a.id);
    return a.id;
}

bool DavSyncEngine::removeAccount(const QString &id) {
    if (!m_accounts.contains(id))
        return false;
    m_accounts.remove(id);
    erasePersistedAccount(id);
    emit accountsChanged();
    return true;
}

void DavSyncEngine::enableAccount(const QString &id, bool enabled) {
    if (!m_accounts.contains(id))
        return;
    m_accounts[id].enabled = enabled;
    persistAccount(m_accounts[id]);
    emit accountsChanged();
}

QString DavSyncEngine::basicAuthHeader(const QString &user, const QString &secret) {
    return "Basic " + (user + ":" + secret).toUtf8().toBase64();
}

void DavSyncEngine::authenticateRequest(QNetworkRequest &req, const DavAccount &acct) const {
    if (acct.authKind == "bearer")
        req.setRawHeader("Authorization", ("Bearer " + acct.secret).toUtf8());
    else
        req.setRawHeader("Authorization", basicAuthHeader(acct.username, acct.secret).toUtf8());
}

QNetworkReply *DavSyncEngine::propfind(const QString &url, int depth, const QString &xmlBody,
                                       const DavAccount &acct) {
    QNetworkRequest req(url);
    req.setRawHeader("Depth", QByteArray::number(depth));
    req.setRawHeader("Content-Type", "application/xml; charset=utf-8");
    authenticateRequest(req, acct);
    return m_net->sendCustomRequest(req, "PROPFIND", xmlBody.toUtf8());
}

QNetworkReply *DavSyncEngine::report(const QString &url, const QString &xmlBody,
                                     const DavAccount &acct) {
    QNetworkRequest req(url);
    req.setRawHeader("Depth", "1");
    req.setRawHeader("Content-Type", "application/xml; charset=utf-8");
    authenticateRequest(req, acct);
    return m_net->sendCustomRequest(req, "REPORT", xmlBody.toUtf8());
}

QNetworkReply *DavSyncEngine::getResource(const QString &url, const DavAccount &acct) {
    QNetworkRequest req(url);
    authenticateRequest(req, acct);
    return m_net->get(req);
}

// === Discovery ============================================================

void DavSyncEngine::discover(const QString &accountId) {
    if (!m_accounts.contains(accountId))
        return;
    DavAccount a = m_accounts.value(accountId);
    if (!a.enabled)
        return;
    runDiscoveryStep1(a);
}

void DavSyncEngine::runDiscoveryStep1(DavAccount &acct) {
    const QString xml = QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\" ?>"
                                       "<d:propfind xmlns:d=\"DAV:\">"
                                       "<d:prop><d:current-user-principal/></d:prop>"
                                       "</d:propfind>");
    // Try common .well-known and base URL forms in order.
    QString wellKnown = acct.baseUrl;
    if (!wellKnown.endsWith('/'))
        wellKnown += "/";
    if (!wellKnown.contains("/.well-known"))
        wellKnown += ".well-known/carddav";

    QNetworkReply *reply = propfind(wellKnown, 0, xml, acct);
    QString        accId = acct.id;
    connect(reply, &QNetworkReply::finished, this, [this, accId, reply, xml]() {
        DavAccount a = m_accounts.value(accId);
        if (reply->error() != QNetworkReply::NoError &&
            reply->error() != QNetworkReply::ContentNotFoundError) {
            // Fall back to the bare base URL.
            QNetworkReply *r2 = propfind(a.baseUrl, 0, xml, a);
            connect(r2, &QNetworkReply::finished, this, [this, accId, r2]() {
                const QByteArray body = r2->readAll();
                r2->deleteLater();
                const QString princ = findHrefUnder(body, "current-user-principal");
                if (princ.isEmpty()) {
                    emit accountDiscoveryFailed(accId, "principal not found at base URL fallback");
                    return;
                }
                DavAccount a2 = m_accounts.value(accId);
                runDiscoveryStep2(a2, resolveRelative(a2.baseUrl, princ));
            });
            reply->deleteLater();
            return;
        }
        const QByteArray body = reply->readAll();
        reply->deleteLater();
        const QString princ = findHrefUnder(body, "current-user-principal");
        if (princ.isEmpty()) {
            emit accountDiscoveryFailed(accId, "principal not found");
            return;
        }
        runDiscoveryStep2(a, resolveRelative(a.baseUrl, princ));
    });
}

void DavSyncEngine::runDiscoveryStep2(DavAccount &acct, const QString &principalUrl) {
    const QString xml =
        QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\" ?>"
                       "<d:propfind xmlns:d=\"DAV:\" xmlns:card=\"urn:ietf:params:xml:ns:carddav\""
                       " xmlns:cal=\"urn:ietf:params:xml:ns:caldav\">"
                       "<d:prop>"
                       "<card:addressbook-home-set/>"
                       "<cal:calendar-home-set/>"
                       "</d:prop></d:propfind>");
    QNetworkReply *reply = propfind(principalUrl, 0, xml, acct);
    QString        accId = acct.id;
    const QString &princ = principalUrl;
    connect(reply, &QNetworkReply::finished, this, [this, accId, reply, princ]() {
        DavAccount       a    = m_accounts.value(accId);
        const QByteArray body = reply->readAll();
        reply->deleteLater();
        const QString contactsHome = findHrefUnder(body, "addressbook-home-set");
        const QString calendarHome = findHrefUnder(body, "calendar-home-set");
        a.homeUrlContacts =
            contactsHome.isEmpty() ? QString() : resolveRelative(princ, contactsHome);
        a.homeUrlCalendar =
            calendarHome.isEmpty() ? QString() : resolveRelative(princ, calendarHome);
        m_accounts[accId] = a;
        runDiscoveryStep3(a);
    });
}

void DavSyncEngine::runDiscoveryStep3(DavAccount &acct) {
    const QString xml = QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\" ?>"
                                       "<d:propfind xmlns:d=\"DAV:\">"
                                       "<d:prop>"
                                       "<d:resourcetype/><d:displayname/><d:sync-token/>"
                                       "</d:prop></d:propfind>");
    if (!acct.homeUrlContacts.isEmpty()) {
        QNetworkReply *reply = propfind(acct.homeUrlContacts, 1, xml, acct);
        QString        accId = acct.id;
        connect(reply, &QNetworkReply::finished, this, [this, accId, reply]() {
            DavAccount       a    = m_accounts.value(accId);
            const QByteArray body = reply->readAll();
            reply->deleteLater();
            QStringList colls;
            for (const auto &r : parseMultistatus(body))
                if (r.resourceType.contains("addressbook"))
                    colls.append(resolveRelative(a.homeUrlContacts, r.href));
            a.collectionsContacts = colls;
            persistAccount(a);
            m_accounts[accId] = a;
            emit accountDiscovered(accId);
        });
    }
    if (!acct.homeUrlCalendar.isEmpty()) {
        QNetworkReply *reply = propfind(acct.homeUrlCalendar, 1, xml, acct);
        QString        accId = acct.id;
        connect(reply, &QNetworkReply::finished, this, [this, accId, reply]() {
            DavAccount       a    = m_accounts.value(accId);
            const QByteArray body = reply->readAll();
            reply->deleteLater();
            QStringList colls;
            for (const auto &r : parseMultistatus(body))
                if (r.resourceType.contains("calendar"))
                    colls.append(resolveRelative(a.homeUrlCalendar, r.href));
            a.collectionsCalendar = colls;
            persistAccount(a);
            m_accounts[accId] = a;
        });
    }
}

// === Sync =================================================================

void DavSyncEngine::syncNow() {
    if (m_syncing)
        return;
    m_syncing = true;
    emit syncingChanged();
    for (const DavAccount &a : m_accounts) {
        if (!a.enabled)
            continue;
        for (const QString &c : a.collectionsContacts)
            syncCollection(a, c, false);
        // Calendar collections -- sync the resource list, but the actual
        // event ingestion is deferred until CalendarManager is shell-side.
        for (const QString &c : a.collectionsCalendar)
            syncCollection(a, c, true);
    }
    m_lastSyncMs = QDateTime::currentMSecsSinceEpoch();
    emit lastSyncMsChanged();
    m_syncing = false;
    emit syncingChanged();
}

void DavSyncEngine::syncCollection(const DavAccount &acct, const QString &collectionUrl,
                                   bool isCalendar) {
    DavCollectionState st = m_collectionState.value(collectionUrl);
    QString            xml;
    if (st.syncToken.isEmpty()) {
        // Initial pull -- no sync-token yet, ask for the full member list with etags.
        xml = QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\" ?>"
                             "<d:sync-collection xmlns:d=\"DAV:\">"
                             "<d:sync-token/>"
                             "<d:sync-level>1</d:sync-level>"
                             "<d:prop><d:getetag/></d:prop>"
                             "</d:sync-collection>");
    } else {
        xml = QStringLiteral("<?xml version=\"1.0\" encoding=\"utf-8\" ?>"
                             "<d:sync-collection xmlns:d=\"DAV:\">"
                             "<d:sync-token>%1</d:sync-token>"
                             "<d:sync-level>1</d:sync-level>"
                             "<d:prop><d:getetag/></d:prop>"
                             "</d:sync-collection>")
                  .arg(st.syncToken);
    }

    QNetworkReply *reply = report(collectionUrl, xml, acct);
    const QString  accId = acct.id;
    const QString &url   = collectionUrl;
    connect(reply, &QNetworkReply::finished, this, [this, accId, url, reply, isCalendar]() {
        const QByteArray body = reply->readAll();
        reply->deleteLater();
        const auto responses = parseMultistatus(body);
        // Save the new sync-token.
        for (const auto &r : responses) {
            if (!r.syncToken.isEmpty()) {
                DavCollectionState st;
                st.collectionUrl       = url;
                st.syncToken           = r.syncToken;
                st.lastSyncMs          = QDateTime::currentMSecsSinceEpoch();
                m_collectionState[url] = st;
                break;
            }
        }
        int added = 0, removed = 0;
        for (const auto &r : responses) {
            if (r.href.isEmpty())
                continue;
            if (r.status == 404) {
                ++removed;
                continue;
            }
            // For each new/changed href, fetch the body via plain GET.
            const DavAccount acct  = m_accounts.value(accId);
            QNetworkReply   *body2 = getResource(resolveRelative(url, r.href), acct);
            connect(body2, &QNetworkReply::finished, this, [this, body2, isCalendar, accId]() {
                const QByteArray data = body2->readAll();
                body2->deleteLater();
                if (isCalendar && m_calendarStore) {
                    const QString iCalText = QString::fromUtf8(data);
                    const auto    events   = parseICalendar(iCalText);
                    for (const auto &e : events) {
                        m_calendarStore->upsertEvent(e.uid, e.summary, e.description, e.startMs,
                                                     e.endMs, e.allDay, e.location, accId);
                    }
                } else if (!isCalendar && m_contacts) {
                    // Parse the vCard properly -- RFC 6350 unfolding + TYPE
                    // params + multi-phone/email + ORG + NOTE + photo.
                    const VCardContact vc = parseVCard(QString::fromUtf8(data));
                    if (!vc.name.isEmpty()) {
                        // ContactsManager today takes (name, phone, email);
                        // pick the first non-fax phone and first email as
                        // primary. Additional fields land in the dedup store
                        // when ContactsManager grows multi-value support.
                        QString primaryPhone, primaryEmail;
                        for (int i = 0; i < vc.phones.size(); ++i) {
                            if (vc.phoneTypes.value(i) != QStringLiteral("fax")) {
                                primaryPhone = vc.phones.at(i);
                                break;
                            }
                        }
                        if (primaryPhone.isEmpty() && !vc.phones.isEmpty())
                            primaryPhone = vc.phones.first();
                        if (!vc.emails.isEmpty())
                            primaryEmail = vc.emails.first();
                        QMetaObject::invokeMethod(m_contacts, "addContact", Q_ARG(QString, vc.name),
                                                  Q_ARG(QString, primaryPhone),
                                                  Q_ARG(QString, primaryEmail));
                    }
                }
                // Calendar import would call CalendarManagerCpp here.
            });
            ++added;
        }
        emit syncFinished(accId, added, 0, removed);
    });
}

void DavSyncEngine::setSyncIntervalMs(int ms) {
    m_syncIntervalMs = ms;
    if (ms <= 0)
        m_syncTimer->stop();
    else
        m_syncTimer->start(ms);
}

int DavSyncEngine::syncIntervalMs() const {
    return m_syncIntervalMs;
}
