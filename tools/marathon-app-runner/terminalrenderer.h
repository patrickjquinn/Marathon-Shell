#pragma once

#include <QColor>
#include <QFont>
#include <QPoint>
#include <QQuickPaintedItem>

namespace marathon::terminal {
class TerminalEngine;
}

class TerminalRenderer : public QQuickPaintedItem {
    Q_OBJECT

    Q_PROPERTY(QObject *terminal READ terminal WRITE setTerminal NOTIFY terminalChanged)
    Q_PROPERTY(QFont font READ font WRITE setFont NOTIFY fontChanged)
    Q_PROPERTY(qreal charWidth READ charWidth NOTIFY charSizeChanged)
    Q_PROPERTY(qreal charHeight READ charHeight NOTIFY charSizeChanged)
    Q_PROPERTY(QColor textColor READ textColor WRITE setTextColor NOTIFY textColorChanged)
    Q_PROPERTY(QColor backgroundColor READ backgroundColor WRITE setBackgroundColor NOTIFY
                   backgroundColorChanged)
    Q_PROPERTY(QColor selectionColor READ selectionColor WRITE setSelectionColor NOTIFY
                   selectionColorChanged)
    Q_PROPERTY(qreal scrollOffset READ scrollOffset WRITE setScrollOffset NOTIFY scrollOffsetChanged)
    Q_PROPERTY(int historyLines READ historyLines NOTIFY historyLinesChanged)

  public:
    explicit TerminalRenderer(QQuickItem *parent = nullptr);

    Q_INVOKABLE void    select(int startX, int startY, int endX, int endY);
    Q_INVOKABLE void    clearSelection();
    Q_INVOKABLE QString selectedText() const;
    Q_INVOKABLE QPoint  positionToGrid(qreal x, qreal y) const;

    QObject *terminal() const;
    void     setTerminal(QObject *terminal);

    QFont font() const {
        return m_font;
    }
    void setFont(const QFont &font);

    QColor textColor() const {
        return m_textColor;
    }
    void setTextColor(const QColor &color);

    QColor backgroundColor() const {
        return m_backgroundColor;
    }
    void setBackgroundColor(const QColor &color);

    QColor selectionColor() const {
        return m_selectionColor;
    }
    void setSelectionColor(const QColor &color);

    qreal scrollOffset() const {
        return m_scrollOffset;
    }
    void setScrollOffset(qreal offset);

    int historyLines() const {
        return m_historyLines;
    }

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
    void scrollOffsetChanged();
    void historyLinesChanged();
    void textCommitted(const QString &text);

  protected:
    void     paint(QPainter *painter) override;
    QVariant inputMethodQuery(Qt::InputMethodQuery query) const override;
    void     inputMethodEvent(QInputMethodEvent *event) override;

  private slots:
    void onScreenChanged();

  private:
    void updateCharSize();

    marathon::terminal::TerminalEngine *m_terminal = nullptr;
    QFont                               m_font;
    qreal                               m_charWidth       = 10;
    qreal                               m_charHeight      = 20;
    qreal                               m_ascent          = 15;
    QColor                              m_textColor       = Qt::white;
    QColor                              m_backgroundColor = Qt::black;
    QColor                              m_selectionColor  = QColor(255, 255, 255, 64);
    qreal                               m_scrollOffset    = 0;
    int                                 m_historyLines    = 0;
};
