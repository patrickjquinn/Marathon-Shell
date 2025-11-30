#pragma once

#include <QQuickPaintedItem>
#include <QFont>
#include <QFontMetrics>

class TerminalScreen;
class TerminalEngine;

class TerminalRenderer : public QQuickPaintedItem {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(TerminalEngine *terminal READ terminal WRITE setTerminal NOTIFY terminalChanged)
    Q_PROPERTY(QFont font READ font WRITE setFont NOTIFY fontChanged)
    Q_PROPERTY(qreal charWidth READ charWidth NOTIFY charSizeChanged)
    Q_PROPERTY(qreal charHeight READ charHeight NOTIFY charSizeChanged)
    Q_PROPERTY(QColor textColor READ textColor WRITE setTextColor NOTIFY textColorChanged)
    Q_PROPERTY(QColor backgroundColor READ backgroundColor WRITE setBackgroundColor NOTIFY
                   backgroundColorChanged)
    Q_PROPERTY(QColor selectionColor READ selectionColor WRITE setSelectionColor NOTIFY
                   selectionColorChanged)

  public:
    explicit TerminalRenderer(QQuickItem *parent = nullptr);

    Q_INVOKABLE void    select(int startX, int startY, int endX, int endY);
    Q_INVOKABLE void    clearSelection();
    Q_INVOKABLE QString selectedText() const;
    Q_INVOKABLE QPoint  positionToGrid(qreal x, qreal y);

    TerminalEngine     *terminal() const {
        return m_terminal;
    }
    void  setTerminal(TerminalEngine *terminal);

    QFont font() const {
        return m_font;
    }
    void   setFont(const QFont &font);

    QColor textColor() const {
        return m_textColor;
    }
    void   setTextColor(const QColor &color);

    QColor backgroundColor() const {
        return m_backgroundColor;
    }
    void   setBackgroundColor(const QColor &color);

    QColor selectionColor() const {
        return m_selectionColor;
    }
    void  setSelectionColor(const QColor &color);

    qreal charWidth() const {
        return m_charWidth;
    }
    qreal charHeight() const {
        return m_charHeight;
    }

  signals:
    void terminalChanged();
    void fontChanged();
    void charSizeChanged();
    void textColorChanged();
    void backgroundColorChanged();
    void selectionColorChanged();

  protected:
    void paint(QPainter *painter) override;

  private slots:
    void onScreenChanged();
    void onCursorChanged();

  private:
    void            updateCharSize();

    TerminalEngine *m_terminal;
    TerminalScreen *m_screen;
    QFont           m_font;
    QColor          m_textColor;
    QColor          m_backgroundColor;
    QColor          m_selectionColor;
    qreal           m_charWidth;
    qreal           m_charHeight;
    qreal           m_ascent;
};
