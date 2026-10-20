#include "telephonyintegrationcpp.h"

#include "notificationservicecpp.h"
#include "marathon-shell-native/src/display.cxxqt.h"
#include "powerpolicycontroller.h"
#include "audiopolicycontroller.h"
#include "hapticmanager.h"
#include "marathon-shell-native/src/modem.cxxqt.h"
#include "smsservice.h"
#include "contactsmanager.h"

#include <QMetaObject>

TelephonyIntegrationCpp::TelephonyIntegrationCpp(
    ContactsManager *contactsManager, NotificationServiceCpp *notificationService,
    PowerPolicyController *powerPolicy, marathon::Display *display, AudioPolicyController *audioPolicy,
    HapticManager *haptics, Modem *telephonyService, SMSService *smsService, QObject *parent)
    : QObject(parent)
    , m_contactsManager(contactsManager)
    , m_notificationService(notificationService)
    , m_powerPolicy(powerPolicy)
    , m_display(display)
    , m_audioPolicy(audioPolicy)
    , m_haptics(haptics)
    , m_telephonyService(telephonyService)
    , m_smsService(smsService) {
    if (m_telephonyService) {
        connect(m_telephonyService, &Modem::incomingCall, this,
                &TelephonyIntegrationCpp::handleIncomingCall);
        connect(m_telephonyService, &Modem::callStateChanged, this,
                &TelephonyIntegrationCpp::handleCallStateChanged);
        connect(m_telephonyService, &Modem::callEnded, this,
                &TelephonyIntegrationCpp::handleCallEnded);
    }

    if (m_smsService) {
        connect(m_smsService, &SMSService::messageReceived, this,
                &TelephonyIntegrationCpp::handleMessageReceived);
    }

    if (m_display) {
        connect(m_display, &marathon::Display::proximityNearChanged, this,
                &TelephonyIntegrationCpp::handleProximityChanged);
    }
}

void TelephonyIntegrationCpp::setLastCallState(const QString &state) {
    if (m_lastCallState == state)
        return;
    m_lastCallState = state;
    emit lastCallStateChanged();
}

void TelephonyIntegrationCpp::setLastCallerNumber(const QString &number) {
    if (m_lastCallerNumber == number)
        return;
    m_lastCallerNumber = number;
    emit lastCallerNumberChanged();
}

void TelephonyIntegrationCpp::setIncomingCallOverlay(QObject *overlay) {
    if (m_incomingCallOverlay == overlay)
        return;
    m_incomingCallOverlay = overlay;
    emit incomingCallOverlayChanged();

    if (!m_pendingIncomingNumber.isEmpty() && m_incomingCallOverlay) {
        showIncomingOverlay(m_pendingIncomingNumber);
        m_pendingIncomingNumber.clear();
    }
}

void TelephonyIntegrationCpp::handleIncomingCall(const QString &number) {
    setLastCallerNumber(number);

    if (m_powerPolicy)
        m_powerPolicy->wake("call");

    if (m_display)
        m_display->turnScreenOn();

    if (m_audioPolicy)
        m_audioPolicy->playRingtone();

    if (m_haptics)
        m_haptics->vibratePattern(QVariantList{1000, 500}, -1);

    showIncomingOverlay(number);
}

void TelephonyIntegrationCpp::handleCallStateChanged(const QString &state) {
    updateHasActiveCall(state);

    if (state == "active" || state == "idle" || state == "terminated") {
        if (m_audioPolicy)
            m_audioPolicy->stopRingtone();
        if (m_haptics)
            m_haptics->stopVibration();
        hideIncomingOverlay();
    }

    // Force-wake on call-end: proximity may have blanked the screen while we
    // were on the call; once the call is over the proximity gate stops
    // firing (handleProximityChanged checks m_hasActiveCall) and a stale
    // "near" reading would otherwise leave the device unwakable.
    if (state == "idle" || state == "terminated") {
        if (m_display)
            m_display->turnScreenOn();
    }

    setLastCallState(state);
}

void TelephonyIntegrationCpp::handleCallEnded(const QString &number, const QString &type) {
    if (type == QLatin1String("missed"))
        createMissedCallNotification(number);
}

