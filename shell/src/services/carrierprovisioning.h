#ifndef CARRIERPROVISIONING_H
#define CARRIERPROVISIONING_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QHash>
#include <qqml.h>

// Maps a SIM's MCC+MNC pair to APN / MMS settings using the freedesktop
// mobile-broadband-provider-info database (/usr/share/mobile-broadband-
// provider-info/serviceproviders.xml).
//
// Mirrors what NetworkManager / oFono do on desktops: instead of asking the
// user to type APN settings, look up their carrier's published values by
// MCC+MNC reported by ModemManager.Modem3gpp.OperatorCode.
//
// Schema reference:
// https://gitlab.gnome.org/GNOME/mobile-broadband-provider-info
class CarrierProvisioning : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
  public:
    // QML_SINGLETON factory — required so the type registers correctly in
    // marathon-app-runner processes that import this module without the
    // shell's explicit qmlRegisterSingletonInstance call. Shell process
    // still calls qmlRegisterSingletonInstance in main.cpp; that override
    // wins so shell-side C++ consumers share the same instance pointer.
    static CarrierProvisioning *create(QQmlEngine *, QJSEngine *);

    Q_PROPERTY(bool databaseAvailable READ databaseAvailable CONSTANT)

  public:
    explicit CarrierProvisioning(QObject *parent = nullptr);

    bool databaseAvailable() const {
        return m_databaseAvailable;
    }

    // Suggest APN entries for a SIM's MCC+MNC (the operator code, e.g.
    // "23410" for O2 UK = MCC 234, MNC 10). Returns a list of
    // QVariantMap entries with keys:
    //   apn (string), name (string, optional), usage (string: internet/mms),
    //   username (string, optional), password (string, optional),
    //   mmsc (string, optional), mmsproxy (string, optional)
    // Empty list means "operator not found in MBPI"; let the user enter
    // manually.
    Q_INVOKABLE QVariantList apnSuggestions(const QString &operatorCode) const;

    // Variant on apnSuggestions() that takes MCC and MNC separately so
    // QML can pass them as numbers without zero-padding bookkeeping.
    Q_INVOKABLE QVariantList apnSuggestionsFor(const QString &mcc, const QString &mnc) const;

    // Provider name (e.g. "Vodafone UK") for a given operator code. Useful
    // for OOBE / settings UI ("Detected carrier: <name>").
    Q_INVOKABLE QString providerName(const QString &operatorCode) const;

  private:
    void loadDatabase();

    struct Apn {
        QString apn;
        QString name;
        QString usage; // "internet" | "mms" | ""
        QString username;
        QString password;
        QString mmsc;
        QString mmsproxy;
    };
    struct Provider {
        QString    name;
        QList<Apn> apns;
    };

    // operatorCode (MCCMNC, zero-padded MNC to 2 or 3 digits) -> Provider
    QHash<QString, Provider> m_byOperatorCode;
    bool                     m_databaseAvailable = false;
};

#endif
