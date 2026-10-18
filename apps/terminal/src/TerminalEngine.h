#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QtQmlIntegration/qqmlintegration.h>
#include "TerminalScreen.h"

class QSocketNotifier;

class TerminalEngine : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    // The shell couldn't start, or died within moments of starting; a
    // restart would only fail again, so the session waits for the user.
    Q_PROPERTY(bool failed READ failed NOTIFY runningChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(TerminalScreen *screen READ screen CONSTANT)

  public:
    explicit TerminalEngine(QObject *parent = nullptr);
    ~TerminalEngine() override;

    bool running() const {
        return m_pid > 0;
    }
    bool failed() const {
        return m_failed;
    }
    QString title() const {
        return m_title;
    }
    TerminalScreen *screen() const {
        return m_screen;
    }

    Q_INVOKABLE void start(const QString &shell = "");
    Q_INVOKABLE void sendInput(const QString &text) const;
    Q_INVOKABLE void sendKey(int key, const QString &text, int modifiers = 0) const;
    Q_INVOKABLE void terminate();
    Q_INVOKABLE void resize(int cols, int rows);
    Q_INVOKABLE QStringList recentLines(int count) const;

  signals:
    void runningChanged();
    void titleChanged();
    void finished(int exitCode);

  private slots:
    void onReadActivated();

  private:
    void             processOutput(const QByteArray &data);
    void             parseEscapeSequence(char ch);
    void             handleCSI(const QString &seq);
    void             handleOSC(const QString &seq);
    void             writeNotice(const QString &text);

    int              m_masterFd;
    pid_t            m_pid;
    bool             m_failed;
    QString          m_shell;
    QElapsedTimer    m_started;
    QSocketNotifier *m_notifier;
    QString          m_title;
    TerminalScreen  *m_screen;

    enum State : quint8 {
        Normal,
        Escape,
        CSI,
        OSC,
        Charset
    };

    State        m_state;
    QString      m_sequenceBuffer;
    QVector<int> m_params;
};
