#include "backdropprobe.h"

#include "marathon-shell-native/src/backdrop.cxxqt.h"

#include <QDebug>
#include <QElapsedTimer>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QQuickWindow>
#include <QRunnable>
#include <QTimer>
#include <algorithm>
#include <cstdint>
#include <vector>

namespace {
    constexpr qint64 kIntervalMs = 250;
    constexpr int    kCollectMs  = 32;
    const bool       kStats      = qEnvironmentVariableIntValue("MARATHON_BACKDROP_STATS") != 0;
} // namespace

// sync() runs on the render thread with the GUI thread blocked; the GL half
// runs on the render thread with the context current.
class BackdropSampler : public QObject {
    Q_OBJECT

  public:
    static BackdropSampler *of(QQuickWindow *window) {
        auto *sampler = window->findChild<BackdropSampler *>(QString(), Qt::FindDirectChildrenOnly);
        return sampler ? sampler : new BackdropSampler(window);
    }

    void add(BackdropProbe *probe) {
        m_probes.append({++m_nextId, probe});
        m_window->update();
    }

    void remove(BackdropProbe *probe) {
        m_probes.removeIf([probe](const Entry &e) { return e.probe == probe; });
    }

  signals:
    void read(quint32 id, bool light);
    void followUpWanted(int ms);
    void frameWanted();

  private:
    struct Entry {
        quint32        id;
        BackdropProbe *probe;
    };
    struct Target {
        quint32 id;
        QRect   rect;
        bool    light;
        bool    read;
    };
    // One frame row, in GL's bottom-up coordinates, shared by the probes on it.
    struct Row {
        int      y;
        int      x0;
        int      x1;
        GLintptr offset;
    };

    explicit BackdropSampler(QQuickWindow *window)
        : QObject(window)
        , m_window(window) {
        m_followUp.setSingleShot(true);
        connect(&m_followUp, &QTimer::timeout, this, [this] {
            m_window->scheduleRenderJob(QRunnable::create([this] { followUp(); }),
                                        QQuickWindow::NoStage);
        });
        connect(this, &BackdropSampler::read, this, &BackdropSampler::deliver,
                Qt::QueuedConnection);
        connect(this, &BackdropSampler::followUpWanted, &m_followUp, qOverload<int>(&QTimer::start),
                Qt::QueuedConnection);
        connect(this, &BackdropSampler::frameWanted, window, &QQuickWindow::update,
                Qt::QueuedConnection);
        connect(window, &QQuickWindow::beforeSynchronizing, this, &BackdropSampler::sync,
                Qt::DirectConnection);
        connect(window, &QQuickWindow::afterRendering, this, &BackdropSampler::frame,
                Qt::DirectConnection);
        connect(window, &QQuickWindow::sceneGraphInvalidated, this, &BackdropSampler::release,
                Qt::DirectConnection);
    }

    void deliver(quint32 id, bool light) {
        for (const Entry &e : std::as_const(m_probes))
            if (e.id == id)
                e.probe->setLight(light);
    }

    void sync() {
        const qreal dpr = m_window->effectiveDevicePixelRatio();
        m_frame         = QRect(QPoint(), m_window->size() * dpr);
        m_targets.clear();
        for (const Entry &e : std::as_const(m_probes)) {
            if (!e.probe->isVisible())
                continue;
            const QRectF scene = e.probe->mapRectToScene(e.probe->boundingRect());
            const QRect  rect =
                QRectF(scene.topLeft() * dpr, scene.size() * dpr).toAlignedRect() & m_frame;
            if (!rect.isEmpty())
                m_targets.push_back({e.id, rect, e.probe->isLight(), e.probe->m_read});
        }
    }

    void frame() {
        QOpenGLExtraFunctions *gl = functions();
        if (!gl)
            return;
        collect(gl);
        if (m_targets.empty())
            return;
        if (m_fence || (m_last.isValid() && m_last.elapsed() < kIntervalMs)) {
            m_dirty = true;
            if (!m_scheduled)
                schedule(m_fence ? kCollectMs : int(kIntervalMs - m_last.elapsed()));
            return;
        }
        // Runs the frame's recorded commands, so the reads see this frame.
        m_window->beginExternalCommands();
        issue(gl);
        m_window->endExternalCommands();
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
        else if (m_dirty && !m_targets.empty() && m_last.elapsed() >= kIntervalMs) {
            if (kStats)
                qWarning() << "[Backdrop] trailing frame";
            emit frameWanted();
        } else if (m_dirty && !m_targets.empty())
            schedule(int(kIntervalMs - m_last.elapsed()));
    }

