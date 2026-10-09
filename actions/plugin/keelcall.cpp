// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "keelcall.h"

#include <QJSValue>
#include <QJsonArray>
#include <QDebug>

const QString KeelCall::UnknownAction = QStringLiteral("UnknownAction");
const QString KeelCall::InvalidArguments = QStringLiteral("InvalidArguments");
const QString KeelCall::Failed = QStringLiteral("Failed");
const QString KeelCall::Timeout = QStringLiteral("Timeout");
const QString KeelCall::NotAvailable = QStringLiteral("NotAvailable");
const QString KeelCall::Cancelled = QStringLiteral("Cancelled");

KeelCall::KeelCall(QString action, QVariantMap arguments, bool userInitiated, QObject *parent)
    : QObject(parent)
    , m_action(std::move(action))
    , m_arguments(std::move(arguments))
    , m_userInitiated(userInitiated)
{
    m_timer.setSingleShot(true);
    connect(&m_timer, &QTimer::timeout, this, [this]() {
        fail(Timeout, QStringLiteral("the action did not answer in time"));
    });
}

QJsonValue KeelCall::toJson(const QVariant &value)
{
    if (!value.isValid())
        return QJsonValue(QJsonValue::Null);
    if (value.metaType() == QMetaType::fromType<QJSValue>())
        return toJson(value.value<QJSValue>().toVariant());
    if (value.metaType() == QMetaType::fromType<QJsonValue>())
        return value.value<QJsonValue>();
    if (value.metaType() == QMetaType::fromType<QJsonObject>())
        return value.value<QJsonObject>();
    if (value.metaType() == QMetaType::fromType<QJsonArray>())
        return value.value<QJsonArray>();
    if (value.metaType().id() == QMetaType::QVariantMap) {
        QJsonObject object;
        const QVariantMap map = value.toMap();
        for (auto it = map.constBegin(); it != map.constEnd(); ++it) {
            // Undefined JavaScript members are left out, as JSON.stringify does.
            if (it.value().isValid())
                object.insert(it.key(), toJson(it.value()));
        }
        return object;
    }
    if (value.metaType().id() == QMetaType::QVariantList || value.metaType().id() == QMetaType::QStringList) {
        QJsonArray array;
        const QVariantList list = value.toList();
        for (const QVariant &item : list)
            array.append(toJson(item));
        return array;
    }
    return QJsonValue::fromVariant(value);
}

void KeelCall::reply(const QVariant &value)
{
    finish(toJson(value), QString(), QString());
}

void KeelCall::replyJson(const QJsonValue &value)
{
    finish(value, QString(), QString());
}

void KeelCall::fail(const QString &code, const QString &message)
{
    finish(QJsonValue(), code.isEmpty() ? Failed : code, message);
}

void KeelCall::startTimer(int milliseconds)
{
    if (!m_finished && milliseconds > 0)
        m_timer.start(milliseconds);
}

void KeelCall::replyIfPending(const QJsonValue &value)
{
    if (!m_finished)
        finish(value, QString(), QString());
}

void KeelCall::finish(const QJsonValue &result, const QString &code, const QString &message)
{
    if (m_finished)
        return;
    m_timer.stop();
    QJsonValue value = result;
    QString errorCode = code;
    QString errorMessage = message;
    if (errorCode.isEmpty() && m_check) {
        QString checkCode = Failed;
        const QString problem = m_check(value, checkCode);
        if (!problem.isEmpty()) {
            errorCode = checkCode;
            if (checkCode == Failed) {
                errorMessage = QStringLiteral("the result does not match the declared schema: ") + problem;
                qWarning().noquote() << "Keel.Actions:" << m_action << errorMessage;
            } else {
                errorMessage = problem;
            }
        }
    }
    m_finished = true;
    m_result = errorCode.isEmpty() ? value : QJsonValue();
    m_errorCode = errorCode;
    m_errorMessage = errorMessage;
    Q_EMIT completed();
}
