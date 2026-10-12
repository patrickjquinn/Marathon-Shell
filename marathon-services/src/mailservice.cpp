#include "mailservice.h"

#include <QAbstractItemModel>
#include <QByteArray>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QDebug>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkInformation>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QVariantList>
#include <QVariantMap>

// QMF public API. qmf-dev ships only the lowercase header files (no
// CamelCase forwarders — upstream uses syncqt which Alpine's package
// doesn't run). Stick to lowercase to stay portable.
#include <qmailaccount.h>
#include <qmailaccountconfiguration.h>
#include <qmailaccountkey.h>
#include <qmailaccountlistmodel.h>
#include <qmailaddress.h>
#include <qmaildatacomparator.h>
#include <qmailfolder.h>
#include <qmailfolderkey.h>
#include <qmailfoldersortkey.h>
#include <qmailmessage.h>
#include <qmailmessagekey.h>
#include <qmailmessagelistmodel.h>
#include <qmailmessagemodelbase.h>
#include <qmailmessagesortkey.h>
#include <qmailserviceaction.h>
#include <qmailstore.h>

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
    , m_accountsModel(nullptr)
    , m_messagesModel(nullptr) {

    // Bootstrap QMF — QMailStore::instance() is the runtime entry point.
    // On a fresh first boot the store directory may not exist yet, or
    // libQmfClient could fail to load credentials plugins; we don't
    // want to segfault the runner constructing an account-list model
    // against a half-initialised QMF. Probe first, only allocate the
    // QMF-backed models if the store is alive.
    auto *store = QMailStore::instance();
    if (!store) {
        qWarning() << "[MailService] QMailStore::instance() returned null —"
                   << "QMF runtime not initialised. Mail will run in "
                   << "service-unavailable mode until next launch.";
        m_syncState = QStringLiteral("offline");
        m_lastError = QStringLiteral("Mail backend unavailable");
        return;
    }

    m_accountsModel = new QMailAccountListModel(this);
    m_accountsModel->setKey(
        QMailAccountKey::status(QMailAccount::Enabled, QMailDataComparator::Includes));

    // Store signals arrive in bursts during a sync; coalesce the list rebuild.
    m_accountListTimer = new QTimer(this);
    m_accountListTimer->setSingleShot(true);
    m_accountListTimer->setInterval(100);
    connect(m_accountListTimer, &QTimer::timeout, this, &MailService::accountListChanged);

    if (QNetworkInformation::loadBackendByFeatures(QNetworkInformation::Feature::Reachability))
        connect(QNetworkInformation::instance(), &QNetworkInformation::reachabilityChanged, this,
                &MailService::onlineChanged);

    {
        connect(store, &QMailStore::accountsAdded, this, [this](const auto &ids) {
            (void)ids;
            m_accountListTimer->start();
            emit currentAccountChanged();
        });
        connect(store, &QMailStore::accountsUpdated, m_accountListTimer,
                qOverload<>(&QTimer::start));
        const auto foldersChanged = [this] {
            // A new account's Inbox only exists once its folder list arrives.
            if (m_currentFolderId.isEmpty() && !m_currentAccountId.isEmpty()) {
                const QMailAccount acct(QMailAccountId(m_currentAccountId.toULongLong()));
                const auto inboxId = acct.standardFolder(QMailFolder::InboxFolder);
                if (inboxId.isValid())
                    setCurrentFolderId(QString::number(inboxId.toULongLong()));
            }
            m_accountListTimer->start();
        };
        connect(store, &QMailStore::foldersAdded, this, foldersChanged);
        connect(store, &QMailStore::foldersUpdated, this, foldersChanged);
        connect(store, &QMailStore::foldersRemoved, this, foldersChanged);
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
            m_accountListTimer->start();
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
                    case QMailServiceAction::Failed:
                        if (m_retrieval->status().errorCode ==
                            QMailServiceAction::Status::ErrCancel) {
                            m_syncState = QStringLiteral("idle");
                        } else {
                            m_syncState = QStringLiteral("error");
                            m_lastError = m_retrieval->status().text;
                        }
                        break;
                    default: break;
                }
                emit syncStateChanged();
            });
    connect(m_transmit, &QMailServiceAction::activityChanged, this,
            [this](QMailServiceAction::Activity a) {
                if (a == QMailServiceAction::Successful) {
                    emit sendSucceeded();
                } else if (a == QMailServiceAction::Failed) {
                    const auto code = m_transmit->status().errorCode;
                    if (code != QMailServiceAction::Status::ErrCancel)
                        emit sendFailed(failureReason(code));
                }
                updateOutboxCount();
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

QObject *MailService::messages() const {
    return m_messagesModel;
}

int MailService::unreadCount() const {
    return m_unreadCount;
}

int MailService::outboxCount() const {
    return m_outboxCount;
}

bool MailService::online() const {
    const auto *info = QNetworkInformation::instance();
    return !info || info->reachability() != QNetworkInformation::Reachability::Disconnected;
}

QStringList MailService::oauthProviders() const {
    return m_oauthProviders;
}

static QMailMessageKey outboxKey(const QMailAccountId &accountId) {
    return QMailMessageKey::parentAccountId(accountId) &
           QMailMessageKey::status(QMailMessage::Outbox) &
           ~QMailMessageKey::status(QMailMessage::Trash);
}

static QMailMessageKey unreadIn(const QMailFolderId &folderId) {
    return QMailMessageKey::parentFolderId(folderId) &
           ~QMailMessageKey::status(QMailMessage::Read);
}

QVariantList MailService::accountList() const {
    QVariantList out;
    if (!m_accountsModel)
        return out;
    auto *store = QMailStore::instance();
    for (int row = 0; row < m_accountsModel->rowCount(); ++row) {
        const QMailAccountId aid = m_accountsModel->idFromIndex(m_accountsModel->index(row));
        const QMailAccount   acct(aid);
        const QList<QPair<QMailFolder::StandardFolder, QString>> standard = {
            {QMailFolder::InboxFolder, QStringLiteral("inbox")},
            {QMailFolder::DraftsFolder, QStringLiteral("drafts")},
            {QMailFolder::SentFolder, QStringLiteral("sent")},
            {QMailFolder::JunkFolder, QStringLiteral("junk")},
            {QMailFolder::TrashFolder, QStringLiteral("trash")},
        };
        QHash<QMailFolderId, QString> kinds;
        for (const auto &[folder, kind] : standard)
            if (acct.standardFolder(folder).isValid())
                kinds.insert(acct.standardFolder(folder), kind);

        const auto entry = [store](const QMailFolderId &id, const QString &kind) {
            const QMailFolder folder(id);
            return QVariantMap{
                {QStringLiteral("id"), QString::number(id.toULongLong())},
                {QStringLiteral("name"), folder.displayName()},
                {QStringLiteral("kind"), kind},
                {QStringLiteral("unread"), store->countMessages(unreadIn(id))},
                {QStringLiteral("count"),
                 store->countMessages(QMailMessageKey::parentFolderId(id))},
            };
        };

        // Jolla order: Inbox, Drafts, Sent, Outbox, the rest, Junk, Trash.
        QVariantList head, middle, tail;
        for (const auto &[folder, kind] : standard) {
            const auto id = acct.standardFolder(folder);
            if (!id.isValid())
                continue;
            (folder == QMailFolder::JunkFolder || folder == QMailFolder::TrashFolder ? tail : head)
                << entry(id, kind);
        }
        const int queued = store->countMessages(outboxKey(aid));
        if (queued > 0)
            head << QVariantMap{
                {QStringLiteral("id"), QStringLiteral("outbox")},
                {QStringLiteral("name"), tr("Outbox")},
                {QStringLiteral("kind"), QStringLiteral("outbox")},
                {QStringLiteral("unread"), 0},
                {QStringLiteral("count"), queued},
            };
        const auto ids = store->queryFolders(QMailFolderKey::parentAccountId(aid),
                                             QMailFolderSortKey::path());
        for (const auto &id : ids)
            if (!kinds.contains(id) && !(QMailFolder(id).status() & QMailFolder::NonMail))
                middle << entry(id, QStringLiteral("other"));

        const auto inbox = acct.standardFolder(QMailFolder::InboxFolder);
        out << QVariantMap{
            {QStringLiteral("id"), QString::number(aid.toULongLong())},
            {QStringLiteral("name"), acct.name()},
            {QStringLiteral("address"), acct.fromAddress().address()},
            {QStringLiteral("unread"), inbox.isValid() ? store->countMessages(unreadIn(inbox)) : 0},
            {QStringLiteral("folders"), head + middle + tail},
        };
    }
    return out;
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
    if (m_currentFolderId == QLatin1String("outbox"))
        return tr("Outbox");
    QMailFolder folder(QMailFolderId(m_currentFolderId.toULongLong()));
    return folder.displayName();
}

void MailService::setCurrentAccountId(const QString &id) {
    if (id == m_currentAccountId)
        return;
    m_currentAccountId = id;
    saveLastSelection();
    updateOutboxCount();

    if (!id.isEmpty()) {
        const QMailAccountId aid(id.toULongLong());
        const QMailAccount   acct(aid);
        const auto           inboxId = acct.standardFolder(QMailFolder::InboxFolder);
        if (inboxId.isValid())
            setCurrentFolderId(QString::number(inboxId.toULongLong()));
        else
            setCurrentFolderId({});
    } else {
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

    const bool outbox = m_currentFolderId == QLatin1String("outbox");
    const QMailFolderId folderId(m_currentFolderId.toULongLong());
    auto *proxy = new MailMessageListProxy(this);
    proxy->inner()->setKey(outbox ? outboxKey(QMailAccountId(m_currentAccountId.toULongLong())) :
                                    QMailMessageKey::parentFolderId(folderId));
    proxy->inner()->setSortKey(QMailMessageSortKey::timeStamp(Qt::DescendingOrder));
    m_messagesModel = proxy;

    m_unreadCount = outbox ? 0 : QMailStore::instance()->countMessages(unreadIn(folderId));
    emit unreadCountChanged();
}

bool MailService::refresh() {
    if (m_currentAccountId.isEmpty())
        return false;
    const QMailAccountId aid(m_currentAccountId.toULongLong());
    if (m_outboxCount > 0 && !m_transmit->isRunning())
        m_transmit->transmitMessages(aid);
    if (m_currentFolderId == QLatin1String("outbox"))
        return true;
    m_retrieval->retrieveMessageList(aid, QMailFolderId(m_currentFolderId.toULongLong()),
                                     100, // window
                                     QMailMessageSortKey::timeStamp(Qt::DescendingOrder));
    return true;
}

void MailService::cancelSync() {
    if (m_retrieval && m_retrieval->isRunning())
        m_retrieval->cancelOperation();
}

void MailService::refreshFolders(const QString &accountId) {
    const QMailAccountId aid(accountId.toULongLong());
    if (!aid.isValid() || !m_accountsModel)
        return;
    auto *action = new QMailRetrievalAction(this);
    connect(action, &QMailServiceAction::activityChanged, action,
            [action](QMailServiceAction::Activity a) {
                if (a == QMailServiceAction::Successful || a == QMailServiceAction::Failed)
                    action->deleteLater();
            });
    action->retrieveFolderList(aid, QMailFolderId(), true);
}

void MailService::updateOutboxCount() {
    const int n = m_currentAccountId.isEmpty() || !m_accountsModel ?
            0 :
            QMailStore::instance()->countMessages(
                outboxKey(QMailAccountId(m_currentAccountId.toULongLong())));
    if (n == m_outboxCount)
        return;
    m_outboxCount = n;
    emit outboxCountChanged();
}

QString MailService::failureReason(int errorCode) const {
    switch (errorCode) {
        case QMailServiceAction::Status::ErrCancel: return QStringLiteral("cancelled");
        case QMailServiceAction::Status::ErrLoginFailed: return QStringLiteral("login");
        case QMailServiceAction::Status::ErrNoSslSupport:
        case QMailServiceAction::Status::ErrUntrustedCertificates:
            return QStringLiteral("certificate");
        case QMailServiceAction::Status::ErrInvalidAddress: return QStringLiteral("address");
        default: return online() ? QStringLiteral("server") : QStringLiteral("offline");
    }
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
    // A deleted Outbox message must not go out on the next send.
    msg.setStatus(QMailMessage::Outbox, false);
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

bool MailService::send(const QString &to, const QString &cc, const QString &bcc,
                       const QString &subject, const QString &body,
                       const QStringList &attachmentPaths) {
    if (m_currentAccountId.isEmpty())
        return false;
    QMailAccount acct(QMailAccountId(m_currentAccountId.toULongLong()));

    QMailMessage msg;
    msg.setFrom(acct.fromAddress());
    msg.setTo(QMailAddress::fromStringList(to));
    if (!cc.isEmpty())
        msg.setCc(QMailAddress::fromStringList(cc));
    if (!bcc.isEmpty())
        msg.setBcc(QMailAddress::fromStringList(bcc));
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
    const auto outboxId = acct.standardFolder(QMailFolder::OutboxFolder);
    msg.setParentFolderId(outboxId.isValid() ? outboxId :
                                               QMailFolderId(QMailFolderId::LocalStorageFolderId));
    // transmitMessages() only picks up messages flagged Outbox.
    msg.setStatus(QMailMessage::Outbox | QMailMessage::Outgoing | QMailMessage::ContentAvailable |
                      QMailMessage::Read,
                  true);

    if (!QMailStore::instance()->addMessage(&msg))
        return false;

    updateOutboxCount();
    if (!m_transmit->isRunning())
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
    // findHtmlContainer / findPlainTextContainer give us the right part
    // (or nullptr if not present). msg owns the container; we just read.
    if (auto *htmlPart = msg.findHtmlContainer()) {
        out[QStringLiteral("bodyHtml")] = QString::fromUtf8(htmlPart->body().data().toUtf8());
    }
    if (auto *plainPart = msg.findPlainTextContainer()) {
        out[QStringLiteral("bodyPlain")] = QString::fromUtf8(plainPart->body().data().toUtf8());
    }

    QVariantList atts;
    msg.foreachPart([&atts](const QMailMessagePart &part) {
        if (part.contentDisposition().type() == QMailMessageContentDisposition::Attachment) {
            QVariantMap a;
            a[QStringLiteral("name")]     = part.displayName();
            a[QStringLiteral("size")]     = static_cast<qulonglong>(part.indicativeSize());
            a[QStringLiteral("mime")]     = QString::fromUtf8(part.contentType().content());
            a[QStringLiteral("location")] = part.location().toString(true);
            atts << a;
        }
        return true;
    });
    out[QStringLiteral("attachments")] = atts;
    return out;
}

bool MailService::saveAttachment(const QString &messageId, const QString &location) {
    const QMailMessageId              mid(messageId.toULongLong());
    const QMailMessagePart::Location  loc(location);
    if (!mid.isValid() || !loc.isValid() || !QMailMessage(mid).contains(loc))
        return false;

    const auto write = [this, mid, loc, messageId, location] {
        const QMailMessage msg(mid);
        const QString      dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
        const QString path = QDir().mkpath(dir) ? msg.partAt(loc).writeBodyTo(dir) : QString();
        if (path.isEmpty())
            emit attachmentFailed(messageId, location);
        else
            emit attachmentSaved(messageId, location, path);
    };
    if (QMailMessage(mid).partAt(loc).contentAvailable()) {
        write();
        return true;
    }
    auto *action = new QMailRetrievalAction(this);
    connect(action, &QMailServiceAction::activityChanged, this,
            [this, action, write, messageId, location](QMailServiceAction::Activity a) {
                if (a != QMailServiceAction::Successful && a != QMailServiceAction::Failed)
                    return;
                action->deleteLater();
                if (a == QMailServiceAction::Successful)
                    write();
                else
                    emit attachmentFailed(messageId, location);
            });
    action->retrieveMessagePart(loc);
    return true;
}

void MailService::onMessagesUpdated() {
    updateOutboxCount();
    m_accountListTimer->start();
    if (m_currentFolderId.isEmpty() || m_currentFolderId == QLatin1String("outbox"))
        return;
    const int n = QMailStore::instance()->countMessages(
        unreadIn(QMailFolderId(m_currentFolderId.toULongLong())));
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
        const QModelIndex    idx = m_accountsModel->index(0);
        const QMailAccountId aid = m_accountsModel->idFromIndex(idx);
        if (aid.isValid())
            setCurrentAccountId(QString::number(aid.toULongLong()));
    }
}

void MailService::saveLastSelection() {
    QSettings s(QStringLiteral("MarathonOS"), QStringLiteral("Mail"));
    s.setValue(QStringLiteral("lastAccountId"), m_currentAccountId);
}

bool MailService::addImapAccount(const QString &name, const QString &email,
                                 const QString &imapHost, int imapPort, int imapEncryption,
                                 const QString &smtpHost, int smtpPort, int smtpEncryption,
                                 const QString &username, const QString &password) {
    if (m_setupAccountId.isValid()) {
        qWarning() << "[MailService] addImapAccount: a setup is already running";
        return false;
    }
    // Basic input validation — refuse incomplete payloads so QMF doesn't
    // see a half-configured account that will keep failing to sync.
    if (imapHost.isEmpty() || smtpHost.isEmpty() || username.isEmpty() || email.isEmpty()) {
        qWarning() << "[MailService] addImapAccount: missing required field";
        return false;
    }
    if (imapPort <= 0)
        imapPort = (imapEncryption == 1) ? 993 : 143;
    if (smtpPort <= 0)
        smtpPort = (smtpEncryption == 1) ? 465 : 587;

    auto *store = QMailStore::instance();
    if (!store) {
        qWarning() << "[MailService] addImapAccount: QMailStore unavailable";
        return false;
    }

    // Encryption value → QMF imap4/smtp plugin "encryption" key. Numeric
    // ladder matches the upstream plugin's enum (none=0, ssl=1, starttls=2).
    const QString encStr        = QString::number(imapEncryption);
    const QString smtpEncStr    = QString::number(smtpEncryption);
    const QString displayName   = name.isEmpty() ? email : name;

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
        return false;
    }
    QMailAccountConfiguration::ServiceConfiguration &imap =
        cfg.serviceConfiguration(QStringLiteral("imap4"));
    imap.setValue(QStringLiteral("servicetype"), QStringLiteral("source"));
    imap.setValue(QStringLiteral("version"), QStringLiteral("1"));
    imap.setValue(QStringLiteral("server"), imapHost);
    imap.setValue(QStringLiteral("port"), QString::number(imapPort));
    imap.setValue(QStringLiteral("encryption"), encStr);
    imap.setValue(QStringLiteral("username"), username);
    // Auth method 0 = PLAIN/LOGIN — QMF picks the strongest the server
    // advertises.
    imap.setValue(QStringLiteral("authentication"), QStringLiteral("0"));
    imap.setValue(QStringLiteral("checkInterval"), QStringLiteral("0"));
    imap.setValue(QStringLiteral("intervalCheckRoamingEnabled"), QStringLiteral("0"));
    imap.setValue(QStringLiteral("pushEnabled"), QStringLiteral("1"));
    // CredentialsPlugin=marathon-classic — QMF will load our plugin
    // (libmarathonclassic.so) at auth time, which shells out to
    // /usr/bin/marathon-mail-oauth classic-get to retrieve the password
    // from Secret-Service. Nothing sensitive is written to QMF's
    // QSettings store.
    imap.setValue(QStringLiteral("CredentialsPlugin"), QStringLiteral("marathon-classic"));

    if (!cfg.addServiceConfiguration(QStringLiteral("smtp"))) {
        qWarning() << "[MailService] addImapAccount: failed to add smtp service";
        return false;
    }
    QMailAccountConfiguration::ServiceConfiguration &smtp =
        cfg.serviceConfiguration(QStringLiteral("smtp"));
    smtp.setValue(QStringLiteral("servicetype"), QStringLiteral("sink"));
    smtp.setValue(QStringLiteral("version"), QStringLiteral("1"));
    smtp.setValue(QStringLiteral("server"), smtpHost);
    smtp.setValue(QStringLiteral("port"), QString::number(smtpPort));
    smtp.setValue(QStringLiteral("encryption"), smtpEncStr);
    smtp.setValue(QStringLiteral("smtpUsername"), username);
    smtp.setValue(QStringLiteral("authentication"), QStringLiteral("0"));
    smtp.setValue(QStringLiteral("address"), email);
    smtp.setValue(QStringLiteral("CredentialsPlugin"), QStringLiteral("marathon-classic"));

    if (!store->addAccount(&account, &cfg)) {
        qWarning() << "[MailService] addImapAccount: QMailStore::addAccount failed";
        return false;
    }

    const QString accountId = QString::number(account.id().toULongLong());
    m_setupAccountId        = account.id();

    // Now that QMF has assigned a stable id, hand the password off to the
    // helper for Secret-Service storage. The helper indexes by accountId.
    // Password goes over stdin so it never lands in /proc/<pid>/cmdline.
    m_setupHelper = new QProcess(this);
    m_setupHelper->setProgram(QStringLiteral("/usr/bin/marathon-mail-oauth"));
    m_setupHelper->setArguments({QStringLiteral("classic-add"), QStringLiteral("--account-id"),
                                 accountId, QStringLiteral("--username"), username});
    connect(m_setupHelper, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart)
            finishAccountSetup(QStringLiteral("keyring"));
    });
    connect(m_setupHelper, &QProcess::finished, this,
            [this, imapHost, imapPort, imapEncryption, smtpHost, smtpPort,
             smtpEncryption](int code, QProcess::ExitStatus status) {
                if (!m_setupHelper)
                    return;
                if (status != QProcess::NormalExit || code != 0) {
                    qWarning() << "[MailService] addImapAccount: helper failed —"
                               << m_setupHelper->readAllStandardError();
                    finishAccountSetup(QStringLiteral("keyring"));
                    return;
                }
                m_setupHelper->deleteLater();
                m_setupHelper = nullptr;
                qInfo() << "[MailService] addImapAccount: verifying accountId="
                        << m_setupAccountId.toULongLong() << "imap=" << imapHost << ":" << imapPort
                        << "(enc=" << imapEncryption << ")"
                        << "smtp=" << smtpHost << ":" << smtpPort << "(enc=" << smtpEncryption
                        << ")";
                verifyNewAccount();
            });
    connect(m_setupHelper, &QProcess::started, this, [this, password] {
        m_setupHelper->write(password.toUtf8());
        m_setupHelper->write("\n");
        m_setupHelper->closeWriteChannel();
    });
    m_setupHelper->start();
    return true;
}

