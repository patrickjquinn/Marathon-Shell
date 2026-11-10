// SPDX-FileCopyrightText: 2014 Jolla Mobile
// SPDX-License-Identifier: LGPL-2.1-only
/***************************************************************************
** Copyright (C) 2014 Jolla Mobile <andrew.den.exter@jollamobile.com>
**
** This library is free software; you can redistribute it and/or
** modify it under the terms of the GNU Lesser General Public
** License version 2.1 as published by the Free Software Foundation
** and appearing in the file LICENSE.LGPL included in the packaging
** of this file.
**
****************************************************************************/

#ifndef MDCONFGROUP_H
#define MDCONFGROUP_H

#include <QObject>
#include <QVariant>

#include <mlite-global.h>

class MDConfGroupPrivate;

/*!
    \brief The MDConfGroup class provides access to a group of properties stored by DConf.

    An instance of MDConfGroup provides accessors for properties relative to
    its \l path() and \l scope().

    The \l value() and \l setValue() functions provide a means of reading and
    writing QVariant values for a relative key where the following types are
    supported:

    \list
    \li bool, int, double, and other basic numeric types.
    \li QString
    \li QByteArray
    \li QStringList
    \li QVariantList
    \li QVariantMap

    The following types are also supported if a type hint is provided to  \l value():

    \list
    \li QPoint
    \li QPointF
    \li QSize
    \li QSizeF
    \li QRect
    \li QRectF
    \endlist

    It is also possible to inherit from MDConfGroup and bind the properties
    of the derived type to values stored in DConf.  This provides a means to
    initialize properties with values read from DConf and update those
    properties automatically when they are changed remotely.  If they are
    changed locally then those changes will also be written back to DConf.

    To enable this feature pass the BindProperties option to the constructor
    and call the \l resolveMetaObject() function when the Qt meta-object is
    complete.  Normally this is would be in the constructor of the derived type
    but types with dynamic meta-objects should defer this call until they are
    constructed.
*/

class MLITESHARED_EXPORT MDConfGroup : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool synchronous READ isSynchronous WRITE setSynchronous NOTIFY synchronousChanged)
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(MDConfGroup *scope READ scope WRITE setScope NOTIFY scopeChanged)
public:

    /*!
        The BindOption enum identifies whether the MDConfGroup should bind
        QObject properties to corresponding keys in DConf.

        \value DontBindProperties MDConfGroup will not bind to properties of
        the derived type.
        \value BindProperties MDConfGroup will bind to properties of the
        derived type.  Note you must call resolveMetaObject to complete
        initialization of a MDConfGroup when using this option.
     */
    enum BindOption
    {
        DontBindProperties,
        BindProperties
    };

    /*!
        Constructs a MDConfGroup with the given \a parent.

        The \a option parameter indicates whether the MDConfGroup should
        attempt to bind properties of the derived type to corresponding keys
        in DConf.
    */
    explicit MDConfGroup(QObject *parent = 0, BindOption option = DontBindProperties);

    /*!
        Constructs a MDConfGroup with the given \a path and \a parent.

        The \a option parameter indicates whether the MDConfGroup should
        attempt to bind properties of the derived type to corresponding keys
        in DConf.
    */
    explicit MDConfGroup(const QString &path, QObject *parent = 0, BindOption option = DontBindProperties);
    ~MDConfGroup();

    /*!
        Returns whether writes and notifications use DConf's synchronous API.

        If true the synchronous API is used otherwise the fast API is used.
        By default the fast API is used.
    */

    bool isSynchronous() const;

    /*!
        Sets whether writes and notifications should use DConf's synchronous API.

        If \a synchronous is true the synchronous API is used otherwise the
        fast API is used.
    */
    void setSynchronous(bool synchronous);

    /*!
        Returns the path of the DConf directory this MDConfGroup corresponds to.
    */
    QString path() const;

    /*!
        Sets the DConf directory \a path for an MDConfGroup

        If the MDConfGroup has a valid scope the path can be relative, the
        absolute path will then be the concatenation of the scope's absolute
        path and this group's relative path.
     */
    void setPath(const QString &path);

    /*!
        Returns an MDConfGroup's parent scope.
    */
    MDConfGroup *scope() const;

    /*!
        Sets the MDConfGroup's parent \a scope.

        Scopes can be used to create hierarchies of configuration groups.
        If a child group has a relative path it will be resolved relative to
        its scope.
    */
    void setScope(MDConfGroup *group);

    /*!
        Reads the value for \a key from DConf.

        Keys can be absolute or relative. If they are relative they will be
        resolved relative to the group's absolute path.

        If no stored value exists for the key the \a defaultValue will be
        returned instead.

        The \a typeHint property allows a QVariant of the correct type to be
        constructed if the mapping to DConf storage type is ambiguous.  Types
        where this parameter is required include:

        \list
        \li QPoint
        \li QPointF
        \li QSize
        \li QSizeF
        \li QRect
        \li QRectF
        \endlist
    */
    Q_INVOKABLE QVariant value(
            const QString &key,
            const QVariant &defaultValue = QVariant(),
            int typeHint = QMetaType::UnknownType) const;

    /*!
        Writes a \a value for \a key to DConf.

        Keys can be absolute or relative. If they are relative they will be
        resolved relative to the group's absolute path.
    */
    Q_INVOKABLE void setValue(const QString &key, const QVariant &value);

public slots:
    /*!
        Syncs and pending writes to DConf.
    */
    void sync();

    /*!
        Clears all values for properties in this group.
    */
    void clear();

signals:
    void synchronousChanged();
    void pathChanged();
    void scopeChanged();
    /*!
        Signals that the value associated with \a key has changed.
    */
    void valueChanged(const QString &key);

    /*!
        Signals that multiple unknown properties of this group have changed.
    */
    void valuesChanged();

protected:
    /*!
        Completes the binding of property declarations in derived types.

        The \a propertyOffset parameter indicates the offset of the first
        property to bind in the meta-object.  If none is given all derived
        properties are bound.
     */
    void resolveMetaObject(int propertyOffset = -1);

private slots:
    void propertyChanged();

private:
    friend class MDConfGroupPrivate;
    QScopedPointer<MDConfGroupPrivate> priv;
};

#endif
