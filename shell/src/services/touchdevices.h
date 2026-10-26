#ifndef TOUCHDEVICES_H
#define TOUCHDEVICES_H

#include <QList>
#include <QObject>
#include <QString>

#include <functional>
#include <map>
#include <memory>

// One touch reader per device node, however often udev announces it.
class TouchDevices : public QObject {
    Q_OBJECT

  public:
    using Open = std::function<std::unique_ptr<QObject>(const QString &node)>;

    explicit TouchDevices(Open open, QObject *parent = nullptr);

    // The new reader, or null when the node is already read or won't open.
    QObject         *add(const QString &node);
    bool             remove(const QString &node);
    int              count() const;
    QList<QObject *> handlers() const;

  private:
    Open                                        m_open;
    std::map<QString, std::unique_ptr<QObject>> m_devices;
};

#endif
