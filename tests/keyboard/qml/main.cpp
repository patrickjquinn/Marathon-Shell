#include <QQmlEngine>
#include <QtQuickTest>

#include "services/autocorrect.h"
#include "services/dictionary.h"
#include "services/domainsuggestions.h"
#include "services/inputcontext.h"

// The keyboard's C++ types join the stubbed MarathonOS.Shell module. The
// dictionary has no word engine, so corrections come from AutoCorrect's typo
// table alone and stay the same on every host.
class Setup : public QObject {
    Q_OBJECT

  public slots:
    void applicationAvailable() {
        qmlRegisterType<InputContext>("MarathonOS.Shell", 1, 0, "InputContext");
        qmlRegisterSingletonType<Dictionary>(
            "MarathonOS.Shell", 1, 0, "Dictionary",
            [](QQmlEngine *, QJSEngine *) { return new Dictionary(nullptr, nullptr, nullptr); });
        qmlRegisterSingletonType<AutoCorrect>(
            "MarathonOS.Shell", 1, 0, "AutoCorrect",
            [](QQmlEngine *, QJSEngine *) { return new AutoCorrect(nullptr); });
        qmlRegisterSingletonType<DomainSuggestions>(
            "MarathonOS.Shell", 1, 0, "DomainSuggestions",
            [](QQmlEngine *, QJSEngine *) { return new DomainSuggestions; });
    }
};

QUICK_TEST_MAIN_WITH_SETUP(keyboard_qml_tests, Setup)

#include "main.moc"
