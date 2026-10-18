#pragma once

#include <QCoreApplication>
#include <QElapsedTimer>
#include <poll.h>
#include <wayland-client.h>

// A roundtrip that keeps the in-process compositor's event loop running, so a
// test can be a client of the compositor it owns on one thread.
inline bool roundtrip(wl_display *display) {
    bool                              done     = false;
    wl_callback                      *callback = wl_display_sync(display);
    static const wl_callback_listener listener = {
        [](void *data, wl_callback *cb, uint32_t) {
            *static_cast<bool *>(data) = true;
            wl_callback_destroy(cb);
        },
    };
    wl_callback_add_listener(callback, &listener, &done);
    QElapsedTimer timer;
    timer.start();
    while (!done && timer.elapsed() < 5000) {
        wl_display_flush(display);
        QCoreApplication::processEvents();
        while (wl_display_prepare_read(display) != 0)
            wl_display_dispatch_pending(display);
        pollfd fd{wl_display_get_fd(display), POLLIN, 0};
        if (poll(&fd, 1, 5) > 0)
            wl_display_read_events(display);
        else
            wl_display_cancel_read(display);
        wl_display_dispatch_pending(display);
    }
    return done;
}
