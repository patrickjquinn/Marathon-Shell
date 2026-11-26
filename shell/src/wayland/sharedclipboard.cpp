#include "src/wayland/sharedclipboard.h"

#include <QClipboard>
#include <QGuiApplication>
#include <QHash>
#include <QMimeData>
#include <QScopedValueRollback>
#include <QSocketNotifier>
#include <QWaylandCompositor>
#include <QWaylandSeat>
#include <QWaylandSurface>
#include <QtWaylandCompositor/private/qwaylandseat_p.h>
#include <QtWaylandCompositor/private/qwldatadevice_p.h>

#include <memory>

#include <csignal>
#include <fcntl.h>
#include <pthread.h>
#include <unistd.h>
#include <wayland-server-protocol.h>

namespace {

    // GTK asks for UTF-8 by name; QMimeData::setText stores only text/plain.
    std::unique_ptr<QMimeData> copyOf(const QMimeData *data) {
        auto              copy    = std::make_unique<QMimeData>();
        const QStringList formats = data->formats();
        for (const QString &format : formats)
            copy->setData(format, data->data(format));
        if (data->hasText())
            copy->setData(QStringLiteral("text/plain;charset=utf-8"), data->text().toUtf8());
        return copy;
    }

    // An app that closes its end early must not end the shell with SIGPIPE.
    ssize_t writeNoSigpipe(int fd, const char *bytes, size_t size) {
        sigset_t pipe;
        sigset_t old;
        sigemptyset(&pipe);
        sigaddset(&pipe, SIGPIPE);
        pthread_sigmask(SIG_BLOCK, &pipe, &old);
        const ssize_t n = ::write(fd, bytes, size);
        if (n < 0 && errno == EPIPE) {
            const timespec now{};
            sigtimedwait(&pipe, nullptr, &now);
        }
        pthread_sigmask(SIG_SETMASK, &old, nullptr);
        return n;
    }

    // Without blocking the compositor on an app that reads slowly, or never.
    void send(int fd, const QByteArray &bytes) {
        if (bytes.isEmpty()) {
            ::close(fd);
            return;
        }
        ::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL) | O_NONBLOCK);
        auto *notifier = new QSocketNotifier(fd, QSocketNotifier::Write);
        QObject::connect(notifier, &QSocketNotifier::activated, notifier,
                         [notifier, fd, bytes, written = qsizetype(0)]() mutable {
                             const ssize_t n = writeNoSigpipe(fd, bytes.constData() + written,
                                                              size_t(bytes.size() - written));
                             if (n > 0)
                                 written += n;
                             const bool again = n < 0 && (errno == EAGAIN || errno == EINTR);
                             if (again || (n > 0 && written < bytes.size()))
                                 return;
                             notifier->setEnabled(false);
                             notifier->deleteLater();
                             ::close(fd);
                         });
    }

    using Contents = QHash<QByteArray, QByteArray>;

    void offerAccept(wl_client *, wl_resource *, uint32_t, const char *) {}

    void offerReceive(wl_client *, wl_resource *resource, const char *mimeType, int32_t fd) {
        send(fd, static_cast<Contents *>(wl_resource_get_user_data(resource))->value(mimeType));
    }

    void offerDestroy(wl_client *, wl_resource *resource) {
        wl_resource_destroy(resource);
    }

    void offerFinish(wl_client *, wl_resource *) {}

    void offerSetActions(wl_client *, wl_resource *, uint32_t, uint32_t) {}

    const struct wl_data_offer_interface kOfferImpl = {
        offerAccept, offerReceive, offerDestroy, offerFinish, offerSetActions,
    };

    void freeContents(wl_resource *resource) {
        delete static_cast<Contents *>(wl_resource_get_user_data(resource));
    }

} // namespace

SharedClipboard::SharedClipboard(QWaylandCompositor *compositor)
    : QObject(compositor)
    , m_compositor(compositor) {
    compositor->setRetainedSelectionEnabled(true);
    connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, &SharedClipboard::claim);
    connect(compositor->defaultSeat(), &QWaylandSeat::keyboardFocusChanged, this,
            [this](QWaylandSurface *focus) { offer(focus); });
}

void SharedClipboard::take(const QMimeData *data) {
    if (m_taking)
        return;
    const QScopedValueRollback taking(m_taking, true);
    QGuiApplication::clipboard()->setMimeData(copyOf(data).release());
}

// The shell copied: an app's own copy, which it would paste in preference to
// any offer, is cancelled.
void SharedClipboard::claim() {
    if (m_taking)
        return;
    QWaylandSurface *focus = m_compositor->defaultSeat()->keyboardFocus();
    // overrideSelection dereferences the focused client's data device.
    if (focus && !hasDataDevice(focus))
        return;
    const QMimeData *clipboard = QGuiApplication::clipboard()->mimeData();
    if (!clipboard)
        return;
    const QScopedValueRollback       taking(m_taking, true);
    const std::unique_ptr<QMimeData> data = copyOf(clipboard);
    m_compositor->overrideSelection(data.get());
    // Qt's override reaches one of the app's data devices; Qt apps have two.
    offer(focus);
}

void SharedClipboard::offer(QWaylandSurface *focus) const {
    const QMimeData *clipboard = QGuiApplication::clipboard()->mimeData();
    if (!focus || !clipboard || !hasDataDevice(focus))
        return;
    const std::unique_ptr<QMimeData> data    = copyOf(clipboard);
    const QStringList                formats = data->formats();
    Contents                         contents;
    for (const QString &format : formats) {
        const QByteArray bytes = data->data(format);
        if (!bytes.isEmpty())
            contents.insert(format.toUtf8(), bytes);
    }
    if (contents.isEmpty())
        return;

    QtWayland::DataDevice *device =
        QWaylandSeatPrivate::get(m_compositor->defaultSeat())->dataDevice();
    const auto resources = device->resourceMap().values(focus->waylandClient());
    for (const auto *resource : resources) {
        wl_resource *offer = wl_resource_create(resource->client(), &wl_data_offer_interface,
                                                resource->version(), 0);
        if (!offer) {
            wl_client_post_no_memory(resource->client());
            return;
        }
        wl_resource_set_implementation(offer, &kOfferImpl, new Contents(contents), freeContents);
        wl_data_device_send_data_offer(resource->handle, offer);
        for (auto it = contents.cbegin(); it != contents.cend(); ++it)
            wl_data_offer_send_offer(offer, it.key().constData());
        wl_data_device_send_selection(resource->handle, offer);
    }
}

bool SharedClipboard::hasDataDevice(QWaylandSurface *surface) const {
    QtWayland::DataDevice *device =
        QWaylandSeatPrivate::get(m_compositor->defaultSeat())->dataDevice();
    return device && device->resourceMap().contains(surface->waylandClient());
}
