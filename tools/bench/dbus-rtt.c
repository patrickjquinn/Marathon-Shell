// SPDX-License-Identifier: Apache-2.0
// Build: cc -O2 -Wall -Wextra -Werror dbus-rtt.c $(pkg-config --cflags --libs dbus-1) -o dbus-rtt
// Run in the graphical user's session. JSON lines measure reply wait time on
// one persistent connection, excluding process startup and message construction.
#include <dbus/dbus.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

struct endpoint {
    const char *label;
    const char *destination;
    const char *path;
    const char *interface;
    const char *member;
    const char *properties;
};

static const struct endpoint endpoints[] = {
    {"bus-control", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetId", NULL},
    {"deckard-runtime", "org.marathonos.Deckard", "/org/marathonos/Deckard", "org.marathonos.Deckard1", "GetRuntime", NULL},
    {"audio-properties", "org.marathonos.Audio", "/org/marathonos/Audio", "org.freedesktop.DBus.Properties", "GetAll", "org.marathonos.Audio1"},
    {"weather-properties", "org.marathonos.Weather", "/org/marathonos/Weather", "org.freedesktop.DBus.Properties", "GetAll", "org.marathonos.Weather1"},
    {"pilot-settings", "org.shipwright.Pilot", "/org/shipwright/Pilot", "org.shipwright.Pilot1", "Settings", NULL},
};

static int64_t monotonic_ns(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * INT64_C(1000000000) + now.tv_nsec;
}

static int compare(const void *left, const void *right) {
    const double a = *(const double *)left;
    const double b = *(const double *)right;
    return (a > b) - (a < b);
}

int main(int argc, char **argv) {
    long count = 1000;
    if (argc > 2) {
        fprintf(stderr, "usage: %s [samples: 10..100000]\n", argv[0]);
        return 2;
    }
    if (argc == 2) {
        char *end;
        errno = 0;
        count = strtol(argv[1], &end, 10);
        if (errno || *end || end == argv[1] || count < 10 || count > 100000) {
            fprintf(stderr, "invalid sample count\n");
            return 2;
        }
    }
    double *samples = calloc((size_t)count, sizeof(*samples));
    if (!samples) {
        perror("samples");
        return 1;
    }
    DBusError error;
    dbus_error_init(&error);
    DBusConnection *bus = dbus_bus_get_private(DBUS_BUS_SESSION, &error);
    if (!bus) {
        fprintf(stderr, "%s: %s\n", error.name, error.message);
        dbus_error_free(&error);
        free(samples);
        return 1;
    }
    dbus_connection_set_exit_on_disconnect(bus, FALSE);
    int failed = 0;
    for (size_t endpoint = 0; endpoint < sizeof(endpoints) / sizeof(endpoints[0]); ++endpoint) {
        const struct endpoint *e = &endpoints[endpoint];
        double total = 0;
        long measured = 0;
        for (long i = -20; i < count; ++i) {
            DBusMessage *request = dbus_message_new_method_call(e->destination, e->path, e->interface, e->member);
            if (e->properties)
                dbus_message_append_args(request, DBUS_TYPE_STRING, &e->properties, DBUS_TYPE_INVALID);
            const int64_t start = monotonic_ns();
            DBusMessage *reply = dbus_connection_send_with_reply_and_block(bus, request, 5000, &error);
            const double elapsed = (double)(monotonic_ns() - start) / 1000.0;
            dbus_message_unref(request);
            if (!reply) {
                fprintf(stderr, "%s: %s: %s\n", e->label, error.name, error.message);
                dbus_error_free(&error);
                failed = 1;
                break;
            }
            dbus_message_unref(reply);
            if (i >= 0) {
                samples[measured++] = elapsed;
                total += elapsed;
            }
        }
        if (measured == count) {
            qsort(samples, (size_t)count, sizeof(*samples), compare);
            printf("{\"endpoint\":\"%s\",\"samples\":%ld,\"errors\":0,\"mean_us\":%.3f,\"p50_us\":%.3f,\"p95_us\":%.3f,\"p99_us\":%.3f}\n",
                   e->label, count, total / (double)count,
                   samples[(count + 1) / 2 - 1], samples[(count * 95 + 99) / 100 - 1], samples[(count * 99 + 99) / 100 - 1]);
            fflush(stdout);
        }
    }
    dbus_connection_close(bus);
    dbus_connection_unref(bus);
    free(samples);
    return failed;
}
