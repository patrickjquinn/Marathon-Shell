// SPDX-FileCopyrightText: 2012-2015 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2012-2015 Jolla Ltd.
 * Contact: <robin.burchell@jollamobile.com>
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

#include "configurationvalue.h"

#include <MDConfItem>
#include <QJSValue>

#include <QDebug>

/*!
    \qmltype ConfigurationValue
    \inqmlmodule Nemo.Configuration
    \brief Provides access to a single configuration value

    ConfigurationValue provides access to a single DConf key. The DConf key value is accessible via
    the \l value property.

    \section2 Type conversion

    Values are automatically converted between QML/JS and DConf values as needed.

    \table
        \header
            \li QML/JS type
            \li DConf type
            \li Notes
        \row
            \li undefined
            \li
            \li An undefined value denotes an unset DConf key.
        \row
            \li double
            \li double
            \li
        \row
            \li int
            \li integer
            \li
        \row
            \li bool
            \li boolean
            \li
        \row
            \li string
            \li string
            \li DConf strings are always UTF-8 encoded.
        \row
            \li list<string>
            \li list of strings
            \li
        \row
            \li list<variant>
            \li list of variants
            \li DConf requires that all elements of a list have the same type. If the variant type
                is \c string a list<string> will be returned instead of list<variant>.
        \row
    \endtable

    Unsupported types, which cannot be converted to a supported type, are ignored.
*/

ConfigurationValue::ConfigurationValue(QObject *parent)
    : QObject(parent)
    , mItem(0)
{
}

/*!
    \qmlproperty string ConfigurationValue::key

    This property holds the key that this ConfigurationValue represents.
*/
QString ConfigurationValue::key() const
{
    if (!mItem)
        return QString();

    return mItem->key();
}

void ConfigurationValue::setKey(const QString &newKey)
{
    if (newKey == key())
        return;

    // don't emit valueChanged unless absolutely necessary
    QVariant oldValue = value();

    delete mItem;
    if (newKey.isEmpty()) {
        mItem = 0;
    } else {
        mItem = new MDConfItem(newKey, this);
        connect(mItem, SIGNAL(valueChanged()), this, SIGNAL(valueChanged()));
    }

    emit keyChanged();
    if (oldValue != value())
        emit valueChanged();
}

/*!
    \qmlproperty variant ConfigurationValue::value

    This property holds the configuration value represented by \l key.
*/
QVariant ConfigurationValue::value() const
{
    if (!mItem)
        return mDefaultValue;

    return mItem->value(mDefaultValue);
}

void ConfigurationValue::setValue(const QVariant &value)
{
    if (!mItem)
        return;

    if (value.userType() == QMetaType::type("QJSValue")) {
        // Qt 5.6 likes to pass a QJSValue
        QJSValue jsValue = qvariant_cast<QJSValue>(value);
        mItem->set(jsValue.toVariant());
    } else {
        mItem->set(value); // TODO: setValue once we change MDConfItem API
    }
    // MDConfItem will emit valueChanged for us
}

/*!
    \qmlproperty variant ConfigurationValue::defaultValue

    This property holds the default value of the \l value property if \l key does not exist.
*/
QVariant ConfigurationValue::defaultValue() const
{
    return mDefaultValue;
}

void ConfigurationValue::setDefaultValue(const QVariant &value)
{
    if (mDefaultValue == value) {
        return;
    }

    QVariant oldValue = this->value();
    mDefaultValue = value;
    emit defaultValueChanged();

    // if changing the default changed the value, emit valueChanged
    if (this->value() != oldValue)
        emit valueChanged();
}

/*!
    \qmlmethod void ConfigurationValue::sync()

    Forces the value to be synchronized with the backing store.
*/
void ConfigurationValue::sync()
{
    if (mItem) {
        mItem->sync();
    }
}
