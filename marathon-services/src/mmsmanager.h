#ifndef MMSMANAGER_H
#define MMSMANAGER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QDBusInterface>
#include <QDBusObjectPath>
#include <QVariantMap>
#include <QVariantList>

// Thin client over mmsd-tng (org.ofono.mms) — the de-facto MMS daemon on
// Linux mobile, used by Plasma Mobile (Spacebar) and Phosh (Chatty).
//
// The daemon is D-Bus session-bus-activated; calling any method spins it up.
// We never start/stop it ourselves.
//
// Method semantics mirror the Service API documented in mmsd-tng's
// doc/service-api.txt. The daemon defines:
//   Manager.GetServices()                  -> a(oa{sv})
//   Service.SendMessage(as, v, a(sss))     -> o
//   Service.MessageAdded / MessageRemoved
//   Message.Status property + PropertyChanged
class MmsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QString servicePath READ servicePath NOTIFY servicePathChanged)

  public:
    struct MmsAttachment {
        QString contentId;   // arbitrary token like "cid-1"
        QString contentType; // e.g. "image/jpeg"
        QString filePath;    // absolute path mmsd will read
    };

    explicit MmsManager(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    QString servicePath() const {
        return m_servicePath;
    }

    // Send an MMS. Recipients are E.164. text is the body (may be empty if
    // attachments-only). attachments may be empty for a text-only group MMS.
    // Returns true if the request was accepted by mmsd; final delivery is
    // signalled via MessageStatusChanged.
    Q_INVOKABLE bool sendMms(const QStringList &recipients, const QString &text,
                             const QVariantList &attachments = {});

  signals:
    void availableChanged();
    void servicePathChanged();
    void messageReceived(const QString &sender, const QString &text, qint64 timestamp,
                         const QVariantList &attachments);
    void messageSent(const QString &messagePath);
    void messageStatusChanged(const QString &messagePath, const QString &status);
    void sendFailed(const QString &reason);

  private slots:
    void onMessageAdded(const QDBusObjectPath &path, const QVariantMap &props);
    void onMessageRemoved(const QDBusObjectPath &path);
    void onMessageSendError(const QVariantMap &errorInfo);
    void onMessageReceiveError(const QVariantMap &errorInfo);

  private:
    void            discoverService();
    bool            stageAttachmentsToTmp(const QVariantList &incoming, QList<MmsAttachment> &out,
                                          QStringList &stagedPaths);

    QDBusInterface *m_manager; // /org/ofono/mms
    QString         m_servicePath;
    QDBusInterface *m_service; // resolved from GetServices()[0]
    bool            m_available;
};

#endif
