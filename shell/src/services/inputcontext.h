#pragma once

#include <QObject>
#include <QString>
#include <qqml.h>

class QInputMethod;

class InputContext : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QObject *keyboard READ keyboard WRITE setKeyboard NOTIFY keyboardChanged)
    Q_PROPERTY(QString inputMode READ inputMode WRITE setInputMode NOTIFY inputModeChanged)
    Q_PROPERTY(QString recommendedLayout READ recommendedLayout NOTIFY inputModeChanged)
    Q_PROPERTY(bool shouldAutoCapitalize READ shouldAutoCapitalize NOTIFY inputModeChanged)
    Q_PROPERTY(bool shouldAutoCorrect READ shouldAutoCorrect NOTIFY inputModeChanged)
    Q_PROPERTY(bool shouldShowPredictions READ shouldShowPredictions NOTIFY inputModeChanged)
    Q_PROPERTY(bool hasActiveFocus READ hasActiveFocus NOTIFY hasActiveFocusChanged)

  public:
    explicit InputContext(QObject *parent = nullptr);

    QObject *keyboard() const {
        return m_keyboard;
    }
    void    setKeyboard(QObject *keyboard);

    QString inputMode() const {
        return m_inputMode;
    }
    void                setInputMode(const QString &mode);

    QString             recommendedLayout() const;
    bool                shouldAutoCapitalize() const;
    bool                shouldAutoCorrect() const;
    bool                shouldShowPredictions() const;
    bool                hasActiveFocus() const;

    Q_INVOKABLE void    insertText(const QString &text);
    Q_INVOKABLE void    handleBackspace();
    Q_INVOKABLE void    handleEnter();
    Q_INVOKABLE void    sendCursorKey(int key);
    Q_INVOKABLE void    replaceCurrentWord(const QString &newWord);
    Q_INVOKABLE QString getCurrentWord() const;
    Q_INVOKABLE void    detectInputMode();

  signals:
    void keyboardChanged();
    void inputModeChanged();
    void hasActiveFocusChanged();
    void textInserted(const QString &text);
    void backspacePressed();
    void enterPressed();
    void cursorKeyPressed(int key);

  private:
    void          setInputModeInternal(const QString &mode);

    QObject      *m_keyboard    = nullptr;
    QInputMethod *m_inputMethod = nullptr;
    QString       m_inputMode   = QStringLiteral("text");
};
