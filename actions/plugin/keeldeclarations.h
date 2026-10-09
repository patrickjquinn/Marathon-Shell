// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Keel.Actions 1.0: the declaration types (ADR-0018, docs/specs/pilot.md 9).
//
//   KeelParam     a typed value: an action parameter, a result field or an
//                 entity property
//   KeelResult    an action's result (a KeelParam whose type defaults to
//                 "none")
//   KeelAction    a typed action; handlers answer through a KeelCall
//   KeelEntity    a type of object the app owns, addressed as
//                 keel://<app-id>/<type>/<id>
//   KeelContext   what the current page shows, for user-initiated requests
//   KeelShortcut  a named sequence of actions, served as an MCP prompt
//
// Declarations are read statically by the generator (keel actions,
// keel/actions/codegen): every property that ends up in actions.json must be
// a literal. At run time the same objects register with KeelActionRegistry,
// which dispatches calls to them.
#ifndef KEEL_ACTIONS_DECLARATIONS_H
#define KEEL_ACTIONS_DECLARATIONS_H

#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QQmlListProperty>
#include <QQmlParserStatus>
#include <QStringList>
#include <QVariant>

#include <functional>
#include <QtQml/qqmlregistration.h>

class KeelCall;

class KeelParam : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString name MEMBER m_name NOTIFY changed)
    // string, integer, number, boolean, entity, array, object (and, for a
    // KeelResult, none).
    Q_PROPERTY(QString type MEMBER m_type NOTIFY changed)
    Q_PROPERTY(QString title MEMBER m_title NOTIFY changed)
    Q_PROPERTY(QString description MEMBER m_description NOTIFY changed)
    Q_PROPERTY(bool required MEMBER m_required NOTIFY changed)
    // -1: unset (the schema then gets Keel's default bound).
    Q_PROPERTY(int maxLength MEMBER m_maxLength NOTIFY changed)
    Q_PROPERTY(int minLength MEMBER m_minLength NOTIFY changed)
    Q_PROPERTY(int maxItems MEMBER m_maxItems NOTIFY changed)
    Q_PROPERTY(QVariant minimum MEMBER m_minimum NOTIFY changed)
    Q_PROPERTY(QVariant maximum MEMBER m_maximum NOTIFY changed)
    Q_PROPERTY(QString pattern MEMBER m_pattern NOTIFY changed)
    Q_PROPERTY(QString format MEMBER m_format NOTIFY changed)
    // Allowed values (JSON Schema enum).
    Q_PROPERTY(QVariantList values MEMBER m_values NOTIFY changed)
    // For type "entity" (or itemType "entity"): "<type>" of this app, or
    // "<app-id>/<type>" of another app.
    Q_PROPERTY(QString entity MEMBER m_entity NOTIFY changed)
    // For type "array": the item type (string by default).
    Q_PROPERTY(QString itemType MEMBER m_itemType NOTIFY changed)
    Q_PROPERTY(QVariant defaultValue MEMBER m_defaultValue NOTIFY changed)
    // For type "object" (or itemType "object"): string fields by name, and
    // typed fields.
    Q_PROPERTY(QStringList fields MEMBER m_fields NOTIFY changed)
    Q_PROPERTY(QQmlListProperty<KeelParam> properties READ properties)
    // Entity properties: may go to a model / may enter Pilot's local index.
    Q_PROPERTY(bool summarisable MEMBER m_summarisable NOTIFY changed)
    Q_PROPERTY(bool indexable MEMBER m_indexable NOTIFY changed)
    Q_CLASSINFO("DefaultProperty", "properties")

public:
    explicit KeelParam(QObject *parent = nullptr);

    QQmlListProperty<KeelParam> properties();
    const QList<KeelParam *> &propertyList() const { return m_properties; }

    // JSON Schema for this value (Keel's bounded subset). Entity references
    // become $refs into `defs`.
    QJsonObject schema(const QString &appId, QJsonObject &defs) const;

    QString name() const { return m_name; }
    QString type() const { return m_type; }
    bool isRequired() const { return m_required; }
    bool summarisable() const { return m_summarisable; }

Q_SIGNALS:
    void changed();

protected:
    QString m_type = QStringLiteral("string");

