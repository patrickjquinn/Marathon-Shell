#include "TerminalRenderer.h"
#include "TerminalEngine.h"
#include "TerminalScreen.h"
#include <QPainter>
#include <QTimer>

TerminalRenderer::TerminalRenderer(QQuickItem *parent)
    : QQuickPaintedItem(parent)
    , m_terminal(nullptr)
    , m_screen(nullptr)
    , m_charWidth(10)
    , m_charHeight(20)
    , m_ascent(15) {
    setFlag(ItemHasContents, true);
    setAntialiasing(true);

    QStringList fonts = {"Cascadia Code", "Fira Code", "Roboto Mono", "Courier New", "Monospace"};
    for (const QString &family : fonts) {
        QFont f(family);
        if (f.exactMatch() || family == "Monospace") {
            m_font.setFamily(family);
            break;
        }
    }
    m_font.setPixelSize(14);
    m_font.setStyleHint(QFont::Monospace);

    m_textColor       = QColor(Qt::white);
    m_backgroundColor = QColor(Qt::black);
    m_selectionColor  = QColor(255, 255, 255, 64);

    updateCharSize();
}

void TerminalRenderer::setTerminal(TerminalEngine *terminal) {
    if (m_terminal == terminal)
        return;

    if (m_terminal) {
        disconnect(m_terminal, nullptr, this, nullptr);
        if (m_screen) {
            disconnect(m_screen, nullptr, this, nullptr);
        }
    }

    m_terminal = terminal;
    m_screen   = m_terminal ? m_terminal->screen() : nullptr;

    if (m_terminal && m_screen) {

        connect(m_screen, &TerminalScreen::screenChanged, this, &QQuickItem::update);
        connect(m_screen, &TerminalScreen::cursorChanged, this, &QQuickItem::update);
    }

    emit terminalChanged();
    update();
}

void TerminalRenderer::setFont(const QFont &font) {
    if (m_font == font)
        return;
    m_font = font;
    updateCharSize();
    emit fontChanged();
    update();
}

void TerminalRenderer::setTextColor(const QColor &color) {
    if (m_textColor == color)
        return;
    m_textColor = color;
    emit textColorChanged();
    update();
}

void TerminalRenderer::setBackgroundColor(const QColor &color) {
    if (m_backgroundColor == color)
        return;
    m_backgroundColor = color;
    emit backgroundColorChanged();
    update();
}

void TerminalRenderer::setSelectionColor(const QColor &color) {
    if (m_selectionColor == color)
        return;
    m_selectionColor = color;
    emit selectionColorChanged();
    update();
}

void TerminalRenderer::updateCharSize() {
    QFontMetricsF fm(m_font);
    m_charWidth  = fm.horizontalAdvance('W');
    m_charHeight = fm.height();
    m_ascent     = fm.ascent();
    emit charSizeChanged();
}

void TerminalRenderer::onScreenChanged() {
    update();
}

void TerminalRenderer::onCursorChanged() {
    update();
}

void TerminalRenderer::select(int startX, int startY, int endX, int endY) {
    if (m_screen) {
        m_screen->setSelection(startX, startY, endX, endY);
    }
}

void TerminalRenderer::clearSelection() {
    if (m_screen) {
        m_screen->clearSelection();
    }
}

QString TerminalRenderer::selectedText() const {
    if (m_screen) {
        return m_screen->getSelectedText();
    }
    return QString();
}

QPoint TerminalRenderer::positionToGrid(qreal x, qreal y) {
    if (m_charWidth <= 0 || m_charHeight <= 0)
        return QPoint(0, 0);

    int col = static_cast<int>(x / m_charWidth);
    int row = static_cast<int>(y / m_charHeight);

    return QPoint(col, row);
}

void TerminalRenderer::paint(QPainter *painter) {
    if (!m_screen)
        return;

    painter->setFont(m_font);

    QMutexLocker locker(m_screen->mutex());

    int          cols = m_screen->cols();
    int          rows = m_screen->rows();

    painter->fillRect(boundingRect(), m_backgroundColor);

    QString lineBuffer;
    lineBuffer.reserve(cols);

    for (int y = 0; y < rows; ++y) {

        if (y * m_charHeight > height())
            break;

        int x = 0;
        while (x < cols) {
            const TerminalCell &startCell = m_screen->cell(x, y);

            int                 runEnd = x + 1;
            while (runEnd < cols) {
                const TerminalCell &next = m_screen->cell(runEnd, y);
                if (next != startCell)
                    break;
                runEnd++;
            }

            if (startCell.bgColor != 0xFF000000 || startCell.inverse) {
                QColor bg;
                if (startCell.inverse) {

                    bg =
                        (startCell.fgColor == 0xFFFFFFFF) ? m_textColor : QColor(startCell.fgColor);
                } else {

                    bg = QColor(startCell.bgColor);
                }

                QRectF bgRect(x * m_charWidth, y * m_charHeight, (runEnd - x) * m_charWidth,
                              m_charHeight);
                painter->fillRect(bgRect, bg);
            }

            if (m_screen->hasSelection()) {
                int selStart = x;
                while (selStart < runEnd) {
                    if (m_screen->isSelected(selStart, y)) {
                        int selEnd = selStart + 1;
                        while (selEnd < runEnd && m_screen->isSelected(selEnd, y)) {
                            selEnd++;
                        }

                        QRectF selRect(selStart * m_charWidth, y * m_charHeight,
                                       (selEnd - selStart) * m_charWidth, m_charHeight);
                        painter->fillRect(selRect, m_selectionColor);
                        selStart = selEnd;
                    } else {
                        selStart++;
                    }
                }
            }

            if (y == m_screen->cursorY() && m_screen->cursorX() >= x &&
                m_screen->cursorX() < runEnd) {
                QRectF cursorRect(m_screen->cursorX() * m_charWidth, y * m_charHeight, m_charWidth,
                                  m_charHeight);

                QColor cursorColor = (m_backgroundColor.lightness() > 128) ?
                    QColor(0, 0, 0, 128) :
                    QColor(255, 255, 255, 128);
                painter->fillRect(cursorRect, cursorColor);
            }

            lineBuffer.clear();
            bool hasText = false;
            for (int i = x; i < runEnd; ++i) {
                uint32_t cp = m_screen->cell(i, y).codePoint;
                if (cp && cp != ' ') {
                    lineBuffer.append(QChar(cp));
                    hasText = true;
                } else {
                    lineBuffer.append(' ');
                }
            }

            if (hasText) {
                QColor fg;
                if (startCell.inverse) {

                    fg = (startCell.bgColor == 0xFF000000) ? m_backgroundColor :
                                                             QColor(startCell.bgColor);
                } else {

                    fg =
                        (startCell.fgColor == 0xFFFFFFFF) ? m_textColor : QColor(startCell.fgColor);
                }

                painter->setPen(fg);

                if (startCell.bold) {
                    QFont f = m_font;
                    f.setBold(true);
                    painter->setFont(f);
                } else {
                    painter->setFont(m_font);
                }

                painter->drawText(QPointF(x * m_charWidth, y * m_charHeight + m_ascent),
                                  lineBuffer);
            }

            x = runEnd;
        }
    }
}
