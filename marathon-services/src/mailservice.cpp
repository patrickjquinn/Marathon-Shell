#include "mailservice.h"

#include <QAbstractItemModel>
#include <QByteArray>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDebug>
#include <QSettings>
#include <QVariantList>
#include <QVariantMap>

// QMF public API. These headers come from qmf-dev. The build won't link
// until the QMF apks land on the build host (see ~/duranium-build
// /duranium/marathon-extras/build-qmf-apk.sh).
#include <QMailAccount>
#include <QMailAccountConfiguration>
#include <QMailAccountId>
#include <QMailAccountKey>
#include <QMailAccountListModel>
#include <QMailAddress>
#include <QMailFolder>
#include <QMailFolderId>
#include <QMailFolderKey>
#include <QMailFolderListModel>
#include <QMailMessage>
#include <QMailMessageId>
#include <QMailMessageKey>
#include <QMailMessageListModel>
#include <QMailMessageSortKey>
#include <QMailRetrievalAction>
#include <QMailServiceAction>
#include <QMailStore>
#include <QMailTransmitAction>

// QML role names exposed to the inbox ListView. The base QMF model
// returns variants by Qt::UserRole offsets; we proxy through a custom
// QAbstractItemModel so QML's role-name binding (`model.subject` etc.)
// resolves correctly.
//
// We could subclass QMailMessageListModel and override roleNames() but
// the QMF base class doesn't mark roleNames() virtual in a Qt6-clean
// way. The proxy approach is mechanical + readable.
class MailMessageListProxy : public QAbstractListModel {
    Q_OBJECT
  public:
    enum Roles {
        SubjectRole = Qt::UserRole + 1,
        FromRole,
        SnippetRole,
        TimestampRole,
        UnreadRole,
        HasAttachmentRole,
        MessageIdRole,
        TintRole,
    };

    explicit MailMessageListProxy(QObject *parent = nullptr)
        : QAbstractListModel(parent)
        , m_inner(new QMailMessageListModel(this)) {
        connect(m_inner, &QMailMessageListModel::modelReset, this, [this] {
            beginResetModel();
            endResetModel();
        });
        connect(m_inner, &QMailMessageListModel::rowsInserted, this,
                [this](const QModelIndex &, int first, int last) {
                    beginInsertRows({}, first, last);
                    endInsertRows();
                });
        connect(m_inner, &QMailMessageListModel::rowsRemoved, this,
                [this](const QModelIndex &, int first, int last) {
                    beginRemoveRows({}, first, last);
                    endRemoveRows();
                });
        connect(m_inner, &QMailMessageListModel::dataChanged, this,
                [this](const QModelIndex &tl, const QModelIndex &br, const QList<int> &) {
                    emit dataChanged(index(tl.row()), index(br.row()));
                });
    }

    QMailMessageListModel *inner() {
        return m_inner;
    }

    int rowCount(const QModelIndex &parent = {}) const override {
        return parent.isValid() ? 0 : m_inner->rowCount();
    }

    QVariant data(const QModelIndex &idx, int role) const override {
        if (!idx.isValid() || idx.row() < 0 || idx.row() >= m_inner->rowCount())
            return {};
        const auto msgIdVar =
            m_inner->data(m_inner->index(idx.row()), QMailMessageModelBase::MessageIdRole);
        const QMailMessageId mid = msgIdVar.value<QMailMessageId>();
        if (!mid.isValid())
            return {};
        const QMailMessage msg(mid);
        switch (role) {
            case SubjectRole: return msg.subject();
            case FromRole:
                return msg.from().name().isEmpty() ? msg.from().address() : msg.from().name();
            case SnippetRole: return msg.preview();
            case TimestampRole: return formatRelative(msg.date().toLocalTime());
            case UnreadRole: return !(msg.status() & QMailMessage::Read);
            case HasAttachmentRole: return msg.status() & QMailMessage::HasAttachments;
            case MessageIdRole: return mid.toULongLong();
            case TintRole: return tintFor(msg.from().address());
        }
        return {};
    }

    QHash<int, QByteArray> roleNames() const override {
        return {
            {SubjectRole, "subject"},     {FromRole, "from"},
            {SnippetRole, "snippet"},     {TimestampRole, "timestamp"},
            {UnreadRole, "unread"},       {HasAttachmentRole, "hasAttachment"},
            {MessageIdRole, "messageId"}, {TintRole, "tint"},
        };
    }

