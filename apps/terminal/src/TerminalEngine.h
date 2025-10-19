#pragma once

#include <QObject>
#include <QProcess>
#include <QString>
#include <QQmlEngine>
#include <QTimer>

class TerminalEngine : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString output READ output NOTIFY outputChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString workingDirectory READ workingDirectory WRITE setWorkingDirectory NOTIFY workingDirectoryChanged)
    
public:
    explicit TerminalEngine(QObject *parent = nullptr);
    ~TerminalEngine() override;
    
    QString output() const { return m_output; }
    bool running() const { return m_process && m_process->state() == QProcess::Running; }
    QString workingDirectory() const { return m_workingDirectory; }
    
    void setWorkingDirectory(const QString &dir);
    
    Q_INVOKABLE void start();
    Q_INVOKABLE void sendInput(const QString &text);
    Q_INVOKABLE void sendCtrlC();
    Q_INVOKABLE void sendCtrlD();
    Q_INVOKABLE void clear();
    Q_INVOKABLE void terminate();
    
signals:
    void outputChanged();
    void runningChanged();
    void workingDirectoryChanged();
    void newOutput(const QString &text);
    void processExited(int exitCode);
    
private slots:
    void handleReadyRead();
    void handleFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void handleError(QProcess::ProcessError error);
    
private:
    QProcess *m_process;
    QString m_output;
    QString m_workingDirectory;
    QString getDefaultShell();
};

