// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "requests.h"

#include "pacificwebview.h"

#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <utility>

LoadRequest::LoadRequest(QUrl url, Status status, QString errorString, int errorCode,
                         QString errorDomain, QObject *parent)
    : QObject(parent)
    , m_url(std::move(url))
    , m_status(status)
    , m_errorString(std::move(errorString))
    , m_errorCode(errorCode)
    , m_errorDomain(std::move(errorDomain)) {}

static PermissionRequest::Kind permissionKind(WebKitPermissionRequest *request) {
    if (WEBKIT_IS_GEOLOCATION_PERMISSION_REQUEST(request))
        return PermissionRequest::Geolocation;
    if (WEBKIT_IS_USER_MEDIA_PERMISSION_REQUEST(request)) {
        auto *media = WEBKIT_USER_MEDIA_PERMISSION_REQUEST(request);
        if (webkit_user_media_permission_is_for_display_device(media))
            return PermissionRequest::ScreenCapture;
        const bool audio = webkit_user_media_permission_is_for_audio_device(media);
        const bool video = webkit_user_media_permission_is_for_video_device(media);
        if (audio && video)
            return PermissionRequest::CameraAndMicrophone;
        return video ? PermissionRequest::Camera : PermissionRequest::Microphone;
    }
    if (WEBKIT_IS_NOTIFICATION_PERMISSION_REQUEST(request))
        return PermissionRequest::Notifications;
    if (WEBKIT_IS_DEVICE_INFO_PERMISSION_REQUEST(request))
        return PermissionRequest::DeviceInfo;
    if (WEBKIT_IS_WEBSITE_DATA_ACCESS_PERMISSION_REQUEST(request))
        return PermissionRequest::WebsiteDataAccess;
    if (WEBKIT_IS_MEDIA_KEY_SYSTEM_PERMISSION_REQUEST(request))
        return PermissionRequest::MediaKeySystem;
    return PermissionRequest::Other;
}

PermissionRequest::PermissionRequest(WebKitPermissionRequest *request, QUrl origin, QObject *parent)
    : QObject(parent)
    , m_request(WEBKIT_PERMISSION_REQUEST(g_object_ref(request)))
    , m_kind(permissionKind(request))
    , m_origin(std::move(origin)) {}

PermissionRequest::~PermissionRequest() {
    deny();
}

void PermissionRequest::allow() {
    if (!m_request)
        return;
    webkit_permission_request_allow(m_request);
    g_clear_object(&m_request);
    Q_EMIT answeredChanged();
}

void PermissionRequest::deny() {
    if (!m_request)
        return;
    webkit_permission_request_deny(m_request);
    g_clear_object(&m_request);
    Q_EMIT answeredChanged();
}

NewWindowRequest::NewWindowRequest(PacificWebView *opener, WebKitNavigationAction *action,
                                   QObject *parent)
    : QObject(parent)
    , m_opener(opener) {
    if (WebKitURIRequest *request = webkit_navigation_action_get_request(action))
        m_url = QUrl(QString::fromUtf8(webkit_uri_request_get_uri(request)));
    m_userInitiated = webkit_navigation_action_is_user_gesture(action);
    if (const char *name = webkit_navigation_action_get_frame_name(action))
        m_frameName = QString::fromUtf8(name);
}

bool NewWindowRequest::openIn(PacificWebView *view) {
    if (!view || !m_opener || m_target)
        return false;
    if (!view->createRelatedWebView(m_opener))
        return false;
    m_target = view;
    return true;
}

WebKitWebView *NewWindowRequest::result() const {
    return m_target ? m_target->webView() : nullptr;
}

NavigationRequest::NavigationRequest(WebKitNavigationPolicyDecision *decision, QObject *parent)
    : QObject(parent) {
    WebKitNavigationAction *action =
        webkit_navigation_policy_decision_get_navigation_action(decision);
    if (WebKitURIRequest *request = webkit_navigation_action_get_request(action))
        m_url = QUrl(QString::fromUtf8(webkit_uri_request_get_uri(request)));
    m_userInitiated = webkit_navigation_action_is_user_gesture(action);
    m_redirect      = webkit_navigation_action_is_redirect(action);
    switch (webkit_navigation_action_get_navigation_type(action)) {
        case WEBKIT_NAVIGATION_TYPE_LINK_CLICKED: m_type = LinkClicked; break;
        case WEBKIT_NAVIGATION_TYPE_FORM_SUBMITTED: m_type = FormSubmitted; break;
        case WEBKIT_NAVIGATION_TYPE_BACK_FORWARD: m_type = BackForward; break;
        case WEBKIT_NAVIGATION_TYPE_RELOAD: m_type = Reload; break;
        case WEBKIT_NAVIGATION_TYPE_FORM_RESUBMITTED: m_type = FormResubmitted; break;
        default: m_type = Other; break;
    }
}