  private:
    static QString formatRelative(const QDateTime &when) {
        // Today: "HH:mm". Yesterday: "Yesterday". This week: short day
        // name. Else: short date. Matches the JSX inbox format ("Thu",
        // "08:51", "Wed").
        const auto now = QDateTime::currentDateTime();
        if (when.date() == now.date())
            return when.toString(QStringLiteral("HH:mm"));
        const qint64 ageDays = when.date().daysTo(now.date());
        if (ageDays == 1)
            return QStringLiteral("Yesterday");
        if (ageDays < 7)
            return QLocale().standaloneDayName(when.date().dayOfWeek(), QLocale::ShortFormat);
        return when.toString(QStringLiteral("d MMM"));
    }

    static QString tintFor(const QString &address) {
        // Stable hash → one of the DS secondary palette colours. The
        // shell's MColors palette restricts to 6 muted hues; we mod the
        // hash into that range so each contact gets a consistent tile
        // colour without storing a per-contact attribute.
        static const QStringList palette = {
            QStringLiteral("#3a6b9c"), // secBlue
            QStringLiteral("#4a8a5e"), // secGreen
            QStringLiteral("#c89545"), // secAmber
            QStringLiteral("#a85968"), // secRose
            QStringLiteral("#6b5d8f"), // secViolet
            QStringLiteral("#1a4a3e"), // teal-dark
        };
        if (address.isEmpty())
            return QStringLiteral("#040404");
        uint hash = 0;
        for (QChar c : address)
            hash = hash * 31 + c.unicode();
        return palette[hash % palette.size()];
    }

    QMailMessageListModel *m_inner;
};

// ── MailService ────────────────────────────────────────────────────────

MailService::MailService(QObject *parent)
    : QObject(parent)
    , m_accountsModel(new QMailAccountListModel(this))
    , m_foldersModel(new QMailFolderListModel(this))
    , m_messagesModel(nullptr) {

    // Configure the account list: enabled + user-visible accounts only.
    m_accountsModel->setKey(
        QMailAccountKey::status(QMailAccount::Enabled, QMailDataComparator::Includes));

    // Hook QMF's account events so QML's accounts property auto-refreshes.
    auto *store = QMailStore::instance();
    if (store) {
        connect(store, &QMailStore::accountsAdded, this, [this](const auto &ids) {
            (void)ids;
            emit currentAccountChanged();
        });
        connect(store, &QMailStore::accountsRemoved, this, [this](const auto &ids) {
            (void)ids;
            // If the removed account was the current one, fall back to
            // the first remaining account (if any).
            if (!ids.isEmpty()) {
                bool removedCurrent = false;
                for (const auto &id : ids)
                    if (QString::number(id.toULongLong()) == m_currentAccountId) {
                        removedCurrent = true;
                        break;
                    }
                if (removedCurrent)
                    restoreLastSelection();
            }
            emit currentAccountChanged();
        });
        // messagesAdded fires for IMAP IDLE arrivals (new server-side
        // messages pulled by messageserver). We dispatch one freedesktop
        // notification per newly-arrived unread incoming message, then
        // recompute unreadCount via the shared onMessagesUpdated path.
        connect(store, &QMailStore::messagesAdded, this, [this](const QMailMessageIdList &ids) {
            notifyForNewMessages(ids);
            onMessagesUpdated();
        });
        connect(store, &QMailStore::messagesUpdated, this, &MailService::onMessagesUpdated);
        connect(store, &QMailStore::messagesRemoved, this, &MailService::onMessagesUpdated);
    }

    m_retrieval = new QMailRetrievalAction(this);
    m_transmit  = new QMailTransmitAction(this);
    connect(m_retrieval, &QMailServiceAction::activityChanged, this,
            [this](QMailServiceAction::Activity a) {
                switch (a) {
                    case QMailServiceAction::InProgress:
                        m_syncState = QStringLiteral("syncing");
                        break;
                    case QMailServiceAction::Successful:
                        m_syncState = QStringLiteral("idle");
                        break;
                    case QMailServiceAction::Failed: m_syncState = QStringLiteral("error"); break;
                    default: break;
                }
                emit syncStateChanged();
            });

    restoreLastSelection();
}

MailService::~MailService() = default;

MailService *MailService::create(QQmlEngine *, QJSEngine *) {
    // Process-wide singleton. The QQmlEngine owns it via take-ownership;
    // we return a heap-allocated instance and let Qt manage lifetime.
    return new MailService();
}

QObject *MailService::accounts() const {
    return m_accountsModel;
}

QObject *MailService::folders() const {
    return m_foldersModel;
}

