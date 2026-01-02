#ifndef TEXTINPUTV3_H
#define TEXTINPUTV3_H

#include <QObject>
#include <QWaylandCompositor>
#include <QWaylandSeat>
#include <QWaylandSurface>
#include <wayland-server-core.h>

class TextInputV3;

class TextInputManagerV3 : public QObject {
    Q_OBJECT
  public:
    explicit TextInputManagerV3(QWaylandCompositor *compositor);
    ~TextInputManagerV3();

    static void bindManager(struct wl_client *client, void *data, uint32_t version, uint32_t id);
    static void handleGetTextInput(struct wl_client *client, struct wl_resource *resource,
                                   uint32_t id, struct wl_resource *seat);
    static void handleManagerDestroy(struct wl_client *client, struct wl_resource *resource);

  signals:
    void textInputEnabled(QWaylandSurface *surface);
    void textInputDisabled(QWaylandSurface *surface);

  private:
    QWaylandCompositor  *m_compositor;
    struct wl_global    *m_global;
    QList<TextInputV3 *> m_textInputs;
};

class TextInputV3 : public QObject {
    Q_OBJECT
  public:
    explicit TextInputV3(TextInputManagerV3 *manager, struct wl_client *client, uint32_t id,
                         QWaylandSeat *seat);
    ~TextInputV3();

    void        sendEnter(QWaylandSurface *surface);
    void        sendLeave(QWaylandSurface *surface);
    void        sendDone(uint32_t serial);

    static void handleEnable(struct wl_client *client, struct wl_resource *resource);
    static void handleDisable(struct wl_client *client, struct wl_resource *resource);
    static void handleSetSurroundingText(struct wl_client *client, struct wl_resource *resource,
                                         const char *text, int32_t cursor, int32_t anchor);
    static void handleSetTextChangeCause(struct wl_client *client, struct wl_resource *resource,
                                         uint32_t cause);
    static void handleSetContentType(struct wl_client *client, struct wl_resource *resource,
                                     uint32_t hint, uint32_t purpose);
    static void handleSetCursorRectangle(struct wl_client *client, struct wl_resource *resource,
                                         int32_t x, int32_t y, int32_t width, int32_t height);
    static void handleCommit(struct wl_client *client, struct wl_resource *resource);
    static void handleDestroy(struct wl_client *client, struct wl_resource *resource);

  signals:
    void enabled();
    void disabled();

  private:
    TextInputManagerV3 *m_manager;
    struct wl_resource *m_resource;
    QWaylandSeat       *m_seat;
    QWaylandSurface    *m_focusSurface;
    bool                m_pendingEnabled;
    uint32_t            m_serial;
};

#endif
