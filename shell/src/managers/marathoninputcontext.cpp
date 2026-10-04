// The shell's platform input context, built in as a static plugin.
//
// Qt's compositor asks for the on-screen keyboard through QInputMethod:
// text-input v2 clients send show/hide_input_panel when a field is tapped,
// and text-input v3 enable calls show(). With no platform input context those
// calls go nowhere, so the shell had to guess from text-input state, and its
// guesses re-opened the keyboard when a focused field merely went away. This
// context only reports the requests as QInputMethod::visibleChanged, which
// MarathonInputMethodEngine already turns into keyboard show/hide. It creates
// no window, unlike the qtvirtualkeyboard plugin that eglfs rejects.

#include <qpa/qplatforminputcontext.h>
#include <qpa/qplatforminputcontextplugin_p.h>

class MarathonInputContext : public QPlatformInputContext {
    Q_OBJECT

  public:
    bool isValid() const override {
        return true;
    }

    bool isInputPanelVisible() const override {
        return m_visible;
    }

    // Emit even when already visible: the user can dismiss the keyboard from
    // the shell without this context hearing about it, and a later tap on a
    // field must still bring it back.
    void showInputPanel() override {
        m_visible = true;
        emitInputPanelVisibleChanged();
    }

    void hideInputPanel() override {
        m_visible = false;
        emitInputPanelVisibleChanged();
    }

  private:
    bool m_visible = false;
};

class MarathonInputContextPlugin : public QPlatformInputContextPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QPlatformInputContextFactoryInterface_iid FILE
                      "marathoninputcontext.json")

  public:
    QPlatformInputContext *create(const QString &key, const QStringList &) override {
        return key == QLatin1String("marathon") ? new MarathonInputContext : nullptr;
    }
};

#include "marathoninputcontext.moc"
