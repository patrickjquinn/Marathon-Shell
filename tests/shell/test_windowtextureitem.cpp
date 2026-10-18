#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickView>
#include <QSGRendererInterface>
#include <QTest>

#include "../../shell/src/components/windowtexturegeometry.h"
#include "../../shell/src/components/windowtextureitem.h"

namespace G = WindowTextureGeometry;

class TestWindowTextureItem : public QObject {
    Q_OBJECT

  private slots:
    void initTestCase() {
        qmlRegisterType<WindowTextureItem>("Test", 1, 0, "WindowTextureItem");
    }

    void cropMapsIntoTheAtlasSubRect() {
        const QRectF t = G::textureRect(QRectF(0.5, 0.25, 0.5, 0.5), QRectF(0, 0, 1, 0.5), false);
        QCOMPARE(t, QRectF(0.5, 0.25, 0.5, 0.25));
    }

    void bottomLeftOriginFlipsTheCrop() {
        // The top half of a bottom-left-origin buffer is v 1 -> 0.5.
        const QRectF t = G::textureRect(QRectF(0, 0, 1, 1), QRectF(0, 0, 1, 0.5), true);
        QCOMPARE(t.top(), 1.0);
        QCOMPARE(t.top() + t.height(), 0.5);
    }

    void octagonInsetsByTheRadius() {
        G::Vertex       body[G::BodyVertices];
        G::CornerVertex corners[G::CornerVertices];
        const qreal r = G::build(QRectF(10, 20, 100, 200), QRectF(0, 0, 1, 1), 10, body, corners);
        QCOMPARE(r, 10.0);
        // Outer left at inner top: (10, 30), texcoord (0, 0.05).
        QCOMPARE(body[1].x, 10.f);
        QCOMPARE(body[1].y, 30.f);
        QCOMPARE(body[1].tx, 0.f);
        QCOMPARE(body[1].ty, 0.05f);
        // Inner right at outer top: (100, 20), texcoord (0.9, 0).
        QCOMPARE(body[5].x, 100.f);
        QCOMPARE(body[5].y, 20.f);
        QCOMPARE(body[5].tx, 0.9f);
        QCOMPARE(body[5].ty, 0.f);
        // Outer right at inner bottom: (110, 210).
        QCOMPARE(body[6].x, 110.f);
        QCOMPARE(body[6].y, 210.f);
    }

    void cornersRunFromTheInnerEdgesToTheOuterCorner() {
        G::Vertex       body[G::BodyVertices];
        G::CornerVertex corners[G::CornerVertices];
        G::build(QRectF(0, 0, 100, 100), QRectF(0, 0, 1, 1), 20, body, corners);
        // Top-right triangle: outer corner, then the two inner-edge points.
        const G::CornerVertex &o = corners[9], &e1 = corners[10], &e2 = corners[11];
        QCOMPARE(QPointF(o.x, o.y), QPointF(100, 0));
        QCOMPARE(QPointF(o.cx, o.cy), QPointF(1, 1));
        QCOMPARE(QPointF(e1.x, e1.y), QPointF(100, 20));
        QCOMPARE(QPointF(e1.cx, e1.cy), QPointF(1, 0));
        QCOMPARE(QPointF(e2.x, e2.y), QPointF(80, 0));
        QCOMPARE(QPointF(e2.cx, e2.cy), QPointF(0, 1));
        QCOMPARE(QPointF(o.tx, o.ty), QPointF(1, 0));
        QCOMPARE(e2.tx, 0.8f);
    }

    void cornerTexcoordsFollowTheCrop() {
        G::Vertex       body[G::BodyVertices];
        G::CornerVertex corners[G::CornerVertices];
        // 100 px showing the top half of the texture: 10 px is 0.05 of v.
        G::build(QRectF(0, 0, 100, 100), QRectF(0, 0, 1, 0.5), 10, body, corners);
        QCOMPARE(corners[4].ty, 0.05f); // top-left, outer left at inner top
        QCOMPARE(corners[1].ty, 0.45f); // bottom-left, outer left at inner bottom
        QCOMPARE(corners[0].ty, 0.5f);
    }

