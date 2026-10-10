// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Drops one harmless warning that every Keel app logged: "load glyph failed
// err=6 face=..., glyph=65535". Sailfish's Sail Sans Pro Light (the UI
// font) carries its ligatures (f_t, f_f_i, ...) in an AAT `morx` table, not
// OpenType GSUB. HarfBuzz's AAT ligatures leave the glyphs they absorb as a
// placeholder, 0xFFFF, removed when shaping ends, and Qt's FreeType engine
// is asked for the placeholder's advance in the meantime: FreeType refuses
// (FT_Err_Invalid_Argument) and Qt warns. Nothing is drawn wrongly. The font
// and Qt are the system's; any text with "ft" ("left", "soft") set it off.
//
// The filter is installed when this plugin loads (every Silica app imports
// Keel) and hands every other message to the handler that was there.

#include <QtCore/qbytearray.h>
#include <QtCore/qglobal.h>
#include <QtCore/qlogging.h>
#include <QtCore/qstring.h>

#include <cstdio>

namespace {

QtMessageHandler g_previous = nullptr;

bool isAatPlaceholderWarning(QtMsgType type, const QString& message)
{
    return type == QtWarningMsg && message.startsWith(QLatin1String("load glyph failed err=6 "))
        && message.endsWith(QLatin1String(", glyph=65535"));
}

void filterMessages(QtMsgType type, const QMessageLogContext& context, const QString& message)
{
    if (isAatPlaceholderWarning(type, message))
        return;
    if (g_previous) {
        g_previous(type, context, message);
    } else {
        // Qt's own handler (qInstallMessageHandler returns it, never null in
        // practice): its format, to stderr.
        const QByteArray line = qFormatLogMessage(type, context, message).toLocal8Bit();
        fprintf(stderr, "%s\n", line.constData());
        fflush(stderr);
    }
}

void installGlyphWarningFilter()
{
    g_previous = qInstallMessageHandler(filterMessages);
}

} // namespace

Q_CONSTRUCTOR_FUNCTION(installGlyphWarningFilter)
