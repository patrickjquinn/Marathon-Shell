#ifndef CONTACTSMANAGER_H
#define CONTACTSMANAGER_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QDir>
#include <QFile>

struct Contact {
    int         id;
    QString     name;
    QString     phone;
    QString     email;
    QString     organization;
    QVariantMap additionalFields;
};

class ContactsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList contacts READ contacts NOTIFY contactsChanged)
    Q_PROPERTY(int count READ count NOTIFY contactsChanged)

  public:
    explicit ContactsManager(QObject *parent = nullptr);
    ~ContactsManager();

    QVariantList             contacts() const;
    int                      count() const;

    Q_INVOKABLE void         addContact(const QString &name, const QString &phone,
                                        const QString &email = QString());
    Q_INVOKABLE void         updateContact(int id, const QVariantMap &data);
    Q_INVOKABLE void         deleteContact(int id);
    Q_INVOKABLE QVariantList searchContacts(const QString &query);
    Q_INVOKABLE QVariantMap  getContact(int id);
    Q_INVOKABLE QVariantMap  getContactByNumber(const QString &phoneNumber);
    Q_INVOKABLE void         importVCard(const QString &path);
    Q_INVOKABLE void         exportVCard(int contactId, const QString &path);

  signals:
    void contactsChanged();
    void contactAdded(int id);
    void contactUpdated(int id);
    void contactDeleted(int id);
    void importComplete(int count);
    void exportComplete(bool success);

  private:
    void           loadFromVCards();
    void           saveToVCard(const Contact &contact);
    QString        parseVCard(const QString &filePath);
    void           writeVCard(const Contact &contact, const QString &filePath);
    QString        sanitizeFileName(const QString &name);
    QString        getContactsDir();

    QList<Contact> m_contacts;
    int            m_nextId;
    QString        m_contactsDir;
};

#endif // CONTACTSMANAGER_H