QObject *MailService::messages() const {
    return m_messagesModel;
}

int MailService::unreadCount() const {
    return m_unreadCount;
}

QString MailService::currentAccountId() const {
    return m_currentAccountId;
}
QString MailService::currentFolderId() const {
    return m_currentFolderId;
}
QString MailService::syncState() const {
    return m_syncState;
}
QString MailService::lastError() const {
    return m_lastError;
}

QString MailService::currentAccountName() const {
    if (m_currentAccountId.isEmpty())
        return {};
    QMailAccount acct(QMailAccountId(m_currentAccountId.toULongLong()));
    return acct.name();
}

QString MailService::currentFolderName() const {
    if (m_currentFolderId.isEmpty())
        return {};
    QMailFolder folder(QMailFolderId(m_currentFolderId.toULongLong()));
    return folder.displayName();
}

void MailService::setCurrentAccountId(const QString &id) {
    if (id == m_currentAccountId)
        return;
    m_currentAccountId = id;
    saveLastSelection();

    // Bind the folder list to this account.
    if (!id.isEmpty()) {
        const QMailAccountId aid(id.toULongLong());
        m_foldersModel->setKey(QMailFolderKey::parentAccountId(aid));
        // Default to the account's Inbox.
        QMailAccount acct(aid);
        const auto   inboxId = acct.standardFolder(QMailFolder::InboxFolder);
        if (inboxId.isValid())
            setCurrentFolderId(QString::number(inboxId.toULongLong()));
        else
            setCurrentFolderId({});
    } else {
        m_foldersModel->setKey(QMailFolderKey());
        setCurrentFolderId({});
    }
    emit currentAccountChanged();
}

void MailService::setCurrentFolderId(const QString &id) {
    if (id == m_currentFolderId)
        return;
    m_currentFolderId = id;
    rebindMessagesToCurrentFolder();
    emit currentFolderChanged();
}

void MailService::rebindMessagesToCurrentFolder() {
    delete m_messagesModel;
    m_messagesModel = nullptr;
    m_unreadCount   = 0;

    if (m_currentFolderId.isEmpty()) {
        emit unreadCountChanged();
        return;
    }

    auto *proxy = new MailMessageListProxy(this);
    proxy->inner()->setKey(
        QMailMessageKey::parentFolderId(QMailFolderId(m_currentFolderId.toULongLong())));
    proxy->inner()->setSortKey(QMailMessageSortKey::timeStamp(Qt::DescendingOrder));
    m_messagesModel = proxy;

    // Unread count from the same key set.
    const auto unreadKey =
        QMailMessageKey::parentFolderId(QMailFolderId(m_currentFolderId.toULongLong())) &
        ~QMailMessageKey::status(QMailMessage::Read);
    m_unreadCount = QMailStore::instance()->countMessages(unreadKey);
    emit unreadCountChanged();
}

bool MailService::refresh() {
    if (m_currentAccountId.isEmpty())
        return false;
    const QMailAccountId aid(m_currentAccountId.toULongLong());
    m_retrieval->retrieveMessageList(aid, QMailFolderId(m_currentFolderId.toULongLong()),
                                     100, // window
                                     QMailMessageSortKey::timeStamp(Qt::DescendingOrder));
    return true;
}

bool MailService::markAsRead(const QString &messageId, bool read) {
    QMailMessageId mid(messageId.toULongLong());
    if (!mid.isValid())
        return false;
    QMailMessage msg(mid);
    if (read)
        msg.setStatus(QMailMessage::Read, true);
    else
        msg.setStatus(QMailMessage::Read, false);
    return QMailStore::instance()->updateMessage(&msg);
}

bool MailService::moveToTrash(const QString &messageId) {
    QMailMessageId mid(messageId.toULongLong());
    if (!mid.isValid() || m_currentAccountId.isEmpty())
        return false;
    QMailAccount acct(QMailAccountId(m_currentAccountId.toULongLong()));
    const auto   trashId = acct.standardFolder(QMailFolder::TrashFolder);
    if (!trashId.isValid())
        return false;
    QMailMessage msg(mid);
    msg.setParentFolderId(trashId);
    return QMailStore::instance()->updateMessage(&msg);
}

