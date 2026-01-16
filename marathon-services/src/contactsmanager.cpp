#include "contactsmanager.h"
#include <QStandardPaths>
#include <QTextStream>
#include <QDebug>
#include <QRegularExpression>

ContactsManager::ContactsManager(QObject *parent)
    : QObject(parent)
    , m_nextId(1) {
    m_contactsDir = getContactsDir();

    QDir dir;
    if (!dir.exists(m_contactsDir)) {
        dir.mkpath(m_contactsDir);
        qDebug() << "[ContactsManager] Created contacts directory:" << m_contactsDir;
    }

    loadFromVCards();
    qDebug() << "[ContactsManager] Initialized with" << m_contacts.size() << "contacts";
}

ContactsManager::~ContactsManager() {}

QString ContactsManager::getContactsDir() {
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    return dataDir + "/marathon/contacts";
}

QVariantList ContactsManager::contacts() const {
    QVariantList list;
    for (const Contact &contact : m_contacts) {
        QVariantMap map;
        map["id"]           = contact.id;
        map["name"]         = contact.name;
        map["phone"]        = contact.phone;
        map["email"]        = contact.email;
        map["organization"] = contact.organization;
        map["favorite"]     = contact.additionalFields.value("favorite", false);
        list.append(map);
    }
    return list;
}

int ContactsManager::count() const {
    return m_contacts.size();
}

void ContactsManager::addContact(const QString &name, const QString &phone, const QString &email) {
    if (name.isEmpty()) {
        qWarning() << "[ContactsManager] Cannot add contact with empty name";
        return;
    }

    Contact contact;
    contact.id                           = m_nextId++;
    contact.name                         = name;
    contact.phone                        = phone;
    contact.email                        = email;
    contact.additionalFields["favorite"] = false;

    m_contacts.append(contact);
    saveToVCard(contact);

    emit contactsChanged();
    emit contactAdded(contact.id);
    qDebug() << "[ContactsManager] Added contact:" << name << "ID:" << contact.id;
}

void ContactsManager::updateContact(int id, const QVariantMap &data) {
    for (int i = 0; i < m_contacts.size(); ++i) {
        if (m_contacts[i].id == id) {
            if (data.contains("name")) {
                m_contacts[i].name = data["name"].toString();
            }
            if (data.contains("phone")) {
                m_contacts[i].phone = data["phone"].toString();
            }
            if (data.contains("email")) {
                m_contacts[i].email = data["email"].toString();
            }
            if (data.contains("organization")) {
                m_contacts[i].organization = data["organization"].toString();
            }
            if (data.contains("favorite")) {
                m_contacts[i].additionalFields["favorite"] = data["favorite"];
            }

            saveToVCard(m_contacts[i]);
            emit contactsChanged();
            emit contactUpdated(id);
            qDebug() << "[ContactsManager] Updated contact ID:" << id;
            return;
        }
    }
    qWarning() << "[ContactsManager] Contact not found for update:" << id;
}

void ContactsManager::deleteContact(int id) {
    for (int i = 0; i < m_contacts.size(); ++i) {
        if (m_contacts[i].id == id) {
            QString fileName =
                sanitizeFileName(m_contacts[i].name) + "_" + QString::number(id) + ".vcf";
            QString filePath = m_contactsDir + "/" + fileName;

            QFile   file(filePath);
            if (file.exists()) {
                file.remove();
            }

            m_contacts.removeAt(i);
            emit contactsChanged();
            emit contactDeleted(id);
            qDebug() << "[ContactsManager] Deleted contact ID:" << id;
            return;
        }
    }
    qWarning() << "[ContactsManager] Contact not found for deletion:" << id;
}

