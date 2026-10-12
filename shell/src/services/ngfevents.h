#pragma once

#include <QList>
#include <QString>

// Nemo.Ngf (non-graphical feedback) events as vibration: what Silica and
// Sailfish apps ask ngfd to play, mapped to Marathon's haptics.
namespace NgfEvents {

struct Effect {
    bool       known = false;
    QList<int> pattern; // vibrate, pause, vibrate, ... in ms
    bool       repeat = false;
};

inline Effect effect(const QString &event) {
    static const struct {
        const char *name;
        QList<int>  pattern;
        bool        repeat;
    } kEffects[] = {
        {"pulldown_highlight", {10}, false},
        {"pulldown_lock", {25}, false},
        {"feedback_press", {15}, false},
        {"feedback_press_weak", {8}, false},
        {"feedback_release", {8}, false},
        {"feedback_lock", {30}, false},
        {"keypad_press", {10}, false},
        {"keyboard_press", {8}, false},
        {"sms", {200, 100, 200}, false},
        {"chat", {200, 100, 200}, false},
        {"email", {150}, false},
        {"im", {200, 100, 200}, false},
        {"notice", {150}, false},
        {"general_warning", {300}, false},
        {"battery_low", {300, 150, 300}, false},
        {"ringtone", {800, 1200}, true},
        {"alarm", {500, 500}, true},
        {"clock", {500, 500}, true},
        {"calendar", {300, 200, 300}, false},
    };
    for (const auto &e : kEffects) {
        if (event == QLatin1String(e.name))
            return {true, e.pattern, e.repeat};
    }
    return {};
}

inline int duration(const QList<int> &pattern) {
    int total = 0;
    for (int ms : pattern)
        total += ms;
    return total;
}

} // namespace NgfEvents
