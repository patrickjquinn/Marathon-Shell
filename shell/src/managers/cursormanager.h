#pragma once

#include <QObject>
#include <QPointF>
#include <QTimer>

class CursorManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(
        bool cursorVisible READ cursorVisible WRITE setCursorVisible NOTIFY cursorVisibleChanged)
    Q_PROPERTY(int hideDelayMs READ hideDelayMs WRITE setHideDelayMs NOTIFY hideDelayMsChanged)
    // Where a mouse or trackpad last put the pointer, in window coordinates;
    // the shell draws the cursor there (Qt's own stays hidden).
    Q_PROPERTY(QPointF position READ position NOTIFY positionChanged)

  public:
    explicit CursorManager(QObject *parent = nullptr);
    ~CursorManager() override;

    bool cursorVisible() const {
        return m_cursorVisible;
    }
    int hideDelayMs() const {
        return m_hideDelayMs;
    }
    QPointF position() const {
        return m_position;
    }

    Q_INVOKABLE void setCursorVisible(bool visible);
    Q_INVOKABLE void setHideDelayMs(int ms);

    Q_INVOKABLE void onMouseActivity();

  signals:
    void cursorVisibleChanged();
    void hideDelayMsChanged();
    void positionChanged();

  protected:
    bool eventFilter(QObject *watched, QEvent *event) override;

  private slots:
    void hideCursor();

  private:
    bool    m_cursorVisible;
    int     m_hideDelayMs;
    QTimer *m_hideTimer;
    QPointF m_position;
};
