#include "audiodclient.h"

#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDebug>

namespace {

    QString path() {
        return QStringLiteral("/org/marathonos/Audio");
    }

    QString iface() {
        return QStringLiteral("org.marathonos.Audio1");
    }

    QString props() {
        return QStringLiteral("org.freedesktop.DBus.Properties");
    }

} // namespace

QDBusArgument &operator<<(QDBusArgument &arg, const AudiodStream &stream) {
    arg.beginStructure();
    arg << stream.id << stream.name << stream.volume << stream.muted;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, AudiodStream &stream) {
    arg.beginStructure();
    arg >> stream.id >> stream.name >> stream.volume >> stream.muted;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter)
}

const QString &AudiodClient::serviceName() {
    static const QString kName = QStringLiteral("org.marathonos.Audio");
    return kName;
}

AudiodClient::AudiodClient(const QDBusConnection &bus, QObject *parent)
    : SinkBackend(parent)
    , m_bus(bus)
    , m_watcher(new QDBusServiceWatcher(serviceName(), m_bus,
                                        QDBusServiceWatcher::WatchForOwnerChange, this)) {
    qDBusRegisterMetaType<AudiodStream>();
    qDBusRegisterMetaType<QList<AudiodStream>>();
    m_bus.connect(serviceName(), path(), props(), QStringLiteral("PropertiesChanged"), this,
                  SLOT(onPropertiesChanged(QString, QVariantMap, QStringList)));
    // A restarted service starts from PipeWire's state, not ours.
    connect(m_watcher, &QDBusServiceWatcher::serviceOwnerChanged, this,
            [this](const QString &, const QString &, const QString &owner) {
                if (owner.isEmpty())
                    setAvailable(false);
                else
                    refresh();
            });
}

void AudiodClient::refresh() {
    QDBusMessage getAll =
        QDBusMessage::createMethodCall(serviceName(), path(), props(), QStringLiteral("GetAll"));
    getAll << iface();
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(getAll), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this](QDBusPendingCallWatcher *call) {
                call->deleteLater();
                const QDBusPendingReply<QVariantMap> reply = *call;
                if (reply.isError()) {
                    qWarning() << "[Audio] marathon-audiod:" << reply.error().message();
                    setAvailable(false);
                    return;
                }
                apply(reply.value());
                setAvailable(true);
            });
}

void AudiodClient::setAvailable(bool available) {
    if (available == m_available)
        return;
    m_available = available;
    if (!available) {
        m_sink.clear();
        emit defaultSinkChanged(m_sink);
        m_streams.clear();
        emit streamsChanged();
    }
    emit availableChanged();
}

void AudiodClient::onPropertiesChanged(const QString &interface, const QVariantMap &changed,
                                       const QStringList &) {
    if (interface == iface())
        apply(changed);
}

void AudiodClient::apply(const QVariantMap &props) {
    const auto sink = props.constFind(QStringLiteral("DefaultSink"));
    if (sink != props.cend() && sink->toString() != m_sink) {
        m_sink = sink->toString();
        emit defaultSinkChanged(m_sink);
    }
    const auto volume = props.constFind(QStringLiteral("Volume"));
    if (volume != props.cend())
        m_volume = volume->toDouble();
    const auto muted = props.constFind(QStringLiteral("Muted"));
    if (muted != props.cend())
        m_muted = muted->toBool();
    if (sink != props.cend() || volume != props.cend() || muted != props.cend())
        emit sinkChanged(m_sink, m_volume, m_muted);

    const auto streams = props.constFind(QStringLiteral("Streams"));
    if (streams != props.cend()) {
        m_streams = qdbus_cast<QList<AudiodStream>>(*streams);
        emit streamsChanged();
    }
}

void AudiodClient::call(const QString &method, const QVariantList &args,
                        const std::function<void()> &done) {
    QDBusMessage msg = QDBusMessage::createMethodCall(serviceName(), path(), iface(), method);
    msg.setArguments(args);
    auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [method, done](QDBusPendingCallWatcher *call) {
                call->deleteLater();
                if (call->isError())
                    qWarning() << "[Audio]" << method << call->error().message();
                if (done)
                    done();
            });
}

void AudiodClient::setSinkVolume(const QString &, double volume) {
    call(QStringLiteral("SetVolume"), {volume}, [this] { emit volumeWritten(); });
}

void AudiodClient::setSinkMuted(const QString &, bool muted) {
    call(QStringLiteral("SetMuted"), {muted}, [this] { emit muteWritten(); });
}

void AudiodClient::setStreamVolume(uint id, double volume) {
    call(QStringLiteral("SetStreamVolume"), {id, volume});
}

void AudiodClient::setStreamMuted(uint id, bool muted) {
    call(QStringLiteral("SetStreamMuted"), {id, muted});
}

void AudiodClient::setInputMuted(bool muted) {
    call(QStringLiteral("SetInputMuted"), {muted});
}

void AudiodClient::setSpeakerphone(bool on) {
    call(QStringLiteral("SetSpeakerphone"), {on});
}
