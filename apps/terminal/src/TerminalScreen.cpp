#include "TerminalScreen.h"
#include <QDebug>
#include <algorithm>

TerminalScreen::TerminalScreen(QObject *parent)
    : QObject(parent)
    , m_cols(80)
    , m_rows(24)
    , m_cursorX(0)
    , m_cursorY(0)
    , m_topRow(0)
    , m_historySize(1000) // 1000 lines of history
    , m_currentFg(0xFFFFFFFF)
    , m_currentBg(0xFF000000)
    , m_currentBold(false)
    , m_currentInverse(false)
    , m_hasSelection(false)
    , m_selStartX(0)
    , m_selStartY(0)
    , m_selEndX(0)
    , m_selEndY(0) {
    // Initialize grid with history capacity
    m_grid.resize(m_historySize);
    for (int i = 0; i < m_historySize; ++i) {
        m_grid[i].resize(m_cols);
    }
}

TerminalCell &TerminalScreen::cellAt(int x, int y) {
    // y is visual row (0..m_rows-1)
    // map to buffer row
    int bufferRow = (m_topRow + y) % m_historySize;
    return m_grid[bufferRow][x];
}

void TerminalScreen::resize(int cols, int rows) {
    QMutexLocker locker(&m_mutex);

    if (cols < 1)
        cols = 1;
    if (rows < 1)
        rows = 1;

    if (cols == m_cols && rows == m_rows)
        return;

    // Resizing a ring buffer is complex.
    // For simplicity in this version, we'll clear history on resize or do a naive copy.
    // Let's do a naive copy to a new grid to keep it clean.

    QVector<QVector<TerminalCell>> newGrid(m_historySize);
    for (int i = 0; i < m_historySize; ++i) {
        newGrid[i].resize(cols);
    }

    // Copy visible portion
    int copyRows = std::min(rows, m_rows);
    int copyCols = std::min(cols, m_cols);

    for (int y = 0; y < copyRows; ++y) {
        for (int x = 0; x < copyCols; ++x) {
            int oldRow    = (m_topRow + y) % m_historySize;
            newGrid[y][x] = m_grid[oldRow][x];
        }
    }

    m_grid   = newGrid;
    m_cols   = cols;
    m_rows   = rows;
    m_topRow = 0; // Reset top to 0 after resize

    // Clamp cursor
    if (m_cursorX >= m_cols)
        m_cursorX = m_cols - 1;
    if (m_cursorY >= m_rows)
        m_cursorY = m_rows - 1;

    emit screenChanged();
}

void TerminalScreen::clear() {
    QMutexLocker locker(&m_mutex);
    for (int y = 0; y < m_rows; ++y) {
        for (int x = 0; x < m_cols; ++x) {
            cellAt(x, y)         = TerminalCell();
            cellAt(x, y).bgColor = m_currentBg;
        }
    }
    m_cursorX = 0;
    m_cursorY = 0;
    emit screenChanged();
}

void TerminalScreen::putChar(uint32_t codePoint) {
    QMutexLocker locker(&m_mutex);

    if (m_cursorX >= m_cols) {
        m_cursorX = 0;
        if (m_cursorY < m_rows - 1) {
            m_cursorY++;
        } else {
            scrollUp();
        }
    }

    TerminalCell &cell = cellAt(m_cursorX, m_cursorY);
    cell.codePoint     = codePoint;
    cell.fgColor       = m_currentFg;
    cell.bgColor       = m_currentBg;
    cell.bold          = m_currentBold;
    cell.inverse       = m_currentInverse;

    m_cursorX++;
    emit screenChanged();
}

void TerminalScreen::newLine() {
    QMutexLocker locker(&m_mutex);
    if (m_cursorY < m_rows - 1) {
        m_cursorY++;
    } else {
        scrollUp();
    }
    emit cursorChanged();
}

void TerminalScreen::backspace() {
    QMutexLocker locker(&m_mutex);
    if (m_cursorX > 0) {
        m_cursorX--;
    } else if (m_cursorY > 0) {
        m_cursorY--;
        m_cursorX = m_cols - 1;
    }
    emit cursorChanged();
}

void TerminalScreen::moveCursor(int x, int y) {
    QMutexLocker locker(&m_mutex);
    m_cursorX = std::clamp(x, 0, m_cols - 1);
    m_cursorY = std::clamp(y, 0, m_rows - 1);
    emit cursorChanged();
}

void TerminalScreen::moveCursorRelative(int dx, int dy) {
    moveCursor(m_cursorX + dx, m_cursorY + dy);
}

void TerminalScreen::setCursorX(int x) {
    moveCursor(x, m_cursorY);
}

void TerminalScreen::setCursorY(int y) {
    moveCursor(m_cursorX, y);
}

void TerminalScreen::clearLine(int mode) {
    QMutexLocker locker(&m_mutex);
    int          start = 0;
    int          end   = m_cols;

    if (mode == 0) { // Cursor to end
        start = m_cursorX;
    } else if (mode == 1) { // Start to cursor
        end = m_cursorX + 1;
    }

    for (int x = start; x < end; ++x) {
        TerminalCell &cell = cellAt(x, m_cursorY);
        cell               = TerminalCell();
        cell.bgColor       = m_currentBg;
    }
    emit screenChanged();
}