// Listing the folders signs in to the IMAP server, which proves the
// password and server settings before the account is kept.
void MailService::verifyNewAccount() {
    m_setupAction = new QMailRetrievalAction(this);
    connect(m_setupAction, &QMailServiceAction::activityChanged, this,
            [this](QMailServiceAction::Activity a) {
                if (a == QMailServiceAction::Successful)
                    finishAccountSetup({});
                else if (a == QMailServiceAction::Failed)
                    finishAccountSetup(failureReason(m_setupAction->status().errorCode));
            });
    m_setupAction->retrieveFolderList(m_setupAccountId, QMailFolderId(), true);
}

void MailService::cancelAccountSetup() {
    if (m_setupAccountId.isValid())
        finishAccountSetup(QStringLiteral("cancelled"));
}

// An empty reason keeps the account; any other removes it and its password.
void MailService::finishAccountSetup(const QString &reason) {
    const QMailAccountId aid = m_setupAccountId;
    m_setupAccountId         = QMailAccountId();
    if (m_setupHelper) {
        m_setupHelper->disconnect(this);
        m_setupHelper->kill();
        m_setupHelper->deleteLater();
        m_setupHelper = nullptr;
    }
    if (m_setupAction) {
        m_setupAction->disconnect(this);
        if (m_setupAction->isRunning())
            m_setupAction->cancelOperation();
        m_setupAction->deleteLater();
        m_setupAction = nullptr;
    }
    const QString accountId = QString::number(aid.toULongLong());
    if (reason.isEmpty()) {
        qInfo() << "[MailService] addImapAccount: created accountId=" << accountId;
        setCurrentAccountId(accountId);
        emit accountSetupSucceeded(accountId);
        return;
    }
    qWarning() << "[MailService] addImapAccount: failed (" << reason << ")";
    QMailStore::instance()->removeAccount(aid);
    QProcess::startDetached(QStringLiteral("/usr/bin/marathon-mail-oauth"),
                            {QStringLiteral("remove"), QStringLiteral("--account-id"), accountId});
    emit accountSetupFailed(reason);
}