    void release() {
        if (QOpenGLContext *ctx = QOpenGLContext::currentContext(); ctx && m_pbo) {
            QOpenGLExtraFunctions *gl = ctx->extraFunctions();
            if (m_fence)
                gl->glDeleteSync(m_fence);
            gl->glDeleteBuffers(1, &m_pbo);
            gl->glDeleteFramebuffers(1, &m_resolveFbo);
            gl->glDeleteRenderbuffers(1, &m_resolveRb);
        }
        m_fence = nullptr;
        m_pbo = m_resolveFbo = m_resolveRb = 0;
        m_capacity                         = 0;
        m_resolveSize                      = QSize();
        m_checked                          = false;
    }

    QOpenGLExtraFunctions *functions() {
        QOpenGLContext *ctx = QOpenGLContext::currentContext();
        if (!ctx || m_unsupported)
            return nullptr;
        // PBOs, fences and framebuffer blits are GLES 3.
        m_unsupported = ctx->format().majorVersion() < 3;
        return m_unsupported ? nullptr : ctx->extraFunctions();
    }

    void schedule(int ms) {
        m_scheduled = true;
        emit followUpWanted(ms);
    }

    void addRow(int y, int x0, int x1) {
        for (Row &r : m_rows) {
            if (r.y == y) {
                r.x0 = std::min(r.x0, x0);
                r.x1 = std::max(r.x1, x1);
                return;
            }
        }
        m_rows.push_back({y, x0, x1, 0});
    }

    const Row &rowAt(int y) const {
        return *std::find_if(m_rows.cbegin(), m_rows.cend(),
                             [y](const Row &r) { return r.y == y; });
    }

    int glY(int y) const {
        return m_issuedHeight - 1 - y;
    }

