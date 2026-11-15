// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The C++ base of the mock WebView (WebView.qml): the real view's
// properties with their real change signals, which QML alone cannot
// declare (a QML property `loading` would take the name `loadingChanged`,
// which the real view uses for its LoadRequest signal). Everything else
// is in WebView.qml. Values are writable here so the QML can drive them.

#pragma once

#include <QtCore/QRectF>
#include <QtCore/QUrl>
#include <QtCore/QVariant>
#include <QtQml/qqmlregistration.h>
#include <QtQuick/QQuickItem>

#define MOCK_PROPERTY(type, name, setter, signal)                                                              \
    Q_PROPERTY(type name MEMBER m_##name WRITE setter NOTIFY signal)                                           \
public:                                                                                                      \
    void setter(const type& v)                                                                               \
    {                                                                                                        \
        if (m_##name == v)                                                                                   \
            return;                                                                                          \
        m_##name = v;                                                                                        \
        Q_EMIT signal();                                                                                     \
    }                                                                                                        \
                                                                                                             \
private:                                                                                                     \
    type m_##name {};

class MockWebViewBase : public QQuickItem {
    Q_OBJECT
    QML_NAMED_ELEMENT(MockWebViewBase)

    MOCK_PROPERTY(QUrl, url, setUrl, urlChanged)
    MOCK_PROPERTY(QString, title, setTitle, titleChanged)
    MOCK_PROPERTY(QUrl, icon, setIcon, iconChanged)
    MOCK_PROPERTY(QString, themeColor, setThemeColor, iconChanged)
    MOCK_PROPERTY(bool, viewportFitCover, setViewportFitCover, viewportFitCoverChanged)
    MOCK_PROPERTY(qreal, safeAreaTop, setSafeAreaTop, safeAreaTopChanged)
    MOCK_PROPERTY(qreal, obscuredBottom, setObscuredBottom, obscuredBottomChanged)
    MOCK_PROPERTY(qreal, pullDistance, setPullDistance, pullDistanceChanged)
    MOCK_PROPERTY(bool, zooming, setZooming, zoomingChanged)
    MOCK_PROPERTY(int, loadProgress, setLoadProgress, loadProgressChanged)
    MOCK_PROPERTY(bool, loading, setLoading, loadingStateChanged)
    MOCK_PROPERTY(bool, canGoBack, setCanGoBack, backForwardChanged)
    MOCK_PROPERTY(bool, canGoForward, setCanGoForward, backForwardChanged)
    MOCK_PROPERTY(QString, historyKey, setHistoryKey, backForwardChanged)
    MOCK_PROPERTY(bool, swipeNavigation, setSwipeNavigation, swipeNavigationChanged)
    MOCK_PROPERTY(bool, secure, setSecure, securityChanged)
    MOCK_PROPERTY(bool, audioPlaying, setAudioPlaying, audioChanged)
    MOCK_PROPERTY(bool, muted, setMuted, audioChanged)
    MOCK_PROPERTY(bool, webProcessRunning, setWebProcessRunning, webProcessRunningChanged)
    MOCK_PROPERTY(bool, created, setCreated, webViewCreated)
    Q_PROPERTY(QObject* profile MEMBER m_profile WRITE setProfile NOTIFY profileChanged)
    // The real view's frameFitsView: a mock frame always has the view's size.
    Q_PROPERTY(bool frameFitsView MEMBER m_frameFitsView NOTIFY frameFitsViewChanged)
    // The real view's pageBlanked: a mock page has no old frames to hide.
    Q_PROPERTY(bool pageBlanked MEMBER m_pageBlanked NOTIFY pageBlankedChanged)
public:
    void setProfile(QObject* p)
    {
        if (m_profile == p)
            return;
        m_profile = p;
        Q_EMIT profileChanged();
    }

private:
    QObject* m_profile = nullptr;
    bool m_frameFitsView = true;
    bool m_pageBlanked = false;
    MOCK_PROPERTY(QString, userAgent, setUserAgent, userAgentChanged)
    MOCK_PROPERTY(bool, desktopMode, setDesktopMode, desktopModeChanged)
    MOCK_PROPERTY(qreal, zoomFactor, setZoomFactor, zoomFactorChanged)
    MOCK_PROPERTY(qreal, contentScale, setContentScale, contentScaleChanged)
    MOCK_PROPERTY(bool, active, setActive, activeChanged)
    MOCK_PROPERTY(bool, headless, setHeadless, headlessChanged)
    MOCK_PROPERTY(bool, directComposite, setDirectComposite, directCompositeChanged)
    MOCK_PROPERTY(bool, pageVisible, setPageVisible, pageVisibleChanged)
    MOCK_PROPERTY(int, inputMode, setInputMode, inputModeChanged)
    MOCK_PROPERTY(bool, scriptSelectMenus, setScriptSelectMenus, scriptSelectMenusChanged)
    MOCK_PROPERTY(bool, captureConsole, setCaptureConsole, captureConsoleChanged)
    MOCK_PROPERTY(bool, javascriptEnabled, setJavascriptEnabled, settingsChanged)
    MOCK_PROPERTY(bool, loadImages, setLoadImages, settingsChanged)
    MOCK_PROPERTY(bool, mediaNeedsUserGesture, setMediaNeedsUserGesture, settingsChanged)
    MOCK_PROPERTY(bool, editableFocused, setEditableFocused, inputMethodStateChanged)
    MOCK_PROPERTY(QRectF, cursorRectangle, setCursorRectangle, inputMethodStateChanged)
    MOCK_PROPERTY(int, inputPurpose, setInputPurpose, inputMethodStateChanged)
    MOCK_PROPERTY(QString, selectedText, setSelectedText, selectionChanged)
    MOCK_PROPERTY(int, findMatchCount, setFindMatchCount, findMatchCountChanged)
    MOCK_PROPERTY(int, blockedRequestCount, setBlockedRequestCount, blockedRequestCountChanged)

public:
    explicit MockWebViewBase(QQuickItem* parent = nullptr)
        : QQuickItem(parent)
    {
        m_created = true;
        m_webProcessRunning = true;
        m_zoomFactor = 1.0;
        m_contentScale = 1.0;
        m_active = true;
        m_javascriptEnabled = true;
        m_loadImages = true;
        m_mediaNeedsUserGesture = true;
    }

Q_SIGNALS:
    void webViewCreated();
    void urlChanged();
    void titleChanged();
    void iconChanged();
    void viewportFitCoverChanged();
    void safeAreaTopChanged();
    void obscuredBottomChanged();
    void pullDistanceChanged();
    void pulledDown();
    void pullMoved(qreal distance);
    void pullEnded(qreal distance, qreal velocity);
    void swipeNavMoved(qreal dx);
    void swipeNavEnded(qreal dx, qreal velocity);
    void swipeNavigationChanged();
    void historyPictureReady(const QString& key);
    void zoomingChanged();
    void loadProgressChanged();
    void loadingStateChanged();
    void loadingChanged(QObject* loadRequest);
    void backForwardChanged();
    void securityChanged();
    void certificateError(const QUrl& url, const QString& host, int errors, const QString& certificatePem);
    void audioChanged();
    void webProcessRunningChanged();
    void webProcessTerminated(int reason);
    void webProcessUnresponsive(bool unresponsive);
    void profileChanged();
    void userAgentChanged();
    void desktopModeChanged();
    void zoomFactorChanged();
    void contentScaleChanged();
    void activeChanged();
    void headlessChanged();
    void directCompositeChanged();
    void frameFitsViewChanged();
    void pageBlankedChanged();
    void pageVisibleChanged();
    void inputModeChanged();
    void scriptSelectMenusChanged();
    void captureConsoleChanged();
    void settingsChanged();
    void newWindowRequested(QObject* request);
    void navigationRequested(QObject* request);
    void closeRequested();
    void permissionRequested(QObject* request);
    void downloadRequested(QObject* download);
    void scriptDialogRequested(QObject* dialog);
    void fileChooserRequested(QObject* request);
    void authenticationRequested(QObject* request);
    void notificationRequested(const QString& title, const QString& body, const QString& tag, const QUrl& origin);
    void fullscreenRequested(bool fullscreen);
    void inputMethodStateChanged();
    void selectionChanged();
    void selectionHandlesChanged(const QPointF& start, const QPointF& end);
    void contextMenuRequested(const QVariantMap& info);
    void selectMenuRequested(const QVariantList& options, int selectedIndex, const QRectF& rect);
    void inputPickerRequested(const QString& type, const QString& value, const QString& min, const QString& max,
        const QString& step, const QRectF& rect);
    void scrollChanged(qreal scrollY, qreal contentHeight, qreal viewportHeight);
    void pinchConsumedByPage(bool consumed);
    void findMatchCountChanged();
    void findResult(int count);
    void consoleMessage(const QString& level, const QString& message, const QString& source);
    void scriptMessage(const QString& name, const QVariant& message);
    // What the engine's content filters blocked (as the real view will add).
    void blockedRequest(const QString& url);
    void blockedRequestCountChanged();
};