bool MailService::moveToArchive(const QString &messageId) {
    QMailMessageId mid(messageId.toULongLong());
    if (!mid.isValid() || m_currentAccountId.isEmpty())
        return false;
    QMailAccount acct(QMailAccountId(m_currentAccountId.toULongLong()));
    // QMF doesn't have a built-in ArchiveFolder constant; fall back to a
    // sensible default if the account exposes "Archive" by name.
    const auto folders = QMailStore::instance()->queryFolders(
        QMailFolderKey::parentAccountId(acct.id()) &
        QMailFolderKey::displayName(QStringLiteral("Archive")));
    if (folders.isEmpty())
        return false;
    QMailMessage msg(mid);
    msg.setParentFolderId(folders.first());
    return QMailStore::instance()->updateMessage(&msg);
}

bool MailService::send(const QString &to, const QString &cc, const QString &subject,
                       const QString &body, const QStringList &attachmentPaths) {
    if (m_currentAccountId.isEmpty())
        return false;
    QMailAccount acct(QMailAccountId(m_currentAccountId.toULongLong()));

    QMailMessage msg;
    msg.setFrom(acct.fromAddress());
    msg.setTo(QMailAddress::fromStringList(to));
    if (!cc.isEmpty())
        msg.setCc(QMailAddress::fromStringList(cc));
    msg.setSubject(subject);
    msg.setBody(QMailMessageBody::fromData(body.toUtf8(),
                                           QMailMessageContentType("text/plain; charset=UTF-8"),
                                           QMailMessageBody::SevenBit));

    for (const auto &path : attachmentPaths) {
        QMailMessagePart part = QMailMessagePart::fromFile(
            path, QMailMessageContentDisposition(QMailMessageContentDisposition::Attachment),
            QMailMessageContentType("application/octet-stream"), QMailMessageBody::Base64,
            QMailMessageBody::RequiresEncoding);
        msg.appendPart(part);
    }

    msg.setParentAccountId(acct.id());
    msg.setStatus(QMailMessage::Outgoing, true);

    if (!QMailStore::instance()->addMessage(&msg))
        return false;

    m_transmit->transmitMessages(acct.id());
    return true;
}

QVariantMap MailService::openMessage(const QString &messageId) {
    QMailMessageId mid(messageId.toULongLong());
    if (!mid.isValid())
        return {};
    QMailMessage msg(mid);
    QVariantMap  out;
    out[QStringLiteral("subject")] = msg.subject();
    out[QStringLiteral("from")]    = msg.from().toString();
    QStringList tos;
    for (const auto &a : msg.to())
        tos << a.toString();
    out[QStringLiteral("to")] = tos;
    QStringList ccs;
    for (const auto &a : msg.cc())
        ccs << a.toString();
    out[QStringLiteral("cc")]   = ccs;
    out[QStringLiteral("date")] = msg.date().toLocalTime();

    // Find HTML + plain bodies. QMF stores them as parts; the
    // findHtmlContainer / findPlainTextContainer convenience methods
    // give us the right part.
    if (msg.hasBody() || msg.partCount() > 0) {
        auto htmlPart = msg.findPlainTextContainer(); // also handles single-part text
        if (htmlPart.contentType().subType().toLower() == "html")
            out[QStringLiteral("bodyHtml")] = QString::fromUtf8(htmlPart.body().data().toUtf8());
        else
            out[QStringLiteral("bodyPlain")] = QString::fromUtf8(htmlPart.body().data().toUtf8());
    }

    QVariantList atts;
    for (uint i = 0; i < msg.partCount(); ++i) {
        const auto &part = msg.partAt(i);
        if (part.contentDisposition().type() == QMailMessageContentDisposition::Attachment) {
            QVariantMap a;
            a[QStringLiteral("name")] = part.displayName();
            a[QStringLiteral("size")] = static_cast<qulonglong>(part.body().length());
            a[QStringLiteral("mime")] = QString::fromUtf8(part.contentType().content());
            atts << a;
        }
    }
    out[QStringLiteral("attachments")] = atts;
    return out;
}

void MailService::onMessagesUpdated() {
    if (m_currentFolderId.isEmpty())
        return;
    const auto unreadKey =
        QMailMessageKey::parentFolderId(QMailFolderId(m_currentFolderId.toULongLong())) &
        ~QMailMessageKey::status(QMailMessage::Read);
    const int n = QMailStore::instance()->countMessages(unreadKey);
    if (n != m_unreadCount) {
        m_unreadCount = n;
        emit unreadCountChanged();
    }
}

