#include <QImage>
#include <QQuickItem>
#include <QQuickView>
#include <QSGSimpleTextureNode>
#include <QSGTextureProvider>
#include <QTest>

#include <algorithm>
#include <cstring>

#include "../../shell/src/components/windowtextureitem.h"

namespace {

    // Zeroed and never freed on delete, so any later use of a deleted texture
    // crashes on its null vtable instead of reading recycled memory.
    class PoisonTexture : public QSGTexture {
      public:
        explicit PoisonTexture(QSGTexture *inner)
            : m_inner(inner) {}
        ~PoisonTexture() override {
            delete m_inner;
        }
        static void operator delete(void *p) {
            std::memset(p, 0, sizeof(PoisonTexture));
        }
        qint64 comparisonKey() const override {
            return m_inner->comparisonKey();
        }
        QRhiTexture *rhiTexture() const override {
            return m_inner->rhiTexture();
        }
        QSize textureSize() const override {
            return m_inner->textureSize();
        }
        bool hasAlphaChannel() const override {
            return m_inner->hasAlphaChannel();
        }
        bool hasMipmaps() const override {
            return m_inner->hasMipmaps();
        }
        void commitTextureOperations(QRhi *rhi, QRhiResourceUpdateBatch *batch) override {
            m_inner->commitTextureOperations(rhi, batch);
        }

      private:
        QSGTexture *m_inner;
    };

    // QWaylandSurfaceTextureProvider: on a commit it deletes the old texture,
    // then emits textureChanged, from inside the item's updatePaintNode.
    class CommitProvider : public QSGTextureProvider {
      public:
        ~CommitProvider() override {
            delete m_texture;
        }
        QSGTexture *texture() const override {
            return m_texture;
        }
        void commit(QQuickWindow *window, const QImage &image) {
            delete m_texture;
            m_texture = new PoisonTexture(window->createTextureFromImage(image));
            emit textureChanged();
        }

      private:
        QSGTexture *m_texture = nullptr;
    };

    class SurfaceItem : public QQuickItem {
      public:
        explicit SurfaceItem(QQuickItem *parent)
            : QQuickItem(parent)
            , m_image(64, 64, QImage::Format_RGB32) {
            setFlag(ItemHasContents);
            m_image.fill(Qt::red);
        }
        ~SurfaceItem() override {
            delete m_provider;
        }
        bool isTextureProvider() const override {
            return true;
        }
        QSGTextureProvider *textureProvider() const override {
            if (!m_provider)
                m_provider = new CommitProvider;
            return m_provider;
        }

        // A mapped client: commits a buffer on every frame.
        bool mapped = true;

      protected:
        QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override {
            if (!mapped) {
                delete oldNode;
                return nullptr;
            }
            auto *node =
                oldNode ? static_cast<QSGSimpleTextureNode *>(oldNode) : new QSGSimpleTextureNode;
            textureProvider();
            m_provider->commit(window(), m_image);
            node->setTexture(m_provider->texture());
            node->setRect(boundingRect());
            return node;
        }

      private:
        QImage                  m_image;
        mutable CommitProvider *m_provider = nullptr;
    };

} // namespace

class TestWindowTextureStress : public QObject {
    Q_OBJECT

  private slots:
    // Two consumers and the surface's own node share one batch; every frame
    // the texture they all point at is deleted before anyone is told.
    void survivesATextureReplacedEveryCommit() {
        QQuickView view;
        view.resize(300, 300);
        auto *surface = new SurfaceItem(view.contentItem());
        surface->setSize(QSizeF(100, 100));
        for (int i = 0; i < 2; ++i) {
            auto *consumer = new WindowTextureItem(view.contentItem());
            consumer->setPosition(QPointF(100 + 100 * i, 0));
            consumer->setSize(QSizeF(100, 100));
            consumer->setRadius(10);
            consumer->setSource(surface);
        }
        int frames = 0;
        connect(
            &view, &QQuickWindow::afterRendering, this, [&frames]() { ++frames; },
            Qt::DirectConnection);
        view.show();
        QVERIFY(QTest::qWaitForWindowExposed(&view));

        for (int i = 0; i < 300; ++i) {
            const int before = frames;
            surface->update();
            QVERIFY(QTest::qWaitFor([&]() { return frames > before; }, 2000));
        }
        const auto consumers = view.contentItem()->findChildren<WindowTextureItem *>();
        QTRY_VERIFY(std::all_of(consumers.begin(), consumers.end(),
                                [](WindowTextureItem *c) { return c->isReady(); }));

        // The provider goes with its item: the consumers drop to nothing.
        delete surface;
        for (int i = 0; i < 5; ++i) {
            const int before = frames;
            view.contentItem()->update();
            for (auto *c : consumers)
                c->update();
            QVERIFY(QTest::qWaitFor([&]() { return frames > before; }, 2000));
        }
        QTRY_VERIFY(std::none_of(consumers.begin(), consumers.end(),
                                 [](WindowTextureItem *c) { return c->isReady(); }));
    }

    // A launch: the surface maps hidden under a splash, sampled by a
    // consumer that synced before it had any texture and is not touched
    // again. The consumer still follows, and its ready with it.
    void followsASurfaceThatMapsUnderASplash() {
        QQuickView view;
        view.resize(300, 300);
        auto *surface = new SurfaceItem(view.contentItem());
        surface->setSize(QSizeF(100, 100));
        surface->setOpacity(0);
        surface->mapped = false;
        auto *consumer  = new WindowTextureItem(view.contentItem());
        consumer->setSize(QSizeF(100, 100));
        consumer->setRadius(10);
        consumer->setSource(surface);
        auto *splash = new QQuickItem(view.contentItem());
        splash->setSize(QSizeF(300, 300));
        int frames = 0;
        connect(
            &view, &QQuickWindow::afterRendering, this, [&frames]() { ++frames; },
            Qt::DirectConnection);
        view.show();
        QVERIFY(QTest::qWaitForWindowExposed(&view));
        const auto frame = [&]() {
            const int before = frames;
            surface->update();
            return QTest::qWaitFor([&]() { return frames > before; }, 2000);
        };
        for (int i = 0; i < 5; ++i)
            QVERIFY(frame());
        QVERIFY(!consumer->isReady());

        surface->mapped = true;
        for (int i = 0; i < 100; ++i)
            QVERIFY(frame());
        QTRY_VERIFY(consumer->isReady());

        surface->mapped = false;
        QVERIFY(frame());
        surface->mapped = true;
        for (int i = 0; i < 100; ++i)
            QVERIFY(frame());
        QTRY_VERIFY(consumer->isReady());
    }
};

QTEST_MAIN(TestWindowTextureStress)
#include "test_windowtexturestress.moc"
