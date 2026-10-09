// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel.WebEngine 1.0 ProfilePolicy (Keel internal): applies the Sailfish
// WebEngineSettings Qt WebEngine has no QML property for to a Qt WebEngine
// profile, through Qt WebEngine's C++ API:
//   cookieBehavior   a cookie filter on the profile's cookie store
//                    (AcceptAll, BlockThirdParty, BlockAll; Gecko's
//                    network.cookie.cookieBehavior values)
//   doNotTrack       a request interceptor that sends "DNT: 1"
//   colorScheme      Chromium's preferred colour scheme (what
//                    prefers-color-scheme reports), a process-wide start-up
//                    setting: preferDark() takes effect when called before
//                    Qt WebEngine's first profile or view
// Built only where Qt WebEngine (Qt6WebEngineQuick) is; Keel's
// WebEngineBackend.qml creates one per profile when the module loads, and
// without it these settings keep their values without effect.

#ifndef KEEL_PROFILEPOLICY_H
#define KEEL_PROFILEPOLICY_H

#include <QObject>
#include <QPointer>
#include <QtQml/qqmlregistration.h>

#include <atomic>
#include <memory>

class QQuickWebEngineProfile;
class QWebEngineUrlRequestInterceptor;

class ProfilePolicy : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QObject *profile READ profile WRITE setProfile NOTIFY profileChanged)
    Q_PROPERTY(int cookieBehavior READ cookieBehavior WRITE setCookieBehavior NOTIFY cookieBehaviorChanged)
    Q_PROPERTY(bool doNotTrack READ doNotTrack WRITE setDoNotTrack NOTIFY doNotTrackChanged)

public:
    // Sailfish's WebEngineSettings.CookieBehavior values.
    enum CookieBehavior { AcceptAll = 0, BlockThirdParty = 1, BlockAll = 2 };
    Q_ENUM(CookieBehavior)

    explicit ProfilePolicy(QObject *parent = nullptr);
    ~ProfilePolicy() override;

    QObject *profile() const;
    void setProfile(QObject *object);
    int cookieBehavior() const { return m_state->cookieBehavior; }
    void setCookieBehavior(int behavior);
    bool doNotTrack() const { return m_state->doNotTrack; }
    void setDoNotTrack(bool doNotTrack);

    // Asks Chromium to report a dark (true) or light (false) preferred
    // colour scheme. Returns false when Qt WebEngine had already started
    // (QTWEBENGINE_CHROMIUM_FLAGS was read), when it no longer applies.
    Q_INVOKABLE static bool preferDark(bool dark);

    struct State
    {
        std::atomic<int> cookieBehavior { AcceptAll };
        std::atomic<bool> doNotTrack { false };
    };

signals:
    void profileChanged();
    void cookieBehaviorChanged();
    void doNotTrackChanged();

private:
    std::shared_ptr<State> m_state;
    QPointer<QQuickWebEngineProfile> m_profile;
    QWebEngineUrlRequestInterceptor *m_interceptor = nullptr;
};

#endif
