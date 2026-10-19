#include "portalfilechooser.h"

#include <QDBusMetaType>
#include <QDir>
#include <QFileInfo>
#include <QUrl>

QDBusArgument &operator<<(QDBusArgument &arg, const PortalPattern &pattern) {
    arg.beginStructure();
    arg << pattern.type << pattern.pattern;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, PortalPattern &pattern) {
    arg.beginStructure();
    arg >> pattern.type >> pattern.pattern;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter) QDBusArgument >> signature
}

QDBusArgument &operator<<(QDBusArgument &arg, const PortalFilter &filter) {
    arg.beginStructure();
    arg << filter.name << filter.patterns;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, PortalFilter &filter) {
    arg.beginStructure();
    arg >> filter.name >> filter.patterns;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter) QDBusArgument >> signature
}

QDBusArgument &operator<<(QDBusArgument &arg, const PortalChoice &choice) {
    arg.beginStructure();
    arg << choice.id << choice.label;
    arg.beginArray(QMetaType::fromType<PortalChosen>());
    for (const auto &option : choice.options)
        arg << PortalChosen{option.first, option.second};
    arg.endArray();
    arg << choice.initial;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, PortalChoice &choice) {
    arg.beginStructure();
    arg >> choice.id >> choice.label;
    choice.options.clear();
    arg.beginArray();
    while (!arg.atEnd()) {
        PortalChosen option;
        arg >> option;
        choice.options.append({option.id, option.value});
    }
    arg.endArray();
    arg >> choice.initial;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter) QDBusArgument >> signature
}

QDBusArgument &operator<<(QDBusArgument &arg, const PortalChosen &chosen) {
    arg.beginStructure();
    arg << chosen.id << chosen.value;
    arg.endStructure();
    return arg;
}

const QDBusArgument &operator>>(const QDBusArgument &arg, PortalChosen &chosen) {
    arg.beginStructure();
    arg >> chosen.id >> chosen.value;
    arg.endStructure();
    return arg; // NOLINT(bugprone-return-const-ref-from-parameter) QDBusArgument >> signature
}

namespace {
    // The portal's byte strings (ay) end with a NUL.
    QString pathOf(const QVariant &value) {
        QByteArray bytes = value.toByteArray();
        while (bytes.endsWith('\0'))
            bytes.chop(1);
        return QString::fromLocal8Bit(bytes);
    }

    template <typename T> QList<T> listOf(const QVariant &value) {
        return value.canConvert<QDBusArgument>() ? qdbus_cast<QList<T>>(value.value<QDBusArgument>()) :
                                                   QList<T>();
    }

    QString fileUri(const QString &path) {
        return QString::fromUtf8(QUrl::fromLocalFile(path).toEncoded());
    }

    // A Request: xdg-desktop-portal closes it when the app gives up.
    class PortalRequest : public QObject {
        Q_OBJECT
        Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.Request")

      public:
        using QObject::QObject;

      public slots:
        void Close() {
            emit closeRequested();
        }

      signals:
        void closeRequested();
    };
} // namespace

FileChooserPortal::FileChooserPortal(QDBusConnection bus, QObject *parent)
    : QObject(parent)
    , m_bus(std::move(bus)) {
    qDBusRegisterMetaType<PortalPattern>();
    qDBusRegisterMetaType<QList<PortalPattern>>();
    qDBusRegisterMetaType<PortalFilter>();
    qDBusRegisterMetaType<QList<PortalFilter>>();
    qDBusRegisterMetaType<PortalChosen>();
    qDBusRegisterMetaType<QList<PortalChosen>>();
    qDBusRegisterMetaType<PortalChoice>();
    qDBusRegisterMetaType<QList<PortalChoice>>();
    qDBusRegisterMetaType<QList<QByteArray>>();
}

