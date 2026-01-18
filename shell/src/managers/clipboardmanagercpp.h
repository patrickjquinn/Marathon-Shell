#ifndef CLIPBOARDMANAGERCPP_H
#define CLIPBOARDMANAGERCPP_H

#include <QObject>
#include <QVariantList>

class SettingsManager;

class ClipboardManagerCpp : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(int maxHistorySize READ maxHistorySize CONSTANT)

  public:
    explicit ClipboardManagerCpp(SettingsManager *settings, QObject *parent = nullptr);

    QVariantList history() const {
        return m_history;
    }
    int maxHistorySize() const {
        return m_maxHistorySize;
    }

    Q_INVOKABLE QVariantList getHistory() const;
    Q_INVOKABLE void         copyToClipboard(const QString &text, const QString &type = "text");
    Q_INVOKABLE void         deleteItem(int index);
    Q_INVOKABLE void         clearHistory();

  signals:
    void historyChanged();
    void historyCleared();

  private:
    void             load();
    void             save();
    void             addToHistory(const QString &text, const QString &type);
    QVariantList     parseHistory(const QVariant &raw) const;

    SettingsManager *m_settings = nullptr;
    QVariantList     m_history;
    int              m_maxHistorySize = 20;
};

#endif