void MailService::notifyForNewMessages(const QMailMessageIdList &ids) {
    if (ids.isEmpty())
        return;

    // Lazy session-bus connect. QDBusConnection::sessionBus() is a cheap
    // accessor; the underlying connection is process-wide and shared.
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return;

    for (const auto &id : ids) {
        const QMailMessage msg(id);
        if (!msg.id().isValid())
            continue;
        // Only Inbox arrivals (Incoming), and only unread. Sent items,
        // drafts, and messages we ourselves mark via syncMail() flow
        // through messagesAdded too — silence those.
        const auto status = msg.status();
        if (!(status & QMailMessage::Incoming))
            continue;
        if (status & QMailMessage::Read)
            continue;

        const QString senderName  = msg.from().name();
        const QString senderEmail = msg.from().address();
        const QString display     = !senderName.isEmpty() ?
                senderName :
                (!senderEmail.isEmpty() ? senderEmail : QStringLiteral("Mail"));
        const QString subject =
            msg.subject().isEmpty() ? QStringLiteral("(no subject)") : msg.subject();

        // org.freedesktop.Notifications.Notify(
        //   app_name: s, replaces_id: u, app_icon: s,
        //   summary: s, body: s,
        //   actions: as, hints: a{sv}, expire_timeout: i) -> u
        auto call = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"),
                                                   QStringLiteral("/org/freedesktop/Notifications"),
                                                   QStringLiteral("org.freedesktop.Notifications"),
                                                   QStringLiteral("Notify"));

        QVariantMap hints;
        // category hint per the fdo spec — lets the shell route into the
        // Hub's Mail filter and apply mail-specific suppression rules.
        hints.insert(QStringLiteral("category"), QStringLiteral("email.arrived"));
        // The shell's FreedesktopNotifications proxy reads `desktop-entry`
        // to attribute the notification to the app (icon lookup, tap
        // routing). "email" matches apps/email/manifest.json's appId.
        hints.insert(QStringLiteral("desktop-entry"), QStringLiteral("email"));

        QVariantList args;
        args << QStringLiteral("Mail")         // app_name
             << static_cast<uint>(0)           // replaces_id
             << QStringLiteral("envelope")     // app_icon — Phosphor glyph
             << display                        // summary
             << subject                        // body
             << QStringList{}                  // actions
             << hints << static_cast<int>(-1); // expire_timeout (default)
        call.setArguments(args);

        // Fire-and-forget: we don't need the returned notification id;
        // a failed call just logs and moves on (the next arrival will
        // retry).
        bus.asyncCall(call);
    }
}

void MailService::restoreLastSelection() {
    QSettings     s(QStringLiteral("MarathonOS"), QStringLiteral("Mail"));
    const QString id = s.value(QStringLiteral("lastAccountId")).toString();
    if (!id.isEmpty()) {
        setCurrentAccountId(id);
        return;
    }
    // No stored selection — pick the first enabled account if any.
    if (m_accountsModel->rowCount() > 0) {
        const auto idx = m_accountsModel->index(0);
        const auto aid = m_accountsModel->data(idx, QMailAccountListModel::MailAccountIdRole)
                             .value<QMailAccountId>();
        if (aid.isValid())
            setCurrentAccountId(QString::number(aid.toULongLong()));
    }
}

void MailService::saveLastSelection() {
    QSettings s(QStringLiteral("MarathonOS"), QStringLiteral("Mail"));
    s.setValue(QStringLiteral("lastAccountId"), m_currentAccountId);
}

