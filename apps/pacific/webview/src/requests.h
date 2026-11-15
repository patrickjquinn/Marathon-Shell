// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// QML wrappers for WebKit's asynchronous requests: loads, permissions, new
// windows, navigation policy, script dialogs, file choosers, HTTP
// authentication, option menus and downloads. Each wraps (and refs) the
// WebKit object; a request that QML neither answers nor keeps is answered
// with the safe default when it is destroyed (deny, cancel, ignore).

#pragma once

#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QRectF>
#include <QStringList>
#include <QUrl>
#include <QVariantList>

#include <wpe/webkit.h>

class PacificWebView;

class LoadRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Delivered by WebView.loadingChanged")
    Q_PROPERTY(QUrl url READ url CONSTANT)
    Q_PROPERTY(Status status READ status CONSTANT)
    Q_PROPERTY(QString errorString READ errorString CONSTANT)
    Q_PROPERTY(int errorCode READ errorCode CONSTANT)
    Q_PROPERTY(QString errorDomain READ errorDomain CONSTANT)

  public:
    enum Status {
        Started,
        Redirected,
        Committed,
        Succeeded,
        Failed,
        Stopped
    };
    Q_ENUM(Status)

    LoadRequest(QUrl url, Status status, QString errorString = {}, int errorCode = 0,
                QString errorDomain = {}, QObject *parent = nullptr);

    QUrl url() const {
        return m_url;
    }
    Status status() const {
        return m_status;
    }
    QString errorString() const {
        return m_errorString;
    }
    int errorCode() const {
        return m_errorCode;
    }
    QString errorDomain() const {
        return m_errorDomain;
    }

  private:
    QUrl    m_url;
    Status  m_status;
    QString m_errorString;
    int     m_errorCode;
    QString m_errorDomain;
};

class PermissionRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Delivered by WebView.permissionRequested")
    Q_PROPERTY(Kind kind READ kind CONSTANT)
    Q_PROPERTY(QUrl origin READ origin CONSTANT)
    Q_PROPERTY(bool answered READ answered NOTIFY answeredChanged)

  public:
    enum Kind {
        Geolocation,
        Camera,
        Microphone,
        CameraAndMicrophone,
        ScreenCapture,
        Notifications,
        DeviceInfo,
        WebsiteDataAccess,
        PointerLock,
        MediaKeySystem,
        ClipboardRead,
        Other
    };
    Q_ENUM(Kind)

    PermissionRequest(WebKitPermissionRequest *request, QUrl origin, QObject *parent = nullptr);
    ~PermissionRequest() override;

    Kind kind() const {
        return m_kind;
    }
    QUrl origin() const {
        return m_origin;
    }
    bool answered() const {
        return !m_request;
    }

    Q_INVOKABLE void allow();
    Q_INVOKABLE void deny();

  Q_SIGNALS:
    void answeredChanged();

  private:
    WebKitPermissionRequest *m_request;
    Kind                     m_kind;
    QUrl                     m_origin;
};

// window.open() / target=_blank. Answer synchronously, inside the
// WebView.newWindowRequested handler: create a WebView (it may stay outside
// any window until it is shown) and call openIn(view); WebKit then runs the
// new page in that view, with window.opener working. Leaving it unanswered
// blocks the popup; the UI can still load request.url in a tab of its own.
class NewWindowRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Delivered by WebView.newWindowRequested")
    Q_PROPERTY(QUrl url READ url CONSTANT)
    Q_PROPERTY(bool userInitiated READ userInitiated CONSTANT)
    Q_PROPERTY(QString frameName READ frameName CONSTANT)

  public:
    NewWindowRequest(PacificWebView *opener, WebKitNavigationAction *action,
                     QObject *parent = nullptr);

    QUrl url() const {
        return m_url;
    }
    bool userInitiated() const {
        return m_userInitiated;
    }
    QString frameName() const {
        return m_frameName;
    }

    Q_INVOKABLE bool openIn(PacificWebView *view);
    WebKitWebView   *result() const;

  private:
    QPointer<PacificWebView> m_opener;
    QPointer<PacificWebView> m_target;
    QUrl                     m_url;
    bool                     m_userInitiated = false;
    QString                  m_frameName;
};

// Main-frame navigation policy, decided synchronously in the
// WebView.navigationRequested handler (HTTPS upgrade, tel:/mailto: hand-off,
// blocking). Unanswered means accept.
class NavigationRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Delivered by WebView.navigationRequested")
    Q_PROPERTY(QUrl url READ url CONSTANT)
    Q_PROPERTY(NavigationType navigationType READ navigationType CONSTANT)
    Q_PROPERTY(bool userInitiated READ userInitiated CONSTANT)
    Q_PROPERTY(bool redirect READ isRedirect CONSTANT)

  public:
    enum NavigationType {
        LinkClicked,
        FormSubmitted,
        BackForward,
        Reload,
        FormResubmitted,
        Other
    };
    Q_ENUM(NavigationType)
    enum Action {
        Accept,
        Ignore,
        Download
    };
    Q_ENUM(Action)

    NavigationRequest(WebKitNavigationPolicyDecision *decision, QObject *parent = nullptr);

    QUrl url() const {
        return m_url;
    }
    NavigationType navigationType() const {
        return m_type;
    }
    bool userInitiated() const {
        return m_userInitiated;
    }
    bool isRedirect() const {
        return m_redirect;
    }

    Q_INVOKABLE void accept() {
        m_action = Accept;
    }
    Q_INVOKABLE void ignore() {
        m_action = Ignore;
    }
    Q_INVOKABLE void download() {
        m_action = Download;
    }
    Action action() const {
        return m_action;
    }

  private:
    QUrl           m_url;
    NavigationType m_type          = Other;
    bool           m_userInitiated = false;
    bool           m_redirect      = false;
    Action         m_action        = Accept;
};

