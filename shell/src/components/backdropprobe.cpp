#include "backdropprobe.h"

#include "marathon-shell-native/src/backdrop.cxxqt.h"

#include <QDebug>
#include <QElapsedTimer>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QPointer>
#include <QQuickWindow>
#include <QRunnable>
#include <cstdint>

namespace {
    constexpr qint64 kIntervalMs = 250;
    constexpr int    kCollectMs  = 32;
    const bool       kStats      = qEnvironmentVariableIntValue("MARATHON_BACKDROP_STATS") != 0;
} // namespace

// Render-thread half: created in sync, deleted by a render job or on scene
// graph invalidation, so it only ever runs with the GL context current.
class BackdropReader : public QObject {
    Q_OBJECT

  public:
    ~BackdropReader() override {
        QOpenGLContext *ctx = QOpenGLContext::currentContext();
        if (!ctx)
            return;
        QOpenGLExtraFunctions *gl = ctx->extraFunctions();
        if (m_fence)
            gl->glDeleteSync(m_fence);
        if (m_pbo)
            gl->glDeleteBuffers(1, &m_pbo);
    }

    // The probe's rect in framebuffer pixels, y down, and the frame's height.
    QRect rect;
    int   frameHeight = 0;
    bool  shown       = false;

    void  frame(QQuickWindow *window) {
        QOpenGLExtraFunctions *gl = functions();
        if (!gl)
            return;
        collect(gl);
        if (!shown || rect.isEmpty())
            return;
        if (m_fence || (m_last.isValid() && m_last.elapsed() < kIntervalMs)) {
            m_dirty = true;
            if (!m_scheduled)
                schedule(m_fence ? kCollectMs : int(kIntervalMs - m_last.elapsed()));
            return;
        }
        // Runs the frame's recorded commands, so the reads see this frame.
        window->beginExternalCommands();
        issue(gl);
        window->endExternalCommands();
        schedule(kCollectMs);
    }

    void followUp() {
        m_scheduled               = false;
        QOpenGLExtraFunctions *gl = functions();
        if (!gl)
            return;
        collect(gl);
        if (m_fence)
            schedule(kCollectMs);
        else if (m_dirty && shown && m_last.elapsed() >= kIntervalMs) {
            if (kStats)
                qWarning() << "[Backdrop] trailing frame";
            emit frameWanted();
        }
        else if (m_dirty && shown)
            schedule(int(kIntervalMs - m_last.elapsed()));
    }

  signals:
    void read(bool light);
    void followUpWanted(int ms);
    void frameWanted();

  private:
    QOpenGLExtraFunctions *functions() {
        QOpenGLContext *ctx = QOpenGLContext::currentContext();
        if (!ctx || m_unsupported)
            return nullptr;
        // PBOs and fences are GLES 3.
        m_unsupported = ctx->format().majorVersion() < 3;
        return m_unsupported ? nullptr : ctx->extraFunctions();
    }

    void schedule(int ms) {
        m_scheduled = true;
        emit followUpWanted(ms);
    }

    void issue(QOpenGLExtraFunctions *gl) {
        QElapsedTimer cost;
        cost.start();
        const GLsizei    width = rect.width();
        const GLsizeiptr row   = GLsizeiptr(width) * 4;
        if (!m_pbo)
            gl->glGenBuffers(1, &m_pbo);
        gl->glBindBuffer(GL_PIXEL_PACK_BUFFER, m_pbo);
        if (m_size != 2 * row) {
            m_size = 2 * row;
            gl->glBufferData(GL_PIXEL_PACK_BUFFER, m_size, nullptr, GL_STREAM_READ);
        }
        gl->glBindFramebuffer(GL_READ_FRAMEBUFFER,
                              QOpenGLContext::currentContext()->defaultFramebufferObject());
        const int rows[2] = {rect.top(), rect.bottom()};
        for (int i = 0; i < 2; ++i)
            gl->glReadPixels(rect.x(), frameHeight - 1 - rows[i], width, 1, GL_RGBA,
                             GL_UNSIGNED_BYTE, reinterpret_cast<void *>(i * row));
        gl->glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
        m_fence = gl->glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
        m_last.start();
        m_dirty   = false;
        m_issueNs = cost.nsecsElapsed();
    }

