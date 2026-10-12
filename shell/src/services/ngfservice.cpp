#include "ngfservice.h"

#include "ngfevents.h"

#include <QTimer>

NgfService::NgfService(Vibrate vibrate, StopVibration stop, QObject *parent)
    : QObject(parent)
    , m_vibrate(std::move(vibrate))
    , m_stop(std::move(stop)) {}

quint32 NgfService::Play(const QString &event, const QVariantMap &) {
    const quint32           id     = m_nextId++;
    const NgfEvents::Effect effect = NgfEvents::effect(event);
    if (!effect.known) {
        QTimer::singleShot(0, this, [this, id]() { emit Status(id, Failed); });
        return id;
    }

    m_vibrate(effect.pattern);
    emit Status(id, Playing);

    auto *timer = new QTimer(this);
    timer->setInterval(NgfEvents::duration(effect.pattern));
    timer->setSingleShot(!effect.repeat);
    connect(timer, &QTimer::timeout, this, [this, id, effect]() {
        if (effect.repeat)
            m_vibrate(effect.pattern);
        else
            finish(id, Completed);
    });
    timer->start();
    m_playing.insert(id, timer);
    return id;
}

bool NgfService::Pause(quint32 id, bool pause) {
    QTimer *timer = m_playing.value(id);
    if (!timer)
        return false;
    if (pause) {
        timer->stop();
        m_stop();
        emit Status(id, Paused);
    } else {
        timer->start();
        emit Status(id, Playing);
    }
    return true;
}

bool NgfService::Stop(quint32 id) {
    if (!m_playing.contains(id))
        return false;
    m_stop();
    finish(id, Completed);
    return true;
}

void NgfService::finish(quint32 id, State state) {
    if (QTimer *timer = m_playing.take(id))
        timer->deleteLater();
    emit Status(id, state);
}
