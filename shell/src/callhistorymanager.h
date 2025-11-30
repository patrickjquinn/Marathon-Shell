#ifndef CALLHISTORYMANAGER_H
#define CALLHISTORYMANAGER_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QSqlDatabase>
#include <QDateTime>

class ContactsManager;

struct CallRecord {
    int     id;
    QString number;
    QString contactName;
    QString type; // "incoming", "outgoing", "missed"
    qint64  timestamp;
    int     duration; // seconds
};

class CallHistoryManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(int count READ count NOTIFY historyChanged)

  public:
    explicit CallHistoryManager(QObject *parent = nullptr);
    ~CallHistoryManager();

    void                     setContactsManager(ContactsManager *contactsManager);

    QVariantList             history() const;
    int                      count() const;

    Q_INVOKABLE void         addCall(const QString &number, const QString &type, qint64 timestamp,
                                     int duration);
    Q_INVOKABLE void         deleteCall(int id);
    Q_INVOKABLE void         clearHistory();
    Q_INVOKABLE QVariantMap  getCallById(int id);
    Q_INVOKABLE QVariantList getCallsByNumber(const QString &number);

  signals:
    void historyChanged();
    void callAdded(int id);

  private:
    void              initDatabase();
    void              loadHistory();
    void              saveCall(const CallRecord &record);
    QString           resolveContactName(const QString &number);

    QList<CallRecord> m_history;
    QSqlDatabase      m_database;
    ContactsManager  *m_contactsManager;
    static const int  MAX_HISTORY_SIZE = 500;
};

#endif // CALLHISTORYMANAGER_H
