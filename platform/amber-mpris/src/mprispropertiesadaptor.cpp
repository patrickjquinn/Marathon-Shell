// SPDX-FileCopyrightText: 2015-2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 * Copyright (C) 2015-2023 Jolla Ltd.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

#include "mprisplayer_p.h"
#include "mprispropertiesadaptor_p.h"

using namespace Amber;

/*
 * Implementation of adaptor class MprisPropertiesAdaptor
 */

MprisPropertiesAdaptor::MprisPropertiesAdaptor(MprisPlayerPrivate *parent)
    : QDBusAbstractAdaptor(parent)
    , m_playerPrivate(parent)
    , m_propertiesLocked(false)
{
    setAutoRelaySignals(true);
}

MprisPropertiesAdaptor::~MprisPropertiesAdaptor()
{
}

void MprisPropertiesAdaptor::replyPropertyNotFoundError(const QString &interface_name, const QString &property_name)
{
    // The property was not found
    m_playerPrivate->sendErrorReply(QDBusError::UnknownProperty,
                                    QString::fromLatin1("Property %1%2%3 was not found in object %4")
                                    .arg(interface_name,
                                         QString::fromLatin1(interface_name.isEmpty() ? "" : "."),
                                         property_name, m_playerPrivate->message().path()));
}

void MprisPropertiesAdaptor::replyPropertyReadOnlyError(const QString &interface_name, const QString &property_name)
{
    // The property is read only
    m_playerPrivate->sendErrorReply(QDBusError::PropertyReadOnly,
                                    QString::fromLatin1("Property %1.%2 is read-only")
                                    .arg(interface_name, property_name));
}

void MprisPropertiesAdaptor::replyInternalError()
{
    // The property is read only
    m_playerPrivate->sendErrorReply(QDBusError::InternalError,
                                    QString::fromLatin1("Internal error"));
}

// Format: {DBus property name, MprisPlayer property name or MprisPlayerPrivate getter() method}
static const QMap<QString, QString> playerGetMap
{
    {"CanControl", "canControl"},
    {"CanGoNext", "canGoNext"},
    {"CanGoPrevious", "canGoPrevious"},
    {"CanPause", "canPause"},
    {"CanPlay", "canPlay"},
    {"CanSeek", "canSeek"},
    {"LoopStatus", "loopStatus()"},
    {"MaximumRate", "maximumRate"},
    {"Metadata", "metaData()"},
    {"MinimumRate", "minimumRate"},
    {"PlaybackStatus", "playbackStatus()"},
    {"Position", "position()"},
    {"Rate", "rate"},
    {"Shuffle", "shuffle"},
    {"Volume", "volume"},
};

static const QMap<QString, QString> serviceGetMap
{
    {"CanQuit", "canQuit()"},
    {"Fullscreen", "fullscreen()"},
    {"CanSetFullscreen", "canSetFullscreen()"},
    {"CanRaise", "canRaise()"},
    {"HasTrackList", "hasTrackList()"},
    {"Identity", "identity()"},
    {"DesktopEntry", "desktopEntry()"},
    {"SupportedUriSchemes", "supportedMimeTypes()"},
    {"SupportedMimeTypes", "supportedUriSchemes()"},
};

QDBusVariant MprisPropertiesAdaptor::Get(const QString &interface_name, const QString &property_name)
{
    QMap<QString, QString> getMap;
    QVariant result;

    if (interface_name == QLatin1String("org.mpris.MediaPlayer2.Player")) {
        getMap = playerGetMap;
    } else if (interface_name == QLatin1String("org.mpris.MediaPlayer2")) {
        getMap = serviceGetMap;
    }

    const bool masked = m_maskedProperties.contains(property_name);
    const QString &getter = masked ? QString() : getMap.value(property_name);
    if (!getter.isEmpty()) {
        result = get(getter);
    } else {
        replyPropertyNotFoundError(interface_name, property_name);
    }

    return QDBusVariant(result);
}

