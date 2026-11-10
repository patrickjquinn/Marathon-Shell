// SPDX-FileCopyrightText: 2010 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-License-Identifier: LGPL-2.1-only
/*
 * This file is part of buteo-syncfw package
 *
 * Copyright (C) 2010 Nokia Corporation and/or its subsidiary(-ies).
 *
 * Contact: Sateesh Kavuri <sateesh.kavuri@nokia.com>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA
 *
 */

#include "ProfileField.h"
#include "ProfileEngineDefs.h"

#include <QDomDocument>

namespace Buteo {

//! ProfileField Visbility Const string for always
const QString ProfileField::VISIBLE_ALWAYS = "always";

//! ProfileField Visbility Const string for never
const QString ProfileField::VISIBLE_NEVER = "never";

//! ProfileField Visbility Const string for user
const QString ProfileField::VISIBLE_USER = "user";

//! ProfileField Visbility Const string for boolean
const QString ProfileField::TYPE_BOOLEAN = "boolean";

// Private implementation class for ProfileField.
class ProfileFieldPrivate
{
public:
    //! \brief Constructor
    ProfileFieldPrivate();

    //! \brief Copy Constructor
    ProfileFieldPrivate(const ProfileFieldPrivate &aSource);

    //! \brief Name of the ProfileField
    QString iName;

    //! \brief Type of the ProfileField
    QString iType;

    //! \brief DefaultValue of the ProfileField
    QString iDefaultValue;

    //! \brief List of Options of the ProfileField
    QStringList iOptions;

    //! \brief Label of the ProfileField
    QString iLabel;

    //! \brief Visibility of the ProfileField
    QString iVisible;

    //! \brief Write Access Specifier of the ProfileField
    bool iReadOnly;
};

}

using namespace Buteo;

ProfileFieldPrivate::ProfileFieldPrivate()
    : iReadOnly(false)
{
}

ProfileFieldPrivate::ProfileFieldPrivate(const ProfileFieldPrivate &aSource)
    : iName(aSource.iName)
    , iType(aSource.iType)
    , iDefaultValue(aSource.iDefaultValue)
    , iOptions(aSource.iOptions)
    , iLabel(aSource.iLabel)
    , iVisible(aSource.iVisible)
    , iReadOnly(aSource.iReadOnly)
{
}

ProfileField::ProfileField(const QDomElement &aRoot)
    : d_ptr(new ProfileFieldPrivate())
{
    d_ptr->iName = aRoot.attribute(ATTR_NAME);
    d_ptr->iType = aRoot.attribute(ATTR_TYPE);
    d_ptr->iDefaultValue = aRoot.attribute(ATTR_DEFAULT);
    d_ptr->iLabel = aRoot.attribute(ATTR_LABEL);
    d_ptr->iVisible = aRoot.attribute(ATTR_VISIBLE);
    d_ptr->iReadOnly = (aRoot.attribute(ATTR_READONLY).compare(BOOLEAN_TRUE, Qt::CaseInsensitive) == 0);

    // Parse options.
    QDomElement option = aRoot.firstChildElement(TAG_OPTION);
    for (; !option.isNull(); option = option.nextSiblingElement(TAG_OPTION)) {
        QString optionStr = option.text();
        if (!optionStr.isEmpty()) {
            d_ptr->iOptions.append(optionStr);
        } else {
            // Empty value.
        }
    }

    // Options for boolean type are inserted automatically.
    if (d_ptr->iOptions.empty()) {
        if (d_ptr->iType == TYPE_BOOLEAN) {
            d_ptr->iOptions.append(BOOLEAN_TRUE);
            d_ptr->iOptions.append(BOOLEAN_FALSE);
        }
    }
}

ProfileField::ProfileField(const ProfileField &aSource)
    : d_ptr(new ProfileFieldPrivate(*aSource.d_ptr))
{
}

ProfileField::~ProfileField()
{
    delete d_ptr;
    d_ptr = nullptr;
}

QString ProfileField::name() const
{
    return d_ptr->iName;
}

QString ProfileField::type() const
{
    return d_ptr->iType;
}

QString ProfileField::defaultValue() const
{
    return d_ptr->iDefaultValue;
}

QStringList ProfileField::options() const
{
    return d_ptr->iOptions;
}

QString ProfileField::label() const
{
    return d_ptr->iLabel;
}

bool ProfileField::validate(const QString &aValue) const
{
    // Value is valid if it exists in the list of options,
    // or if options have not been defined.
    return (!aValue.isEmpty() && (d_ptr->iOptions.contains(aValue) || d_ptr->iOptions.empty()));
}

QDomElement ProfileField::toXml(QDomDocument &aDoc) const
{
    QDomElement root = aDoc.createElement(TAG_FIELD);
    root.setAttribute(ATTR_NAME, d_ptr->iName);
    root.setAttribute(ATTR_TYPE, d_ptr->iType);
    root.setAttribute(ATTR_DEFAULT, d_ptr->iDefaultValue);
    root.setAttribute(ATTR_LABEL, d_ptr->iLabel);
    if (!d_ptr->iVisible.isEmpty())
        root.setAttribute(ATTR_VISIBLE, d_ptr->iVisible);
    if (d_ptr->iReadOnly)
        root.setAttribute(ATTR_READONLY, BOOLEAN_TRUE);

    if (d_ptr->iType == TYPE_BOOLEAN) {
        // No need to specify true/false options, field parser will add
        // them automatically.
    } else if (!d_ptr->iOptions.isEmpty()) {
        foreach (QString optionStr, d_ptr->iOptions) {
            QDomElement e = aDoc.createElement(TAG_OPTION);
            QDomText t = aDoc.createTextNode(optionStr);
            e.appendChild(t);
            root.appendChild(e);
        }
    }

    return root;
}

QString ProfileField::visible() const
{
    if (d_ptr->iVisible.isEmpty()) {
        return VISIBLE_USER;
    } else {
        return d_ptr->iVisible;
    }
}

bool ProfileField::isReadOnly() const
{
    return d_ptr->iReadOnly;
}