QVariantList ContactsManager::searchContacts(const QString &query) {
    QVariantList results;
    QString      lowerQuery = query.toLower();

    for (const Contact &contact : m_contacts) {
        if (contact.name.toLower().contains(lowerQuery) || contact.phone.contains(query) ||
            contact.email.toLower().contains(lowerQuery)) {

            QVariantMap map;
            map["id"]           = contact.id;
            map["name"]         = contact.name;
            map["phone"]        = contact.phone;
            map["email"]        = contact.email;
            map["organization"] = contact.organization;
            results.append(map);
        }
    }

    return results;
}

QVariantMap ContactsManager::getContact(int id) {
    for (const Contact &contact : m_contacts) {
        if (contact.id == id) {
            QVariantMap map;
            map["id"]           = contact.id;
            map["name"]         = contact.name;
            map["phone"]        = contact.phone;
            map["email"]        = contact.email;
            map["organization"] = contact.organization;
            map["favorite"]     = contact.additionalFields.value("favorite", false);
            return map;
        }
    }
    return QVariantMap();
}

QVariantMap ContactsManager::getContactByNumber(const QString &phoneNumber) {
    if (phoneNumber.isEmpty()) {
        return QVariantMap();
    }

    QString cleanNumber = phoneNumber;
    cleanNumber.remove(QRegularExpression("[^0-9+]"));

    for (const Contact &contact : m_contacts) {
        QString cleanContactNumber = contact.phone;
        cleanContactNumber.remove(QRegularExpression("[^0-9+]"));

        if (cleanContactNumber == cleanNumber ||
            cleanContactNumber.endsWith(cleanNumber.right(10)) ||
            cleanNumber.endsWith(cleanContactNumber.right(10))) {

            QVariantMap map;
            map["id"]           = contact.id;
            map["name"]         = contact.name;
            map["phone"]        = contact.phone;
            map["email"]        = contact.email;
            map["organization"] = contact.organization;
            map["favorite"]     = contact.additionalFields.value("favorite", false);
            return map;
        }
    }

    return QVariantMap();
}

void ContactsManager::loadFromVCards() {
    m_contacts.clear();

    QDir        dir(m_contactsDir);
    QStringList vcfFiles = dir.entryList(QStringList() << "*.vcf", QDir::Files);

    for (const QString &fileName : vcfFiles) {
        QString filePath = m_contactsDir + "/" + fileName;
        QFile   file(filePath);

        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            continue;
        }

        QTextStream in(&file);
        QString     content = in.readAll();
        file.close();

        Contact                 contact;

        QRegularExpression      idRegex("_(\\d+)\\.vcf$");
        QRegularExpressionMatch match = idRegex.match(fileName);
        if (match.hasMatch()) {
            contact.id = match.captured(1).toInt();
            if (contact.id >= m_nextId) {
                m_nextId = contact.id + 1;
            }
        } else {
            contact.id = m_nextId++;
        }

        QRegularExpression fnRegex("FN:(.*?)\\r?\\n");
        match = fnRegex.match(content);
        if (match.hasMatch()) {
            contact.name = match.captured(1).trimmed();
        }

        QRegularExpression telRegex("TEL[^:]*:(.*?)\\r?\\n");
        match = telRegex.match(content);
        if (match.hasMatch()) {
            contact.phone = match.captured(1).trimmed();
        }

        QRegularExpression emailRegex("EMAIL[^:]*:(.*?)\\r?\\n");
        match = emailRegex.match(content);
        if (match.hasMatch()) {
            contact.email = match.captured(1).trimmed();
        }

        QRegularExpression orgRegex("ORG:(.*?)\\r?\\n");
        match = orgRegex.match(content);
        if (match.hasMatch()) {
            contact.organization = match.captured(1).trimmed();
        }

        if (!contact.name.isEmpty()) {
            m_contacts.append(contact);
        }
    }

    qDebug() << "[ContactsManager] Loaded" << m_contacts.size() << "contacts from vCards";
}

