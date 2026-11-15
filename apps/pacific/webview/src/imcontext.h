// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// The web view's WebKitInputMethodContext, bridged to Qt's input method
// (Maliit on Sailfish OS). WebKit tells it when an editable element gains or
// loses focus, where the caret is, the text around it, and the field's
// purpose (email, number, URL, password ...); the view answers Qt's
// inputMethodQuery() from that, so the keyboard opens for editable fields
// only, places itself, and shows the right layout. Text from the keyboard
// goes back through the context's preedit/commit/delete-surrounding signals,
// which WebKit applies as real editing (beforeinput/input events, undo).

#pragma once

#include <QRect>
#include <QString>

#include <wpe/webkit.h>

class PacificWebView;

struct ImState {
    bool focused = false;
    QRect cursorRect; // WebKit (CSS px) coordinates
    QString surrounding;
    int cursor = 0;
    int anchor = 0;
    WebKitInputPurpose purpose = WEBKIT_INPUT_PURPOSE_FREE_FORM;
    WebKitInputHints hints = WEBKIT_INPUT_HINT_NONE;
};

namespace ImContext {
// A new context reporting to the view (unref with g_object_unref).
WebKitInputMethodContext* create(PacificWebView* view);
// Clears the back-pointer when the view goes away first.
void detach(WebKitInputMethodContext* context);

// Keyboard -> WebKit.
void setPreedit(WebKitInputMethodContext* context, const QString& text, int cursor);
void commit(WebKitInputMethodContext* context, const QString& text);
void deleteSurrounding(WebKitInputMethodContext* context, int offset, int count);
} // namespace ImContext
