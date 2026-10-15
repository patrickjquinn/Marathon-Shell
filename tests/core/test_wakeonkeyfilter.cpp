#include "services/wakeonkeyfilter.h"

#include <QGuiApplication>
#include <QKeyEvent>
#include <QTest>
#include <QWindow>
#include <qpa/qwindowsysteminterface.h>

namespace {

    class KeyWindow : public QWindow {
      public:
        QList<int> pressed;
        QList<int> released;

      protected:
        void keyPressEvent(QKeyEvent *e) override {
            pressed << e->key();
        }
        void keyReleaseEvent(QKeyEvent *e) override {
            released << e->key();
        }
    };

    void sendKey(QWindow *w, QEvent::Type type, int key, quint32 scanCode, bool autoRepeat) {
        QWindowSystemInterface::handleExtendedKeyEvent(w, type, key, Qt::NoModifier, scanCode, 0, 0,
                                                       QString(), autoRepeat);
        QWindowSystemInterface::flushWindowSystemEvents();
    }

} // namespace

class TestWakeOnKeyFilter : public QObject {
    Q_OBJECT

    bool             m_screenOff = false;
    int              m_wakes     = 0;
    WakeOnKeyFilter *m_filter    = nullptr;
    KeyWindow       *m_window    = nullptr;

  private slots:
    void init() {
        m_screenOff = false;
        m_wakes     = 0;
        m_filter    = new WakeOnKeyFilter([this]() { return m_screenOff; },
                                          [this]() {
                                           ++m_wakes;
                                           m_screenOff = false;
                                          });
        qApp->installEventFilter(m_filter);
        m_window = new KeyWindow;
        m_window->show();
    }

    void cleanup() {
        delete m_window;
        delete m_filter;
    }

    void keyWhileOnReachesWindow() {
        QTest::keyClick(m_window, Qt::Key_A);
        QCOMPARE(m_wakes, 0);
        QCOMPARE(m_window->pressed, QList<int>{Qt::Key_A});
        QCOMPARE(m_window->released, QList<int>{Qt::Key_A});
    }

    void keyWhileOffWakesAndIsSwallowed() {
        m_screenOff = true;
        sendKey(m_window, QEvent::KeyPress, Qt::Key_A, 30, false);
        sendKey(m_window, QEvent::KeyRelease, Qt::Key_A, 30, true);
        sendKey(m_window, QEvent::KeyPress, Qt::Key_A, 30, true);
        sendKey(m_window, QEvent::KeyRelease, Qt::Key_A, 30, false);
        QCOMPARE(m_wakes, 1);
        QVERIFY(m_window->pressed.isEmpty());
        QVERIFY(m_window->released.isEmpty());

        QTest::keyClick(m_window, Qt::Key_B);
        QCOMPARE(m_wakes, 1);
        QCOMPARE(m_window->pressed, QList<int>{Qt::Key_B});
    }

    void otherKeysHeldAcrossWakeStillDeliver() {
        m_screenOff = true;
        QTest::keyPress(m_window, Qt::Key_A);
        QTest::keyClick(m_window, Qt::Key_B);
        QTest::keyRelease(m_window, Qt::Key_A);
        QCOMPARE(m_wakes, 1);
        QCOMPARE(m_window->pressed, QList<int>{Qt::Key_B});
        QCOMPARE(m_window->released, QList<int>{Qt::Key_B});
    }

    void powerKeyIsLeftToThePowerPath() {
        m_screenOff = true;
        QTest::keyClick(m_window, Qt::Key_PowerOff);
        QTest::keyClick(m_window, Qt::Key_Sleep);
        QCOMPARE(m_wakes, 0);
        QCOMPARE(m_window->pressed, (QList<int>{Qt::Key_PowerOff, Qt::Key_Sleep}));
    }

    void lostReleaseDoesNotEatTheNextPress() {
        m_screenOff = true;
        QTest::keyPress(m_window, Qt::Key_A);
        QTest::keyClick(m_window, Qt::Key_A);
        QCOMPARE(m_wakes, 1);
        QCOMPARE(m_window->pressed, QList<int>{Qt::Key_A});
    }

    void syntheticKeysAreIgnored() {
        m_screenOff = true;
        QKeyEvent press(QEvent::KeyPress, Qt::Key_A, Qt::NoModifier);
        QCoreApplication::sendEvent(m_window, &press);
        QCOMPARE(m_wakes, 0);
        QCOMPARE(m_window->pressed, QList<int>{Qt::Key_A});
    }
};

QTEST_MAIN(TestWakeOnKeyFilter)
#include "test_wakeonkeyfilter.moc"