void FileChooserPortal::request(Mode mode, const QDBusMessage &message,
                                const QDBusObjectPath &handle, const QString &appId,
                                const QString &title, const QVariantMap &options) {
    Q_UNUSED(appId);
    if (!m_handle.isEmpty()) {
        finish(2, {});
        emit closed();
    }
    m_message = message;
    m_handle  = handle.path();
    m_mode    = mode;
    m_filters = listOf<PortalFilter>(options.value(QStringLiteral("filters")));
    m_files.clear();
    const QList<QByteArray> files = listOf<QByteArray>(options.value(QStringLiteral("files")));
    for (const QByteArray &file : files)
        m_files << QFileInfo(pathOf(file)).fileName();

    auto *requestObject = new PortalRequest(this);
    connect(requestObject, &PortalRequest::closeRequested, this, [this]() {
        finish(2, {});
        emit closed();
    });
    m_bus.registerObject(m_handle, requestObject, QDBusConnection::ExportAllSlots);
    m_requestObject = requestObject;

    QVariantList filters;
    for (const PortalFilter &filter : std::as_const(m_filters)) {
        QStringList globs, mimes;
        for (const PortalPattern &pattern : filter.patterns)
            (pattern.type == 1 ? mimes : globs) << pattern.pattern;
        filters << QVariantMap{{QStringLiteral("name"), filter.name},
                               {QStringLiteral("globs"), globs},
                               {QStringLiteral("mimes"), mimes}};
    }
    int        filterIndex = filters.isEmpty() ? -1 : 0;
    const auto current     = options.value(QStringLiteral("current_filter"));
    if (current.canConvert<QDBusArgument>()) {
        const auto chosen = qdbus_cast<PortalFilter>(current.value<QDBusArgument>());
        for (int i = 0; i < m_filters.size(); ++i)
            if (m_filters.at(i).name == chosen.name)
                filterIndex = i;
    }
    QVariantList choices;
    const QList<PortalChoice> asked = listOf<PortalChoice>(options.value(QStringLiteral("choices")));
    for (const PortalChoice &choice : asked) {
        QVariantList choiceOptions;
        for (const auto &option : choice.options)
            choiceOptions << QVariantMap{{QStringLiteral("id"), option.first},
                                         {QStringLiteral("label"), option.second}};
        choices << QVariantMap{{QStringLiteral("id"), choice.id},
                               {QStringLiteral("label"), choice.label},
                               {QStringLiteral("options"), choiceOptions},
                               {QStringLiteral("value"), choice.initial}};
    }

    QString folder = pathOf(options.value(QStringLiteral("current_folder")));
    QString name   = options.value(QStringLiteral("current_name")).toString();
    if (const QString file = pathOf(options.value(QStringLiteral("current_file"))); !file.isEmpty()) {
        folder = QFileInfo(file).absolutePath();
        name   = QFileInfo(file).fileName();
    }
    static const char *const modes[] = {"open", "save", "saveMany"};
    emit requested({{QStringLiteral("mode"), QString::fromLatin1(modes[mode])},
                    {QStringLiteral("title"), title},
                    {QStringLiteral("acceptLabel"), options.value(QStringLiteral("accept_label"))},
                    {QStringLiteral("multiple"), mode == Open && options.value(QStringLiteral("multiple")).toBool()},
                    {QStringLiteral("directory"),
                     mode == SaveMany || options.value(QStringLiteral("directory")).toBool()},
                    {QStringLiteral("filters"), filters},
                    {QStringLiteral("filterIndex"), filterIndex},
                    {QStringLiteral("folder"), folder},
                    {QStringLiteral("name"), name},
                    {QStringLiteral("files"), m_files},
                    {QStringLiteral("choices"), choices}});
}

void FileChooserPortal::accept(const QStringList &paths, int filterIndex,
                               const QVariantMap &choices) {
    if (m_handle.isEmpty())
        return;
    QStringList uris;
    if (m_mode == SaveMany) {
        const QString folder = paths.value(0);
        for (const QString &file : std::as_const(m_files))
            uris << fileUri(QDir(folder).filePath(file));
    } else {
        for (const QString &path : paths)
            uris << fileUri(path);
    }
    QVariantMap results{{QStringLiteral("uris"), uris}};
    if (filterIndex >= 0 && filterIndex < m_filters.size())
        results.insert(QStringLiteral("current_filter"), QVariant::fromValue(m_filters.at(filterIndex)));
    if (!choices.isEmpty()) {
        QList<PortalChosen> chosen;
        for (auto it = choices.cbegin(); it != choices.cend(); ++it)
            chosen << PortalChosen{it.key(), it.value().toString()};
        results.insert(QStringLiteral("choices"), QVariant::fromValue(chosen));
    }
    if (m_mode != Open)
        results.insert(QStringLiteral("writable"), true);
    finish(0, results);
}

void FileChooserPortal::cancel() {
    finish(1, {});
}

void FileChooserPortal::finish(uint response, const QVariantMap &results) {
    if (m_handle.isEmpty())
        return;
    m_bus.send(m_message.createReply({response, results}));
    m_bus.unregisterObject(m_handle);
    if (m_requestObject)
        m_requestObject->deleteLater();
    m_handle.clear();
    m_message = QDBusMessage();
}

FileChooserAdaptor::FileChooserAdaptor(QObject *parent, FileChooserPortal *portal)
    : QDBusAbstractAdaptor(parent)
    , m_portal(portal) {}

uint FileChooserAdaptor::OpenFile(const QDBusObjectPath &handle, const QString &appId,
                                  const QString &parentWindow, const QString &title,
                                  const QVariantMap &options, const QDBusMessage &message,
                                  QVariantMap &results) {
    Q_UNUSED(parentWindow);
    Q_UNUSED(results);
    message.setDelayedReply(true);
    m_portal->request(FileChooserPortal::Open, message, handle, appId, title, options);
    return 0;
}

uint FileChooserAdaptor::SaveFile(const QDBusObjectPath &handle, const QString &appId,
                                  const QString &parentWindow, const QString &title,
                                  const QVariantMap &options, const QDBusMessage &message,
                                  QVariantMap &results) {
    Q_UNUSED(parentWindow);
    Q_UNUSED(results);
    message.setDelayedReply(true);
    m_portal->request(FileChooserPortal::Save, message, handle, appId, title, options);
    return 0;
}

uint FileChooserAdaptor::SaveFiles(const QDBusObjectPath &handle, const QString &appId,
                                   const QString &parentWindow, const QString &title,
                                   const QVariantMap &options, const QDBusMessage &message,
                                   QVariantMap &results) {
    Q_UNUSED(parentWindow);
    Q_UNUSED(results);
    message.setDelayedReply(true);
    m_portal->request(FileChooserPortal::SaveMany, message, handle, appId, title, options);
    return 0;
}

#include "portalfilechooser.moc"