void TerminalScreen::clearScreen(int mode) {
    QMutexLocker locker(&m_mutex);
    int          startRow = 0;
    int          endRow   = m_rows;

    if (mode == 0) { // Cursor to end
        clearLine(0);
        startRow = m_cursorY + 1;
    } else if (mode == 1) { // Start to cursor
        clearLine(1);
        endRow = m_cursorY;
    } else if (mode == 2) { // All
        startRow  = 0;
        endRow    = m_rows;
        m_cursorX = 0;
        m_cursorY = 0;
    }

    for (int y = startRow; y < endRow; ++y) {
        for (int x = 0; x < m_cols; ++x) {
            TerminalCell &cell = cellAt(x, y);
            cell               = TerminalCell();
            cell.bgColor       = m_currentBg;
        }
    }
    emit screenChanged();
}

void TerminalScreen::deleteChars(int count) {
    QMutexLocker locker(&m_mutex);
    int          remaining = m_cols - m_cursorX;
    int          toDelete  = std::min(count, remaining);

    for (int x = m_cursorX; x < m_cols - toDelete; ++x) {
        cellAt(x, m_cursorY) = cellAt(x + toDelete, m_cursorY);
    }

    for (int x = m_cols - toDelete; x < m_cols; ++x) {
        TerminalCell &cell = cellAt(x, m_cursorY);
        cell               = TerminalCell();
        cell.bgColor       = m_currentBg;
    }
    emit screenChanged();
}

void TerminalScreen::insertChars(int count) {
    QMutexLocker locker(&m_mutex);
    for (int x = m_cols - 1; x >= m_cursorX + count; --x) {
        cellAt(x, m_cursorY) = cellAt(x - count, m_cursorY);
    }

    for (int x = m_cursorX; x < std::min(m_cursorX + count, m_cols); ++x) {
        TerminalCell &cell = cellAt(x, m_cursorY);
        cell               = TerminalCell();
        cell.bgColor       = m_currentBg;
    }
    emit screenChanged();
}

void TerminalScreen::setFgColor(uint32_t color) {
    m_currentFg = color;
}

void TerminalScreen::setBgColor(uint32_t color) {
    m_currentBg = color;
}

void TerminalScreen::setBold(bool bold) {
    m_currentBold = bold;
}

void TerminalScreen::setInverse(bool inverse) {
    m_currentInverse = inverse;
}

void TerminalScreen::resetStyle() {
    m_currentFg      = 0xFFFFFFFF;
    m_currentBg      = 0xFF000000;
    m_currentBold    = false;
    m_currentInverse = false;
}

const TerminalCell &TerminalScreen::cell(int x, int y) const {
    static TerminalCell empty;
    if (y >= 0 && y < m_rows && x >= 0 && x < m_cols) {
        // Const cast to call helper, but we know we are reading
        return const_cast<TerminalScreen *>(this)->cellAt(x, y);
    }
    return empty;
}

void TerminalScreen::scrollUp() {
    // Ring buffer scroll: just increment top pointer
    m_topRow = (m_topRow + 1) % m_historySize;

    // Clear the new bottom row (which was the old top row)
    // The bottom row is at visual index m_rows - 1
    int bottomRowIndex = (m_topRow + m_rows - 1) % m_historySize;

    for (int x = 0; x < m_cols; ++x) {
        m_grid[bottomRowIndex][x]         = TerminalCell();
        m_grid[bottomRowIndex][x].bgColor = m_currentBg;
    }

    emit screenChanged();
}

void TerminalScreen::setSelection(int startX, int startY, int endX, int endY) {
    QMutexLocker locker(&m_mutex);
    m_hasSelection = true;

    // Normalize coordinates (start should be before end)
    if (startY > endY || (startY == endY && startX > endX)) {
        std::swap(startX, endX);
        std::swap(startY, endY);
    }

    m_selStartX = std::clamp(startX, 0, m_cols - 1);
    m_selStartY = std::clamp(startY, 0, m_rows - 1);
    m_selEndX   = std::clamp(endX, 0, m_cols - 1);
    m_selEndY   = std::clamp(endY, 0, m_rows - 1);

    emit screenChanged();
}

void TerminalScreen::clearSelection() {
    QMutexLocker locker(&m_mutex);
    if (m_hasSelection) {
        m_hasSelection = false;
        emit screenChanged();
    }
}

bool TerminalScreen::isSelected(int x, int y) const {
    if (!m_hasSelection)
        return false;

    if (y < m_selStartY || y > m_selEndY)
        return false;

    if (y == m_selStartY && y == m_selEndY) {
        return x >= m_selStartX && x <= m_selEndX;
    }

    if (y == m_selStartY)
        return x >= m_selStartX;
    if (y == m_selEndY)
        return x <= m_selEndX;

    return true; // In between rows
}

QString TerminalScreen::getSelectedText() const {
    if (!m_hasSelection)
        return QString();

    // Note: We can't easily lock here if this is called from GUI thread while worker is writing
    // Ideally, caller locks mutex()

    QString text;
    for (int y = m_selStartY; y <= m_selEndY; ++y) {
        int startX = (y == m_selStartY) ? m_selStartX : 0;
        int endX   = (y == m_selEndY) ? m_selEndX : m_cols - 1;

        for (int x = startX; x <= endX; ++x) {
            const TerminalCell &c = cell(x, y);
            if (c.codePoint) {
                text.append(QChar(c.codePoint));
            } else {
                text.append(' '); // Empty cells are spaces
            }
        }

        if (y < m_selEndY) {
            text.append('\n');
        }
    }
    return text;
}
