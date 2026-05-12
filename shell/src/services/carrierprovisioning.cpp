#include "carrierprovisioning.h"

#include <QDebug>
#include <QFile>
#include <QXmlStreamReader>

namespace {
    constexpr const char *kMbpiPath =
        "/usr/share/mobile-broadband-provider-info/serviceproviders.xml";
}

CarrierProvisioning::CarrierProvisioning(QObject *parent)
    : QObject(parent) {
    loadDatabase();
}

void CarrierProvisioning::loadDatabase() {
    QFile f(QString::fromLatin1(kMbpiPath));
    if (!f.open(QIODevice::ReadOnly)) {
        qWarning() << "[CarrierProvisioning] MBPI not present at" << kMbpiPath
                   << "-- automatic APN provisioning disabled";
        return;
    }
    m_databaseAvailable = true;

    QXmlStreamReader xml(&f);
    Provider         currentProvider;
    QList<QString>   pendingOperatorCodes; // network-id codes for the current <gsm>
    bool             inGsm = false;
    Apn              currentApn;
    bool             inApn = false;

    while (!xml.atEnd() && !xml.hasError()) {
        xml.readNext();
        if (xml.isStartElement()) {
            const auto name = xml.name();
            if (name == QStringLiteral("provider")) {
                currentProvider = {};
                pendingOperatorCodes.clear();
                inGsm = false;
            } else if (name == QStringLiteral("gsm")) {
                inGsm = true;
            } else if (name == QStringLiteral("network-id") && inGsm) {
                const auto attrs = xml.attributes();
                const auto mcc   = attrs.value(QStringLiteral("mcc")).toString();
                const auto mnc   = attrs.value(QStringLiteral("mnc")).toString();
                if (!mcc.isEmpty() && !mnc.isEmpty())
                    pendingOperatorCodes.append(mcc + mnc);
            } else if (name == QStringLiteral("name") && !inApn && currentProvider.name.isEmpty()) {
                // First <name> child of <provider> is the operator's human name.
                currentProvider.name = xml.readElementText();
            } else if (name == QStringLiteral("apn") && inGsm) {
                currentApn     = {};
                currentApn.apn = xml.attributes().value(QStringLiteral("value")).toString();
                inApn          = true;
            } else if (inApn) {
                if (name == QStringLiteral("name"))
                    currentApn.name = xml.readElementText();
                else if (name == QStringLiteral("username"))
                    currentApn.username = xml.readElementText();
                else if (name == QStringLiteral("password"))
                    currentApn.password = xml.readElementText();
                else if (name == QStringLiteral("mmsc"))
                    currentApn.mmsc = xml.readElementText();
                else if (name == QStringLiteral("mmsproxy"))
                    currentApn.mmsproxy = xml.readElementText();
                else if (name == QStringLiteral("usage"))
                    currentApn.usage = xml.attributes().value(QStringLiteral("type")).toString();
            }
        } else if (xml.isEndElement()) {
            const auto name = xml.name();
            if (name == QStringLiteral("apn")) {
                inApn = false;
                currentProvider.apns.append(currentApn);
            } else if (name == QStringLiteral("gsm")) {
                inGsm = false;
            } else if (name == QStringLiteral("provider")) {
                for (const QString &code : pendingOperatorCodes) {
                    // Last-write-wins; MBPI sometimes lists multiple providers per code
                    // (MVNOs reusing parent code). Prefer the first match in file order,
                    // which tends to be the major carrier.
                    if (!m_byOperatorCode.contains(code))
                        m_byOperatorCode.insert(code, currentProvider);
                }
            }
        }
    }

    if (xml.hasError()) {
        qWarning() << "[CarrierProvisioning] MBPI parse error:" << xml.errorString();
    }
    qInfo() << "[CarrierProvisioning] Loaded MBPI:" << m_byOperatorCode.size()
            << "operator entries";
}

QVariantList CarrierProvisioning::apnSuggestions(const QString &operatorCode) const {
    QVariantList out;
    if (operatorCode.isEmpty())
        return out;

    const auto it = m_byOperatorCode.constFind(operatorCode);
    if (it == m_byOperatorCode.constEnd())
        return out;

    for (const Apn &a : it.value().apns) {
        QVariantMap m;
        m.insert(QStringLiteral("apn"), a.apn);
        m.insert(QStringLiteral("name"), a.name);
        m.insert(QStringLiteral("usage"), a.usage);
        m.insert(QStringLiteral("username"), a.username);
        m.insert(QStringLiteral("password"), a.password);
        m.insert(QStringLiteral("mmsc"), a.mmsc);
        m.insert(QStringLiteral("mmsproxy"), a.mmsproxy);
        out.append(m);
    }
    return out;
}

QVariantList CarrierProvisioning::apnSuggestionsFor(const QString &mcc, const QString &mnc) const {
    // MBPI encodes MNCs as 2 or 3 digit strings; the caller may pass them as
    // "10" or "010" depending on what ModemManager reports. Try the literal
    // first, then the 2-digit and 3-digit zero-padded variants.
    const QStringList tries = {mcc + mnc, mcc + mnc.rightJustified(2, QLatin1Char('0')),
                               mcc + mnc.rightJustified(3, QLatin1Char('0'))};
    for (const QString &code : tries) {
        const auto suggestions = apnSuggestions(code);
        if (!suggestions.isEmpty())
            return suggestions;
    }
    return {};
}

QString CarrierProvisioning::providerName(const QString &operatorCode) const {
    const auto it = m_byOperatorCode.constFind(operatorCode);
    return it == m_byOperatorCode.constEnd() ? QString() : it.value().name;
}