    void radiusClampsToHalfTheShortSide() {
        QCOMPARE(G::clampRadius(QRectF(0, 0, 30, 100), 40), 15.0);
        QCOMPARE(G::clampRadius(QRectF(0, 0, 30, 100), -1), 0.0);
    }

    void arcFadesOverOnePixel() {
        const QPointF e = G::cornerEdges(10, 1);
        // dot(c, c) at 10.5 px is fully out, at 9.5 px fully in.
        QCOMPARE(e.x(), 1.05 * 1.05);
        QCOMPARE(e.y(), 0.95 * 0.95);
        QCOMPARE(G::cornerEdges(0, 1), QPointF(1, 1));
    }

    void shownFollowsAncestorsOpacityAndVisibility() {
        QQmlEngine    engine;
        QQmlComponent c(&engine);
        c.setData(
            "import QtQuick\nimport Test\nItem { property alias src: src; property alias tex: tex;"
            " Item { id: src } WindowTextureItem { id: tex; source: src } }",
            QUrl());
        std::unique_ptr<QObject> root(c.create());
        QVERIFY2(root, qPrintable(c.errorString()));
        QQuickView view;
        auto      *item = qobject_cast<QQuickItem *>(root.get());
        item->setParentItem(view.contentItem());
        auto *src = root->property("src").value<QQuickItem *>();
        auto *tex = root->property("tex").value<QQuickItem *>();
        QVERIFY(WindowTextureItem::isShown(src));
        QVERIFY(WindowTextureItem::isSampled(src));
        src->setOpacity(0);
        QVERIFY(!WindowTextureItem::isShown(src));
        QVERIFY(WindowTextureItem::isSampled(src));
        item->setOpacity(0);
        QVERIFY(!WindowTextureItem::isSampled(src));
        item->setOpacity(1);
        tex->setVisible(false);
        QVERIFY(!WindowTextureItem::isSampled(src));
        tex->setVisible(true);
        static_cast<WindowTextureItem *>(tex)->setSource(nullptr);
        QVERIFY(!WindowTextureItem::isSampled(src));
    }

    // Draws a layer's texture rounded: the corner shows what is behind, the
    // body the source, and the arc a blend.
    void drawsTheSourceRounded() {
        QQuickView view;
        if (view.rendererInterface()->graphicsApi() == QSGRendererInterface::Software)
            QSKIP("software scene graph: no corner shader");
        view.setColor(Qt::black);
        view.setResizeMode(QQuickView::SizeRootObjectToView);
        view.setSource(QUrl(QStringLiteral("data:text/plain,")));
        QQmlComponent c(view.engine());
        c.setData("import QtQuick\nimport Test\nItem { anchors.fill: parent;"
                  " Rectangle { id: src; width: 100; height: 100; color: '#ff0000'; opacity: 0;"
                  " layer.enabled: true; Rectangle { width: 100; height: 20; color: '#00ff00' } }"
                  " WindowTextureItem { x: 0; y: 0; width: 100; height: 100; radius: 30;"
                  " source: src } }",
                  QUrl());
        auto *root = qobject_cast<QQuickItem *>(c.create());
        QVERIFY2(root, qPrintable(c.errorString()));
        root->setParentItem(view.contentItem());
        root->setSize(QSizeF(100, 100));
        view.resize(100, 100);
        view.show();
        QVERIFY(QTest::qWaitForWindowExposed(&view));
        QTRY_VERIFY_WITH_TIMEOUT(view.grabWindow().pixelColor(50, 50).red() > 200, 3000);
        const QImage img = view.grabWindow();
        QCOMPARE(img.pixelColor(1, 1).red(), 0);
        QCOMPARE(img.pixelColor(98, 98).red(), 0);
        QVERIFY(img.pixelColor(10, 50).red() > 200);
        QVERIFY(img.pixelColor(50, 90).red() > 200);
        // Upright: the source's top strip is at the top.
        QVERIFY(img.pixelColor(50, 10).green() > 200);
        // Pixel (9, 8) is centred 29.7 px from the arc's centre: inside the fade.
        const int mid = img.pixelColor(9, 8).green();
        QVERIFY2(mid > 0 && mid < 255, qPrintable(QString::number(mid)));
    }
};

QTEST_MAIN(TestWindowTextureItem)
#include "test_windowtextureitem.moc"
