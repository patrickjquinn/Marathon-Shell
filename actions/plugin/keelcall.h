// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// One invocation of an action, entity lookup or entity search. The handler
// answers with reply(value) or fail(code, message), at once or later; the
// first answer wins. An unanswered call fails with "Timeout" after the
// action's timeout. Not creatable from QML.
#ifndef KEEL_ACTIONS_CALL_H
#define KEEL_ACTIONS_CALL_H

#include <QJsonObject>
#include <QJsonValue>
#include <QObject>
#include <QTimer>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

#include <functional>

class KeelCall : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("A KeelCall is handed to onInvoked, onResolve and onFind handlers")
    Q_PROPERTY(QString action READ action CONSTANT)
    Q_PROPERTY(QVariantMap arguments READ arguments CONSTANT)
    // The request was started by the person (not by a background agent).
    Q_PROPERTY(bool userInitiated READ userInitiated CONSTANT)
    Q_PROPERTY(bool finished READ isFinished NOTIFY completed)
    Q_PROPERTY(bool succeeded READ succeeded NOTIFY completed)
    Q_PROPERTY(QVariant result READ result NOTIFY completed)
    Q_PROPERTY(QString errorCode READ errorCode NOTIFY completed)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY completed)

public:
    // Error codes; on D-Bus they are org.shipwright.Keel.Actions.Error.<code>.
    static const QString UnknownAction;
    static const QString InvalidArguments;
    static const QString Failed;
    static const QString Timeout;
    static const QString NotAvailable;
    static const QString Cancelled;

    // `check` validates and normalises the handler's value; it returns an
    // error message (empty when the value is accepted) and may set the error
    // code (Failed by default).
    using Check = std::function<QString(QJsonValue &, QString &)>;

    KeelCall(QString action, QVariantMap arguments, bool userInitiated,
             QObject *parent = nullptr);

    Q_INVOKABLE void reply(const QVariant &value = QVariant());
    Q_INVOKABLE void fail(const QString &code, const QString &message = QString());
    // The answer as JSON (native actions).
    void replyJson(const QJsonValue &value);

    QString action() const { return m_action; }
    QVariantMap arguments() const { return m_arguments; }
    bool userInitiated() const { return m_userInitiated; }
    bool isFinished() const { return m_finished; }
    bool succeeded() const { return m_finished && m_errorCode.isEmpty(); }
    QVariant result() const { return m_result.toVariant(); }
    QJsonValue jsonResult() const { return m_result; }
    QString errorCode() const { return m_errorCode; }
    QString errorMessage() const { return m_errorMessage; }

    void setCheck(Check check) { m_check = std::move(check); }
    void startTimer(int milliseconds);
    // Completes with `value` when the handler has not answered by now (for
    // actions without a result).
    void replyIfPending(const QJsonValue &value);

    // QML values (QJSValue, QVariantMap, lists) as JSON.
    static QJsonValue toJson(const QVariant &value);

Q_SIGNALS:
    void completed();

private:
    void finish(const QJsonValue &result, const QString &code, const QString &message);

    QString m_action;
    QVariantMap m_arguments;
    bool m_userInitiated = false;
    bool m_finished = false;
    QJsonValue m_result;
    QString m_errorCode;
    QString m_errorMessage;
    Check m_check;
    QTimer m_timer;
};

#endif
