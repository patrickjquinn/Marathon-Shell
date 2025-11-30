#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QtQmlIntegration>
#include "TerminalScreen.h"

class QSocketNotifier;

class TerminalEngine : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(TerminalScreen *screen READ screen CONSTANT)

  public:
    explicit TerminalEngine(QObject *parent = nullptr);
    ~TerminalEngine() override;

    bool running() const {
        return m_pid > 0;
    }
    QString title() const {
        return m_title;
    }
    TerminalScreen *screen() const {
        return m_screen;
    }

    Q_INVOKABLE void start(const QString &shell = "");
    Q_INVOKABLE void sendInput(const QString &text);
    Q_INVOKABLE void sendKey(int key, const QString &text, int modifiers = 0);
    Q_INVOKABLE void terminate();
    Q_INVOKABLE void resize(int cols, int rows);
    Q_INVOKABLE void sendSignal(int signal);

    // Mouse handling
    Q_INVOKABLE void sendMousePress(int x, int y, int button);
    Q_INVOKABLE void sendMouseRelease(int x, int y, int button);
    Q_INVOKABLE void sendMouseMove(int x, int y, int buttons);

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

    int              m_masterFd;
    pid_t            m_pid;
    QSocketNotifier *m_notifier;
    QString          m_title;
    TerminalScreen  *m_screen;

    // ANSI parser state
    enum State {
        Normal,
        Escape,
        CSI,    // Control Sequence Introducer [
        OSC,    // Operating System Command ]
        Charset // ( or )
    };

    State        m_state;
    QString      m_sequenceBuffer;
    QVector<int> m_params;
};
