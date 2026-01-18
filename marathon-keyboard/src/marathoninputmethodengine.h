

#ifndef MARATHONINPUTMETHODENGINE_H
#define MARATHONINPUTMETHODENGINE_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QRect>
#include <QInputMethod>

class MarathonInputMethodEngine : public QObject {
    Q_OBJECT

    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QString preeditText READ preeditText WRITE setPreeditText NOTIFY preeditTextChanged)
    Q_PROPERTY(bool hasActiveFocus READ hasActiveFocus NOTIFY hasActiveFocusChanged)
    Q_PROPERTY(int cursorPosition READ cursorPosition NOTIFY cursorPositionChanged)
    Q_PROPERTY(QRect inputItemRect READ inputItemRect NOTIFY inputItemRectChanged)

  public:
    explicit MarathonInputMethodEngine(QObject *parent = nullptr);
    ~MarathonInputMethodEngine();

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

    Q_INVOKABLE void    commitText(const QString &text);

    Q_INVOKABLE void    sendBackspace();

    Q_INVOKABLE void    sendEnter();

    Q_INVOKABLE void    replacePreedit(const QString &word);

    Q_INVOKABLE QString getTextBeforeCursor(int length = 100);

    Q_INVOKABLE QString getTextAfterCursor(int length = 100);

    Q_INVOKABLE QString getCurrentWord();

    Q_INVOKABLE void    showKeyboard(bool show);

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
    void onInputMethodAnimatingChanged();
    void onCursorRectangleChanged();

  private:
    void          connectToInputMethod();
    void          disconnectFromInputMethod();

    bool          m_active;
    QString       m_preeditText;
    QInputMethod *m_inputMethod;
};

#endif
