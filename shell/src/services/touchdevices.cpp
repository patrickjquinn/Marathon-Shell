#include "touchdevices.h"

TouchDevices::TouchDevices(Open open, QObject *parent)
    : QObject(parent)
    , m_open(std::move(open)) {}

QObject *TouchDevices::add(const QString &node) {
    if (m_devices.count(node))
        return nullptr;
    auto handler = m_open(node);
    if (!handler)
        return nullptr;
    return m_devices.emplace(node, std::move(handler)).first->second.get();
}

bool TouchDevices::remove(const QString &node) {
    return m_devices.erase(node) > 0;
}

int TouchDevices::count() const {
    return int(m_devices.size());
}

QList<QObject *> TouchDevices::handlers() const {
    QList<QObject *> list;
    for (const auto &[node, handler] : m_devices)
        list << handler.get();
    return list;
}
