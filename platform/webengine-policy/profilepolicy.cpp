// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// See profilepolicy.h.

#include "profilepolicy.h"

#include <QQuickWebEngineProfile>
#include <QWebEngineCookieStore>
#include <QWebEngineUrlRequestInfo>
#include <QWebEngineUrlRequestInterceptor>

namespace {

class DntInterceptor : public QWebEngineUrlRequestInterceptor
{
public:
    DntInterceptor(std::shared_ptr<ProfilePolicy::State> state, QObject *parent)
        : QWebEngineUrlRequestInterceptor(parent)
        , m_state(std::move(state))
    {
    }

    void interceptRequest(QWebEngineUrlRequestInfo &info) override
    {
        if (m_state->doNotTrack)
            info.setHttpHeader(QByteArrayLiteral("DNT"), QByteArrayLiteral("1"));
    }

private:
    std::shared_ptr<ProfilePolicy::State> m_state;
};

// Set once Qt WebEngine has created its first profile (it reads its
// command-line flags then); preferDark() cannot change anything after that.
std::atomic<bool> engineStarted { false };

} // namespace

ProfilePolicy::ProfilePolicy(QObject *parent)
    : QObject(parent)
    , m_state(std::make_shared<State>())
{
}

ProfilePolicy::~ProfilePolicy()
{
    if (m_profile) {
        m_profile->setUrlRequestInterceptor(nullptr);
        m_profile->cookieStore()->setCookieFilter(nullptr);
    }
}

QObject *ProfilePolicy::profile() const
{
    return m_profile.data();
}

void ProfilePolicy::setProfile(QObject *object)
{
    auto *profile = qobject_cast<QQuickWebEngineProfile *>(object);
    if (profile == m_profile)
        return;
    if (m_profile) {
        m_profile->setUrlRequestInterceptor(nullptr);
        m_profile->cookieStore()->setCookieFilter(nullptr);
    }
    delete m_interceptor;
    m_interceptor = nullptr;
    m_profile = profile;
    if (profile) {
        engineStarted = true;
        m_interceptor = new DntInterceptor(m_state, this);
        profile->setUrlRequestInterceptor(m_interceptor);
        // The filter outlives nothing it uses: it holds the shared state.
        std::shared_ptr<State> state = m_state;
        profile->cookieStore()->setCookieFilter([state](const QWebEngineCookieStore::FilterRequest &request) {
            switch (state->cookieBehavior.load()) {
            case BlockAll:
                return false;
            case BlockThirdParty:
                return !request.thirdParty;
            default:
                return true;
            }
        });
    }
    emit profileChanged();
}

void ProfilePolicy::setCookieBehavior(int behavior)
{
    if (m_state->cookieBehavior == behavior)
        return;
    m_state->cookieBehavior = behavior;
    emit cookieBehaviorChanged();
}

void ProfilePolicy::setDoNotTrack(bool doNotTrack)
{
    if (m_state->doNotTrack == doNotTrack)
        return;
    m_state->doNotTrack = doNotTrack;
    emit doNotTrackChanged();
}

bool ProfilePolicy::preferDark(bool dark)
{
    if (engineStarted)
        return false;
    // Blink's preferredColorScheme setting: 0 dark, 1 light.
    static const QByteArray Prefix = QByteArrayLiteral("--blink-settings=preferredColorScheme=");
    QList<QByteArray> flags = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS").split(' ');
    flags.removeIf([](const QByteArray &flag) { return flag.isEmpty() || flag.startsWith(Prefix); });
    flags.append(Prefix + (dark ? '0' : '1'));
    qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags.join(' '));
    return true;
}
