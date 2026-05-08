#include "updateservice.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDesktopServices>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QUrl>

namespace {
    constexpr int kAutoCheckIntervalMs = 6 * 60 * 60 * 1000; // 6 hours
    const QString kDefaultRepo         = QStringLiteral("patrickjquinn/Marathon-Shell");
} // namespace

UpdateService::UpdateService(QObject *parent)
    : QObject(parent)
    , m_currentVersion(QCoreApplication::applicationVersion())
    , m_net(new QNetworkAccessManager(this))
    , m_autoCheckTimer(new QTimer(this)) {
    if (m_currentVersion.isEmpty())
        m_currentVersion = QStringLiteral("0.0.0");

    QSettings s;
    s.beginGroup("updates");
    const bool autoCheck = s.value("autoCheck", true).toBool();
    s.endGroup();

    m_autoCheckTimer->setInterval(kAutoCheckIntervalMs);
    connect(m_autoCheckTimer, &QTimer::timeout, this, &UpdateService::checkNow);
    if (autoCheck) {
        // Stagger first check 30s after startup so we don't compete with the
        // boot path for bandwidth.
        QTimer::singleShot(30 * 1000, this, &UpdateService::checkNow);
        m_autoCheckTimer->start();
    }
}

bool UpdateService::updateAvailable() const {
    if (m_latestVersion.isEmpty())
        return false;
    return compareVersion(m_latestVersion, m_currentVersion) > 0;
}

bool UpdateService::isStableChannel() const {
    QSettings s;
    s.beginGroup("updates");
    const QString c = s.value("channel", "stable").toString();
    s.endGroup();
    return c == "stable";
}

void UpdateService::setChannel(const QString &channel) {
    if (channel != "stable" && channel != "edge")
        return;
    QSettings s;
    s.beginGroup("updates");
    s.setValue("channel", channel);
    s.endGroup();
    s.sync();
    checkNow();
}

void UpdateService::checkNow() {
    if (m_checking)
        return;

    QSettings s;
    s.beginGroup("updates");
    const QString repo = s.value("feedRepo", kDefaultRepo).toString();
    s.endGroup();

    const QUrl      url(QString("https://api.github.com/repos/%1/releases").arg(repo));
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QString("MarathonShell/%1 (linux)").arg(m_currentVersion));
    req.setRawHeader("Accept", "application/vnd.github+json");

    m_checking = true;
    emit checkingChanged();
    m_lastError.clear();
    emit lastErrorChanged();

    m_reply = m_net->get(req);
    connect(m_reply, &QNetworkReply::finished, this, &UpdateService::onReleasesReply);
}

void UpdateService::onReleasesReply() {
    if (!m_reply)
        return;
    QNetworkReply *reply = m_reply;
    m_reply              = nullptr;
    m_checking           = false;
    emit checkingChanged();

    if (reply->error() != QNetworkReply::NoError) {
        m_lastError = reply->errorString();
        emit lastErrorChanged();
        qWarning() << "[UpdateService] check failed:" << m_lastError;
        reply->deleteLater();
        return;
    }

    const QByteArray body = reply->readAll();
    reply->deleteLater();
    QJsonParseError perr;
    QJsonDocument   doc = QJsonDocument::fromJson(body, &perr);
    if (perr.error != QJsonParseError::NoError || !doc.isArray()) {
        m_lastError = "Invalid JSON from GitHub Releases";
        emit lastErrorChanged();
        return;
    }

    const QJsonArray arr             = doc.array();
    const bool       allowPrerelease = !isStableChannel();
    for (const QJsonValue &v : arr) {
        const QJsonObject o          = v.toObject();
        const bool        prerelease = o.value("prerelease").toBool();
        if (prerelease && !allowPrerelease)
            continue;
        if (o.value("draft").toBool())
            continue;
        QString tag = o.value("tag_name").toString();
        // Normalise a leading 'v'.
        if (tag.startsWith('v') || tag.startsWith('V'))
            tag = tag.mid(1);
        if (tag.isEmpty())
            continue;

        m_latestVersion = tag;
        m_releaseUrl    = o.value("html_url").toString();
        m_releaseNotes  = o.value("body").toString();
        emit latestVersionChanged();
        return;
    }

    // No suitable release found.
    if (!m_latestVersion.isEmpty()) {
        m_latestVersion.clear();
        m_releaseUrl.clear();
        m_releaseNotes.clear();
        emit latestVersionChanged();
    }
}

void UpdateService::openInBrowser() {
    if (!m_releaseUrl.isEmpty())
        QDesktopServices::openUrl(QUrl(m_releaseUrl));
}

int UpdateService::compareVersion(const QString &a, const QString &b) {
    const QStringList ap = a.split(QRegularExpression("[.\\-]"), Qt::SkipEmptyParts);
    const QStringList bp = b.split(QRegularExpression("[.\\-]"), Qt::SkipEmptyParts);
    const int         n  = qMax(ap.size(), bp.size());
    for (int i = 0; i < n; ++i) {
        const QString as  = i < ap.size() ? ap.at(i) : QStringLiteral("0");
        const QString bs  = i < bp.size() ? bp.at(i) : QStringLiteral("0");
        bool          aok = false, bok = false;
        const int     ai = as.toInt(&aok);
        const int     bi = bs.toInt(&bok);
        if (aok && bok) {
            if (ai != bi)
                return ai - bi;
            continue;
        }
        // Mixed numeric/string segments: compare as strings.
        const int sc = QString::compare(as, bs);
        if (sc != 0)
            return sc;
    }
    return 0;
}
