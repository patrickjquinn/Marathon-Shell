// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Policy and libsailfishpolicy-qt6 against a fake policy store (a
// temporary /var/lib/policy, KEEL_POLICY_DIR) and a fake privacy switch
// daemon on a private session bus: values as MDM applications write them,
// changes followed, and fail-closed reads (no store, unreadable or broken
// policy.conf, a Qt 5 access policy plugin installed: every policy false or
// unknown, never true). jolla-camera's use: AccessPolicy.cameraEnabled and
// AccessPolicy.microphoneEnabled from QML.

#include <accesspolicy.h>
#include <policyvalue.h>

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

using Sailfish::AccessPolicy;
using Sailfish::PolicyValue;

namespace {

const char *const PrivacyService = "org.sailfishos.privacyswitch";

// privacyswitchd's D-Bus face, as Sailfish.Policy reads it.
class FakePrivacySwitch : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.sailfishos.privacyswitch")
public:
    bool active = true;

public slots:
    bool privacyModeActive() const { return active; }

signals:
    void privacyModeActiveChanged(bool);
};

} // namespace

class TestSailfishPolicy : public QObject
{
    Q_OBJECT

private slots:
    void initTestCase();
    void noStore();
    void noPoliciesSet();
    void mdmPolicies();
    void invalidValue();
    void brokenFile();
    void unreadableFile();
    void qt5PluginInstalled();
    void readOnly();
    void privacySwitch();
    void qml();
    void storeRemoved();

private:
    QString dir() const { return m_root.filePath(QStringLiteral("policy")); }
    QString file() const { return dir() + QStringLiteral("/policy.conf"); }
    // Writes policy.conf as GLib does: a new file renamed over the old.
    void writePolicies(const QByteArray &contents);

    QTemporaryDir m_root;
    QDBusConnection m_fakeBus = QDBusConnection(QString());
    FakePrivacySwitch m_privacy;
    std::unique_ptr<AccessPolicy> m_policy;
};

void TestSailfishPolicy::writePolicies(const QByteArray &contents)
{
    const QString temp = file() + QStringLiteral(".tmp");
    QFile f(temp);
    QVERIFY(f.open(QIODevice::WriteOnly | QIODevice::Truncate));
    f.write(contents);
    f.close();
    QFile::remove(file());
    QVERIFY(QFile::rename(temp, file()));
}

void TestSailfishPolicy::initTestCase()
{
    QVERIFY(m_root.isValid());
    qputenv("KEEL_POLICY_DIR", dir().toLocal8Bit());
    qputenv("KEEL_POLICY_PLUGIN", m_root.filePath(QStringLiteral("plugin/libsailfishpolicyplugin.so")).toLocal8Bit());

    m_fakeBus = QDBusConnection::connectToBus(QDBusConnection::SessionBus, QStringLiteral("fake-privacyswitch"));
    QVERIFY(m_fakeBus.isConnected());
    QVERIFY(m_fakeBus.registerObject(QStringLiteral("/privacyswitch"), &m_privacy,
                                     QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals));
    QVERIFY(m_fakeBus.registerService(QLatin1String(PrivacyService)));

    m_policy = std::make_unique<AccessPolicy>();
}

void TestSailfishPolicy::noStore()
{
    // No /var/lib/policy (sailfish-policy not installed): unknown.
    QVERIFY(!m_policy->cameraEnabled());
    QVERIFY(!m_policy->microphoneEnabled());
    QVERIFY(!m_policy->appsupportEnabled());
    PolicyValue value;
    value.setPolicyType(PolicyValue::CameraEnabled);
    QCOMPARE(value.key(), QStringLiteral("CameraEnabled"));
    QVERIFY(!value.value().isValid());
    QVERIFY(!PolicyValue::keyValue(PolicyValue::BrowserEnabled).isValid());
}

