#pragma once

#include <QHash>

// Paces frame callbacks of surfaces nobody can see, as lipstick's 1 Hz fake
// repaint does: a backgrounded client that keeps drawing gets a callback at
// most once an interval instead of on every compositor frame, so it neither
// spins at 60 Hz unseen nor keeps the compositor rendering for it. A shown
// surface is never held. Keys are opaque surface pointers.
class HiddenFrameThrottle {
  public:
    explicit HiddenFrameThrottle(qint64 intervalMs = 1000)
        : m_interval(intervalMs) {}

    qint64 interval() const {
        return m_interval;
    }

    // Whether the surface's pending callbacks may go out at nowMs.
    bool allow(const void *surface, bool shown, qint64 nowMs) {
        const auto it = m_lastSent.constFind(surface);
        if (!shown && it != m_lastSent.cend() && nowMs - *it < m_interval)
            return false;
        m_lastSent.insert(surface, nowMs);
        return true;
    }

    void forget(const void *surface) {
        m_lastSent.remove(surface);
    }

  private:
    qint64                      m_interval;
    QHash<const void *, qint64> m_lastSent;
};
