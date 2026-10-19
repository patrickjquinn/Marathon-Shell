#pragma once

#include <QDBusContext>
#include <QDBusServiceWatcher>
#include <QObject>
#include <QString>
#include <QVariant>

#include <functional>

class QInputMethodEvent;

// Marathon's keyboard for apps whose input method is a session service
// (Deckard's Android IME, through deckardd), not text-input on their surface.
class RemoteTextInput : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString appIdPrefix READ appIdPrefix NOTIFY appIdPrefixChanged)
    // The app shown in the app window, or empty.
    Q_PROPERTY(QString frontAppId READ frontAppId WRITE setFrontAppId NOTIFY frontAppIdChanged)

  public:
    // The app id of the window a focus object shows, or empty.
    using AppIdOf = std::function<QString(QObject *)>;
    // Keys sent from a QInputDevice of this name come from the on-screen keyboard.
    // NOLINTNEXTLINE(bugprone-throwing-static-initialization) QStringLiteral never allocates
    static inline const QString kKeyboardDevice = QStringLiteral("marathon-osk");

    explicit RemoteTextInput(AppIdOf appIdOf, QObject *parent = nullptr);
    ~RemoteTextInput() override;

    QString appIdPrefix() const {
        return m_prefix;
    }
    QString frontAppId() const {
        return m_frontAppId;
    }
    void setFrontAppId(const QString &appId);
    // The app's windows get the keyboard's height from their input method,
    // so the shell must not shrink them too.
    Q_INVOKABLE bool handles(const QString &appId) const;
    // How much of the app's window the keyboard covers, out of its height.
    Q_INVOKABLE void setPanel(const QString &appId, int covered, int height);

    // The service's side; false when the app id is not the service's.
    void setService(const QString &appIdPrefix);
    bool setEditor(const QString &appId, uint purpose, uint hints);
    bool setSurroundingText(const QString &appId, const QString &text, int cursor, int anchor);
    bool clearEditor(const QString &appId);
    bool requestPanel(const QString &appId, bool show);

    // zwp_text_input_v3 content purpose and hints as Qt hints.
    static Qt::InputMethodHints qtHints(uint purpose, uint hints);

  signals:
    void appIdPrefixChanged();
    void frontAppIdChanged();
    void panelRequested(bool show);
    void hintsChanged();
    void commitString(const QString &appId, const QString &text, int before, int after);
    void key(const QString &appId, const QString &name);
    void panelChanged(const QString &appId, int covered, int height);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    bool     owns(const QString &appId) const;
    bool     targets(QObject *object) const;
    QVariant query(Qt::InputMethodQuery query) const;
    void     commit(const QInputMethodEvent &event);
    void     edit(const QString &text, int before, int after);

    struct Editor {
        QString              appId;
        Qt::InputMethodHints hints;
        QString              text;
        int                  cursor = 0;
        int                  anchor = 0;
    };

    AppIdOf m_appIdOf;
    QString m_prefix;
    Editor  m_editor;
    QString m_panelAppId;
    QString m_frontAppId;
    int     m_covered = -1;
    int     m_height  = -1;
};

// org.marathonos.Shell.TextInput1 on /org/marathonos/Shell/TextInput, for one
// session service declaring the "text-input" permission. Its events go to it
// alone, as targeted signals.
class RemoteTextInputService : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.TextInput1")

  public:
    explicit RemoteTextInputService(RemoteTextInput *input, QObject *parent = nullptr);

  public slots:
    // Claims the windows whose app id starts with appIdPrefix.
    void Register(const QString &appIdPrefix);
    void SetEditor(const QString &appId, uint purpose, uint hints);
    void SetSurroundingText(const QString &appId, const QString &text, int cursor, int anchor);
    void ClearEditor(const QString &appId);
    void ShowPanel(const QString &appId);
    void HidePanel(const QString &appId);

  private:
    bool                fromOwner();
    void                send(const QString &name, const QVariantList &arguments);

    RemoteTextInput    *m_input;
    QString             m_owner;
    QDBusServiceWatcher m_watcher;
};
