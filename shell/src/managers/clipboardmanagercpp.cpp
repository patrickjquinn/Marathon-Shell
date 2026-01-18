#include "clipboardmanagercpp.h"
#include "settingsmanager.h"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

ClipboardManagerCpp::ClipboardManagerCpp(SettingsManager *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings) {
    load();
}

QVariantList ClipboardManagerCpp::getHistory() const {
    return m_history;
}

void ClipboardManagerCpp::copyToClipboard(const QString &text, const QString &type) {
    addToHistory(text, type);
}

void ClipboardManagerCpp::deleteItem(int index) {
    if (index < 0 || index >= m_history.size())
        return;

    m_history.removeAt(index);
    save();
    emit historyChanged();
}

void ClipboardManagerCpp::clearHistory() {
    if (m_history.isEmpty())
        return;

    m_history.clear();
    save();
    emit historyChanged();
    emit historyCleared();
}

void ClipboardManagerCpp::load() {
    if (!m_settings) {
        m_history.clear();
        return;
    }

    const QVariant raw = m_settings->get("clipboard/history", QVariantList());
    m_history          = parseHistory(raw);
}

void ClipboardManagerCpp::save() {
    if (!m_settings)
        return;

    m_settings->set("clipboard/history", m_history);
    m_settings->sync();
}

void ClipboardManagerCpp::addToHistory(const QString &text, const QString &type) {
    if (text.isEmpty())
        return;

    for (int i = 0; i < m_history.size(); ++i) {
        const QVariantMap item = m_history[i].toMap();
        if (item.value("text").toString() == text) {
            m_history.removeAt(i);
            break;
        }
    }

    QVariantMap item;
    item["text"]      = text;
    item["type"]      = type;
    item["timestamp"] = QDateTime::currentMSecsSinceEpoch();
    m_history.prepend(item);

    if (m_history.size() > m_maxHistorySize)
        m_history = m_history.mid(0, m_maxHistorySize);

    save();
    emit historyChanged();
}

QVariantList ClipboardManagerCpp::parseHistory(const QVariant &raw) const {
    if (raw.canConvert<QVariantList>())
        return raw.toList();

    if (raw.typeId() == QMetaType::QString) {
        const QJsonDocument doc = QJsonDocument::fromJson(raw.toString().toUtf8());
        if (!doc.isArray())
            return {};

        QVariantList     list;
        const QJsonArray arr = doc.array();
        list.reserve(arr.size());
        for (const QJsonValue &value : arr) {
            if (!value.isObject())
                continue;
            list.append(value.toObject().toVariantMap());
        }
        return list;
    }

    return {};
}