    void collect(QOpenGLExtraFunctions *gl) {
        if (!m_fence)
            return;
        const GLenum state = gl->glClientWaitSync(m_fence, 0, 0);
        if (state != GL_ALREADY_SIGNALED && state != GL_CONDITION_SATISFIED)
            return;
        QElapsedTimer cost;
        cost.start();
        gl->glDeleteSync(m_fence);
        m_fence = nullptr;
        gl->glBindBuffer(GL_PIXEL_PACK_BUFFER, m_pbo);
        const auto *pixels = static_cast<const std::uint8_t *>(
            gl->glMapBufferRange(GL_PIXEL_PACK_BUFFER, 0, m_size, GL_MAP_READ_BIT));
        bool light = m_light;
        if (pixels) {
            light = marathon::backdrop::is_light(
                rust::Slice<const std::uint8_t>(pixels, size_t(m_size)), m_light);
            gl->glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
        }
        gl->glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
        if (light != m_light || !m_reported) {
            m_light    = light;
            m_reported = true;
            emit read(light);
        }
        if (kStats)
            qWarning().nospace() << "[Backdrop] " << rect << " light=" << m_light
                                 << " issue=" << m_issueNs / 1000
                                 << "us collect=" << cost.nsecsElapsed() / 1000
                                 << "us latency=" << m_last.elapsed() << "ms";
    }

    GLuint        m_pbo   = 0;
    GLsizeiptr    m_size  = 0;
    GLsync        m_fence = nullptr;
    QElapsedTimer m_last;
    qint64        m_issueNs     = 0;
    bool          m_dirty       = false;
    bool          m_scheduled   = false;
    bool          m_light       = false;
    bool          m_reported    = false;
    bool          m_unsupported = false;
};

BackdropProbe::BackdropProbe(QQuickItem *parent)
    : QQuickItem(parent) {
    m_followUp.setSingleShot(true);
    connect(&m_followUp, &QTimer::timeout, this, &BackdropProbe::followUp);
    connect(this, &QQuickItem::windowChanged, this, &BackdropProbe::attach);
}

BackdropProbe::~BackdropProbe() {
    if (m_reader && window())
        releaseResources();
}

void BackdropProbe::setFallbackLight(bool light) {
    if (m_fallbackLight == light)
        return;
    m_fallbackLight = light;
    emit lightChanged();
}

void BackdropProbe::attach(QQuickWindow *window) {
    if (m_window)
        disconnect(m_window, nullptr, this, nullptr);
    m_window = window;
    if (!window)
        return;
    connect(window, &QQuickWindow::beforeSynchronizing, this, &BackdropProbe::sync,
            Qt::DirectConnection);
    connect(window, &QQuickWindow::sceneGraphInvalidated, this, &BackdropProbe::cleanup,
            Qt::DirectConnection);
}

// Render thread, GUI thread blocked.
void BackdropProbe::sync() {
    QQuickWindow *win = window();
    if (!m_reader) {
        m_reader = new BackdropReader;
        connect(
            win, &QQuickWindow::afterRendering, m_reader, [r = m_reader, win] { r->frame(win); },
            Qt::DirectConnection);
        connect(m_reader, &BackdropReader::read, this, &BackdropProbe::setLight);
        connect(m_reader, &BackdropReader::followUpWanted, &m_followUp,
                qOverload<int>(&QTimer::start));
        connect(m_reader, &BackdropReader::frameWanted, win, &QQuickWindow::update);
    }
    const qreal  dpr      = win->effectiveDevicePixelRatio();
    const QRect  frame    = QRect(QPoint(), win->size() * dpr);
    const QRectF scene    = mapRectToScene(boundingRect());
    const QRect  rect     = QRectF(scene.topLeft() * dpr, scene.size() * dpr).toAlignedRect();
    m_reader->rect        = rect & frame;
    m_reader->frameHeight = frame.height();
    m_reader->shown       = isVisible();
}

// Render thread, on scene graph invalidation.
void BackdropProbe::cleanup() {
    delete m_reader;
    m_reader = nullptr;
}

void BackdropProbe::releaseResources() {
    window()->scheduleRenderJob(QRunnable::create([r = m_reader] { delete r; }),
                                QQuickWindow::BeforeSynchronizingStage);
    m_reader = nullptr;
}

void BackdropProbe::followUp() {
    if (!m_reader || !window())
        return;
    window()->scheduleRenderJob(QRunnable::create([r = QPointer<BackdropReader>(m_reader)] {
                                    if (r)
                                        r->followUp();
                                }),
                                QQuickWindow::NoStage);
}

void BackdropProbe::setLight(bool light) {
    const bool was = isLight();
    m_light        = light;
    m_read         = true;
    if (isLight() != was)
        emit lightChanged();
}

#include "backdropprobe.moc"