void TestSailfishPolicy::noPoliciesSet()
{
    // The directory, empty: no MDM restricts anything.
    QSignalSpy camera(m_policy.get(), &AccessPolicy::cameraEnabledChanged);
    PolicyValue value;
    value.setKey(QStringLiteral("ScreenshotEnabled"));
    QCOMPARE(value.policyType(), int(PolicyValue::ScreenshotEnabled));
    QSignalSpy valueChanged(&value, &PolicyValue::valueChanged);
    QVERIFY(QDir().mkpath(dir()));
    QTRY_VERIFY(m_policy->cameraEnabled());
    QCOMPARE(camera.count(), 1);
    QVERIFY(m_policy->microphoneEnabled());
    QVERIFY(m_policy->ringtoneLevelEnabled());
    QTRY_COMPARE(value.value(), QVariant(true));
    QCOMPARE(valueChanged.count(), 1);
}

void TestSailfishPolicy::mdmPolicies()
{
    QSignalSpy camera(m_policy.get(), &AccessPolicy::cameraEnabledChanged);
    QSignalSpy microphone(m_policy.get(), &AccessPolicy::microphoneEnabledChanged);
    PolicyValue usb;
    usb.setPolicyType(PolicyValue::UsbMtpEnabled);
    writePolicies("# MDM\n[policy]\nCameraEnabled=false\nMicrophoneEnabled=true\nUsbMtpEnabled=false\n"
                  "[other]\nBrowserEnabled=false\n");
    QTRY_VERIFY(!m_policy->cameraEnabled());
    QCOMPARE(camera.count(), 1);
    QCOMPARE(microphone.count(), 0);
    QVERIFY(m_policy->microphoneEnabled());
    QVERIFY(m_policy->browserEnabled()); // another group
    QTRY_COMPARE(usb.value(), QVariant(false));
    QCOMPARE(PolicyValue::keyValue(QStringLiteral("CameraEnabled")), QVariant(false));
    QCOMPARE(PolicyValue::keyValue(QStringLiteral("NoSuchPolicy")), QVariant());

    // The MDM lifts the camera policy.
    writePolicies("[policy]\nCameraEnabled=true\nUsbMtpEnabled=1\n");
    QTRY_VERIFY(m_policy->cameraEnabled());
    QCOMPARE(camera.count(), 2);
    QTRY_COMPARE(usb.value(), QVariant(true));
}

void TestSailfishPolicy::invalidValue()
{
    writePolicies("[policy]\nCameraEnabled=maybe\n");
    QTRY_VERIFY(!m_policy->cameraEnabled());
    QVERIFY(m_policy->microphoneEnabled());
    QCOMPARE(PolicyValue::keyValue(PolicyValue::CameraEnabled), QVariant(false));
}

void TestSailfishPolicy::brokenFile()
{
    writePolicies("[policy]\nthis is not a key file\n");
    QTRY_VERIFY(!m_policy->microphoneEnabled());
    QVERIFY(!m_policy->cameraEnabled());
    QVERIFY(!PolicyValue::keyValue(PolicyValue::MicrophoneEnabled).isValid());
    writePolicies("[policy]\n");
    QTRY_VERIFY(m_policy->microphoneEnabled());
}

void TestSailfishPolicy::unreadableFile()
{
    // (The tests may run as root, which reads any file: a directory in the
    // file's place cannot be read as one.)
    QVERIFY(QFile::remove(file()));
    QVERIFY(QDir().mkpath(file()));
    QTRY_VERIFY(!m_policy->cameraEnabled());
    QVERIFY(!m_policy->wlanToggleEnabled());
    QVERIFY(QDir(file()).removeRecursively());
    QTRY_VERIFY(m_policy->cameraEnabled());
}

void TestSailfishPolicy::qt5PluginInstalled()
{
    QVERIFY(QDir().mkpath(m_root.filePath(QStringLiteral("plugin"))));
    QFile plugin(m_root.filePath(QStringLiteral("plugin/libsailfishpolicyplugin.so")));
    QVERIFY(plugin.open(QIODevice::WriteOnly));
    plugin.close();
    writePolicies("[policy]\nCameraEnabled=true\n");
    QTRY_VERIFY(!m_policy->cameraEnabled());
    QVERIFY(!PolicyValue::keyValue(PolicyValue::CameraEnabled).isValid());
    QVERIFY(plugin.remove());
    writePolicies("[policy]\n");
    QTRY_VERIFY(m_policy->cameraEnabled());
}

