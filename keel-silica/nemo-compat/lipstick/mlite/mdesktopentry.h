// SPDX-FileCopyrightText: 2010 2011 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-FileCopyrightText: 2011 Intel Corp
// SPDX-FileCopyrightText: 2012 2013 Jolla Ltd
// SPDX-FileCopyrightText: 2020 - 2021 Open Mobile Platform LLC
// SPDX-License-Identifier: LGPL-2.1-only

/***************************************************************************
** This file was derived from the MDesktopEntry implementation in the
** libmeegotouch library.
**
** Copyright (C) 2010, 2011 Nokia Corporation and/or its subsidiary(-ies).
** Copyright (C) 2011 Intel Corp.
** Copyright (C) 2012, 2013 Jolla Ltd.
** Copyright (C) 2020 - 2021 Open Mobile Platform LLC.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file LICENSE.LGPL included in the packaging
** of this file.
**
****************************************************************************/

#ifndef MDESKTOPENTRY_H_
#define MDESKTOPENTRY_H_

#include <mlite-global.h>
#include <QMap>
#include <QIODevice>

class MDesktopEntryPrivate;

/*!
 * MDesktopEntry provides the means to read freedesktop.org desktop entry
 * files.
 *
 * MDesktopEntry object reads desktop file data from the desktop file given as
 * a construction parameter.
 *
 * The isValid() method determines whether the input desktop file conforms to the
 * standard defined by freedesktop.org.
 *
 * For more information see:
 * http://standards.freedesktop.org/desktop-entry-spec/latest/index.html
 *
 */
class MLITESHARED_EXPORT MDesktopEntry
{
public:
    /*!
     * Reads input desktop file and constructs new MDesktopEntry object
     * of it.
     *
     * \param fileName the name of the file to read the desktop entry from
     */
    MDesktopEntry(const QString &fileName);

    /*!
     * Destroys the MDesktopEntry.
     */
    virtual ~MDesktopEntry();

    /*!
     * Returns the name of the file where the information for this
     * desktop entry was read from.
     * \return The desktop entry file name.
     */
    QString fileName() const;

    /*!
     * Indicates whether desktop entry information adheres to the requirements
     * set in the freedesktop.org standard.
     * Freedesktop.org defines required keys that one has to fill to have a
     * valid desktop file. This checks whether those keys are defined.
     */
    virtual bool isValid() const;

    /*!
     * Calculates a hash value based on the required type and name keys
     * of the desktop definition.
     */
    virtual uint hash() const;

    /*!
     * Returns the value of Type key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString type() const;

    /*!
     * Returns the value of Version key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString version() const;

    /*!
     * Returns the localized value of Name key or an empty string if it is
     * not defined in the input desktop entry file. The localization
     * requires either a X-MeeGo-Logical-Id attribute with optional
     * X-MeeGo-Translation-Catalog attribute or freedesktop.org standard
     * style localized name attribute. Returns the name as unlocalized
     * if the logical id cannot be found from the catalog. \see nameUnlocalized
     */
    QString name() const;

    /*!
     * Returns the unlocalized value of Name key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString nameUnlocalized() const;

    /*!
     * Returns the value of GenericName key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString genericName() const;

    /*!
     * Indicates whether value of NoDisplay key is true or false.
     * Returns false if NoDisplay key is undefined.
     */
    bool noDisplay() const;

    /*!
     * Returns the value of Comment key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString comment() const;

    /*!
     * Returns the value of Icon key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString icon() const;

    /*!
     * Indicates whether value of Hidden key is true or false.
     * Returns false if Hidden key is undefined.
     */
    bool hidden() const;

    /*!
     * Returns the value of OnlyShowIn key or an empty string list if it is
     * not defined in the input desktop entry file.
     */
    QStringList onlyShowIn() const;

    /*!
     * Returns the value of NotShowIn key or an empty string list if it is
     * not defined in the input desktop entry file.
     */
    QStringList notShowIn() const;

    /*!
     * Returns the value of TryExec key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString tryExec() const;

    /*!
     * Returns the value of Exec key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString exec() const;

    /*!
     * Returns the value of Path key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString path() const;

    /*!
     * Indicates whether value of Terminal key is true or false.
     * Returns false if Terminal key is undefined.
     */
    bool terminal() const;

    /*!
     * Returns the value of MimeTypes key or an empty string list if it is
     * not defined in the input desktop entry file.
     */
    QStringList mimeType() const;

    /*!
     * Returns the value of Categories key or an empty string list if it is
     * not defined in the input desktop entry file.
     */
    QStringList categories() const;

    /*!
     * Indicates whether value of StartupNotify key is true or false.
     * Returns false if StartupNotify key is undefined.
     */
    bool startupNotify() const;

    /*!
     * Returns the value of StartupWMClass key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString startupWMClass() const;

    /*!
     * Returns the value of URL key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString url() const;

    /*!
     * Returns the value of X-Osso-Service key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString xMaemoService() const;

    /*!
     * Returns the value of the key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString value(const QString &key) const;

    /*!
     * Returns the value of the group-key stored as "group/key"
     * key or an empty string if it is not defined in the input desktop entry file.
     */
    QString value(const QString &group, const QString &key) const;

    /*!
     * Returns the value of the key or an empty string list if it is
     * not defined in the input desktop entry file.
     */
    QStringList stringListValue(const QString &key) const;

    /*!
     * Returns the value of the group-key stored as "group/key"
     * key or an empty string list if it is not defined in the input desktop entry file.
     */
    QStringList stringListValue(const QString &group, const QString &key) const;

    /*!
     * Indicates whether map contains key or not.
     * Returns false if key is not present.
     */
    bool contains(const QString &key) const;

    /*!
     * Indicates whether map contains group/key or not.
     * Returns false if key is not present.
     */
    bool contains(const QString &group, const QString &key) const;

    /*!
     * Parses a desktop entry file.
     *
     * \param device the QIODevice to read the desktop file from
     * \param map the QMap to store key-value pairs to
     * \return true if desktop file can be parsed
     */
    static bool readDesktopFile(QIODevice &device, QMap<QString, QString> &desktopEntriesMap);

    /*!
     * Returns whether the application is sandboxed.
     */
    bool isSandboxed() const;

    /*!
     * Returns the localized value of the key or an empty string if it is
     * not defined in the input desktop entry file.
     */
    QString localizedValue(const QString &key) const;

    /*!
     * Returns the localized value of the group-key stored as "group/key"
     * key or an empty string if it is not defined in the input desktop entry file.
     */
    QString localizedValue(const QString &group, const QString &key) const;

protected:
    /*! \internal */
    //! Pointer to the private class
    MDesktopEntryPrivate *const d_ptr;
    MDesktopEntry(MDesktopEntryPrivate &dd);
    /*! \internal_end */

private:
    Q_DISABLE_COPY(MDesktopEntry)
    Q_DECLARE_PRIVATE(MDesktopEntry)
};

#endif /* MDESKTOPENTRY_H_ */
