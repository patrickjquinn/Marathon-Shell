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

#ifndef PROFILEFIELD_H
#define PROFILEFIELD_H

#include <QString>
#include <QStringList>

class QDomDocument;
class QDomElement;

namespace Buteo {

class ProfileFieldPrivate;

/*! \brief This class represents a profile field.
 *
 * Profile field is a bunch of information about a setting whose value must
 * be defined as a separate key/value pair in some profile. The key name must
 * be same as the profile field name.
 * The class includes functions for accessing the name,
 * type, description and possible values of the setting. Only the name is a
 * mandatory field. The class also has a function for validating a given value
 * against the possible values defined by the field. A ProfileField can be
 * constructed from XML and exported to XML.
 */
class ProfileField
{
public:
    //! Field should be always visible in UI.
    static const QString VISIBLE_ALWAYS;

    //! Field should never be visible in UI.
    static const QString VISIBLE_NEVER;

    //! Field should be visible in UI if a value for the field has not
    // been pre-defined in the sub-profiles loaded by the main profile.
    static const QString VISIBLE_USER;

    //! Field type for boolean fields.
    static const QString TYPE_BOOLEAN;

    /*! \brief Constructs a ProfileField from XML.
     *
     * \param aRoot Root element of the field XML.
     */
    explicit ProfileField(const QDomElement &aRoot);

    /*! \brief Copy constructor.
     *
     * \param aSource Copy source.
     */
    ProfileField(const ProfileField &aSource);

    /*! \brief Destructor.
     */
    ~ProfileField();

    /*! \brief Gets the field name.
     *
     * \return Field name.
     */
    QString name() const;

    /*! \brief Get the field type.
     *
     * \return Field type.
     */
    QString type() const;

    /*! \brief Gets the field default value.
     *
     * \return Field default value.
     */
    QString defaultValue() const;

    /*! \brief Gets the allowed values for the field.
     *
     * \return List of valid values.
     */
    QStringList options() const;

    /*! \brief Gets the field label.
     *
     * The label can be for example displayed in the UI that asks for the field
     * value.
     * \return Field label.
     */
    QString label() const;

    /*! \brief Checks if the given value is in the list of allowed values.
     *
     * If allowed values have not been defined, any value is accepted.
     * \param aValue The value to validate.
     * \return Is the given value in the list of allowed values (options).
     */
    bool validate(const QString &aValue) const;

    /*! \brief Exports the field to XML.
     *
     * \param aDoc Parent document for the created XML elements. The created
     *  elements are not inserted to the document by this function, but the
     *  document is still required for creating the elements.
     * \return The root element of the created XML node tree.
     */
    QDomElement toXml(QDomDocument &aDoc) const;

    /*! \brief Gets the visibility of the field.
     *
     * \return String defining the visibility. See VISIBLE_ constants for
     *  predefined values.
     */
    QString visible() const;

    /*! \brief Checks if the field is read only.
     *
     * UI should not allow modifying the value of a read only field.
     * \return True if readonly.
     */
    bool isReadOnly() const;

private:
    ProfileField &operator=(const ProfileField &aRhs);
    ProfileFieldPrivate *d_ptr;
};

}

#endif // PROFILEFIELD_H
