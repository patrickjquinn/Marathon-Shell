#include "domainsuggestions.h"

DomainSuggestions::DomainSuggestions(QObject *parent)
    : QObject(parent)
    , m_commonTlds({"com", "org", "net", "edu", "gov", "co.uk", "co", "io", "app", "dev",
                    "uk",  "ca",  "au",  "de",  "fr",  "jp",    "cn", "in", "br",  "ru"})
    , m_emailDomains({"gmail.com", "outlook.com", "yahoo.com", "hotmail.com", "icloud.com",
                      "protonmail.com", "me.com", "live.com", "msn.com"}) {}

QStringList DomainSuggestions::getSuggestions(const QString &text, bool isEmail) const {
    if (text.isEmpty()) {
        return {};
    }

    QStringList   suggestions;
    const QString lowerText = text.toLower();

    if (isEmail) {
        if (lowerText.contains("@")) {
            const QStringList parts = lowerText.split("@");
            if (parts.size() == 2) {
                const QString domain = parts[1];
                for (const QString &emailDomain : m_emailDomains) {
                    if (suggestions.size() >= 3) {
                        break;
                    }
                    if (emailDomain.startsWith(domain) && emailDomain != domain) {
                        suggestions.append(parts[0] + "@" + emailDomain);
                    }
                }
            }
        } else if (lowerText.size() >= 2) {
            for (const QString &emailDomain : m_emailDomains) {
                if (suggestions.size() >= 3) {
                    break;
                }
                suggestions.append(lowerText + "@" + emailDomain);
            }
        }
        return suggestions;
    }

    const int lastDot = lowerText.lastIndexOf(".");
    if (lastDot != -1) {
        const QString afterDot  = lowerText.mid(lastDot + 1);
        const QString beforeDot = lowerText.left(lastDot + 1);
        for (const QString &tld : m_commonTlds) {
            if (suggestions.size() >= 3) {
                break;
            }
            if (tld.startsWith(afterDot) && tld != afterDot) {
                suggestions.append(beforeDot + tld);
            }
        }
    } else if (lowerText.size() >= 2 && !lowerText.contains("://")) {
        for (int i = 0; i < m_commonTlds.size() && suggestions.size() < 3; ++i) {
            suggestions.append(lowerText + "." + m_commonTlds[i]);
        }
    }

    return suggestions;
}

bool DomainSuggestions::shouldShowDomainSuggestions(const QString &text, bool isEmail,
                                                    bool isUrl) const {
    if (text.isEmpty()) {
        return false;
    }

    if (isEmail) {
        return text.contains("@") || text.size() >= 2;
    }

    if (isUrl) {
        return text.contains(".") || (text.size() >= 2 && !text.contains("://"));
    }

    return false;
}
