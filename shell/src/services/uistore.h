#pragma once

#include <QObject>
#include <QString>
#include <QVariant>
#include <qqml.h>

class UIStore : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool quickSettingsOpen READ quickSettingsOpen NOTIFY quickSettingsOpenChanged)
    Q_PROPERTY(double quickSettingsHeight READ quickSettingsHeight WRITE setQuickSettingsHeight
                   NOTIFY quickSettingsHeightChanged)
    Q_PROPERTY(bool quickSettingsDragging READ quickSettingsDragging WRITE setQuickSettingsDragging
                   NOTIFY quickSettingsDraggingChanged)
    Q_PROPERTY(bool appWindowOpen READ appWindowOpen NOTIFY appWindowOpenChanged)
    Q_PROPERTY(QString currentAppId READ currentAppId NOTIFY currentAppIdChanged)
    Q_PROPERTY(QString currentAppName READ currentAppName NOTIFY currentAppNameChanged)
    Q_PROPERTY(QString currentAppIcon READ currentAppIcon NOTIFY currentAppIconChanged)
    Q_PROPERTY(bool settingsOpen READ settingsOpen NOTIFY settingsOpenChanged)
    Q_PROPERTY(bool searchOpen READ searchOpen NOTIFY searchOpenChanged)
    Q_PROPERTY(bool shareSheetOpen READ shareSheetOpen NOTIFY shareSheetOpenChanged)
    Q_PROPERTY(
        bool clipboardManagerOpen READ clipboardManagerOpen NOTIFY clipboardManagerOpenChanged)
    Q_PROPERTY(QObject *shellRef READ shellRef WRITE setShellRef NOTIFY shellRefChanged)

  public:
    explicit UIStore(QObject *parent = nullptr);

    bool quickSettingsOpen() const {
        return m_quickSettingsOpen;
    }
    double quickSettingsHeight() const {
        return m_quickSettingsHeight;
    }
    bool quickSettingsDragging() const {
        return m_quickSettingsDragging;
    }
    bool appWindowOpen() const {
        return m_appWindowOpen;
    }
    QString currentAppId() const {
        return m_currentAppId;
    }
    QString currentAppName() const {
        return m_currentAppName;
    }
    QString currentAppIcon() const {
        return m_currentAppIcon;
    }
    bool settingsOpen() const {
        return m_settingsOpen;
    }
    bool searchOpen() const {
        return m_searchOpen;
    }
    bool shareSheetOpen() const {
        return m_shareSheetOpen;
    }
    bool clipboardManagerOpen() const {
        return m_clipboardManagerOpen;
    }
    QObject *shellRef() const {
        return m_shellRef;
    }
    void             setShellRef(QObject *shellRef);

    Q_INVOKABLE void openSearch();
    Q_INVOKABLE void closeSearch();
    Q_INVOKABLE void toggleSearch();
    Q_INVOKABLE void openShareSheet(const QVariant &content, const QString &contentType);
    Q_INVOKABLE void closeShareSheet();
    Q_INVOKABLE void openClipboardManager();
    Q_INVOKABLE void closeClipboardManager();
    Q_INVOKABLE void openQuickSettings();
    Q_INVOKABLE void closeQuickSettings();
    Q_INVOKABLE void toggleQuickSettings();
    Q_INVOKABLE void openApp(const QString &appId, const QString &appName, const QString &appIcon);
    Q_INVOKABLE void openApp(const QVariant &appId, const QVariant &appName,
                             const QVariant &appIcon);
    Q_INVOKABLE void closeApp();
    Q_INVOKABLE void minimizeApp();
    Q_INVOKABLE void restoreApp(const QString &appId, const QString &appName,
                                const QString &appIcon);
    Q_INVOKABLE void restoreApp(const QVariant &appId, const QVariant &appName,
                                const QVariant &appIcon);
    Q_INVOKABLE void openSettings();
    Q_INVOKABLE void closeSettings();
    Q_INVOKABLE void minimizeSettings();
    Q_INVOKABLE void closeAll();

  signals:
    void quickSettingsOpenChanged();
    void quickSettingsHeightChanged();
    void quickSettingsDraggingChanged();
    void appWindowOpenChanged();
    void currentAppIdChanged();
    void currentAppNameChanged();
    void currentAppIconChanged();
    void settingsOpenChanged();
    void searchOpenChanged();
    void shareSheetOpenChanged();
    void clipboardManagerOpenChanged();
    void shellRefChanged();

    void showNotificationToast(const QVariant &notification);
    void showSystemHUD(const QString &type, double value);
    void showConfirmDialog(const QString &title, const QString &message, const QVariant &onConfirm);
    void showShareSheet(const QVariant &content, const QString &contentType);

  private:
    void     setQuickSettingsOpen(bool open);
    void     setQuickSettingsHeight(double height);
    void     setQuickSettingsDragging(bool dragging);
    void     setAppWindowOpen(bool open);
    void     setCurrentAppId(const QString &appId);
    void     setCurrentAppName(const QString &appName);
    void     setCurrentAppIcon(const QString &appIcon);
    void     setSettingsOpen(bool open);
    void     setSearchOpen(bool open);
    void     setShareSheetOpen(bool open);
    void     setClipboardManagerOpen(bool open);

    bool     m_quickSettingsOpen     = false;
    double   m_quickSettingsHeight   = 0.0;
    bool     m_quickSettingsDragging = false;
    bool     m_appWindowOpen         = false;
    QString  m_currentAppId;
    QString  m_currentAppName;
    QString  m_currentAppIcon;
    bool     m_settingsOpen         = false;
    bool     m_searchOpen           = false;
    bool     m_shareSheetOpen       = false;
    bool     m_clipboardManagerOpen = false;
    QObject *m_shellRef             = nullptr;
};
