#pragma once

#include <QObject>
#include <QString>

class SecurityManager;

// Settings' "Erase all content" (docs/FACTORY_RESET.md). Once the owner's
// PIN checks out, asks the root marathon-factory-reset service for an erase
// at the next boot; that service restarts the device. Its socket is outside
// every app sandbox, and exists only on images that can erase themselves.
class FactoryReset : public QObject {
    Q_OBJECT

  public:
    static constexpr const char *SOCKET = "/run/marathon/factory-reset.sock";

    explicit FactoryReset(SecurityManager *security, QString socketPath = QString::fromLatin1(SOCKET),
                          QObject *parent = nullptr);

    bool supported() const;
    void erase(const QString &secret);

  signals:
    void failed(const QString &reason);

  private:
    SecurityManager *m_security;
    QString          m_socketPath;
};
