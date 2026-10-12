#pragma once

#include <QDBusConnection>
#include <QHash>
#include <QList>
#include <QObject>
#include <QVariantMap>

#include <functional>

class QDBusServer;

// The Keel host contract (Keel's shell/PROTOCOL.md, version 1): the
// environment a Keel app reads at start and a peer-to-peer D-Bus server with
// org.shipwright.keel.Shell1. keel-shell plays this role on Sailfish; the
// runner plays it on Marathon.
class KeelHost : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.shipwright.keel.Shell1")
    Q_PROPERTY(int ProtocolVersion READ protocolVersion)
    Q_PROPERTY(int Orientation READ orientation)
    Q_PROPERTY(int ContentOrientation READ contentOrientation)
    Q_PROPERTY(bool Active READ active)
    Q_PROPERTY(int CoverStatus READ coverStatus)
    Q_PROPERTY(QVariantMap Ambience READ ambience)
    Q_PROPERTY(int Dpi READ dpi)

  public:
    explicit KeelHost(int dpi, QObject *parent = nullptr);

    bool                    start(const QString &runtimeDir);
    QString                 address() const;
    QHash<QString, QString> environment() const;

    void setAmbience(const QVariantMap &ambience);
    void setActive(bool active);
    // 1 while the app's cover is on screen in the task switcher.
    void setCoverStatus(int status);
    void requestClose();

    int protocolVersion() const {
        return 1;
    }
    int orientation() const {
        return 0;
    }
    int contentOrientation() const {
        return m_contentOrientation;
    }
    bool active() const {
        return m_active;
    }
    int coverStatus() const {
        return m_coverStatus;
    }
    QVariantMap ambience() const {
        return m_ambience;
    }
    int dpi() const {
        return m_dpi;
    }

    std::function<void()> onActivate;

  public slots:
    QString     Ping();
    QVariantMap GetAmbience();
    void        Activate() const;
    void        SetContentOrientation(int degrees);

  signals:
    void OrientationChanged(int degrees);
    void ContentOrientationChanged(int degrees);
    void ActiveChanged(bool active);
    void CoverStatusChanged(int status);
    void AmbienceChanged(const QVariantMap &ambience);
    void DpiChanged(int dpi);
    void CloseRequested();

  private:
    QDBusServer           *m_server = nullptr;
    QList<QDBusConnection> m_peers;
    QVariantMap            m_ambience;
    bool                   m_active             = false;
    int                    m_coverStatus        = 0;
    int                    m_contentOrientation = 0;
    int                    m_dpi;
};

// A Keel app's window close (xdg_toplevel.close from the task switcher)
// becomes CloseRequested: the first close is held back and reported, so the
// app gets its grace period before the runner quits.
class KeelCloseGuard : public QObject {
    Q_OBJECT

  public:
    explicit KeelCloseGuard(std::function<void()> onFirstClose, QObject *parent = nullptr)
        : QObject(parent)
        , m_onFirstClose(std::move(onFirstClose)) {}

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    std::function<void()> m_onFirstClose;
    bool                  m_closing = false;
};
