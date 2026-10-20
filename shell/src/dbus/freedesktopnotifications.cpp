#include "freedesktopnotifications.h"
#include "../ipc/callerpid.h"
#include "appmodel.h"
#include "nemoremoteaction.h"
#include "marathonappregistry.h"
#include "notificationmodel.h"
#include "notificationtarget.h"
#include "marathon-shell-native/src/power.cxxqt.h"
#include <QBuffer>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QDBusServiceWatcher>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDateTime>
#include <QDebug>
#include <QCoreApplication>
#include <QImage>
#include <QTimer>

namespace {

    // image-data's (iiibiiay): width, height, rowstride, has_alpha,
    // bits_per_sample, channels, bytes.
    QImage imageFromHint(const QVariant &hint) {
        if (!hint.canConvert<QDBusArgument>())
            return {};
        const QDBusArgument arg   = hint.value<QDBusArgument>();
        int                 width = 0, height = 0, stride = 0, bits = 0, channels = 0;
        bool                alpha = false;
        QByteArray          bytes;
        arg.beginStructure();
        arg >> width >> height >> stride >> alpha >> bits >> channels >> bytes;
        arg.endStructure();
        if (width <= 0 || height <= 0 || bits != 8 || channels != (alpha ? 4 : 3) ||
            stride < width * channels || qint64(stride) * height > bytes.size())
            return {};
        // copy(): the QImage would otherwise borrow the local bytes.
        QImage image = QImage(reinterpret_cast<const uchar *>(bytes.constData()), width, height,
                              stride, alpha ? QImage::Format_RGBA8888 : QImage::Format_RGB888)
                           .copy();
        if (width <= 128 && height <= 128)
            return image;
        return image.scaled(128, 128, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }

    // The spec's order: image-data, image-path, then app_icon. Pixels travel
    // as a data URL so the Hub keeps them across restarts.
    QString notificationIcon(const QString &appIcon, QVariantMap &hints) {
        const QImage  image = imageFromHint(hints.take(QStringLiteral("image-data")));
        const QString path  = hints.value(QStringLiteral("image-path")).toString();
        if (image.isNull())
            return path.isEmpty() ? appIcon : path;
        QByteArray png;
        QBuffer    buffer(&png);
        buffer.open(QIODevice::WriteOnly);
        image.save(&buffer, "PNG");
        return QStringLiteral("data:image/png;base64,") + QString::fromLatin1(png.toBase64());
    }

} // namespace

FreedesktopNotifications::FreedesktopNotifications(NotificationDatabase *database,
                                                   NotificationModel    *model,
                                                   Power *powerManager, QObject *parent)
    : QObject(parent)
    , m_database(database)
    , m_model(model)
    , m_powerManager(powerManager) {
    // A row the user swiped away (or opened) must not come back on restart.
    if (m_model) {
        connect(m_model, &NotificationModel::notificationDismissed, this, [this](int id) {
            if (id > 0 && m_database->dismiss(uint(id)))
                emit NotificationClosed(uint(id), 2);
        });
        connect(m_model, &NotificationModel::notificationRead, this, [this](int id) {
            if (id > 0)
                m_database->markAsRead(uint(id));
        });
    }
}

FreedesktopNotifications::~FreedesktopNotifications() = default;

bool FreedesktopNotifications::registerService() {
    QDBusConnection bus = QDBusConnection::sessionBus();

    if (!bus.registerService("org.freedesktop.Notifications")) {
        qDebug() << "[FreedesktopNotifications] org.freedesktop.Notifications already registered "
                    "(desktop environment)";

        if (bus.registerService("org.marathon.Notifications")) {
            qInfo() << "[FreedesktopNotifications] Registered fallback service: "
                       "org.marathon.Notifications";

            if (!bus.registerObject("/org/freedesktop/Notifications", this,
                                    QDBusConnection::ExportAllSlots |
                                        QDBusConnection::ExportAllSignals)) {
                qWarning() << "[FreedesktopNotifications] Failed to register object on fallback:"
                           << bus.lastError().message();
                return false;
            }
            return true;
        }

        qDebug() << "[FreedesktopNotifications] This is expected on desktop and will work on "
                    "actual device";
        return false;
    }

    if (!bus.registerObject("/org/freedesktop/Notifications", this,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals)) {
        qWarning() << "[FreedesktopNotifications] Failed to register object:"
                   << bus.lastError().message();
        return false;
    }

    qInfo() << "[FreedesktopNotifications] Registered org.freedesktop.Notifications on D-Bus";
    return true;
}

void FreedesktopNotifications::setAppRegistry(MarathonAppRegistry *registry) {
    m_registry = registry;
}

void FreedesktopNotifications::setAppModel(AppModel *apps) {
    m_apps = apps;
}

void FreedesktopNotifications::activate(uint id, const QString &action) {
    emit ActionInvoked(id, action);
    const auto records = m_database->getNotifications();
    for (const auto &record : records) {
        if (record.id != id)
            continue;
        const QString hint = record.metadata.value(NemoRemoteAction::hintName(action)).toString();
        bool          ok   = false;
        const QDBusMessage call = NemoRemoteAction::decode(hint, &ok);
        if (ok)
            QDBusConnection::sessionBus().asyncCall(call);
        // As the spec has it, an action closes the notification unless it is
        // resident. A tap is closed by NotificationHandler once the app is open.
        if (action != QLatin1String("default") &&
            !record.metadata.value(QStringLiteral("resident")).toBool() && m_model)
            m_model->dismissNotification(int(id));
        return;
    }
}

uint FreedesktopNotifications::Notify(const QString &app_name, uint replaces_id,
                                      const QString &app_icon, const QString &summary,
                                      const QString &body, const QStringList &actions,
                                      const QVariantMap &hints, int expire_timeout) {
    QVariantList actionList;
    for (int i = 0; i < actions.size(); i += 2) {
        if (i + 1 < actions.size()) {
            QVariantMap action;
            action["key"]   = actions[i];
            action["label"] = actions[i + 1];
            actionList.append(action);
        }
    }

    const bool ongoing = hints.contains(QStringLiteral("value"));

    // Progress moves the row it replaces without a new banner or sound.
    if (ongoing && replaces_id > 0 && m_model) {
        const Notification *shown = m_model->getNotification(int(replaces_id));
        if (shown && shown->ongoing()) {
            QVariantMap metadata = hints;
            m_model->updateNotification(int(replaces_id), summary, body,
                                        notificationIcon(app_icon, metadata), actionList, metadata);
            trackSender(replaces_id);
            return replaces_id;
        }
    }

    QString appId = extractAppName(app_name, hints);

    qInfo() << "[FreedesktopNotifications] Notify from:" << appId << "title:" << summary;

    // Transient (the spec's hint): shown, then gone, with no record, Hub row
    // or sound. x-marathon-toast (Deckard's Android toasts) is a bottom toast.
    const bool toast = hints.value(QStringLiteral("x-marathon-toast")).toBool();
    if (toast || hints.value(QStringLiteral("transient")).toBool()) {
        QVariantMap metadata = hints;
        const uint  id       = m_nextTransientId++;
        const QVariantMap shown{{"id", id},
                                {"appId", appId},
                                {"title", summary},
                                {"body", body},
                                {"icon", notificationIcon(app_icon, metadata)},
                                {"actions", actionList},
                                {"actionIcons", hints.value(QStringLiteral("action-icons")).toBool()}};
        if (toast)
            emit toastRequested(shown);
        else
            emit bannerRequested(shown);
        QTimer::singleShot(expire_timeout > 0 ? expire_timeout : 5000, this,
                           [this, id]() { emit NotificationClosed(id, 1); });
        return id;
    }

    if (replaces_id > 0) {
        m_database->dismiss(replaces_id);
        if (m_model) {
            m_model->dismissNotification(replaces_id);
        }
    }

    NotificationDatabase::NotificationRecord record;
    record.metadata  = hints;
    record.appId     = appId;
    record.title     = summary;
    record.body      = body;
    record.iconPath  = notificationIcon(app_icon, record.metadata);
    record.timestamp = QDateTime::currentDateTime();
    record.read      = false;
    record.dismissed = false;

    record.metadata["expire_timeout"] = expire_timeout;

    if (hints.contains("category")) {
        record.category = hints.value("category").toString();
    } else {
        record.category = "general";
    }

    record.priority = mapUrgencyToPriority(hints);

    int urgency = hints.value("urgency", 1).toInt();
    if (urgency >= 2 && m_powerManager) {
        m_powerManager->acquireWakelock("notification");
        qInfo() << "[FreedesktopNotifications] Acquired wakelock for critical notification";

        QTimer::singleShot(5000, this, [this]() {
            if (m_powerManager) {
                m_powerManager->releaseWakelock("notification");
                qInfo() << "[FreedesktopNotifications] Released notification wakelock";
            }
        });
    }

    record.actions = actionList;
    const QString replyPlaceholder = hints.value("x-kde-reply-placeholder-text").toString();

    uint id = m_database->saveNotification(record);
    if (ongoing && id > 0)
        trackSender(id);

    if (m_model) {
        if (id > 0) {
            // Adopt the database's row id so the model and the database
            // share one id space. They were independent counters, which
            // made the replaces_id dismissal below able to evict an
            // unrelated Hub row.
            m_model->addNotificationWithId(static_cast<int>(id), appId, summary, body,
                                           record.iconPath, actionList, replyPlaceholder,
                                           record.metadata);
        } else {
            // saveNotification returns 0 on insert failure, and 0 is not a
            // valid id: two failures in a row would have put two rows under
            // id 0 and orphaned the first. Fall back to a transient id so
            // the notification still reaches the Hub.
            qWarning() << "[FreedesktopNotifications] Persist failed; "
                          "showing" << summary << "as transient";
            m_model->addNotification(appId, summary, body, record.iconPath, actionList,
                                     replyPlaceholder, record.metadata);
        }
    }

    return id;
}

// An ongoing row lasts only as long as its sender: one that quits or
// crashes mid-job can no longer finish or close it.
void FreedesktopNotifications::trackSender(uint id) {
    if (!calledFromDBus())
        return;
    const QString sender = message().service();
    if (!m_senderWatcher) {
        m_senderWatcher = new QDBusServiceWatcher(
            QString(), connection(), QDBusServiceWatcher::WatchForUnregistration, this);
        connect(m_senderWatcher, &QDBusServiceWatcher::serviceUnregistered, this,
                &FreedesktopNotifications::onSenderGone);
    }
    m_senderWatcher->addWatchedService(sender);
    m_senders.insert(id, sender);
}

void FreedesktopNotifications::onSenderGone(const QString &sender) {
    m_senderWatcher->removeWatchedService(sender);
    for (auto it = m_senders.begin(); it != m_senders.end();) {
        if (it.value() != sender) {
            ++it;
            continue;
        }
        const Notification *shown = m_model ? m_model->getNotification(int(it.key())) : nullptr;
        if (shown && shown->ongoing())
            CloseNotification(it.key());
        it = m_senders.erase(it);
    }
}

void FreedesktopNotifications::CloseNotification(uint id) {
    qDebug() << "[FreedesktopNotifications] CloseNotification:" << id;

    if (m_database->dismiss(id)) {
        emit NotificationClosed(id, 3);
    }
    if (m_model)
        m_model->dismissNotification(int(id));
}

QStringList FreedesktopNotifications::GetCapabilities() {

    return QStringList{"actions",     "body",         "body-markup", "icon-static",
                       "persistence", "action-icons", "inline-reply"};
}

void FreedesktopNotifications::InvokeReply(uint id, const QString &text) {
    qInfo() << "[FreedesktopNotifications] InvokeReply:" << id << "text:" << text;
    emit NotificationReplied(id, text);
}

void FreedesktopNotifications::GetServerInformation(QString &name, QString &vendor,
                                                    QString &version, QString &spec_version) {
    name    = "Marathon Notification Service";
    vendor  = "Marathon OS";
    version = QCoreApplication::applicationVersion();
    if (version.isEmpty()) {
        version = "1.0.0";
    }
    spec_version = "1.2";

    qDebug() << "[FreedesktopNotifications] GetServerInformation called";
}

QString FreedesktopNotifications::extractAppName(const QString     &provided,
                                                 const QVariantMap &hints) {
    // app_name is a display name the sender picks; the desktop-entry hint and
    // the sender's own app scope say which installed app it really is.
    QString senderApp;
    if (calledFromDBus() && connection().interface()) {
        if (const qint64 pid = callerPid(connection(), message().service()); pid >= 0)
            senderApp = NotificationTarget::appForPid(pid);
    }
    QString installed = NotificationTarget::resolve(
        {hints.value(QStringLiteral("desktop-entry")).toString(), senderApp, provided}, m_registry);
    if (!installed.isEmpty())
        return installed;

    QString desktopEntry = hints.value(QStringLiteral("desktop-entry")).toString();
    if (desktopEntry.endsWith(QLatin1String(".desktop")))
        desktopEntry.chop(int(qstrlen(".desktop")));
    if (!desktopEntry.isEmpty() && m_apps && m_apps->getApp(desktopEntry))
        return desktopEntry;

    // An entry no app lists ("waydroid.com.android.deskclock") says less
    // than the name the sender gave.
    if (!provided.isEmpty())
        return provided;
    if (!desktopEntry.isEmpty())
        return desktopEntry;

    if (calledFromDBus()) {
        return message().service();
    }

    return "unknown";
}

int FreedesktopNotifications::mapUrgencyToPriority(const QVariantMap &hints) {

    if (hints.contains("urgency")) {
        int urgency = hints.value("urgency").toInt();
        switch (urgency) {
            case 0: return 0;
            case 1: return 1;
            case 2: return 3;
            default: return 1;
        }
    }

    return 1;
}