private:
    QJsonObject objectSchema(const QString &appId, QJsonObject &defs) const;
    QJsonObject scalarSchema(const QString &type, const QString &appId, QJsonObject &defs) const;

    QString m_name;
    QString m_title;
    QString m_description;
    bool m_required = false;
    int m_maxLength = -1;
    int m_minLength = -1;
    int m_maxItems = -1;
    QVariant m_minimum;
    QVariant m_maximum;
    QString m_pattern;
    QString m_format;
    QVariantList m_values;
    QString m_entity;
    QString m_itemType;
    QVariant m_defaultValue;
    QStringList m_fields;
    QList<KeelParam *> m_properties;
    bool m_summarisable = false;
    bool m_indexable = false;
};

class KeelResult : public KeelParam
{
    Q_OBJECT
    QML_ELEMENT

public:
    explicit KeelResult(QObject *parent = nullptr);
};

class KeelAction : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(QString name MEMBER m_name NOTIFY changed)
    Q_PROPERTY(QString title MEMBER m_title NOTIFY changed)
    Q_PROPERTY(QString description MEMBER m_description NOTIFY changed)
    Q_PROPERTY(bool readOnly MEMBER m_readOnly NOTIFY changed)
    Q_PROPERTY(bool destructive MEMBER m_destructive NOTIFY changed)
    Q_PROPERTY(bool idempotent MEMBER m_idempotent NOTIFY changed)
    Q_PROPERTY(bool openWorld MEMBER m_openWorld NOTIFY changed)
    // Always ask the person first, even if not destructive.
    Q_PROPERTY(bool confirm MEMBER m_confirm NOTIFY changed)
    // The result is for the person only, never for a model.
    Q_PROPERTY(bool sensitive MEMBER m_sensitive NOTIFY changed)
    // The result carries content the app does not vouch for (web pages,
    // others' messages): data for a model, never instructions.
    Q_PROPERTY(bool untrusted MEMBER m_untrusted NOTIFY changed)
    // For Reef review: why an action that sounds destructive is not.
    Q_PROPERTY(QString notDestructiveBecause MEMBER m_notDestructiveBecause NOTIFY changed)
    // Milliseconds an unanswered call waits before it fails with Timeout.
    Q_PROPERTY(int timeout MEMBER m_timeout NOTIFY changed)
    // Run time only: a disabled action answers NotAvailable.
    Q_PROPERTY(bool enabled MEMBER m_enabled NOTIFY changed)
    Q_PROPERTY(QQmlListProperty<KeelParam> parameters READ parameters)
    Q_PROPERTY(KeelResult *returns MEMBER m_returns NOTIFY changed)

public:
    explicit KeelAction(QObject *parent = nullptr);
    ~KeelAction() override;

    void classBegin() override {}
    void componentComplete() override;

    QQmlListProperty<KeelParam> parameters();

    // Invokes the action in the app, as a D-Bus call would: validates
    // `arguments`, emits invoked() and returns the call (owned by the
    // caller's JavaScript engine when called from QML).
    Q_INVOKABLE KeelCall *invoke(const QVariantMap &arguments);

    // The MCP tool for this action (name without the app prefix resolved by
    // the registry).
    QJsonObject tool(const QString &appId) const;

    QString name() const { return m_name; }
    bool enabled() const { return m_enabled; }
    int timeout() const { return m_timeout; }
    bool hasResult() const;

    // Dispatches an already created call (the registry's path).
    void dispatch(KeelCall *call);

Q_SIGNALS:
    void changed();
    // The handler answers with call.reply(value) or call.fail(code, message).
    void invoked(const QVariantMap &args, KeelCall *call);

private:
    QString m_name;
    QString m_title;
    QString m_description;
    bool m_readOnly = false;
    bool m_destructive = false;
    bool m_idempotent = false;
    bool m_openWorld = false;
    bool m_confirm = false;
    bool m_sensitive = false;
    bool m_untrusted = false;
    QString m_notDestructiveBecause;
    int m_timeout = 25000;
    bool m_enabled = true;
    QList<KeelParam *> m_parameters;
    KeelResult *m_returns = nullptr;
    bool m_registered = false;
};

