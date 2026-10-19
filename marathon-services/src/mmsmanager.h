#ifndef MMSMANAGER_H
#define MMSMANAGER_H

#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusVariant>
#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

class QDBusServiceWatcher;

// The shell's client of mmsd-tng (org.ofono.mms, session bus,
// doc/service-api.txt and doc/message-api.txt in mmsd-tng). Every call is
// asynchronous: mmsd-tng is bus-activated, and nothing here may block the
// shell's thread on it.
class MmsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

  public:
    // A part to send. filePath is a file the shell owns; mmsd-tng reads it
    // when the message is queued.
    struct Part {
        QString contentType;
        QString name;
        QString filePath;
    };

    explicit MmsManager(QObject *parent = nullptr);

    bool available() const {
        return !m_servicePath.isEmpty();
    }
    // The carrier's limits, as mmsd-tng reports them (0: not reported).
    qint64 maxAttachmentSize() const {
        return m_maxAttachmentSize;
    }
    int maxAttachments() const {
        return m_maxAttachments;
    }

    // Queues a message with mmsd-tng: queued(token, path) or
    // failed(token, reason) follows.
    void send(int token, const QStringList &recipients, const QString &text,
              const QList<Part> &parts);

  signals:
    void availableChanged();
    // attachments: [{name, contentType, data}], the text parts joined in text.
    void received(const QString &path, const QString &sender, const QStringList &recipients,
                  const QString &text, qint64 timestamp, const QVariantList &attachments);
    void queued(int token, const QString &path);
    void failed(int token, const QString &reason);
    // A queued message became "sent" or "failed".
    void statusChanged(const QString &path, const QString &status);

  private slots:
    void onMessageAdded(const QDBusObjectPath &path, const QVariantMap &props);
    void onMessageSendError(const QVariantMap &errorInfo);
    void onMessagePropertyChanged(const QString &name, const QDBusVariant &value,
                                  const QDBusMessage &message);

  private:
    void discover();
    void forget();

    QDBusServiceWatcher *m_watcher = nullptr;
    QString              m_servicePath;
    qint64               m_maxAttachmentSize = 0;
    int                  m_maxAttachments    = 0;
};

#endif
