// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The C++ runtime and the Rust generator agree: KeelActions.describe() for
// the test app equals the generator's golden actions.json for the same QML
// (keel/actions/codegen/tests/golden/qml-notes).

#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QtTest>

#include <memory>

class TestDescribeGolden : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void describeMatchesGenerator()
    {
        QQmlEngine engine;
        engine.addImportPath(QStringLiteral(KEEL_QML_DIR));
        QQmlComponent component(&engine, QUrl::fromLocalFile(QStringLiteral(KEEL_ACTIONS_TEST_APP)));
        const std::unique_ptr<QObject> app(component.create());
        QVERIFY2(app, qPrintable(component.errorString()));

        QQmlComponent probe(&engine);
        probe.setData("import QtQml 2.15\nimport Keel.Actions 1.0\nQtObject { property string m: JSON.stringify(KeelActions.describe()) }",
                      QUrl());
        const std::unique_ptr<QObject> holder(probe.create());
        QVERIFY2(holder, qPrintable(probe.errorString()));
        const QJsonObject described = QJsonDocument::fromJson(holder->property("m").toString().toUtf8()).object();

        QFile file(QStringLiteral(KEEL_ACTIONS_GOLDEN));
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QJsonObject golden = QJsonDocument::fromJson(file.readAll()).object();
        QVERIFY(!golden.isEmpty());

        const QJsonArray a = described.value(QLatin1String("tools")).toArray();
        const QJsonArray b = golden.value(QLatin1String("tools")).toArray();
        QCOMPARE(a.size(), b.size());
        for (qsizetype i = 0; i < b.size(); ++i) {
            QCOMPARE(QJsonDocument(a.at(i).toObject()).toJson(QJsonDocument::Compact),
                     QJsonDocument(b.at(i).toObject()).toJson(QJsonDocument::Compact));
        }
        QCOMPARE(QJsonDocument(described).toJson(QJsonDocument::Compact),
                 QJsonDocument(golden).toJson(QJsonDocument::Compact));
    }
};

QTEST_MAIN(TestDescribeGolden)
#include "tst_describe_golden.moc"