QString MailService::addImapAccount(const QString &name, const QString &email,
                                    const QString &imapHost, int imapPort, int imapEncryption,
                                    const QString &smtpHost, int smtpPort, int smtpEncryption,
                                    const QString &username, const QString &password) {
    // Basic input validation — refuse incomplete payloads so QMF doesn't
    // see a half-configured account that will keep failing to sync.
    if (imapHost.isEmpty() || smtpHost.isEmpty() || username.isEmpty() || email.isEmpty()) {
        qWarning() << "[MailService] addImapAccount: missing required field";
        return {};
    }
    if (imapPort <= 0)
        imapPort = (imapEncryption == 1) ? 993 : 143;
    if (smtpPort <= 0)
        smtpPort = (smtpEncryption == 1) ? 465 : 587;

    auto *store = QMailStore::instance();
    if (!store) {
        qWarning() << "[MailService] addImapAccount: QMailStore unavailable";
        return {};
    }

    // Encryption value → QMF imap4/smtp plugin "encryption" key. Numeric
    // ladder matches the upstream plugin's enum (none=0, ssl=1, starttls=2).
    const QString encStr        = QString::number(imapEncryption);
    const QString smtpEncStr    = QString::number(smtpEncryption);
    const QString displayName   = name.isEmpty() ? email : name;
    const QString fromAddrLabel = displayName + QStringLiteral(" <") + email + QStringLiteral(">");

    QMailAccount  account;
    account.setName(displayName);
    account.setFromAddress(QMailAddress(displayName, email));
    account.setMessageType(QMailMessageMetaData::Email);

    // Status flags — Android/iOS-equivalent default is fully on (sync,
    // retrieve, transmit, user-editable, user-removable). QMF will refuse
    // to use the account as a message source/sink unless these bits are
    // set, even if the service configurations are present.
    account.setStatus(QMailAccount::SynchronizationEnabled | QMailAccount::Enabled |
                          QMailAccount::CanRetrieve | QMailAccount::CanTransmit |
                          QMailAccount::MessageSource | QMailAccount::MessageSink |
                          QMailAccount::UserEditable | QMailAccount::UserRemovable,
                      true);

    QMailAccountConfiguration cfg;

    // IMAP4 service — the keys match QMF's upstream imap4 plugin
    // (qmf/src/plugins/messageservices/imap/imapconfiguration.cpp).
    if (!cfg.addServiceConfiguration(QStringLiteral("imap4"))) {
        qWarning() << "[MailService] addImapAccount: failed to add imap4 service";
        return {};
    }
    auto &imap = cfg.serviceConfiguration(QStringLiteral("imap4"));
    imap.setValue(QStringLiteral("servicetype"), QStringLiteral("source"));
    imap.setValue(QStringLiteral("version"), QStringLiteral("1"));
    imap.setValue(QStringLiteral("server"), imapHost);
    imap.setValue(QStringLiteral("port"), QString::number(imapPort));
    imap.setValue(QStringLiteral("encryption"), encStr);
    imap.setValue(QStringLiteral("username"), username);
    // Auth method 0 = PLAIN/LOGIN — QMF picks the strongest the server
    // advertises. Marked PLAIN-only so we don't need NTLM/DIGEST-MD5
    // dependencies on the image.
    imap.setValue(QStringLiteral("authentication"), QStringLiteral("0"));
    imap.setValue(QStringLiteral("checkInterval"), QStringLiteral("0")); // IDLE only, no polling
    imap.setValue(QStringLiteral("intervalCheckRoamingEnabled"), QStringLiteral("0"));
    imap.setValue(QStringLiteral("pushEnabled"), QStringLiteral("1"));
    // SECURITY (tracked under credentials-plugin work): v1 stores the
    // password in QMF's per-user config file (~/.config/QMF/QMF.conf).
    // That file is u=rw,go= by default on systemd-tmpfiles-managed
    // homes; the next iteration migrates password retrieval through a
    // marathonclassic QMailCredentialsPlugin backed by Secret-Service,
    // mirroring how marathonoauth already handles OAuth tokens.
    imap.setValue(QStringLiteral("password"), password);

    // SMTP service.
    if (!cfg.addServiceConfiguration(QStringLiteral("smtp"))) {
        qWarning() << "[MailService] addImapAccount: failed to add smtp service";
        return {};
    }
    auto &smtp = cfg.serviceConfiguration(QStringLiteral("smtp"));
    smtp.setValue(QStringLiteral("servicetype"), QStringLiteral("sink"));
    smtp.setValue(QStringLiteral("version"), QStringLiteral("1"));
    smtp.setValue(QStringLiteral("server"), smtpHost);
    smtp.setValue(QStringLiteral("port"), QString::number(smtpPort));
    smtp.setValue(QStringLiteral("encryption"), smtpEncStr);
    smtp.setValue(QStringLiteral("smtpUsername"), username);
    smtp.setValue(QStringLiteral("authentication"), QStringLiteral("0"));
    smtp.setValue(QStringLiteral("smtppassword"), password);
    smtp.setValue(QStringLiteral("address"), email);

    if (!store->addAccount(&account, &cfg)) {
        qWarning() << "[MailService] addImapAccount: QMailStore::addAccount failed";
        return {};
    }

    const QString accountId = QString::number(account.id().toULongLong());
    qInfo() << "[MailService] addImapAccount: created accountId=" << accountId
            << "imap=" << imapHost << ":" << imapPort << "(enc=" << imapEncryption << ")"
            << "smtp=" << smtpHost << ":" << smtpPort << "(enc=" << smtpEncryption << ")"
            << "fromAddr=" << fromAddrLabel;

    setCurrentAccountId(accountId);
    return accountId;
}

#include "mailservice.moc"
