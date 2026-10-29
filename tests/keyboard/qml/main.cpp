#include <QInputMethodEvent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QtQuickTest/quicktest.h>

#include <algorithm>

#include "marathon-shell-native/src/words.cxxqt.h"
#include "services/inputcontext.h"

// A field that reports its text `lag` edits late, as an app over text-input
// v2 does when it answers slower than the typing. The cursor stays at the end.
class LaggingField : public QQuickItem {
    Q_OBJECT
    Q_PROPERTY(QString text READ text NOTIFY textChanged)
    Q_PROPERTY(int lag MEMBER m_lag)

  public:
    LaggingField() {
        setFlag(ItemAcceptsInputMethod);
    }

    QString text() const {
        return m_history.constLast();
    }

    Q_INVOKABLE void reset(const QString &text) {
        m_history = {text};
        emit textChanged();
    }

    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override {
        const QString reported = m_history.at(std::max<qsizetype>(0, m_history.size() - 1 - m_lag));
        switch (query) {
            case Qt::ImEnabled: return true;
            case Qt::ImSurroundingText:
            case Qt::ImTextBeforeCursor: return reported;
            case Qt::ImCursorPosition:
            case Qt::ImAnchorPosition: return int(reported.size());
            case Qt::ImCurrentSelection:
            case Qt::ImTextAfterCursor: return QString();
            default: return QQuickItem::inputMethodQuery(query);
        }
    }

  signals:
    void textChanged();

  protected:
    void inputMethodEvent(QInputMethodEvent *event) override {
        QString         t     = text();
        const qsizetype start = std::max<qsizetype>(0, t.size() + event->replacementStart());
        t.remove(start, event->replacementLength());
        t.insert(start, event->commitString());
        m_history << t;
        emit textChanged();
        event->accept();
    }

  private:
    QStringList m_history{QString()};
    int         m_lag = 0;
};

// The keyboard's native types join the stubbed MarathonOS.Shell module.
class Setup : public QObject {
    Q_OBJECT

  public slots:
    void applicationAvailable() {
        qmlRegisterType<InputContext>("MarathonOS.Shell", 1, 0, "InputContext");
        qmlRegisterSingletonType<marathon::Dictionary>(
            "MarathonOS.Shell", 1, 0, "Dictionary",
            [](QQmlEngine *, QJSEngine *) -> QObject * { return new marathon::Dictionary(); });
        qmlRegisterSingletonType<marathon::DomainSuggestions>(
            "MarathonOS.Shell", 1, 0, "DomainSuggestions",
            [](QQmlEngine *, QJSEngine *) -> QObject * {
                return new marathon::DomainSuggestions();
            });
        qmlRegisterType<LaggingField>("KeyboardTest", 1, 0, "LaggingField");
    }
};

QUICK_TEST_MAIN_WITH_SETUP(keyboard_qml_tests, Setup)

#include "main.moc"
