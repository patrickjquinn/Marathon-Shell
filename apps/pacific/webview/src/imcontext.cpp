// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "imcontext.h"

#include "pacificwebview.h"

#include <QPointer>

// GObject subclass of WebKitInputMethodContext. Plain C-style GObject code:
// the type system wants static class/instance init functions.

struct PacificImContext {
    WebKitInputMethodContext  parent;
    QPointer<PacificWebView> *view;
    char                     *preedit;
    guint                     preeditCursor;
    bool                      preeditActive;
};

struct PacificImContextClass {
    WebKitInputMethodContextClass parent_class;
};

G_DEFINE_TYPE(PacificImContext, pacific_im_context, WEBKIT_TYPE_INPUT_METHOD_CONTEXT)

#define PACIFIC_IM_CONTEXT(obj)                                                                    \
    (G_TYPE_CHECK_INSTANCE_CAST((obj), pacific_im_context_get_type(), PacificImContext))

static PacificWebView *viewOf(WebKitInputMethodContext *context) {
    auto *self = PACIFIC_IM_CONTEXT(context);
    return self->view ? self->view->data() : nullptr;
}

static void pacific_im_context_finalize(GObject *object) {
    auto *self = PACIFIC_IM_CONTEXT(object);
    delete self->view;
    self->view = nullptr;
    g_free(self->preedit);
    G_OBJECT_CLASS(pacific_im_context_parent_class)->finalize(object);
}

static void imGetPreedit(WebKitInputMethodContext *context, gchar **text, GList **underlines,
                         guint *cursorOffset) {
    auto *self = PACIFIC_IM_CONTEXT(context);
    if (text)
        *text = g_strdup(self->preedit ? self->preedit : "");
    if (underlines) {
        *underlines = nullptr;
        if (self->preedit && *self->preedit) {
            const auto length = static_cast<guint>(g_utf8_strlen(self->preedit, -1));
            *underlines = g_list_prepend(nullptr, webkit_input_method_underline_new(0, length));
        }
    }
    if (cursorOffset)
        *cursorOffset = self->preeditCursor;
}

static gboolean imFilterKeyEvent(WebKitInputMethodContext *, gpointer) {
    // Hardware and soft keys reach WebKit as ordinary key events; the
    // keyboard's composed text comes through commit/preedit instead.
    return FALSE;
}

static void imNotifyFocusIn(WebKitInputMethodContext *context) {
    if (PacificWebView *view = viewOf(context)) {
        ImState state = view->imState();
        state.focused = true;
        state.purpose = webkit_input_method_context_get_input_purpose(context);
        state.hints   = webkit_input_method_context_get_input_hints(context);
        view->setImState(state, true);
    }
}

static void imNotifyFocusOut(WebKitInputMethodContext *context) {
    auto *self = PACIFIC_IM_CONTEXT(context);
    g_clear_pointer(&self->preedit, g_free);
    self->preeditActive = false;
    if (PacificWebView *view = viewOf(context)) {
        ImState state;
        view->setImState(state, true);
    }
}

static void imNotifyCursorArea(WebKitInputMethodContext *context, int x, int y, int width,
                               int height) {
    if (PacificWebView *view = viewOf(context)) {
        ImState state    = view->imState();
        state.cursorRect = QRect(x, y, width, height);
        view->setImState(state, false);
    }
}

static void imNotifySurrounding(WebKitInputMethodContext *context, const gchar *text, guint length,
                                guint cursorIndex, guint selectionIndex) {
    if (PacificWebView *view = viewOf(context)) {
        ImState state = view->imState();
        // WebKit's indices are byte offsets into the UTF-8 text.
        const QByteArray utf8(text ? text : "", static_cast<qsizetype>(text ? length : 0));
        state.surrounding = QString::fromUtf8(utf8);
        state.cursor      = static_cast<int>(QString::fromUtf8(utf8.left(cursorIndex)).size());
        state.anchor      = static_cast<int>(QString::fromUtf8(utf8.left(selectionIndex)).size());
        view->setImState(state, false);
    }
}

static void imReset(WebKitInputMethodContext *context) {
    auto *self = PACIFIC_IM_CONTEXT(context);
    g_clear_pointer(&self->preedit, g_free);
    self->preeditActive = false;
    if (PacificWebView *view = viewOf(context))
        view->resetInputMethod();
}

static void pacific_im_context_class_init(PacificImContextClass *klass) {
    G_OBJECT_CLASS(klass)->finalize = pacific_im_context_finalize;
    auto *im                        = WEBKIT_INPUT_METHOD_CONTEXT_CLASS(klass);
    im->get_preedit                 = imGetPreedit;
    im->filter_key_event            = imFilterKeyEvent;
    im->notify_focus_in             = imNotifyFocusIn;
    im->notify_focus_out            = imNotifyFocusOut;
    im->notify_cursor_area          = imNotifyCursorArea;
    im->notify_surrounding          = imNotifySurrounding;
    im->reset                       = imReset;
}

static void pacific_im_context_init(PacificImContext *self) {
    self->view          = nullptr;
    self->preedit       = nullptr;
    self->preeditCursor = 0;
    self->preeditActive = false;
}

WebKitInputMethodContext *ImContext::create(PacificWebView *view) {
    auto *self =
        static_cast<PacificImContext *>(g_object_new(pacific_im_context_get_type(), nullptr));
    self->view = new QPointer<PacificWebView>(view);
    return WEBKIT_INPUT_METHOD_CONTEXT(self);
}

void ImContext::detach(WebKitInputMethodContext *context) {
    auto *self = PACIFIC_IM_CONTEXT(context);
    if (self->view)
        *self->view = nullptr;
}

void ImContext::setPreedit(WebKitInputMethodContext *context, const QString &text, int cursor) {
    auto *self = PACIFIC_IM_CONTEXT(context);
    if (text.isEmpty()) {
        if (!self->preeditActive)
            return;
        g_clear_pointer(&self->preedit, g_free);
        self->preeditCursor = 0;
        g_signal_emit_by_name(context, "preedit-changed");
        g_signal_emit_by_name(context, "preedit-finished");
        self->preeditActive = false;
        return;
    }
    if (!self->preeditActive) {
        self->preeditActive = true;
        g_signal_emit_by_name(context, "preedit-started");
    }
    g_free(self->preedit);
    self->preedit = g_strdup(text.toUtf8().constData());
    self->preeditCursor =
        static_cast<guint>(cursor < 0 ? text.size() : qMin(cursor, static_cast<int>(text.size())));
    g_signal_emit_by_name(context, "preedit-changed");
}

void ImContext::commit(WebKitInputMethodContext *context, const QString &text) {
    auto *self = PACIFIC_IM_CONTEXT(context);
    if (self->preeditActive) {
        // The committed text replaces the composition.
        g_clear_pointer(&self->preedit, g_free);
        self->preeditCursor = 0;
        g_signal_emit_by_name(context, "preedit-changed");
        g_signal_emit_by_name(context, "preedit-finished");
        self->preeditActive = false;
    }
    if (!text.isEmpty())
        g_signal_emit_by_name(context, "committed", text.toUtf8().constData());
}

void ImContext::deleteSurrounding(WebKitInputMethodContext *context, int offset, int count) {
    if (count > 0)
        g_signal_emit_by_name(context, "delete-surrounding", offset, static_cast<guint>(count));
}
