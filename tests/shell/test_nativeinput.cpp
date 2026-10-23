#include <QtTest>

#include "nativeinput.h"

class TestNativeInput : public QObject {
    Q_OBJECT

  private slots:
    void cosmicUsesPointerFallback() {
        QVERIFY(NativeInput::needsPointerFallback(
            {QStringLiteral("AudioVideo"), QStringLiteral("COSMIC")}));
        QVERIFY(NativeInput::needsPointerFallback({QStringLiteral("cosmic")}));
    }

    void otherToolkitsKeepNativeTouch() {
        QVERIFY(!NativeInput::needsPointerFallback({}));
        QVERIFY(!NativeInput::needsPointerFallback(
            {QStringLiteral("GTK"), QStringLiteral("GNOME"), QStringLiteral("Qt")}));
        QVERIFY(!NativeInput::needsPointerFallback({QStringLiteral("cosmic-ray")}));
    }
};

QTEST_GUILESS_MAIN(TestNativeInput)
#include "test_nativeinput.moc"