void ContactsManager::saveToVCard(const Contact &contact) {
    QString fileName = sanitizeFileName(contact.name) + "_" + QString::number(contact.id) + ".vcf";
    QString filePath = m_contactsDir + "/" + fileName;

    QFile   file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "[ContactsManager] Failed to save vCard:" << filePath;
        return;
    }

    QTextStream out(&file);

    out << "BEGIN:VCARD\n";
    out << "VERSION:3.0\n";
    out << "FN:" << contact.name << "\n";

    if (!contact.phone.isEmpty()) {
        out << "TEL;TYPE=CELL:" << contact.phone << "\n";
    }

    if (!contact.email.isEmpty()) {
        out << "EMAIL;TYPE=INTERNET:" << contact.email << "\n";
    }

    if (!contact.organization.isEmpty()) {
        out << "ORG:" << contact.organization << "\n";
    }

    out << "END:VCARD\n";

    file.close();
    qDebug() << "[ContactsManager] Saved vCard:" << fileName;
}

void ContactsManager::importVCard(const QString &path) {
    QFile file(path);
    if (!file.exists()) {
        qWarning() << "[ContactsManager] Import failed: file does not exist:" << path;
        emit importComplete(0);
        return;
    }

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[ContactsManager] Import failed: cannot open:" << path;
        emit importComplete(0);
        return;
    }

    QTextStream   in(&file);
    const QString content = in.readAll();
    file.close();

    QString                 name;
    QString                 phone;
    QString                 email;
    QString                 organization;

    QRegularExpressionMatch match;
    match = QRegularExpression("FN:(.*?)\\r?\\n").match(content);
    if (match.hasMatch()) {
        name = match.captured(1).trimmed();
    }

    match = QRegularExpression("TEL[^:]*:(.*?)\\r?\\n").match(content);
    if (match.hasMatch()) {
        phone = match.captured(1).trimmed();
    }

    match = QRegularExpression("EMAIL[^:]*:(.*?)\\r?\\n").match(content);
    if (match.hasMatch()) {
        email = match.captured(1).trimmed();
    }

    match = QRegularExpression("ORG:(.*?)\\r?\\n").match(content);
    if (match.hasMatch()) {
        organization = match.captured(1).trimmed();
    }

    if (name.isEmpty()) {
        qWarning() << "[ContactsManager] Import failed: no FN field found in vCard:" << path;
        emit importComplete(0);
        return;
    }

    addContact(name, phone, email);

    if (!organization.isEmpty()) {

        const int   newId = m_nextId - 1;
        QVariantMap update;
        update["organization"] = organization;
        updateContact(newId, update);
    }

    emit importComplete(1);
}

void ContactsManager::exportVCard(int contactId, const QString &path) {
    QVariantMap contactMap = getContact(contactId);
    if (contactMap.isEmpty()) {
        qWarning() << "[ContactsManager] Export failed: contact not found:" << contactId;
        emit exportComplete(false);
        return;
    }

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        qWarning() << "[ContactsManager] Export failed: cannot open:" << path;
        emit exportComplete(false);
        return;
    }

    QTextStream out(&file);
    out << "BEGIN:VCARD\n";
    out << "VERSION:3.0\n";
    out << "FN:" << contactMap.value("name").toString() << "\n";

    const QString phone = contactMap.value("phone").toString();
    if (!phone.isEmpty()) {
        out << "TEL;TYPE=CELL:" << phone << "\n";
    }

    const QString email = contactMap.value("email").toString();
    if (!email.isEmpty()) {
        out << "EMAIL;TYPE=INTERNET:" << email << "\n";
    }

    const QString org = contactMap.value("organization").toString();
    if (!org.isEmpty()) {
        out << "ORG:" << org << "\n";
    }

    out << "END:VCARD\n";
    file.close();

    emit exportComplete(true);
}

QString ContactsManager::sanitizeFileName(const QString &name) {
    QString sanitized = name;

    sanitized.replace(QRegularExpression("[/\\\\:*?\"<>|]"), "_");
    sanitized.replace(" ", "_");
    return sanitized;
}
