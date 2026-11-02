#ifndef MARATHONINPUTMETHODENGINE_H
#define MARATHONINPUTMETHODENGINE_H

#include <QInputMethod>
#include <QObject>
#include <QRect>
#include <QString>
#include <QStringList>

class QKeyEvent;
namespace marathon {
    class Settings;
}

class MarathonInputMethodEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QString preeditText READ preeditText WRITE setPreeditText NOTIFY preeditTextChanged)
    Q_PROPERTY(bool hasActiveFocus READ hasActiveFocus NOTIFY hasActiveFocusChanged)
    Q_PROPERTY(int cursorPosition READ cursorPosition NOTIFY cursorPositionChanged)
    Q_PROPERTY(QRect inputItemRect READ inputItemRect NOTIFY inputItemRectChanged)

  public:
    explicit MarathonInputMethodEngine(const marathon::Settings *settings,
                                       QObject                  *parent = nullptr);
    ~MarathonInputMethodEngine() override;

    bool active() const {
        return m_active;
    }
    QString preeditText() const {
        return m_preeditText;
    }
    bool                hasActiveFocus() const;
    int                 cursorPosition() const;
    QRect               inputItemRect() const;

    void                setActive(bool active);
    void                setPreeditText(const QString &text);

    Q_INVOKABLE QString getCurrentWord();
    // Qt::InputMethodHints of the focused field (an app's text-input hints arrive through its surface item).
    Q_INVOKABLE int  focusHints() const;
    Q_INVOKABLE void showKeyboard(bool show);

  signals:
    void activeChanged();
    void preeditTextChanged();
    void hasActiveFocusChanged();
    void cursorPositionChanged();
    void inputItemRectChanged();
    void inputItemFocused();
    void inputItemUnfocused();
    void keyboardRequested();
    void keyboardHideRequested();

  private slots:
    void onInputMethodVisibleChanged();
    void onCursorRectangleChanged();

  protected:
    bool eventFilter(QObject *obj, QEvent *event) override;

  private:
    void                      connectToInputMethod();
    void                      disconnectFromInputMethod();
    bool                      capitalise(QObject *obj, const QKeyEvent *key);

    bool                      m_active;
    QString                   m_preeditText;
    QInputMethod             *m_inputMethod;
    const marathon::Settings *m_settings;
    // The hardware key typed as a capital, whose release and repeats the app must not see.
    quint32 m_heldCapital = 0;
    // The text before the cursor at the last capital: a field reporting it still has not caught up.
    QString m_capitalisedAt;
};

#endif
