// SPDX-FileCopyrightText: 2014 Jolla Mobile
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2014 Jolla Mobile <andrew.den.exter@jollamobile.com>
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

#include "configurationgroup.h"

/*!
    \qmltype ConfigurationGroup
    \inqmlmodule Nemo.Configuration
    \brief Provides access to a group of configuration values

    ConfigurationGroup provides access to a group of DConf key values relative to \l path.
    ConfigurationGroups can be nested in which case \l path is relative to the parent
    ConfigurationGroup.

    Key values can be accessed using the \l value() and \l setValue() methods. Value change
    notifications are via the \l valueChanged and \l valuesChanged signals.

    Properties declared on the ConfigurationGroup will be synchronized with DConf keys with the same
    name. Due to the requirement that QML properties start with a lower case letter this method does
    not allow accessing all possible key values. The \l value() and \l setValue() methods can be
    used in these cases.
*/

/*!
    \qmlproperty bool ConfigurationGroup::synchronous

    This property holds whether synchronous access is used.

    Defaults to false.
*/

/*!
    \qmlproperty string ConfigurationGroup::path

    This property holds the path of the configuration group. If this ConfigurationGroup is nested
    within another ConfigurationGroup then \c path is relative to the \c path of the parent group.
*/

/*!
    \qmlproperty ConfigurationGroup ConfigurationGroup::scope

    This property holds the parent scope of the configuration group. The \l path property is
    relative to the \c path of the parent scope.

    This property is automatically set when creating nested ConfigurationGroups.
*/

/*!
    \qmlmethod variant ConfigurationGroup::value(string key, variant defaultValue, int typeHint)

    Returns the value of \a key as a variant. If \a key does not exist \a defaultValue will be
    returned. If specified, the key value will be converted to the meta type id \a typeHint.
*/

/*!
    \qmlmethod void ConfigurationGroup::setValue(string key, variant value)

    Sets the value of \a key to \a value.
*/

/*!
    \qmlmethod void ConfigurationGroup::sync()

    Forces any pending writes to be synchronized with the backing store.
*/

/*!
    \qmlmethod void ConfigurationGroup::clear()

    Clears all values for properties in this configuration group.
*/

/*!
    \qmlsignal ConfigurationGroup::valueChanged(key)

    This signal is emitted when the value of \a key changes.
*/

/*!
    \qmlsignal ConfigurationGroup::valuesChanged()

    This signal is emitted when unknown properties of this configuration group change.
*/

ConfigurationGroup::ConfigurationGroup(QObject *parent)
    : MDConfGroup(parent, BindProperties)
{
}

ConfigurationGroup::~ConfigurationGroup()
{
}

void ConfigurationGroup::classBegin()
{
}

void ConfigurationGroup::componentComplete()
{
    resolveMetaObject(staticMetaObject.propertyCount());
}

QQmlListProperty<QObject> ConfigurationGroup::data()
{
    return QQmlListProperty<QObject>(this, 0, data_append, data_count, data_at, data_clear);
}

void ConfigurationGroup::data_append(QQmlListProperty<QObject> *property, QObject *value)
{
    ConfigurationGroup *settings = static_cast<ConfigurationGroup *>(property->object);
    settings->m_data.append(value);
    if (MDConfGroup *child = qobject_cast<MDConfGroup *>(value))
        child->setScope(settings);
}

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
QObject *ConfigurationGroup::data_at(QQmlListProperty<QObject> *property, int index)
#else
QObject *ConfigurationGroup::data_at(QQmlListProperty<QObject> *property, qsizetype index)
#endif
{
    return static_cast<ConfigurationGroup *>(property->object)->m_data.at(index);
}

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
int ConfigurationGroup::data_count(QQmlListProperty<QObject> *property)
#else
qsizetype ConfigurationGroup::data_count(QQmlListProperty<QObject> *property)
#endif
{
    return static_cast<ConfigurationGroup *>(property->object)->m_data.count();
}

void ConfigurationGroup::data_clear(QQmlListProperty<QObject> *property)
{
    ConfigurationGroup *settings = static_cast<ConfigurationGroup *>(property->object);
    QList<QObject *> data = settings->m_data;
    settings->m_data.clear();

    foreach (QObject *object, data) {
        ConfigurationGroup *group = qobject_cast<ConfigurationGroup *>(object);
        if (group && group->scope() == settings) {
            group->setScope(0);
        }
    }
}