bool MailService::startOAuthLogin(const QString &provider) {
    const QString canon   = provider.toLower();
    const bool    isGmail = (canon == QStringLiteral("gmail") || canon == QStringLiteral("google"));
    const bool    isOutlook = (canon == QStringLiteral("outlook") ||
                            canon == QStringLiteral("microsoft") || canon == QStringLiteral("ms"));
    if (!isGmail && !isOutlook) {
        emit oauthLoginFailed(
            QStringLiteral("invalid_provider"),
            QStringLiteral("Unknown provider %1; expected gmail or outlook").arg(provider));
        return false;
    }

    auto *store = QMailStore::instance();
    if (!store) {
        emit oauthLoginFailed(QStringLiteral("io"), QStringLiteral("QMailStore is not available"));
        return false;
    }

    // Provider-specific IMAP + SMTP server settings. Values taken from
    // Google's / Microsoft's IMAP setup docs as of 2026 — both stable
    // for years (Gmail since 2008, Outlook IMAP since 2012). Encryption
    // codes match QMF's imap4/smtp plugins: 1=SSL/implicit, 2=STARTTLS.
    const QString imapHost =
        isGmail ? QStringLiteral("imap.gmail.com") : QStringLiteral("outlook.office365.com");
    const int     imapPort = 993;
    const QString smtpHost =
        isGmail ? QStringLiteral("smtp.gmail.com") : QStringLiteral("smtp.office365.com");
    const int     smtpPort     = isGmail ? 465 : 587;
    const int     smtpEnc      = isGmail ? 1 : 2;
    const QString providerName = isGmail ? QStringLiteral("Gmail") : QStringLiteral("Outlook");

    QMailAccount  account;
    account.setName(providerName);
    account.setMessageType(QMailMessageMetaData::Email);
    account.setStatus(QMailAccount::SynchronizationEnabled | QMailAccount::Enabled |
                          QMailAccount::CanRetrieve | QMailAccount::CanTransmit |
                          QMailAccount::MessageSource | QMailAccount::MessageSink |
                          QMailAccount::UserEditable | QMailAccount::UserRemovable,
                      true);

    QMailAccountConfiguration cfg;

    if (!cfg.addServiceConfiguration(QStringLiteral("imap4"))) {
        emit oauthLoginFailed(QStringLiteral("io"), QStringLiteral("Failed to add imap4 service"));
        return false;
    }
    QMailAccountConfiguration::ServiceConfiguration &imap =
        cfg.serviceConfiguration(QStringLiteral("imap4"));
    imap.setValue(QStringLiteral("servicetype"), QStringLiteral("source"));
    imap.setValue(QStringLiteral("version"), QStringLiteral("1"));
    imap.setValue(QStringLiteral("server"), imapHost);
    imap.setValue(QStringLiteral("port"), QString::number(imapPort));
    imap.setValue(QStringLiteral("encryption"), QStringLiteral("1")); // SSL
    // authentication=4 = OAuth2/XOAUTH2 SASL mechanism. The QMF imap4
    // plugin then asks our CredentialsPlugin for an access token via
    // QMailCredentialsInterface::accessToken().
    imap.setValue(QStringLiteral("authentication"), QStringLiteral("4"));
    imap.setValue(QStringLiteral("checkInterval"), QStringLiteral("0"));
    imap.setValue(QStringLiteral("pushEnabled"), QStringLiteral("1"));
    imap.setValue(QStringLiteral("CredentialsPlugin"), QStringLiteral("marathon-oauth"));

    if (!cfg.addServiceConfiguration(QStringLiteral("smtp"))) {
        emit oauthLoginFailed(QStringLiteral("io"), QStringLiteral("Failed to add smtp service"));
        return false;
    }
    QMailAccountConfiguration::ServiceConfiguration &smtp =
        cfg.serviceConfiguration(QStringLiteral("smtp"));
    smtp.setValue(QStringLiteral("servicetype"), QStringLiteral("sink"));
    smtp.setValue(QStringLiteral("version"), QStringLiteral("1"));
    smtp.setValue(QStringLiteral("server"), smtpHost);
    smtp.setValue(QStringLiteral("port"), QString::number(smtpPort));
    smtp.setValue(QStringLiteral("encryption"), QString::number(smtpEnc));
    smtp.setValue(QStringLiteral("authentication"), QStringLiteral("4"));
    smtp.setValue(QStringLiteral("CredentialsPlugin"), QStringLiteral("marathon-oauth"));

    if (!store->addAccount(&account, &cfg)) {
        emit oauthLoginFailed(QStringLiteral("io"),
                              QStringLiteral("QMailStore::addAccount failed"));
        return false;
    }

    const QString accountId      = QString::number(account.id().toULongLong());
    const QString helperProvider = isGmail ? QStringLiteral("gmail") : QStringLiteral("outlook");

    // Spawn the helper as a long-running process. The helper:
    //   • binds 127.0.0.1:<random>, prints the auth URL on stderr
    //   • blocks waiting for the loopback redirect
    //   • on success, writes the Added envelope to stdout and exits 0
    auto *proc       = new QProcess(this);
    m_oauthHelper    = proc;
    m_oauthCancelled = false;
    proc->setProgram(QStringLiteral("/usr/bin/marathon-mail-oauth"));
    proc->setArguments({QStringLiteral("add"), QStringLiteral("--provider"), helperProvider,
                        QStringLiteral("--account-id"), accountId});
    proc->setProcessChannelMode(QProcess::SeparateChannels);

    connect(proc, &QProcess::readyReadStandardError, this, [this, proc] {
        // The helper writes the auth URL on its own line on stderr.
        // Capture the FIRST line that looks like an HTTPS URL — that's
        // the prompt. Anything else (warnings, debug) gets dropped.
        for (const auto &line : proc->readAllStandardError().split('\n')) {
            const QString s = QString::fromUtf8(line.trimmed());
            if (s.startsWith(QStringLiteral("https://"))) {
                emit oauthAuthUrlReady(s);
                return;
            }
        }
    });

    auto        accountIdCopy = accountId;
    QByteArray *stdoutBuf     = new QByteArray;
    connect(proc, &QProcess::readyReadStandardOutput, this,
            [proc, stdoutBuf] { stdoutBuf->append(proc->readAllStandardOutput()); });
    connect(proc, &QProcess::finished, this,
            [this, store, proc, stdoutBuf, accountIdCopy, account](int, QProcess::ExitStatus es) {
                stdoutBuf->append(proc->readAllStandardOutput());

                // Find the last non-empty JSON line.
                QByteArray last;
                for (const auto &line : stdoutBuf->split('\n'))
                    if (!line.trimmed().isEmpty())
                        last = line;

                const auto doc  = QJsonDocument::fromJson(last);
                const auto obj  = doc.object();
                const auto kind = obj.value(QStringLiteral("kind")).toString();

                proc->deleteLater();
                delete stdoutBuf;

                if (m_oauthCancelled) {
                    m_oauthCancelled = false;
                    store->removeAccount(account.id());
                    emit oauthLoginFailed(QStringLiteral("cancelled"),
                                          QStringLiteral("Sign-in cancelled"));
                    return;
                }
                if (es != QProcess::NormalExit || kind == QStringLiteral("error")) {
                    const auto code =
                        obj.value(QStringLiteral("code")).toString(QStringLiteral("io"));
                    const auto msg = obj.value(QStringLiteral("message"))
                                         .toString(QStringLiteral("OAuth helper failed"));
                    QMailAccount toRemove(account.id());
                    Q_UNUSED(toRemove);
                    store->removeAccount(account.id());
                    emit oauthLoginFailed(code, msg);
                    return;
                }
                if (kind != QStringLiteral("added")) {
                    store->removeAccount(account.id());
                    emit oauthLoginFailed(QStringLiteral("io"),
                                          QStringLiteral("Unexpected helper reply: ") + kind);
                    return;
                }

                // Backfill the From: address now that the helper has
                // fetched it from the userinfo endpoint.
                const QString email = obj.value(QStringLiteral("email")).toString();
                if (!email.isEmpty()) {
                    QMailAccount acct(account.id());
                    acct.setFromAddress(QMailAddress(acct.name(), email));
                    store->updateAccount(&acct, nullptr);
                }

                setCurrentAccountId(accountIdCopy);
                emit oauthLoginSucceeded(accountIdCopy);
            });

    // start() not startDetached() — we need the QProcess signals to
    // fire on stdout/stderr/finished. The lambdas above keep the
    // process attached to MailService's lifetime.
    proc->start();
    if (!proc->waitForStarted(2000)) {
        store->removeAccount(account.id());
        delete stdoutBuf;
        proc->deleteLater();
        emit oauthLoginFailed(QStringLiteral("io"),
                              QStringLiteral("Could not start /usr/bin/marathon-mail-oauth"));
        return false;
    }
    return true;
}

void MailService::cancelOAuthLogin() {
    if (!m_oauthHelper || m_oauthHelper->state() == QProcess::NotRunning)
        return;
    m_oauthCancelled = true;
    m_oauthHelper->kill();
}

void MailService::checkOAuthProviders() {
    if (m_oauthProvidersChecked)
        return;
    m_oauthProvidersChecked = true;
    auto *proc              = new QProcess(this);
    connect(proc, &QProcess::finished, this, [this, proc](int code, QProcess::ExitStatus status) {
        proc->deleteLater();
        if (status != QProcess::NormalExit || code != 0)
            return;
        const auto reply = QJsonDocument::fromJson(proc->readAllStandardOutput()).object();
        QStringList found;
        for (const auto &v : reply.value(QStringLiteral("configured")).toArray())
            found << v.toString();
        if (found != m_oauthProviders) {
            m_oauthProviders = found;
            emit oauthProvidersChanged();
        }
    });
    connect(proc, &QProcess::errorOccurred, proc, &QObject::deleteLater);
    proc->start(QStringLiteral("/usr/bin/marathon-mail-oauth"), {QStringLiteral("providers")});
}

#include "mailservice.moc"
