#include "telephonyintegrationcpp.h"

#include "notificationservicecpp.h"
#include "powermanagercpp.h"
#include "displaymanagercpp.h"
#include "displaypolicycontroller.h"
#include "powerpolicycontroller.h"
#include "audiopolicycontroller.h"
#include "hapticmanager.h"
#include "telephonyservice.h"
#include "smsservice.h"
#include "contactsmanager.h"
#include "sensormanagercpp.h"

#include <QMetaObject>

TelephonyIntegrationCpp::TelephonyIntegrationCpp(
    ContactsManager *contactsManager, NotificationServiceCpp *notificationService,
    PowerPolicyController *powerPolicy, PowerManagerCpp *powerManager,
    DisplayPolicyController *displayPolicy, DisplayManagerCpp *displayManager,
    AudioPolicyController *audioPolicy, HapticManager *haptics, TelephonyService *telephonyService,
    SMSService *smsService, SensorManagerCpp *sensorManager, QObject *parent)
    : QObject(parent)
    , m_contactsManager(contactsManager)
    , m_notificationService(notificationService)
    , m_powerPolicy(powerPolicy)
    , m_powerManager(powerManager)
    , m_displayPolicy(displayPolicy)
    , m_displayManager(displayManager)
    , m_audioPolicy(audioPolicy)
    , m_haptics(haptics)
    , m_telephonyService(telephonyService)
    , m_smsService(smsService)
    , m_sensorManager(sensorManager) {
    if (m_telephonyService) {
        connect(m_telephonyService, &TelephonyService::incomingCall, this,
                &TelephonyIntegrationCpp::handleIncomingCall);
        connect(m_telephonyService, &TelephonyService::callStateChanged, this,
                &TelephonyIntegrationCpp::handleCallStateChanged);
    }

    if (m_smsService) {
        connect(m_smsService, &SMSService::messageReceived, this,
                &TelephonyIntegrationCpp::handleMessageReceived);
    }

    if (m_sensorManager) {
        connect(m_sensorManager, &SensorManagerCpp::proximityNearChanged, this,
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

void TelephonyIntegrationCpp::setCallWasAnswered(bool answered) {
    if (m_callWasAnswered == answered)
        return;
    m_callWasAnswered = answered;
    emit callWasAnsweredChanged();
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
    setCallWasAnswered(false);

    if (m_powerPolicy)
        m_powerPolicy->wake("call");
    else if (m_powerManager)
        m_powerManager->acquireWakelock("call");

    if (m_displayPolicy)
        m_displayPolicy->turnScreenOn();
    else if (m_displayManager)
        m_displayManager->setScreenState(true);

    if (m_audioPolicy)
        m_audioPolicy->playRingtone();

    if (m_haptics)
        m_haptics->vibratePattern(QVariantList{1000, 500}, -1);

    showIncomingOverlay(number);
}

void TelephonyIntegrationCpp::handleCallStateChanged(const QString &state) {
    updateHasActiveCall(state);

    if (m_lastCallState == "incoming" && (state == "idle" || state == "terminated")) {
        if (!m_callWasAnswered)
            createMissedCallNotification(m_lastCallerNumber);
    }

    if (state == "active" || state == "idle" || state == "terminated") {
        if (m_audioPolicy)
            m_audioPolicy->stopRingtone();
        if (m_haptics)
            m_haptics->stopVibration();
        hideIncomingOverlay();
        emit unlockRequested();
    }

    // Force-wake on call-end: proximity may have blanked the screen while we
    // were on the call; once the call is over the proximity gate stops
    // firing (handleProximityChanged checks m_hasActiveCall) and a stale
    // "near" reading would otherwise leave the device unwakable.
    if (state == "idle" || state == "terminated") {
        if (m_displayPolicy)
            m_displayPolicy->turnScreenOn();
        else if (m_displayManager)
            m_displayManager->setScreenState(true);
    }

    setLastCallState(state);
}

void TelephonyIntegrationCpp::handleMessageReceived(const QString &sender, const QString &text,
                                                    qint64) {
    if (m_powerPolicy)
        m_powerPolicy->wake("notification");
    else if (m_powerManager)
        m_powerManager->acquireWakelock("notification");

    const QString contactName = resolveContactName(sender);
    if (m_notificationService) {
        QVariantList actions;
        actions.append(QVariantMap{{"id", "reply"}, {"label", "Reply"}});
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
}

void TelephonyIntegrationCpp::handleProximityChanged() {
    if (!m_hasActiveCall || !m_sensorManager || !m_displayManager)
        return;

    // CRITICAL: only act on proximity if the sensor is actually present and
    // running. On hardware without a proximity sensor (e.g. QEMU, mid-range
    // devices), QtSensors may still synthesise readings from a default
    // backend, and a stray "near" report will leave the user stuck with a
    // dark screen during a call -- there's no way to re-wake without the
    // sensor reporting "far". SensorManagerCpp clears proximityAvailable
    // unless connectToBackend() AND start() both succeeded.
    if (!m_sensorManager->proximityAvailable()) {
        qDebug()
            << "[TelephonyIntegration] Ignoring proximity event - no proximity sensor available";
        return;
    }

    if (m_sensorManager->proximityNear()) {
        qInfo() << "[TelephonyIntegration] Proximity near during call - screen off";
        m_displayManager->setScreenState(false);
    } else {
        qInfo() << "[TelephonyIntegration] Proximity far during call - screen on";
        m_displayManager->setScreenState(true);
    }
}
