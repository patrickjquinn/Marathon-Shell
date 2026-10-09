// SPDX-FileCopyrightText: 2010 2011 Nokia Corporation and/or its subsidiary(-ies)
// SPDX-FileCopyrightText: 2011 Intel Corp
// SPDX-FileCopyrightText: 2012 - 2014 Jolla Ltd
// SPDX-FileCopyrightText: 2020 - 2021 Open Mobile Platfrom LLC
// SPDX-License-Identifier: LGPL-2.1-only

/***************************************************************************
** This file was derived from the MDesktopEntry implementation in the
** libmeegotouch library.
**
** Copyright (C) 2010, 2011 Nokia Corporation and/or its subsidiary(-ies).
** Copyright (C) 2011 Intel Corp.
** Copyright (C) 2012 - 2014 Jolla Ltd.
** Copyright (C) 2020 - 2021 Open Mobile Platfrom LLC.
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file LICENSE.LGPL included in the packaging
** of this file.
**
****************************************************************************/

#ifndef MDESKTOPENTRY_P_H
#define MDESKTOPENTRY_P_H

#include <glib.h>

class MDesktopEntry;
class QTranslator;

class GKeyFileWrapper
{
public:
    GKeyFileWrapper();
    ~GKeyFileWrapper();

    bool load(QIODevice &device);

    QString startGroup() const;
    QStringList sections() const;
    QStringList keys(const QString &section) const;
    QString stringValue(const QString &section, const QString &key) const;
    QString localizedValue(const QString &section, const QString &key) const;
    bool booleanValue(const QString &section, const QString &key) const;
    QStringList stringList(const QString &section, const QString &key) const;
    bool contains(const QString &section, const QString &key) const;
    bool hasSection(const QString &section) const;

private:
    GKeyFile *m_key_file;
};


/*!
 * MDesktopEntryPrivate is the private class for MDesktopEntry.
 */
class MDesktopEntryPrivate
{
    Q_DECLARE_PUBLIC(MDesktopEntry)

public:
    /*!
     * Constructs a new MDesktopEntryPrivate class.
     *
     * \param fileName the name of the file to read the desktop entry from
     */
    MDesktopEntryPrivate(const QString &fileName);

    /*!
     * Destroys the MDesktopEntryPrivate.
     */
    virtual ~MDesktopEntryPrivate();

    //! The name of the file where the information for this desktop entry was read from.
    QString sourceFileName;

    //! Wrapper around GKeyFile that stores the parsed desktop entry.
    GKeyFileWrapper keyFile;

    /*!
     * Returns the boolean value of a key.
     *
     * \param section the section of the string list value (e.g. "Desktop Entry")
     * \param key the key to return the boolean value for
     * \return true if the value of specified key is set to "true" and false otherwise.
     */
    bool boolValue(const QString &section, const QString &key) const;

    /*!
     * Returns the string list value of a key. The list will be populated
     * with semicolon separated parts of the key value.
     *
     * \param section the section of the string list value (e.g. "Desktop Entry")
     * \param key the key to return the string list value for
     * \return a string list containing the semicolon separated parts of the key value
     */
    QStringList stringListValue(const QString &section, const QString &key) const;

    //! Flag to indicate whether the desktop entry is valid during parsing
    bool valid;

    //! Cached translated name
    mutable QString translatedName;

    /*!
     * Loads QTranslator from X-Amber/MeeGo-Translation-Catalog
     * \return A translator for specified catalog, or null
     */
    QTranslator *loadTranslator() const;

    //! Translator cache, limits how long it can live
    mutable QScopedPointer<QTimer> translatorCacheTimer;

    //! Cached translator
    mutable QScopedPointer<QTranslator> cachedTranslator;

    //! Translator is unavailable, don't try to load again
    mutable bool translatorUnavailable;

protected:
    /*
     * \brief this q_ptr starts the inheritance hierarchy
     */
    MDesktopEntry *q_ptr;
};

#endif
