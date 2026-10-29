#ifndef NATIVESURFACEITEM_H
#define NATIVESURFACEITEM_H

#include <QWaylandQuickShellSurfaceItem>
#include <QMetaObject>
#include <QPointer>

class QWaylandXdgPopup;
class QWaylandXdgSurface;

class NativeSurfaceItem : public QWaylandQuickShellSurfaceItem {
    Q_OBJECT
    Q_PROPERTY(QStringList applicationTerms READ applicationTerms WRITE setApplicationTerms NOTIFY
                   applicationTermsChanged)

  public:
    explicit NativeSurfaceItem(QQuickItem *parent = nullptr);

    QStringList applicationTerms() const;
    void        setApplicationTerms(const QStringList &terms);

  signals:
    void applicationTermsChanged();

  protected:
    void touchEvent(QTouchEvent *event) override;
    void touchUngrabEvent() override;

  private:
    void                       releasePointer();
    void                       setupShellSurface();
    void                       createPopup(QWaylandXdgPopup *popup, QWaylandXdgSurface *xdgSurface);
    void                       attachPopup(QWaylandXdgPopup *popup);
    void                       updatePopupGeometry();

    QStringList                m_applicationTerms;
    bool                       m_pointerFallback = false;
    int                        m_pointerTouchId  = -1;
    QPointer<QWaylandXdgPopup> m_popup;
    QMetaObject::Connection    m_popupCreatedConnection;
};

#endif