ScriptDialog::ScriptDialog(WebKitScriptDialog *dialog, QObject *parent)
    : QObject(parent)
    , m_dialog(webkit_script_dialog_ref(dialog))
    , m_message(QString::fromUtf8(webkit_script_dialog_get_message(dialog))) {
    switch (webkit_script_dialog_get_dialog_type(dialog)) {
        case WEBKIT_SCRIPT_DIALOG_CONFIRM: m_type = Confirm; break;
        case WEBKIT_SCRIPT_DIALOG_PROMPT:
            m_type        = Prompt;
            m_defaultText = QString::fromUtf8(webkit_script_dialog_prompt_get_default_text(dialog));
            break;
        case WEBKIT_SCRIPT_DIALOG_BEFORE_UNLOAD_CONFIRM: m_type = BeforeUnload; break;
        default: m_type = Alert; break;
    }
}

ScriptDialog::~ScriptDialog() {
    reject();
}

void ScriptDialog::accept(const QString &text) {
    if (!m_dialog)
        return;
    if (m_type == Confirm || m_type == BeforeUnload)
        webkit_script_dialog_confirm_set_confirmed(m_dialog, TRUE);
    else if (m_type == Prompt)
        webkit_script_dialog_prompt_set_text(m_dialog, text.toUtf8().constData());
    close();
}

void ScriptDialog::reject() {
    if (!m_dialog)
        return;
    if (m_type == Confirm || m_type == BeforeUnload)
        webkit_script_dialog_confirm_set_confirmed(m_dialog, FALSE);
    close();
}

void ScriptDialog::close() {
    webkit_script_dialog_close(m_dialog);
    webkit_script_dialog_unref(m_dialog);
    m_dialog = nullptr;
}

FileChooserRequest::FileChooserRequest(WebKitFileChooserRequest *request, QObject *parent)
    : QObject(parent)
    , m_request(WEBKIT_FILE_CHOOSER_REQUEST(g_object_ref(request))) {}

FileChooserRequest::~FileChooserRequest() {
    cancel();
}

static QStringList toStringList(const gchar *const *strv) {
    QStringList out;
    for (; strv && *strv; ++strv)
        out.append(QString::fromUtf8(*strv));
    return out;
}

QStringList FileChooserRequest::mimeTypes() const {
    return m_request ? toStringList(webkit_file_chooser_request_get_mime_types(m_request)) :
                       QStringList();
}

bool FileChooserRequest::multiple() const {
    return m_request && webkit_file_chooser_request_get_select_multiple(m_request);
}

QStringList FileChooserRequest::selectedFiles() const {
    return m_request ? toStringList(webkit_file_chooser_request_get_selected_files(m_request)) :
                       QStringList();
}

void FileChooserRequest::select(const QStringList &files) {
    if (!m_request)
        return;
    QList<QByteArray> paths;
    for (const QString &f : files) {
        const QUrl url(f);
        paths.append((url.isLocalFile() ? url.toLocalFile() : f).toUtf8());
    }
    QList<const gchar *> argv;
    for (const QByteArray &p : std::as_const(paths))
        argv.append(p.constData());
    argv.append(nullptr);
    webkit_file_chooser_request_select_files(m_request, argv.data());
    g_clear_object(&m_request);
}

void FileChooserRequest::cancel() {
    if (!m_request)
        return;
    webkit_file_chooser_request_cancel(m_request);
    g_clear_object(&m_request);
}

AuthenticationRequest::AuthenticationRequest(WebKitAuthenticationRequest *request, QObject *parent)
    : QObject(parent)
    , m_request(WEBKIT_AUTHENTICATION_REQUEST(g_object_ref(request))) {}

AuthenticationRequest::~AuthenticationRequest() {
    cancel();
}

QString AuthenticationRequest::host() const {
    return m_request ? QString::fromUtf8(webkit_authentication_request_get_host(m_request)) :
                       QString();
}

int AuthenticationRequest::port() const {
    return m_request ? static_cast<int>(webkit_authentication_request_get_port(m_request)) : 0;
}

QString AuthenticationRequest::realm() const {
    return m_request ? QString::fromUtf8(webkit_authentication_request_get_realm(m_request)) :
                       QString();
}

bool AuthenticationRequest::proxy() const {
    return m_request && webkit_authentication_request_is_for_proxy(m_request);
}

bool AuthenticationRequest::retry() const {
    return m_request && webkit_authentication_request_is_retry(m_request);
}

void AuthenticationRequest::authenticate(const QString &user, const QString &password,
                                         bool remember) {
    if (!m_request)
        return;
    WebKitCredential *credential =
        webkit_credential_new(user.toUtf8().constData(), password.toUtf8().constData(),
                              remember ? WEBKIT_CREDENTIAL_PERSISTENCE_PERMANENT :
                                         WEBKIT_CREDENTIAL_PERSISTENCE_FOR_SESSION);
    webkit_authentication_request_authenticate(m_request, credential);
    webkit_credential_free(credential);
    g_clear_object(&m_request);
}

