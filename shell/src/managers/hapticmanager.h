#ifndef HAPTICMANAGER_H
#define HAPTICMANAGER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <qqml.h>

class HapticManager : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
  public:
    // QML_SINGLETON factory — required so the type registers correctly in
    // marathon-app-runner processes that import this module without the
    // shell's explicit qmlRegisterSingletonInstance call. Shell process
    // still calls qmlRegisterSingletonInstance in main.cpp; that override
    // wins so shell-side C++ consumers share the same instance pointer.
    static HapticManager *create(QQmlEngine *, QJSEngine *);
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

  public:
    explicit HapticManager(QObject *parent = nullptr);

    bool available() const {
        return m_available;
    }
    bool enabled() const {
        return m_enabled;
    }
    void             setEnabled(bool enabled);

    Q_INVOKABLE void vibrate(int duration = 50);
    Q_INVOKABLE void vibratePattern(const QList<int> &pattern);
    Q_INVOKABLE void cancelVibration();
    Q_INVOKABLE void vibratePatternVariant(const QVariantList &pattern);
    Q_INVOKABLE void light();
    Q_INVOKABLE void medium();
    Q_INVOKABLE void heavy();
    Q_INVOKABLE void pattern(const QVariantList &durations);
    Q_INVOKABLE void vibratePattern(const QVariantList &durations, int repeat = 0);
    Q_INVOKABLE void stopVibration();

  signals:
    void availableChanged();
    void enabledChanged();

  private:
    bool    detectVibrator();
    void    writeVibrator(int value);

    bool    m_available;
    bool    m_enabled;
    QString m_vibratorPath;
};

#endif
