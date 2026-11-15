// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Pacific's WebProcess extension (loaded into every WebProcess from the
// directory the view sets on the shared WebKitWebContext).
//
// Content filters (WebKitUserContentFilter) block requests inside the
// WebProcess before anything reaches the UI process: no resource-load signal,
// no failed load, no send-request. WebKit does log each one to the page's
// console, from the content-extension code:
//   "Content blocker prevented frame displaying <page> from loading a resource from <url>"
// This extension watches the console of every page for that message and
// sends the blocked URL to the view as a user message "pacific.blocked" with
// parameters (s url, s page). PacificWebView counts them (blockedRequestCount)
// and emits blockedRequest(url).

#include <string.h>
#include <wpe/webkit-web-process-extension.h>

static const char kPrefix[] = "Content blocker prevented frame displaying ";
static const char kSeparator[] = " from loading a resource from ";

static void
console_message_sent (WebKitWebPage *page, WebKitConsoleMessage *message, gpointer user_data)
{
    (void) user_data;
    const char *text = webkit_console_message_get_text (message);
    if (!text || strncmp (text, kPrefix, sizeof (kPrefix) - 1) != 0)
        return;
    const char *separator = strstr (text + sizeof (kPrefix) - 1, kSeparator);
    if (!separator)
        return;
    char *document = g_strndup (text + sizeof (kPrefix) - 1, (gsize) (separator - text - (sizeof (kPrefix) - 1)));
    const char *url = separator + sizeof (kSeparator) - 1;
    // Some WebKit versions end the message with a period.
    gsize len = strlen (url);
    if (len && url[len - 1] == '.')
        len--;
    char *resource = g_strndup (url, len);
    WebKitUserMessage *msg = webkit_user_message_new ("pacific.blocked", g_variant_new ("(ss)", resource, document));
    webkit_web_page_send_message_to_view (page, msg, NULL, NULL, NULL);
    g_free (resource);
    g_free (document);
}

static void
page_created (WebKitWebProcessExtension *extension, WebKitWebPage *page, gpointer user_data)
{
    (void) extension;
    (void) user_data;
    g_signal_connect (page, "console-message-sent", G_CALLBACK (console_message_sent), NULL);
}

G_MODULE_EXPORT void
webkit_web_process_extension_initialize (WebKitWebProcessExtension *extension)
{
    g_signal_connect (extension, "page-created", G_CALLBACK (page_created), NULL);
}
