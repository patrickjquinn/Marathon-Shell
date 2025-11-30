#pragma once

#include <QObject>
#include <QString>
#include <functional>

/**
 * @brief CrashHandler - Provides crash protection for Marathon Shell
 * 
 * This class installs signal handlers to catch crashes (SIGSEGV, SIGABRT, etc.)
 * and attempts to prevent them from taking down the entire shell.
 * 
 * WARNING: This is a MITIGATION, not a solution. The proper fix is to run
 * apps in separate processes. Signal handlers have limitations and can't
 * always recover from all types of crashes.
 */
class CrashHandler : public QObject {
    Q_OBJECT

  public:
    static CrashHandler *instance();

    // Install crash handlers
    void install();

    // Set callback for crash notifications
    void setCrashCallback(std::function<void(const QString &)> callback);

    // Check if we're currently in a crash handler
    static bool isInCrashHandler();

  signals:
    void crashDetected(const QString &signal, const QString &message);

  private:
    explicit CrashHandler(QObject *parent = nullptr);
    ~CrashHandler() override;

    static void                          signalHandler(int signum);
    static void                          setupSignalHandlers();

    std::function<void(const QString &)> m_crashCallback;
    static CrashHandler                 *s_instance;
    static bool                          s_inCrashHandler;
};
