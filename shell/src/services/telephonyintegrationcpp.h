#ifndef TELEPHONYINTEGRATIONCPP_H
#define TELEPHONYINTEGRATIONCPP_H

#include <QObject>
#include <QString>
#include <QVariantMap>

class ContactsManager;
class NotificationServiceCpp;
class PowerPolicyController;
class PowerManagerCpp;
class DisplayPolicyController;
class DisplayManagerCpp;
class AudioPolicyController;
class HapticManager;
class TelephonyService;
class SMSService;

class TelephonyIntegrationCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(
        QString lastCallState READ lastCallState WRITE setLastCallState NOTIFY lastCallStateChanged)
    Q_PROPERTY(QString lastCallerNumber READ lastCallerNumber WRITE setLastCallerNumber NOTIFY
                   lastCallerNumberChanged)
    Q_PROPERTY(bool callWasAnswered READ callWasAnswered WRITE setCallWasAnswered NOTIFY
                   callWasAnsweredChanged)
    Q_PROPERTY(QObject *incomingCallOverlay READ incomingCallOverlay WRITE setIncomingCallOverlay
                   NOTIFY incomingCallOverlayChanged)
    Q_PROPERTY(bool hasActiveCall READ hasActiveCall NOTIFY hasActiveCallChanged)

  public:
    explicit TelephonyIntegrationCpp(
        ContactsManager *contactsManager, NotificationServiceCpp *notificationService,
        PowerPolicyController *powerPolicy, PowerManagerCpp *powerManager,
        DisplayPolicyController *displayPolicy, DisplayManagerCpp *displayManager,
        AudioPolicyController *audioPolicy, HapticManager *haptics,
        TelephonyService *telephonyService, SMSService *smsService, QObject *parent = nullptr);

    QString lastCallState() const {
        return m_lastCallState;
    }
    void    setLastCallState(const QString &state);

    QString lastCallerNumber() const {
        return m_lastCallerNumber;
    }
    void setLastCallerNumber(const QString &number);

    bool callWasAnswered() const {
        return m_callWasAnswered;
    }
    void     setCallWasAnswered(bool answered);

    QObject *incomingCallOverlay() const {
        return m_incomingCallOverlay;
    }
    void setIncomingCallOverlay(QObject *overlay);

    bool hasActiveCall() const {
        return m_hasActiveCall;
    }

  signals:
    void lastCallStateChanged();
    void lastCallerNumberChanged();
    void callWasAnsweredChanged();
    void incomingCallOverlayChanged();
    void hasActiveCallChanged();
    void incomingCallRequested(const QString &number);
    void callOverlayDismissRequested();
    void unlockRequested();

  private slots:
    void handleIncomingCall(const QString &number);
    void handleCallStateChanged(const QString &state);
    void handleMessageReceived(const QString &sender, const QString &text, qint64 timestamp);

  private:
    QString                  resolveContactName(const QString &number) const;
    void                     createMissedCallNotification(const QString &number);
    void                     showIncomingOverlay(const QString &number);
    void                     hideIncomingOverlay();
    void                     updateHasActiveCall(const QString &state);

    ContactsManager         *m_contactsManager     = nullptr;
    NotificationServiceCpp  *m_notificationService = nullptr;
    PowerPolicyController   *m_powerPolicy         = nullptr;
    PowerManagerCpp         *m_powerManager        = nullptr;
    DisplayPolicyController *m_displayPolicy       = nullptr;
    DisplayManagerCpp       *m_displayManager      = nullptr;
    AudioPolicyController   *m_audioPolicy         = nullptr;
    HapticManager           *m_haptics             = nullptr;
    TelephonyService        *m_telephonyService    = nullptr;
    SMSService              *m_smsService          = nullptr;

    QString                  m_lastCallState = "idle";
    QString                  m_lastCallerNumber;
    bool                     m_callWasAnswered     = false;
    QObject                 *m_incomingCallOverlay = nullptr;
    bool                     m_hasActiveCall       = false;
    QString                  m_pendingIncomingNumber;
};

#endif