    void issue(QOpenGLExtraFunctions *gl) {
        QElapsedTimer cost;
        cost.start();
        QOpenGLContext *ctx = QOpenGLContext::currentContext();
        const GLuint    fb  = ctx->defaultFramebufferObject();
        m_issued            = m_targets;
        m_issuedHeight      = m_frame.height();
        m_rows.clear();
        for (const Target &t : std::as_const(m_issued)) {
            addRow(glY(t.rect.top()), t.rect.left(), t.rect.right() + 1);
            addRow(glY(t.rect.bottom()), t.rect.left(), t.rect.right() + 1);
        }
        m_size = 0;
        for (Row &r : m_rows) {
            r.offset = m_size;
            m_size += GLintptr(r.x1 - r.x0) * 4;
        }
        if (!m_checked)
            while (gl->glGetError() != GL_NO_ERROR) {}

        gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, fb);
        // A multisampled frame reads back only through a synchronous resolve in
        // the driver, so resolve the rows into a plain buffer first. Blits out
        // of a multisampled buffer keep their coordinates.
        if (ctx->format().samples() > 1) {
            if (m_resolveSize != m_frame.size()) {
                if (!m_resolveFbo) {
                    gl->glGenFramebuffers(1, &m_resolveFbo);
                    gl->glGenRenderbuffers(1, &m_resolveRb);
                }
                gl->glBindRenderbuffer(GL_RENDERBUFFER, m_resolveRb);
                gl->glRenderbufferStorage(GL_RENDERBUFFER,
                                          ctx->format().alphaBufferSize() > 0 ? GL_RGBA8 : GL_RGB8,
                                          m_frame.width(), m_frame.height());
                gl->glBindRenderbuffer(GL_RENDERBUFFER, 0);
                gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, m_resolveFbo);
                gl->glFramebufferRenderbuffer(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                              GL_RENDERBUFFER, m_resolveRb);
                m_resolveSize = m_frame.size();
            }
            gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, m_resolveFbo);
            for (const Row &r : std::as_const(m_rows))
                gl->glBlitFramebuffer(r.x0, r.y, r.x1, r.y + 1, r.x0, r.y, r.x1, r.y + 1,
                                      GL_COLOR_BUFFER_BIT, GL_NEAREST);
            gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, m_resolveFbo);
        }

        if (!m_pbo)
            gl->glGenBuffers(1, &m_pbo);
        gl->glBindBuffer(GL_PIXEL_PACK_BUFFER, m_pbo);
        if (m_size > m_capacity) {
            m_capacity = m_size;
            gl->glBufferData(GL_PIXEL_PACK_BUFFER, m_capacity, nullptr, GL_STREAM_READ);
        }
        for (const Row &r : std::as_const(m_rows))
            gl->glReadPixels(r.x0, r.y, r.x1 - r.x0, 1, GL_RGBA, GL_UNSIGNED_BYTE,
                             reinterpret_cast<void *>(r.offset));
        gl->glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
        gl->glBindFramebuffer(GL_FRAMEBUFFER, fb);

        if (!m_checked) {
            m_checked = true;
            if (const GLenum error = gl->glGetError(); error != GL_NO_ERROR) {
                qWarning() << "[Backdrop] the frame can't be read, GL error" << Qt::hex << error
                           << "samples" << ctx->format().samples();
                m_unsupported = true;
                release();
                return;
            }
            if (kStats)
                qWarning() << "[Backdrop] reading" << m_frame.size() << "samples"
                           << ctx->format().samples();
        }
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
        if (pixels) {
            for (Target &t : m_issued) {
                m_strip.clear();
                for (const int y : {glY(t.rect.top()), glY(t.rect.bottom())}) {
                    const Row          &r     = rowAt(y);
                    const std::uint8_t *start = pixels + r.offset + (t.rect.left() - r.x0) * 4;
                    m_strip.insert(m_strip.end(), start, start + t.rect.width() * 4);
                }
                const bool light = marathon::backdrop::is_light(
                    rust::Slice<const std::uint8_t>(m_strip.data(), m_strip.size()), t.light);
                if (light != t.light || !t.read)
                    emit read(t.id, light);
                t.light = light;
            }
            gl->glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
        }
        gl->glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
        if (!kStats)
            return;
        const qint64 collectNs = cost.nsecsElapsed();
        for (const Target &t : std::as_const(m_issued))
            qWarning().nospace() << "[Backdrop] " << t.rect << " light=" << t.light;
        qWarning().nospace() << "[Backdrop] round rows=" << m_rows.size()
                             << " issue=" << m_issueNs / 1000 << "us collect=" << collectNs / 1000
                             << "us latency=" << m_last.elapsed() << "ms";
    }

    QQuickWindow             *m_window;
    QTimer                    m_followUp;
    QList<Entry>              m_probes;
    quint32                   m_nextId = 0;

    QRect                     m_frame;
    int                       m_issuedHeight = 0;
    std::vector<Target>       m_targets;
    std::vector<Target>       m_issued;
    std::vector<Row>          m_rows;
    std::vector<std::uint8_t> m_strip;
    GLuint                    m_pbo        = 0;
    GLintptr                  m_size       = 0;
    GLintptr                  m_capacity   = 0;
    GLuint                    m_resolveFbo = 0;
    GLuint                    m_resolveRb  = 0;
    QSize                     m_resolveSize;
    GLsync                    m_fence = nullptr;
    QElapsedTimer             m_last;
    qint64                    m_issueNs     = 0;
    bool                      m_dirty       = false;
    bool                      m_scheduled   = false;
    bool                      m_checked     = false;
    bool                      m_unsupported = false;
};

BackdropProbe::BackdropProbe(QQuickItem *parent)
    : QQuickItem(parent) {
    connect(this, &QQuickItem::windowChanged, this, &BackdropProbe::attach);
}

BackdropProbe::~BackdropProbe() {
    if (m_sampler)
        m_sampler->remove(this);
}

void BackdropProbe::setFallbackLight(bool light) {
    if (m_fallbackLight == light)
        return;
    m_fallbackLight = light;
    emit lightChanged();
}

void BackdropProbe::attach(QQuickWindow *window) {
    if (m_sampler)
        m_sampler->remove(this);
    m_sampler = window ? BackdropSampler::of(window) : nullptr;
    if (m_sampler)
        m_sampler->add(this);
}

void BackdropProbe::setLight(bool light) {
    const bool was = isLight();
    m_light        = light;
    m_read         = true;
    if (isLight() != was)
        emit lightChanged();
}

#include "backdropprobe.moc"
