// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// See policyvalue.h.

#include "policyvalue.h"

#include "policystore_p.h"

namespace Sailfish {

namespace {

bool readOnly(const char *what)
{
    qCWarning(lcSailfishPolicy) << "PolicyValue::" << what
                                << ": policies are set by MDM applications; Keel only reads them";
    return false;
}

} // namespace

class PolicyValuePrivate
{
public:
    int type = PolicyValue::Unknown;
    QVariant value;
};

PolicyValue::PolicyValue(QObject *parent)
    : QObject(parent)
    , d(new PolicyValuePrivate)
{
    connect(PolicyStore::instance(), &PolicyStore::changed, this, &PolicyValue::update);
}

PolicyValue::~PolicyValue()
{
    delete d;
}

int PolicyValue::policyType() const
{
    return d->type;
}

void PolicyValue::setPolicyType(int type)
{
    if (PolicyStore::keyForType(type).isEmpty())
        type = Unknown;
    if (d->type == type)
        return;
    d->type = type;
    emit policyTypeChanged();
    emit keyChanged();
    update();
}

QString PolicyValue::key() const
{
    return PolicyStore::keyForType(d->type);
}

void PolicyValue::setKey(const QString &newKey)
{
    setPolicyType(PolicyStore::typeForKey(newKey));
}

QVariant PolicyValue::value() const
{
    return d->value;
}

void PolicyValue::update()
{
    const QVariant value = PolicyStore::instance()->value(key());
    if (value == d->value && value.isValid() == d->value.isValid())
        return;
    d->value = value;
    emit valueChanged();
}

QVariant PolicyValue::keyValue(const QString &key)
{
    return PolicyStore::instance()->value(key);
}

QVariant PolicyValue::keyValue(int type)
{
    return PolicyStore::instance()->value(PolicyStore::keyForType(type));
}

bool PolicyValue::setKeyValue(const QString & /*key*/, const QVariant & /*value*/)
{
    return readOnly("setKeyValue");
}

bool PolicyValue::setKeyValue(int /*type*/, const QVariant & /*value*/)
{
    return readOnly("setKeyValue");
}

bool PolicyValue::setValue(const QVariant & /*value*/)
{
    return readOnly("setValue");
}

bool PolicyValue::enforcePolicy(int /*type*/, bool /*value*/)
{
    return readOnly("enforcePolicy");
}

bool PolicyValue::enforcePolicy(const QString & /*key*/, bool /*value*/)
{
    return readOnly("enforcePolicy");
}

} // namespace Sailfish