QVariant MprisPropertiesAdaptor::get(const QString &getter)
{
    QVariant result;

    // Start by checking MprisPlayerPrivate methods
    int pidx = m_playerPrivate->metaObject()->indexOfMethod(
                getter.toLocal8Bit().data());

    if (pidx != -1) {
        const QMetaMethod method = m_playerPrivate->metaObject()->method(pidx);
        Q_ASSERT(method.parameterCount() == 0);

        QMetaType returnType(method.returnType());
        void * returnValue = returnType.create();
        bool success = method.invoke(m_playerPrivate, Qt::DirectConnection,
                                     QGenericReturnArgument(method.typeName(),
                                                            returnValue));
        if (success) {
            // Conversion to QVariant will take a copy
#if (QT_VERSION >= QT_VERSION_CHECK(6, 0, 0))
            result = QVariant(returnType, returnValue);
#else
            result = QVariant(method.returnType(), returnValue);
#endif
        } else {
            replyInternalError();
        }
        returnType.destroy(returnValue);
    } else {
        // Nothing in MprisPlayerPrivate so check MprisPlayer properties instead
        pidx = m_playerPrivate->q_ptr->metaObject()->indexOfProperty(
                    getter.toLocal8Bit().data());

        if (pidx != -1) {
            QMetaProperty mp = m_playerPrivate->q_ptr->metaObject()->property(pidx);
            result = mp.read(m_playerPrivate->q_ptr);
        } else {
            replyInternalError();
        }
    }

    return result;
}

QVariantMap MprisPropertiesAdaptor::GetAll(const QString &interface_name)
{
    QVariantMap result;
    QMap<QString, QString> getMap;

    lockProperties();

    if (interface_name == QLatin1String("org.mpris.MediaPlayer2.Player")) {
        getMap = playerGetMap;
    } else if (interface_name == QLatin1String("org.mpris.MediaPlayer2")) {
        getMap = serviceGetMap;
    } else {
        replyPropertyNotFoundError(interface_name, "");
    }

    QMap<QString, QString>::const_iterator it = getMap.constBegin();
    while (it != getMap.constEnd()) {
        if (!m_maskedProperties.contains(it.key())) {
            QVariant value = get(it.value());
            result.insert(it.key(), value);
        }
        ++it;
    }

    return result;
}

// Format: {DBus property name, method to call in MprisPlayerPrivate}
static const QMap<QString, QString> playerSetMap
{
    {"LoopStatus", "setLoopStatus(QString)"},
    {"Rate", "setRate(double)"},
    {"Shuffle", "setShuffle(bool)"},
    {"Volume", "setVolume(double)"},
};

static const QMap<QString, QString> serviceSetMap
{
    {"Fullscreen", "setFullscreen(bool)"},
};

void MprisPropertiesAdaptor::Set(const QString &interface_name, const QString &property_name, const QDBusVariant &value)
{
    QMap<QString, QString> setMap;
    QMap<QString, QString> getMap;

    if (interface_name == QLatin1String("org.mpris.MediaPlayer2.Player")) {
        setMap = playerSetMap;
        getMap = playerGetMap;
    } else if (interface_name == QLatin1String("org.mpris.MediaPlayer2")) {
        setMap = serviceSetMap;
        getMap = serviceGetMap;
    }

    const bool masked = m_maskedProperties.contains(property_name);
    const QString &setter = masked ? QString() : setMap.value(property_name);
    if (!setter.isEmpty()) {
        set(setter, value);
    } else {
        if (!masked && getMap.contains(property_name)) {
            replyPropertyReadOnlyError(interface_name, property_name);
        } else {
            replyPropertyNotFoundError(interface_name, property_name);
        }
    }
}

void MprisPropertiesAdaptor::set(const QString &setter, const QDBusVariant &value)
{
    const QMetaObject *metaobject = m_playerPrivate->metaObject();
    bool success = false;

    int pidx = metaobject->indexOfMethod(
                setter.toLocal8Bit().data());

    if (pidx != -1) {
        QMetaMethod method = metaobject->method(pidx);
        Q_ASSERT(method.parameterCount() == 1);

        // QMetaType maps to Type, as long as our methods stick to the standard types
        if (method.parameterType(0) == value.variant().userType()) {
            success = method.invoke(m_playerPrivate, Qt::DirectConnection,
                                    QGenericArgument(method.parameterNames()[0],
                                                     value.variant().data()));
        }
    }

    if (!success) {
        replyInternalError();
    }
}

bool MprisPropertiesAdaptor::propertiesLocked() const
{
    return m_propertiesLocked;
}

void MprisPropertiesAdaptor::hideProperty(const QString &property, bool hidden)
{
    if (hidden) {
        m_maskedProperties.insert(property);
    } else {
        m_maskedProperties.remove(property);
    }
}

void MprisPropertiesAdaptor::reset()
{
    // Caller is responsible for unregistering the object
    m_propertiesLocked = false;
}

bool MprisPropertiesAdaptor::hasMaskedProperties() const
{
    return !m_maskedProperties.isEmpty();
}

bool MprisPropertiesAdaptor::propertyMasked(const QString &property) const
{
    return m_maskedProperties.contains(property);
}

void MprisPropertiesAdaptor::lockProperties()
{
    m_propertiesLocked = true;
}
