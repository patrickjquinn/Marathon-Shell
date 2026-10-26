#include "terminalrenderer.h"
#include "marathon-app-native/src/terminal.cxxqt.h"

#include <QFontMetricsF>
#include <QInputMethodEvent>
#include <QPainter>
#include <algorithm>
#include <cmath>

TerminalRenderer::TerminalRenderer(QQuickItem *parent)
    : QQuickPaintedItem(parent) {
    setFlag(ItemHasContents, true);
    setFlag(ItemAcceptsInputMethod, true);
    setAntialiasing(true);

    const QStringList fonts = {QStringLiteral("JetBrains Mono"), QStringLiteral("Cascadia Code"),
                               QStringLiteral("Fira Code"),      QStringLiteral("Roboto Mono"),
                               QStringLiteral("Courier New"),    QStringLiteral("Monospace")};
    for (const QString &family : fonts) {
        QFont f(family);
        if (f.exactMatch() || family == QLatin1String("Monospace")) {
            m_font.setFamily(family);
            break;
        }
    }
    m_font.setPixelSize(14);
    m_font.setStyleHint(QFont::Monospace);
    updateCharSize();
}

QObject *TerminalRenderer::terminal() const {
    return m_terminal;
}

void TerminalRenderer::setTerminal(QObject *terminal) {
    auto *eng = qobject_cast<marathon::terminal::TerminalEngine *>(terminal);
    if (m_terminal == eng)
        return;

    if (m_terminal)
        disconnect(m_terminal, nullptr, this, nullptr);

    m_terminal = eng;
    if (m_terminal) {
        connect(m_terminal, &marathon::terminal::TerminalEngine::screenChanged, this,
                &TerminalRenderer::onScreenChanged);
    }

    emit terminalChanged();
    onScreenChanged();
}

void TerminalRenderer::setScrollOffset(qreal offset) {
    if (qFuzzyCompare(m_scrollOffset, offset))
        return;
    m_scrollOffset = offset;
    emit scrollOffsetChanged();
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
    m_charWidth  = fm.horizontalAdvance(QLatin1Char('W'));
    m_charHeight = fm.height();
    m_ascent     = fm.ascent();
    emit charSizeChanged();
}

void TerminalRenderer::onScreenChanged() {
    const int history = m_terminal ? m_terminal->historyLines() : 0;
    if (history != m_historyLines) {
        m_historyLines = history;
        emit historyLinesChanged();
    }
    update();
}

void TerminalRenderer::select(int startX, int startY, int endX, int endY) {
    if (m_terminal)
        m_terminal->select(startX, startY, endX, endY);
}

void TerminalRenderer::clearSelection() {
    if (m_terminal)
        m_terminal->clearSelection();
}

QString TerminalRenderer::selectedText() const {
    return m_terminal ? m_terminal->selectedText() : QString();
}

QPoint TerminalRenderer::positionToGrid(qreal x, qreal y) const {
    if (m_charWidth <= 0 || m_charHeight <= 0)
        return QPoint(0, 0);
    const int col = static_cast<int>(x / m_charWidth);
    const int row = static_cast<int>(std::floor((y - m_scrollOffset) / m_charHeight));
    return QPoint(col, row);
}

