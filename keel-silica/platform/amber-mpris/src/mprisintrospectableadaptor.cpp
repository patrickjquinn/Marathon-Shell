// SPDX-FileCopyrightText: 2023 Jolla Ltd.
// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 * Copyright (C) 2023 Jolla Ltd.
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

#include <QBuffer>
#include <QXmlStreamReader>
#include "mprisplayer_p.h"
#include "mprisintrospectableadaptor_p.h"

using namespace Amber;

namespace {
    const char *IntrospectPreface = 
        "<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\" \n"
        "\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
        "<node name=\"/org/mpris/MediaPlayer2\">\n"
        "  <interface name=\"org.freedesktop.DBus.Peer\">\n"
        "    <method name=\"Ping\"/>\n"
        "    <method name=\"GetMachineId\">\n"
        "      <arg name=\"machine_uuid\" type=\"s\" direction=\"out\"/>\n"
        "    </method>\n"
        "  </interface>";
    const char *IntrospectPostface = "</node>";

    Q_LOGGING_CATEGORY(lcIntrospectable, "org.amber.mpris.introspectable", QtWarningMsg)
} // namespace

/*
 * Implementation of adaptor class MprisIntrospectableAdaptor
 */

MprisIntrospectableAdaptor::MprisIntrospectableAdaptor(MprisPropertiesAdaptor *propertiesAdaptor, MprisPlayerPrivate *parent)
    : QDBusAbstractAdaptor(parent)
    , m_propertiesAdaptor(propertiesAdaptor)
{
}

MprisIntrospectableAdaptor::~MprisIntrospectableAdaptor()
{
}

QString MprisIntrospectableAdaptor::Introspect()
{
    QBuffer xml;
    if (!xml.open(QIODevice::WriteOnly)) {
        qCCritical(lcIntrospectable) << "Could not open buffer to write";
        return QString();
    }
    xml.write(IntrospectPreface);

    m_propertiesAdaptor->lockProperties();

    for (const QObject *child : parent()->children()) {
        const QDBusAbstractAdaptor *adaptor = qobject_cast<const QDBusAbstractAdaptor *>(child);
        if (adaptor) {
            const QMetaObject *metaObject = adaptor->metaObject();
            int index = metaObject->indexOfClassInfo("D-Bus Introspection");
            if (index < metaObject->classInfoOffset())
                continue;
            const char *content = metaObject->classInfo(index).value();
            if (!content || !content[0])
                continue;

            if (!m_propertiesAdaptor->hasMaskedProperties()
                    || adaptor == this || adaptor == m_propertiesAdaptor) {
                xml.write(content);
            } else {
                QXmlStreamReader reader(content);
                QXmlStreamWriter writer(&xml);
                writer.setAutoFormatting(true);
                while (!reader.atEnd()) {
                    switch (reader.readNext()) {
                    case QXmlStreamReader::StartElement:
                        if (reader.name() == QLatin1String("property")) {
                            QString property = reader.attributes().value(
                                    QString(), QLatin1String("name")).toString();
                            if (m_propertiesAdaptor->propertyMasked(property)) {
                                reader.skipCurrentElement();
                                continue;
                            }
                        }
                        writer.writeStartElement(reader.qualifiedName().toString());
                        writer.writeAttributes(reader.attributes());
                        break;
                    case QXmlStreamReader::EndElement:
                        writer.writeEndElement();
                        break;
                    case QXmlStreamReader::StartDocument:
                    case QXmlStreamReader::EndDocument:
                    case QXmlStreamReader::Characters:
                        break;
                    default:
                        qCWarning(lcIntrospectable) << "Unexpected token type:" << reader.tokenType();
                        break;
                    }
                }
            }
        }
    }

    xml.write(IntrospectPostface);
    xml.close();
    return QString::fromUtf8(xml.data());
}
