#pragma once

#include <QObject>
#include <QVector>
#include <QColor>
#include <QMutex>

struct TerminalCell {
    uint32_t codePoint = ' ';
    uint32_t fgColor   = 0xFFFFFFFF;
    uint32_t bgColor   = 0xFF000000;
    bool     bold      = false;
    bool     italic    = false;
    bool     underline = false;
    bool     inverse   = false;

    bool     operator==(const TerminalCell &other) const {
        return codePoint == other.codePoint && fgColor == other.fgColor &&
            bgColor == other.bgColor && bold == other.bold && italic == other.italic &&
            underline == other.underline && inverse == other.inverse;
    }

    bool operator!=(const TerminalCell &other) const {
        return !(*this == other);
    }
};

class TerminalScreen : public QObject {
    Q_OBJECT

  public:
    explicit TerminalScreen(QObject *parent = nullptr);

    void resize(int cols, int rows);
    void clear();

    void putChar(uint32_t codePoint);
    void newLine();
    void backspace();

    void moveCursor(int x, int y);
    void moveCursorRelative(int dx, int dy);
    void setCursorX(int x);
    void setCursorY(int y);

    void clearLine(int mode);
    void clearScreen(int mode);
    void deleteChars(int count);
    void insertChars(int count);

    void setFgColor(uint32_t color);
    void setBgColor(uint32_t color);
    void setBold(bool bold);
    void setInverse(bool inverse);
    void resetStyle();

    int  cols() const {
        return m_cols;
    }
    int rows() const {
        return m_rows;
    }
    int cursorX() const {
        return m_cursorX;
    }
    int cursorY() const {
        return m_cursorY;
    }
    const TerminalCell &cell(int x, int y) const;

    void                setSelection(int startX, int startY, int endX, int endY);
    void                clearSelection();
    bool                hasSelection() const {
        return m_hasSelection;
    }
    bool    isSelected(int x, int y) const;
    QString getSelectedText() const;

    QMutex *mutex() {
        return &m_mutex;
    }

  signals:
    void screenChanged();
    void cursorChanged();

  private:
    void                           scrollUp();
    TerminalCell                  &cellAt(int x, int y);

    int                            m_cols;
    int                            m_rows;
    int                            m_cursorX;
    int                            m_cursorY;

    int                            m_topRow;
    int                            m_historySize;

    uint32_t                       m_currentFg;
    uint32_t                       m_currentBg;
    bool                           m_currentBold;
    bool                           m_currentInverse;

    bool                           m_hasSelection;
    int                            m_selStartX, m_selStartY;
    int                            m_selEndX, m_selEndY;

    QVector<QVector<TerminalCell>> m_grid;

    QMutex                         m_mutex;
};