void TerminalRenderer::paint(QPainter *painter) {
    if (!m_terminal)
        return;

    painter->setFont(m_font);
    const int cols    = m_terminal->cols();
    const int rows    = m_terminal->rows();
    const int cursorX = m_terminal->cursorX();
    const int cursorY = m_terminal->cursorY();

    painter->fillRect(boundingRect(), m_backgroundColor);

    QString lineBuffer;
    lineBuffer.reserve(cols);

    painter->translate(0, m_scrollOffset);
    const int firstRow = std::max(-m_terminal->historyLines(),
                                  static_cast<int>(std::floor(-m_scrollOffset / m_charHeight)));

    for (int y = firstRow; y < rows; ++y) {
        if (y * m_charHeight + m_scrollOffset > height())
            break;

        int x = 0;
        while (x < cols) {
            const uint32_t startFg    = m_terminal->cellFg(x, y);
            const uint32_t startBg    = m_terminal->cellBg(x, y);
            const uint     startFlags = m_terminal->cellFlags(x, y);
            const bool     bold       = (startFlags & 1U) != 0;
            const bool     inverse    = (startFlags & 2U) != 0;

            int runEnd = x + 1;
            while (runEnd < cols) {
                const uint nextFlags = m_terminal->cellFlags(runEnd, y);
                if (m_terminal->cellFg(runEnd, y) != startFg ||
                    m_terminal->cellBg(runEnd, y) != startBg ||
                    (nextFlags & 3U) != (startFlags & 3U)) {
                    break;
                }
                runEnd++;
            }

            if (startBg != 0xFF000000U || inverse) {
                QColor bg;
                if (inverse)
                    bg = (startFg == 0xFFFFFFFFU) ? m_textColor : QColor::fromRgba(startFg);
                else
                    bg = QColor::fromRgba(startBg);

                painter->fillRect(QRectF(x * m_charWidth, y * m_charHeight,
                                         (runEnd - x) * m_charWidth, m_charHeight),
                                  bg);
            }

            int selStart = x;
            while (selStart < runEnd) {
                if ((uint(m_terminal->cellFlags(selStart, y)) & 4U) != 0) {
                    int selEnd = selStart + 1;
                    while (selEnd < runEnd && (uint(m_terminal->cellFlags(selEnd, y)) & 4U) != 0)
                        selEnd++;
                    painter->fillRect(QRectF(selStart * m_charWidth, y * m_charHeight,
                                             (selEnd - selStart) * m_charWidth, m_charHeight),
                                      m_selectionColor);
                    selStart = selEnd;
                } else {
                    selStart++;
                }
            }

            if (y == cursorY && cursorX >= x && cursorX < runEnd) {
                const QColor cursorColor = (m_backgroundColor.lightness() > 128) ?
                    QColor(0, 0, 0, 128) :
                    QColor(255, 255, 255, 128);
                painter->fillRect(
                    QRectF(cursorX * m_charWidth, y * m_charHeight, m_charWidth, m_charHeight),
                    cursorColor);
            }

            lineBuffer.clear();
            bool hasText = false;
            for (int i = x; i < runEnd; ++i) {
                const uint32_t cp = m_terminal->cellCode(i, y);
                if (cp && cp != ' ') {
                    for (char16_t u : QChar::fromUcs4(cp))
                        lineBuffer.append(QChar(u));
                    hasText = true;
                } else {
                    lineBuffer.append(QLatin1Char(' '));
                }
            }

            if (hasText) {
                QColor fg;
                if (inverse)
                    fg = (startBg == 0xFF000000U) ? m_backgroundColor : QColor::fromRgba(startBg);
                else
                    fg = (startFg == 0xFFFFFFFFU) ? m_textColor : QColor::fromRgba(startFg);

                painter->setPen(fg);
                if (bold) {
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

QVariant TerminalRenderer::inputMethodQuery(Qt::InputMethodQuery query) const {
    switch (query) {
        case Qt::ImEnabled: return true;
        case Qt::ImHints:
            return int(Qt::ImhNoPredictiveText | Qt::ImhNoAutoUppercase | Qt::ImhPreferLatin);
        case Qt::ImCursorRectangle:
            if (m_terminal) {
                return QRectF(m_terminal->cursorX() * m_charWidth,
                              m_terminal->cursorY() * m_charHeight + m_scrollOffset, m_charWidth,
                              m_charHeight);
            }
            return QRectF();
        case Qt::ImSurroundingText: return QString();
        case Qt::ImCursorPosition:
        case Qt::ImAnchorPosition: return 0;
        default: return QQuickPaintedItem::inputMethodQuery(query);
    }
}

void TerminalRenderer::inputMethodEvent(QInputMethodEvent *event) {
    if (!event->commitString().isEmpty())
        emit textCommitted(event->commitString());
    event->accept();
}