class KeelEntity : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(QString type MEMBER m_type NOTIFY changed)
    Q_PROPERTY(QString title MEMBER m_title NOTIFY changed)
    Q_PROPERTY(QString description MEMBER m_description NOTIFY changed)
    Q_PROPERTY(QQmlListProperty<KeelParam> properties READ properties)
    Q_CLASSINFO("DefaultProperty", "properties")

public:
    explicit KeelEntity(QObject *parent = nullptr);
    ~KeelEntity() override;

    void classBegin() override {}
    void componentComplete() override;

    QQmlListProperty<KeelParam> properties();

    // keel://<app-id>/<type>/<id>
    Q_INVOKABLE QString uri(const QString &id) const;
    // Resolve one entity / search entities, as GetEntity / FindEntities do.
    Q_INVOKABLE KeelCall *lookup(const QString &id);
    Q_INVOKABLE KeelCall *search(const QString &query, int limit = 10);

    QString type() const { return m_type; }
    // The entity's object schema (full: every property), and the manifest
    // entry (with the find tool).
    QJsonObject schema(const QString &appId, QJsonObject &defs) const;
    QJsonObject summarySchema(const QString &appId, QJsonObject &defs) const;
    QJsonObject manifestEntry(const QString &appId) const;
    QJsonObject findTool(const QString &appId) const;

    void dispatchLookup(KeelCall *call, const QString &id);
    void dispatchSearch(KeelCall *call, const QString &query, int limit);
    // The check of a find answer: summaries only, uri added, at most `limit`.
    static std::function<QString(QJsonValue &, QString &)> findCheck(const QJsonObject &output,
                                                                      const QString &prefix, int limit);

Q_SIGNALS:
    void changed();
    void resolve(const QString &id, KeelCall *call);
    void find(const QString &query, int limit, KeelCall *call);

private:
    QJsonObject entitySchema(const QString &appId, QJsonObject &defs, bool summaryOnly) const;

    QString m_type;
    QString m_title;
    QString m_description;
    QList<KeelParam *> m_properties;
    bool m_registered = false;
};

class KeelContext : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)
    // What the page is for ("reading a message", "editing a note").
    Q_PROPERTY(QString purpose MEMBER m_purpose NOTIFY changed)
    // The selected entity, as a keel:// URI.
    Q_PROPERTY(QString entity MEMBER m_entity NOTIFY changed)
    // Visible text the app chooses to expose (at most 4,000 characters are
    // returned).
    Q_PROPERTY(QString text MEMBER m_text NOTIFY changed)
    // True while this page is the current one (bind to the page status).
    Q_PROPERTY(bool active MEMBER m_active NOTIFY activeChanged)

public:
    explicit KeelContext(QObject *parent = nullptr);
    ~KeelContext() override;

    void classBegin() override {}
    void componentComplete() override;

    bool isActive() const { return m_active; }
    QJsonObject snapshot(const QString &appId) const;

Q_SIGNALS:
    void changed();
    void activeChanged();

private:
    QString m_purpose;
    QString m_entity;
    QString m_text;
    bool m_active = false;
    bool m_registered = false;
};

class KeelShortcut : public QObject, public QQmlParserStatus
{
    Q_OBJECT
    QML_ELEMENT
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(QString name MEMBER m_name NOTIFY changed)
    Q_PROPERTY(QString title MEMBER m_title NOTIFY changed)
    Q_PROPERTY(QString description MEMBER m_description NOTIFY changed)
    Q_PROPERTY(QQmlListProperty<KeelParam> arguments READ arguments)
    // [{ action: "notes.create", arguments: { title: "{{title}}" } }, ...]
    Q_PROPERTY(QVariantList steps MEMBER m_steps NOTIFY changed)

public:
    explicit KeelShortcut(QObject *parent = nullptr);
    ~KeelShortcut() override;

    void classBegin() override {}
    void componentComplete() override;

    QQmlListProperty<KeelParam> arguments();
    QString name() const { return m_name; }
    QJsonObject prompt(const QString &appId) const;

Q_SIGNALS:
    void changed();

private:
    QString m_name;
    QString m_title;
    QString m_description;
    QList<KeelParam *> m_arguments;
    QVariantList m_steps;
    bool m_registered = false;
};

#endif
