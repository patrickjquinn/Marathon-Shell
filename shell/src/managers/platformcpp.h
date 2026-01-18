#ifndef PLATFORMCPP_H
#define PLATFORMCPP_H

#include <QObject>
#include <QString>
#include "platform.h"

class PlatformCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString os READ os CONSTANT)
    Q_PROPERTY(bool isLinux READ isLinux CONSTANT)
    Q_PROPERTY(bool isMacOS READ isMacOS CONSTANT)
    Q_PROPERTY(bool isAndroid READ isAndroid CONSTANT)
    Q_PROPERTY(bool isIOS READ isIOS CONSTANT)
    Q_PROPERTY(bool hasDBus READ hasDBus CONSTANT)
    Q_PROPERTY(bool hasSystemdLogind READ hasSystemdLogind CONSTANT)
    Q_PROPERTY(bool hasUPower READ hasUPower CONSTANT)
    Q_PROPERTY(bool hasNetworkManager READ hasNetworkManager CONSTANT)
    Q_PROPERTY(bool hasModemManager READ hasModemManager CONSTANT)
    Q_PROPERTY(bool hasPulseAudio READ hasPulseAudio CONSTANT)
    Q_PROPERTY(bool hasHardwareKeyboard READ hasHardwareKeyboard CONSTANT)
    Q_PROPERTY(QString backend READ backend CONSTANT)

  public:
    explicit PlatformCpp(QObject *parent = nullptr)
        : QObject(parent) {
#if defined(Q_OS_LINUX)
        m_os      = "linux";
        m_isLinux = true;
#elif defined(Q_OS_MACOS)
        m_os      = "osx";
        m_isMacOS = true;
#elif defined(Q_OS_ANDROID)
        m_os        = "android";
        m_isAndroid = true;
#elif defined(Q_OS_IOS)
        m_os    = "ios";
        m_isIOS = true;
#else
        m_os = "unknown";
#endif
        m_hasDBus           = m_isLinux || m_isAndroid;
        m_hasSystemdLogind  = m_isLinux;
        m_hasUPower         = m_isLinux;
        m_hasNetworkManager = m_isLinux;
        m_hasModemManager   = m_isLinux;
        m_hasPulseAudio     = m_isLinux;
    }

    QString os() const {
        return m_os;
    }
    bool isLinux() const {
        return m_isLinux;
    }
    bool isMacOS() const {
        return m_isMacOS;
    }
    bool isAndroid() const {
        return m_isAndroid;
    }
    bool isIOS() const {
        return m_isIOS;
    }
    bool hasDBus() const {
        return m_hasDBus;
    }
    bool hasSystemdLogind() const {
        return m_hasSystemdLogind;
    }
    bool hasUPower() const {
        return m_hasUPower;
    }
    bool hasNetworkManager() const {
        return m_hasNetworkManager;
    }
    bool hasModemManager() const {
        return m_hasModemManager;
    }
    bool hasPulseAudio() const {
        return m_hasPulseAudio;
    }
    bool hasHardwareKeyboard() const {
        return Platform::hasHardwareKeyboard();
    }
    QString backend() const {
        return m_os;
    }

  private:
    QString m_os;
    bool    m_isLinux           = false;
    bool    m_isMacOS           = false;
    bool    m_isAndroid         = false;
    bool    m_isIOS             = false;
    bool    m_hasDBus           = false;
    bool    m_hasSystemdLogind  = false;
    bool    m_hasUPower         = false;
    bool    m_hasNetworkManager = false;
    bool    m_hasModemManager   = false;
    bool    m_hasPulseAudio     = false;
};

#endif
