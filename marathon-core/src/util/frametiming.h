// Header-only diagnostic. Hooks QQuickWindow::frameSwapped and emits
// P50/P99/max frame-delta every kReportEveryN swaps via qInfo. Off by default
// at every call site; gate with an env var or runtime flag in the caller.

#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QQuickWindow>
#include <QString>
#include <QtGlobal>
#include <algorithm>
#include <vector>

namespace marathon::diag {

    inline void installFrameTimingTracker(QQuickWindow *window, QString label) {
        constexpr int kReportEveryN = 240;

        struct State {
            QElapsedTimer       timer;
            qint64              lastNs = 0;
            bool                primed = false;
            QString             label;
            std::vector<qint64> samples;
        };

        auto *s = new State{{}, 0, false, std::move(label), {}};
        s->samples.reserve(kReportEveryN);

        QObject::connect(window, &QQuickWindow::frameSwapped, window, [s]() {
            if (!s->primed) {
                s->timer.start();
                s->lastNs = s->timer.nsecsElapsed();
                s->primed = true;
                return;
            }
            const qint64 now = s->timer.nsecsElapsed();
            s->samples.push_back(now - s->lastNs);
            s->lastNs = now;
            if (s->samples.size() < static_cast<size_t>(kReportEveryN))
                return;
            auto sorted = s->samples;
            std::sort(sorted.begin(), sorted.end());
            const qint64 p50 = sorted[sorted.size() / 2];
            const qint64 p99 = sorted[sorted.size() * 99 / 100];
            const qint64 max = sorted.back();
            qInfo().nospace() << "[FrameTiming] " << s->label << "  P50=" << (p50 / 1000)
                              << "µs  P99=" << (p99 / 1000) << "µs  max=" << (max / 1000) << "µs  ("
                              << sorted.size() << " frames)";
            s->samples.clear();
        });

        QObject::connect(window, &QObject::destroyed, window, [s]() { delete s; });
    }

} // namespace marathon::diag