void TelephonyIntegrationCpp::replyToMessageNotification(uint id, const QString &text) {
    if (!m_notificationService || !m_smsService || text.trimmed().isEmpty())
        return;
    const QVariantMap notification = m_notificationService->getNotification(int(id));
    const QString     recipient    = notification.value("replyTarget").toString();
    if (notification.value("appId").toString() != QLatin1String("messages") || recipient.isEmpty())
        return;
    m_smsService->sendMessage(recipient, text);
    m_notificationService->markAsRead(int(id));
}

void TelephonyIntegrationCpp::handleMessageReceived(const QString &sender, const QString &text,
                                                    qint64) {
    if (m_powerPolicy)
        m_powerPolicy->wake("notification");

    const QString contactName = resolveContactName(sender);
    if (m_notificationService) {
        QVariantList actions;
        actions.append(QVariantMap{{"id", "inline-reply"}, {"label", "Reply"}});
        actions.append(QVariantMap{{"id", "mark_read"}, {"label", "Mark Read"}});
        QVariantMap options;
        options["icon"]        = "message-circle";
        options["category"]    = "message";
        options["priority"]    = "high";
        options["actions"]     = actions;
        options["replyTarget"] = sender;
        m_notificationService->sendNotification("messages", contactName, text, options);
    }

    if (m_haptics)
        m_haptics->medium();
    if (m_audioPolicy)
        m_audioPolicy->playNotificationSound();
}

QString TelephonyIntegrationCpp::resolveContactName(const QString &number) const {
    if (!m_contactsManager)
        return number;
    const QVariantMap contact = m_contactsManager->getContactByNumber(number);
    const QString     name    = contact.value("name").toString();
    return name.isEmpty() ? number : name;
}

void TelephonyIntegrationCpp::createMissedCallNotification(const QString &number) {
    if (!m_notificationService)
        return;

    const QString contactName = resolveContactName(number);
    QVariantList  actions;
    actions.append(QVariantMap{{"id", "call_back"}, {"label", "Call Back"}});
    actions.append(QVariantMap{{"id", "message"}, {"label", "Message"}});

    QVariantMap options;
    options["icon"]     = "phone-missed";
    options["category"] = "call";
    options["priority"] = "high";
    options["actions"]  = actions;

    m_notificationService->sendNotification("phone", "Missed Call", "From: " + contactName,
                                            options);

    if (m_haptics)
        m_haptics->heavy();
}

void TelephonyIntegrationCpp::showIncomingOverlay(const QString &number) {
    if (!m_incomingCallOverlay) {
        m_pendingIncomingNumber = number;
        emit incomingCallRequested(number);
        return;
    }

    const QString contactName = resolveContactName(number);
    QMetaObject::invokeMethod(m_incomingCallOverlay, "show", Q_ARG(QVariant, number),
                              Q_ARG(QVariant, contactName));
}

void TelephonyIntegrationCpp::hideIncomingOverlay() {
    if (m_incomingCallOverlay)
        QMetaObject::invokeMethod(m_incomingCallOverlay, "hide");
    m_pendingIncomingNumber.clear();
    emit callOverlayDismissRequested();
}

void TelephonyIntegrationCpp::updateHasActiveCall(const QString &state) {
    const bool active = (state == "incoming" || state == "ringing" || state == "active");
    if (m_hasActiveCall == active)
        return;
    m_hasActiveCall = active;
    emit hasActiveCallChanged();

    // Drive the shared call-state flag so the proximity sensor gets
    // powered on/off for the duration of the call (main.cpp wires
    // PowerPolicyController::hasActiveCalls -> marathon::Display::
    // setProximityWanted). Without this the sensor never starts and the
    // proximity blank below never fires. Also gates canSleep().
    if (m_powerPolicy)
        m_powerPolicy->setHasActiveCalls(active);

    // Call ended with the screen still proximity-blanked (phone was at
    // the ear when the other side hung up): un-blank immediately.
    if (!active && m_display)
        m_display->setProximityBlank(false);
}

void TelephonyIntegrationCpp::handleProximityChanged() {
    if (!m_hasActiveCall || !m_display)
        return;

    // Use the lightweight backlight-only blank, NOT turnScreenOff —
    // the latter triggers the full deep-idle Doze (CRTC ACTIVE=0 +
    // DDR downshift + lock), which is far too heavy to toggle every
    // time the phone moves to/from the ear and would lock the session
    // mid-call. setProximityBlank just powers the LED down/up.
    qInfo() << "[TelephonyIntegration] Proximity during call - backlight"
            << (m_display->getProximityNear() ? "off" : "on");
    m_display->setProximityBlank(m_display->getProximityNear());
}