void AuthenticationRequest::cancel() {
    if (!m_request)
        return;
    webkit_authentication_request_cancel(m_request);
    g_clear_object(&m_request);
}

Download::Download(WebKitDownload *download, QString downloadDirectory, QObject *parent)
    : QObject(parent)
    , m_download(WEBKIT_DOWNLOAD(g_object_ref(download)))
    , m_directory(std::move(downloadDirectory)) {
    g_signal_connect(
        download, "decide-destination",
        G_CALLBACK(+[](WebKitDownload *, const char *suggested, Download *self) -> gboolean {
            return self->decideDestination(suggested);
        }),
        this);
    g_signal_connect_swapped(download, "notify::response",
                             G_CALLBACK(+[](Download *self) { Q_EMIT self->responseChanged(); }),
                             this);
    g_signal_connect_swapped(download, "received-data",
                             G_CALLBACK(+[](Download *self) { Q_EMIT self->progressChanged(); }),
                             this);
    g_signal_connect(download, "failed",
                     G_CALLBACK(+[](WebKitDownload *, GError *error, Download *self) {
                         const bool cancelled = g_error_matches(
                             error, WEBKIT_DOWNLOAD_ERROR, WEBKIT_DOWNLOAD_ERROR_CANCELLED_BY_USER);
                         self->m_state       = cancelled ? Cancelled : Failed;
                         self->m_errorString = QString::fromUtf8(error->message);
                         Q_EMIT self->stateChanged();
                     }),
                     this);
    g_signal_connect_swapped(download, "finished", G_CALLBACK(+[](Download *self) {
                                 if (self->m_state == InProgress) {
                                     self->m_state = Finished;
                                     Q_EMIT self->progressChanged();
                                     Q_EMIT self->stateChanged();
                                 }
                             }),
                             this);
}

Download::~Download() {
    g_signal_handlers_disconnect_by_data(m_download, this);
    g_object_unref(m_download);
}

QUrl Download::url() const {
    WebKitURIRequest *request = webkit_download_get_request(m_download);
    return request ? QUrl(QString::fromUtf8(webkit_uri_request_get_uri(request))) : QUrl();
}

void Download::setDestination(const QString &path) {
    if (m_destinationDecided || path == m_destination)
        return;
    m_destination = path;
    Q_EMIT destinationChanged();
}

static QString uniquePath(const QString &directory, const QString &name) {
    QDir    dir(directory);
    QString candidate = dir.filePath(name);
    if (!QFileInfo::exists(candidate))
        return candidate;
    const QFileInfo info(name);
    const QString   base   = info.completeBaseName();
    const QString   suffix = info.suffix().isEmpty() ? QString() : QLatin1Char('.') + info.suffix();
    for (int i = 1; i < 1000; ++i) {
        candidate = dir.filePath(QStringLiteral("%1 (%2)%3").arg(base).arg(i).arg(suffix));
        if (!QFileInfo::exists(candidate))
            return candidate;
    }
    return candidate;
}

bool Download::decideDestination(const char *suggested) {
    m_suggestedFilename = QFileInfo(QString::fromUtf8(suggested)).fileName();
    if (m_suggestedFilename.isEmpty())
        m_suggestedFilename = QStringLiteral("download");
    Q_EMIT suggestedFilenameChanged();
    // A destination the app set (before or in reply to the suggested name)
    // is its choice: it may have claimed it as an empty file to keep the
    // name (Pacific does), which the engine would otherwise refuse as an
    // existing file. One chosen here is always a free name.
    const bool chosenByApp = !m_destination.isEmpty();
    if (!chosenByApp) {
        QString dir = m_directory;
        if (dir.isEmpty())
            dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
        QDir().mkpath(dir);
        m_destination = uniquePath(dir, m_suggestedFilename);
        Q_EMIT destinationChanged();
    }
    m_destinationDecided = true;
    webkit_download_set_allow_overwrite(m_download, chosenByApp);
    webkit_download_set_destination(m_download, m_destination.toUtf8().constData());
    return TRUE;
}

QString Download::mimeType() const {
    WebKitURIResponse *response = webkit_download_get_response(m_download);
    return response ? QString::fromUtf8(webkit_uri_response_get_mime_type(response)) : QString();
}

qreal Download::progress() const {
    return webkit_download_get_estimated_progress(m_download);
}

qint64 Download::receivedBytes() const {
    return static_cast<qint64>(webkit_download_get_received_data_length(m_download));
}

qint64 Download::totalBytes() const {
    WebKitURIResponse *response = webkit_download_get_response(m_download);
    return response ? static_cast<qint64>(webkit_uri_response_get_content_length(response)) : 0;
}

WebKitWebView *Download::webView() const {
    return webkit_download_get_web_view(m_download);
}

void Download::cancel() {
    if (m_state == InProgress)
        webkit_download_cancel(m_download);
}
