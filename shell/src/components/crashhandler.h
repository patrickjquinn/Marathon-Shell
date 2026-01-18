#pragma once

#include <QObject>
#include <QString>
#include <functional>

class CrashHandler : public QObject {
    Q_OBJECT

  public:
    static CrashHandler *instance();

    void                 install();

    void                 setCrashCallback(std::function<void(const QString &)> callback);

    static bool          isInCrashHandler();

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
