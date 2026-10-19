#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QList>
#include <QObject>
#include <QPair>
#include <QPointer>
#include <QStringList>
#include <QVariantMap>

// xdg-desktop-portal's FileChooser types: a filter (sa(us)), a choice
// (ssa(ss)s) and a chosen value (ss).
struct PortalPattern {
    uint    type = 0; // 0 a glob, 1 a MIME type
    QString pattern;
};
struct PortalFilter {
    QString              name;
    QList<PortalPattern> patterns;
};
struct PortalChoice {
    QString                         id;
    QString                         label;
    QList<QPair<QString, QString>> options;
    QString                         initial;
};
struct PortalChosen {
    QString id;
    QString value;
};
Q_DECLARE_METATYPE(PortalPattern)
Q_DECLARE_METATYPE(PortalFilter)
Q_DECLARE_METATYPE(PortalChoice)
Q_DECLARE_METATYPE(PortalChosen)

QDBusArgument       &operator<<(QDBusArgument &arg, const PortalPattern &pattern);
const QDBusArgument &operator>>(const QDBusArgument &arg, PortalPattern &pattern);
QDBusArgument       &operator<<(QDBusArgument &arg, const PortalFilter &filter);
const QDBusArgument &operator>>(const QDBusArgument &arg, PortalFilter &filter);
QDBusArgument       &operator<<(QDBusArgument &arg, const PortalChoice &choice);
const QDBusArgument &operator>>(const QDBusArgument &arg, PortalChoice &choice);
QDBusArgument       &operator<<(QDBusArgument &arg, const PortalChosen &chosen);
const QDBusArgument &operator>>(const QDBusArgument &arg, PortalChosen &chosen);

// The shell's file chooser for xdg-desktop-portal (Flatpaks, and Android's
// pickers through deckardd): a request opens the picker sheet, and its
// reply waits for the person's choice. One request at a time; a second
// one closes the first.
class FileChooserPortal : public QObject {
    Q_OBJECT

  public:
    enum Mode : quint8 { Open, Save, SaveMany };
    Q_ENUM(Mode)

    explicit FileChooserPortal(QDBusConnection bus, QObject *parent = nullptr);

    void request(Mode mode, const QDBusMessage &message, const QDBusObjectPath &handle,
                 const QString &appId, const QString &title, const QVariantMap &options);

    // paths: the files chosen; for SaveMany the folder. filterIndex: the
    // filter in effect, -1 for none. choices: id -> value.
    Q_INVOKABLE void accept(const QStringList &paths, int filterIndex, const QVariantMap &choices);
    Q_INVOKABLE void cancel();

  signals:
    // mode ("open", "save", "saveMany"), title, acceptLabel, multiple,
    // directory, filters [{name, globs, mimes}], filterIndex, folder, name,
    // files (SaveMany), choices [{id, label, options [{id, label}], value}]
    void requested(const QVariantMap &request);
    // The request went (the app closed it, or a newer one replaced it).
    void closed();

  private:
    void finish(uint response, const QVariantMap &results);

    QDBusConnection        m_bus;
    QDBusMessage           m_message;
    QString                m_handle;
    Mode                   m_mode = Open;
    QList<PortalFilter>    m_filters;
    QStringList            m_files;
    QPointer<QObject>      m_requestObject;
};

// org.freedesktop.impl.portal.FileChooser on the object that serves the
// portal's other interfaces (/org/freedesktop/portal/desktop).
class FileChooserAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.impl.portal.FileChooser")
    Q_PROPERTY(uint version READ version CONSTANT)

  public:
    FileChooserAdaptor(QObject *parent, FileChooserPortal *portal);

    uint version() const {
        return 4;
    }

  public slots:
    uint OpenFile(const QDBusObjectPath &handle, const QString &appId, const QString &parentWindow,
                  const QString &title, const QVariantMap &options, const QDBusMessage &message,
                  QVariantMap &results);
    uint SaveFile(const QDBusObjectPath &handle, const QString &appId, const QString &parentWindow,
                  const QString &title, const QVariantMap &options, const QDBusMessage &message,
                  QVariantMap &results);
    uint SaveFiles(const QDBusObjectPath &handle, const QString &appId,
                   const QString &parentWindow, const QString &title, const QVariantMap &options,
                   const QDBusMessage &message, QVariantMap &results);

  private:
    FileChooserPortal *m_portal;
};
