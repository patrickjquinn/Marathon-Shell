#include "contactsmanager.h"
#include <QStandardPaths>
#include <QTextStream>
#include <QDebug>
#include <QRegularExpression>

ContactsManager::ContactsManager(QObject *parent)
    : QObject(parent)
    , m_nextId(1) {
    m_contactsDir = getContactsDir();

    // Create contacts directory if it doesn't exist
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

        // Simple vCard parsing (supports v3.0 and v4.0)
        Contact contact;

        // Extract ID from filename
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

        // Parse FN (formatted name)
        QRegularExpression fnRegex("FN:(.*?)\\r?\\n");
        match = fnRegex.match(content);
        if (match.hasMatch()) {
            contact.name = match.captured(1).trimmed();
        }

        // Parse TEL (phone)
        QRegularExpression telRegex("TEL[^:]*:(.*?)\\r?\\n");
        match = telRegex.match(content);
        if (match.hasMatch()) {
            contact.phone = match.captured(1).trimmed();
        }

        // Parse EMAIL
        QRegularExpression emailRegex("EMAIL[^:]*:(.*?)\\r?\\n");
        match = emailRegex.match(content);
        if (match.hasMatch()) {
            contact.email = match.captured(1).trimmed();
        }

        // Parse ORG (organization)
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

    // Write vCard v3.0 format
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
    // TODO: Implement vCard import from external file
    qDebug() << "[ContactsManager] Import vCard:" << path;
}

void ContactsManager::exportVCard(int contactId, const QString &path) {
    // TODO: Implement vCard export to external file
    qDebug() << "[ContactsManager] Export vCard for contact" << contactId << "to" << path;
}

QString ContactsManager::sanitizeFileName(const QString &name) {
    QString sanitized = name;
    // Remove or replace characters that are invalid in filenames
    sanitized.replace(QRegularExpression("[/\\\\:*?\"<>|]"), "_");
    sanitized.replace(" ", "_");
    return sanitized;
}