// alert(), confirm(), prompt(), onbeforeunload. Answer with accept() /
// reject(); the page is blocked until then.
class ScriptDialog : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Delivered by WebView.scriptDialogRequested")
    Q_PROPERTY(Type type READ type CONSTANT)
    Q_PROPERTY(QString message READ message CONSTANT)
    Q_PROPERTY(QString defaultText READ defaultText CONSTANT)

  public:
    enum Type {
        Alert,
        Confirm,
        Prompt,
        BeforeUnload
    };
    Q_ENUM(Type)

    ScriptDialog(WebKitScriptDialog *dialog, QObject *parent = nullptr);
    ~ScriptDialog() override;

    Type type() const {
        return m_type;
    }
    QString message() const {
        return m_message;
    }
    QString defaultText() const {
        return m_defaultText;
    }

    Q_INVOKABLE void accept(const QString &text = QString());
    Q_INVOKABLE void reject();

  private:
    void                close();
    WebKitScriptDialog *m_dialog;
    Type                m_type;
    QString             m_message;
    QString             m_defaultText;
};

// <input type=file>. Answer with select([paths or file: URLs]) or cancel().
class FileChooserRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Delivered by WebView.fileChooserRequested")
    Q_PROPERTY(QStringList mimeTypes READ mimeTypes CONSTANT)
    Q_PROPERTY(bool multiple READ multiple CONSTANT)
    Q_PROPERTY(QStringList selectedFiles READ selectedFiles CONSTANT)

  public:
    FileChooserRequest(WebKitFileChooserRequest *request, QObject *parent = nullptr);
    ~FileChooserRequest() override;

    QStringList      mimeTypes() const;
    bool             multiple() const;
    QStringList      selectedFiles() const;

    Q_INVOKABLE void select(const QStringList &files);
    Q_INVOKABLE void cancel();

  private:
    WebKitFileChooserRequest *m_request;
};

class AuthenticationRequest : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Delivered by WebView.authenticationRequested")
    Q_PROPERTY(QString host READ host CONSTANT)
    Q_PROPERTY(int port READ port CONSTANT)
    Q_PROPERTY(QString realm READ realm CONSTANT)
    Q_PROPERTY(bool proxy READ proxy CONSTANT)
    Q_PROPERTY(bool retry READ retry CONSTANT)

  public:
    AuthenticationRequest(WebKitAuthenticationRequest *request, QObject *parent = nullptr);
    ~AuthenticationRequest() override;

    QString          host() const;
    int              port() const;
    QString          realm() const;
    bool             proxy() const;
    bool             retry() const;

    Q_INVOKABLE void authenticate(const QString &user, const QString &password,
                                  bool remember = false);
    Q_INVOKABLE void cancel();

  private:
    WebKitAuthenticationRequest *m_request;
};

class Download : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Delivered by WebProfile.downloadStarted / WebView.downloadRequested")
    Q_PROPERTY(QUrl url READ url CONSTANT)
    Q_PROPERTY(QString suggestedFilename READ suggestedFilename NOTIFY suggestedFilenameChanged)
    Q_PROPERTY(QString destination READ destination WRITE setDestination NOTIFY destinationChanged)
    Q_PROPERTY(QString mimeType READ mimeType NOTIFY responseChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(qint64 receivedBytes READ receivedBytes NOTIFY progressChanged)
    Q_PROPERTY(qint64 totalBytes READ totalBytes NOTIFY responseChanged)
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY stateChanged)

  public:
    enum State {
        InProgress,
        Finished,
        Failed,
        Cancelled
    };
    Q_ENUM(State)

    Download(WebKitDownload *download, QString downloadDirectory, QObject *parent = nullptr);
    ~Download() override;

    QUrl    url() const;
    QString suggestedFilename() const {
        return m_suggestedFilename;
    }
    QString destination() const {
        return m_destination;
    }
    // Takes effect only before WebKit asked for the destination, that is in
    // the downloadStarted / downloadRequested handler.
    void    setDestination(const QString &path);
    QString mimeType() const;
    qreal   progress() const;
    qint64  receivedBytes() const;
    qint64  totalBytes() const;
    State   state() const {
        return m_state;
    }
    QString errorString() const {
        return m_errorString;
    }
    WebKitWebView   *webView() const;

    Q_INVOKABLE void cancel();

  Q_SIGNALS:
    void suggestedFilenameChanged();
    void destinationChanged();
    void responseChanged();
    void progressChanged();
    void stateChanged();

  private:
    bool            decideDestination(const char *suggested);
    WebKitDownload *m_download;
    QString         m_directory;
    QString         m_suggestedFilename;
    QString         m_destination;
    bool            m_destinationDecided = false;
    State           m_state              = InProgress;
    QString         m_errorString;
};
