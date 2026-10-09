// SPDX-FileCopyrightText: 2012-2016 Canonical Ltd.
// SPDX-License-Identifier: LGPL-2.1-only
// Modified by Shipwright for Qt 6: QVariant::type() and its enum are deprecated; typeId() and QMetaType.
/* vi: set et sw=4 ts=4 cino=t0,(0: */
/*
 * This file is part of libaccounts-qt
 *
 * Copyright (C) 2012-2016 Canonical Ltd.
 *
 * Contact: Alberto Mardegan <alberto.mardegan@canonical.com>
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
 */

#include "accountscommon.h"
#include "utils.h"

#include <QStringList>

namespace Accounts {

static QVariantMap gVariantToQVariantMap(GVariant *variant)
{
    QVariantMap ret;
    GVariantIter iter;
    gchar *key;
    GVariant *value;

    g_variant_iter_init (&iter, variant);
    while (g_variant_iter_next (&iter, "{sv}", &key, &value)) {
        ret.insert(UTF8(key), gVariantToQVariant(value));
        g_variant_unref(value);
        g_free(key);
    }

    return ret;
}

static GVariant *qStringListToGVariant(const QStringList &stringList)
{
    GVariantBuilder builder;

    g_variant_builder_init(&builder, G_VARIANT_TYPE_STRING_ARRAY);
    Q_FOREACH (const QString &string, stringList) {
        g_variant_builder_add(&builder, "s", string.toUtf8().constData());
    }
    return g_variant_builder_end(&builder);
}

static QStringList gVariantToQStringList(GVariant *variant)
{
    QStringList ret;

    gsize length;
    const gchar **strings = g_variant_get_strv(variant, &length);
    ret.reserve(length);
    for (gsize i = 0; i < length; i++) {
        ret.append(UTF8(strings[i]));
    }

    g_free(strings);
    return ret;
}

QVariant gVariantToQVariant(GVariant *value)
{
    GVariantClass variantClass = g_variant_classify(value);

    QVariant variant;

    switch (variantClass)
    {
    case G_VARIANT_CLASS_STRING:
        variant = UTF8(g_variant_get_string(value, NULL));
        break;
    case G_VARIANT_CLASS_INT32:
        variant = g_variant_get_int32(value);
        break;
    case G_VARIANT_CLASS_UINT32:
        variant = g_variant_get_uint32(value);
        break;
    case G_VARIANT_CLASS_INT64:
        variant = qint64(g_variant_get_int64(value));
        break;
    case G_VARIANT_CLASS_UINT64:
        variant = quint64(g_variant_get_uint64(value));
        break;
    case G_VARIANT_CLASS_BOOLEAN:
        variant = bool(g_variant_get_boolean(value));
        break;
    case G_VARIANT_CLASS_ARRAY:
        if (g_variant_is_of_type(value, G_VARIANT_TYPE_VARDICT)) {
            variant = gVariantToQVariantMap(value);
            break;
        } else if (g_variant_is_of_type(value, G_VARIANT_TYPE_STRING_ARRAY)) {
            variant = gVariantToQStringList(value);
            break;
        }
        // fall through
    default:
        qWarning() << "Unsupported type" << UTF8(g_variant_get_type_string(value));
        break;
    }

    return variant;
}

GVariant *qVariantToGVariant(const QVariant &variant)
{
    GVariant *ret = nullptr;
    QByteArray tmpvalue;

    switch (variant.typeId())
    {
    case QMetaType::QString:
        tmpvalue = variant.toString().toUtf8();
        ret = g_variant_new_string(tmpvalue.constData());
        break;
    case QMetaType::Int:
        ret = g_variant_new_int32(variant.toInt());
        break;
    case QMetaType::UInt:
        ret = g_variant_new_uint32(variant.toUInt());
        break;
    case QMetaType::LongLong:
        ret = g_variant_new_int64(variant.toLongLong());
        break;
    case QMetaType::ULongLong:
        ret = g_variant_new_uint64(variant.toULongLong());
        break;
    case QMetaType::Bool:
        ret = g_variant_new_boolean(variant.toBool());
        break;
    case QMetaType::QStringList:
        ret = qStringListToGVariant(variant.toStringList());
        break;
    default:
        qWarning() << "Unsupported datatype" << variant.typeName();
    }

    return ret;
}

}; // namespace
