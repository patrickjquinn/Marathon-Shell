#pragma once

#include <QObject>
#include <QTimer>

/**
 * @brief CursorManager - Controls global cursor visibility for EGLFS
 *
 * QML MouseArea cursorShape doesn't work reliably with EGLFS hardware cursor.
 * This class uses QGuiApplication::setOverrideCursor() for reliable control.
 */
class CursorManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(
        bool cursorVisible READ cursorVisible WRITE setCursorVisible NOTIFY cursorVisibleChanged)
    Q_PROPERTY(int hideDelayMs READ hideDelayMs WRITE setHideDelayMs NOTIFY hideDelayMsChanged)

  public:
    explicit CursorManager(QObject *parent = nullptr);
    ~CursorManager() override;

    bool cursorVisible() const {
        return m_cursorVisible;
    }
    int hideDelayMs() const {
        return m_hideDelayMs;
    }

    Q_INVOKABLE void setCursorVisible(bool visible);
    Q_INVOKABLE void setHideDelayMs(int ms);

    // Call this when mouse moves to show cursor and reset hide timer
    Q_INVOKABLE void onMouseActivity();

  signals:
    void cursorVisibleChanged();
    void hideDelayMsChanged();

  private slots:
    void hideCursor();

  private:
    bool    m_cursorVisible;
    int     m_hideDelayMs;
    QTimer *m_hideTimer;
    bool    m_overrideActive;
};
