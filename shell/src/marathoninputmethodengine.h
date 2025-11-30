// Marathon Input Method Engine - Qt Platform Integration
// Proper IME implementation for system-level text input
#ifndef MARATHONINPUTMETHODENGINE_H
#define MARATHONINPUTMETHODENGINE_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QRect>
#include <QInputMethod>

/**
 * @brief Marathon Input Method Engine
 * 
 * This class integrates with Qt's input method system to provide
 * proper text input from the virtual keyboard to any text field.
 * 
 * Key responsibilities:
 * - Register as system input method
 * - Handle focus changes
 * - Commit text to focused input fields
 * - Manage cursor position
 * - Provide input method hints
 */
class MarathonInputMethodEngine : public QObject {
    Q_OBJECT

    // Properties exposed to QML
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QString preeditText READ preeditText WRITE setPreeditText NOTIFY preeditTextChanged)
    Q_PROPERTY(bool hasActiveFocus READ hasActiveFocus NOTIFY hasActiveFocusChanged)
    Q_PROPERTY(int cursorPosition READ cursorPosition NOTIFY cursorPositionChanged)
    Q_PROPERTY(QRect inputItemRect READ inputItemRect NOTIFY inputItemRectChanged)

  public:
    explicit MarathonInputMethodEngine(QObject *parent = nullptr);
    ~MarathonInputMethodEngine();

    // Property getters
    bool active() const {
        return m_active;
    }
    QString preeditText() const {
        return m_preeditText;
    }
    bool  hasActiveFocus() const;
    int   cursorPosition() const;
    QRect inputItemRect() const;

    // Property setters
    void setActive(bool active);
    void setPreeditText(const QString &text);

    /**
     * @brief Commit text to the currently focused input field
     * @param text The text to commit
     * 
     * This is the primary method for inserting text from the keyboard.
     * It uses Qt.inputMethod to commit text properly.
     */
    Q_INVOKABLE void commitText(const QString &text);

    /**
     * @brief Send a backspace key event
     * 
     * Deletes the character before the cursor.
     */
    Q_INVOKABLE void sendBackspace();

    /**
     * @brief Send an enter/return key event
     */
    Q_INVOKABLE void sendEnter();

    /**
     * @brief Replace the current preedit text with a new word
     * @param word The new word to commit
     * 
     * Used for accepting predictions/autocorrections.
     */
    Q_INVOKABLE void replacePreedit(const QString &word);

    /**
     * @brief Get the text before the cursor
     * @param length Maximum length to retrieve
     * @return Text before cursor
     */
    Q_INVOKABLE QString getTextBeforeCursor(int length = 100);

    /**
     * @brief Get the text after the cursor
     * @param length Maximum length to retrieve
     * @return Text after cursor
     */
    Q_INVOKABLE QString getTextAfterCursor(int length = 100);

    /**
     * @brief Get the current word being typed
     * @return Current word (text from last space/newline to cursor)
     */
    Q_INVOKABLE QString getCurrentWord();

    /**
     * @brief Show/hide the virtual keyboard
     * @param show True to show, false to hide
     */
    Q_INVOKABLE void showKeyboard(bool show);

  signals:
    void activeChanged();
    void preeditTextChanged();
    void hasActiveFocusChanged();
    void cursorPositionChanged();
    void inputItemRectChanged();

    /**
     * @brief Emitted when an input field gains focus
     */
    void inputItemFocused();

    /**
     * @brief Emitted when an input field loses focus
     */
    void inputItemUnfocused();

    /**
     * @brief Emitted when the keyboard should be shown
     */
    void keyboardRequested();

    /**
     * @brief Emitted when the keyboard should be hidden
     */
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

#endif // MARATHONINPUTMETHODENGINE_H
