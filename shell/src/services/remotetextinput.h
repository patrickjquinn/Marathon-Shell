#pragma once

#include <QObject>
#include <QString>
#include <QVariant>

#include <functional>

class QInputMethodEvent;
class RemoteTextInput;

// Marathon's keyboard typing into an input method service's editor (Deckard's
// Android apps): the keyboard's queries, commits and keys for that editor's
// window go to RemoteTextInput (Rust), which serves the service.
class RemoteTextInputFilter : public QObject {
    Q_OBJECT

  public:
    // The app id of the window a focus object shows, or empty.
    using AppIdOf = std::function<QString(QObject *)>;
    // Keys sent from a QInputDevice of this name come from the on-screen keyboard.
    // NOLINTNEXTLINE(bugprone-throwing-static-initialization) QStringLiteral never allocates
    static inline const QString kKeyboardDevice = QStringLiteral("marathon-osk");

    RemoteTextInputFilter(RemoteTextInput *input, AppIdOf appIdOf, QObject *parent = nullptr);
    ~RemoteTextInputFilter() override;

    // Qt's focus is on the editor's window.
    bool targetsFocus() const;

    // zwp_text_input_v3 content purpose and hints as Qt hints.
    static Qt::InputMethodHints qtHints(uint purpose, uint hints);

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private:
    bool             targets(QObject *object) const;
    QVariant         query(Qt::InputMethodQuery query) const;
    void             commit(const QInputMethodEvent &event);

    RemoteTextInput *m_input;
    AppIdOf          m_appIdOf;
};