void TestSailfishPolicy::readOnly()
{
    writePolicies("[policy]\nCameraEnabled=false\n");
    QTRY_VERIFY(!m_policy->cameraEnabled());
    QVERIFY(!m_policy->setCameraEnabled(true));
    QVERIFY(!PolicyValue::setKeyValue(PolicyValue::CameraEnabled, true));
    QVERIFY(!PolicyValue::enforcePolicy(QStringLiteral("CameraEnabled"), true));
    PolicyValue value;
    value.setPolicyType(PolicyValue::CameraEnabled);
    QVERIFY(!value.setValue(true));
    QFile f(file());
    QVERIFY(f.open(QIODevice::ReadOnly));
    QCOMPARE(f.readAll(), QByteArray("[policy]\nCameraEnabled=false\n"));
    QVERIFY(!m_policy->cameraEnabled());
}

void TestSailfishPolicy::privacySwitch()
{
    // Read when the store started; followed through the signal.
    QTRY_VERIFY(m_policy->privacyModeActive());
    QSignalSpy spy(m_policy.get(), &AccessPolicy::privacyModeActiveChanged);
    m_privacy.active = false;
    emit m_privacy.privacyModeActiveChanged(false);
    QTRY_COMPARE(spy.count(), 1);
    QVERIFY(!m_policy->privacyModeActive());
}

void TestSailfishPolicy::qml()
{
    writePolicies("[policy]\nCameraEnabled=false\n");
    QTRY_VERIFY(!m_policy->cameraEnabled());
    QQmlEngine engine;
    engine.addImportPath(QStringLiteral(KEEL_QML_DIR));
    QQmlComponent component(&engine);
    component.setData(R"(
import QtQuick 2.6
import Sailfish.Policy 1.0
Item {
    // jolla-camera: DisabledByMdmView's enabled and the video recorder.
    readonly property bool cameraDisabled: !AccessPolicy.cameraEnabled
    readonly property bool microphoneEnabled: AccessPolicy.microphoneEnabled
    readonly property var screenshots: PolicyValue { policyType: PolicyValue.ScreenshotEnabled }
    readonly property var camera: PolicyValue { key: "CameraEnabled" }
    property int changes
    Connections {
        target: AccessPolicy
        function onCameraEnabledChanged() { changes++ }
    }
}
)",
                      QUrl(QStringLiteral("file:///policy.qml")));
    std::unique_ptr<QObject> root(component.create());
    QVERIFY2(root, qPrintable(component.errorString()));
    QCOMPARE(root->property("cameraDisabled").toBool(), true);
    QCOMPARE(root->property("microphoneEnabled").toBool(), true);
    auto *screenshots = root->property("screenshots").value<QObject *>();
    QVERIFY(screenshots);
    QCOMPARE(screenshots->property("key").toString(), QStringLiteral("ScreenshotEnabled"));
    QCOMPARE(screenshots->property("value"), QVariant(true));
    auto *camera = root->property("camera").value<QObject *>();
    QCOMPARE(camera->property("policyType").toInt(), int(PolicyValue::CameraEnabled));
    QCOMPARE(camera->property("value"), QVariant(false));
    writePolicies("[policy]\n");
    QTRY_COMPARE(root->property("cameraDisabled").toBool(), false);
    QCOMPARE(root->property("changes").toInt(), 1);
    QTRY_COMPARE(camera->property("value"), QVariant(true));
}

void TestSailfishPolicy::storeRemoved()
{
    QTRY_VERIFY(m_policy->microphoneEnabled());
    QVERIFY(QDir(dir()).removeRecursively());
    QTRY_VERIFY(!m_policy->microphoneEnabled());
    QVERIFY(!m_policy->cameraEnabled());
    QVERIFY(!PolicyValue::keyValue(PolicyValue::CameraEnabled).isValid());
}

QTEST_GUILESS_MAIN(TestSailfishPolicy)
#include "tst_sailfishpolicy.moc"
