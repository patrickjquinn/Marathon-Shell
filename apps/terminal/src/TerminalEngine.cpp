#include "TerminalEngine.h"
#include "TerminalScreen.h"
#include <QDebug>
#include <QSocketNotifier>
#include <QCoreApplication>

#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>

#if defined(Q_OS_LINUX) || defined(Q_OS_MACOS)
#include <termios.h>
#if defined(Q_OS_MACOS)
#include <util.h>
#else
#include <pty.h>
#endif
#endif

TerminalEngine::TerminalEngine(QObject *parent)
    : QObject(parent)
    , m_masterFd(-1)
    , m_pid(-1)
    , m_notifier(nullptr)
    , m_title("Terminal")
    , m_screen(new TerminalScreen(this))
    , m_state(Normal) {
    qDebug() << "[TerminalEngine] Created";
}

TerminalEngine::~TerminalEngine() {
    terminate();
}

void TerminalEngine::start(const QString &shell) {
    if (m_pid > 0)
        return;

    QString shellProgram = shell;
    if (shellProgram.isEmpty()) {
        shellProgram = qEnvironmentVariable("SHELL");
        if (shellProgram.isEmpty())
            shellProgram = "/bin/bash";
    }

    struct winsize winp;
    winp.ws_col    = m_screen->cols();
    winp.ws_row    = m_screen->rows();
    winp.ws_xpixel = 0;
    winp.ws_ypixel = 0;

    pid_t pid = forkpty(&m_masterFd, nullptr, nullptr, &winp);

    if (pid < 0) {
        qCritical() << "[TerminalEngine] forkpty failed";
        return;
    }

    if (pid == 0) {
        setenv("TERM", "xterm-256color", 1);
        setenv("COLORTERM", "truecolor", 1);
        QByteArray  shellPath = shellProgram.toUtf8();
        const char *argv[]    = {shellPath.constData(), "-i", nullptr};
        execvp(argv[0], (char *const *)argv);
        _exit(1);
    } else {
        m_pid     = pid;
        int flags = fcntl(m_masterFd, F_GETFL);
        fcntl(m_masterFd, F_SETFL, flags | O_NONBLOCK);

        m_notifier = new QSocketNotifier(m_masterFd, QSocketNotifier::Read, this);
        connect(m_notifier, &QSocketNotifier::activated, this, &TerminalEngine::onReadActivated);

        emit runningChanged();
    }
}

void TerminalEngine::onReadActivated() {
    char    buffer[4096];
    ssize_t bytesRead = read(m_masterFd, buffer, sizeof(buffer));

    if (bytesRead > 0) {
        processOutput(QByteArray(buffer, bytesRead));
    } else if (bytesRead <= 0 && errno != EAGAIN) {
        terminate();
    }
}

void TerminalEngine::processOutput(const QByteArray &data) {
    for (char ch : data) {
        if (m_state == Normal) {
            if (ch == '\x1b') {
                m_state = Escape;
            } else if (ch == '\r') {
                m_screen->setCursorX(0);
            } else if (ch == '\n') {
                m_screen->newLine();
            } else if (ch == '\b') {
                m_screen->backspace();
            } else if (ch == '\t') {
                // Simple tab handling (every 8 chars)
                int x       = m_screen->cursorX();
                int nextTab = (x / 8 + 1) * 8;
                m_screen->setCursorX(nextTab);
            } else if (ch == '\a') {
                // Bell - ignore
            } else if (static_cast<unsigned char>(ch) >= 32) {
                m_screen->putChar(ch);
            }
        } else {
            parseEscapeSequence(ch);
        }
    }
}

void TerminalEngine::parseEscapeSequence(char ch) {
    if (m_state == Escape) {
        if (ch == '[') {
            m_state = CSI;
            m_sequenceBuffer.clear();
            m_params.clear();
        } else if (ch == ']') {
            m_state = OSC;
            m_sequenceBuffer.clear();
        } else if (ch == '(' || ch == ')') {
            m_state = Charset;
        } else {
            // Unknown escape sequence, reset
            m_state = Normal;
        }
    } else if (m_state == CSI) {
        if (isdigit(ch)) {
            m_sequenceBuffer.append(ch);
        } else if (ch == ';') {
            m_params.append(m_sequenceBuffer.toInt());
            m_sequenceBuffer.clear();
        } else if (ch >= 0x40 && ch <= 0x7E) {
            // Final byte
            m_params.append(m_sequenceBuffer.toInt());
            handleCSI(QString(ch));
            m_state = Normal;
        }
    } else if (m_state == OSC) {
        if (ch == '\a' || ch == '\x9c') { // BEL or ST
            handleOSC(m_sequenceBuffer);
            m_state = Normal;
        } else {
            m_sequenceBuffer.append(ch);
        }
    } else if (m_state == Charset) {
        // Ignore charset selection
        m_state = Normal;
    }
}

void TerminalEngine::handleCSI(const QString &seq) {
    int p1 = m_params.value(0, 0);
    int p2 = m_params.value(1, 0);

    if (seq == "m") { // SGR - Select Graphic Rendition
        if (m_params.isEmpty()) {
            m_screen->resetStyle();
        } else {
            for (int param : m_params) {
                if (param == 0)
                    m_screen->resetStyle();
                else if (param == 1)
                    m_screen->setBold(true);
                else if (param == 7)
                    m_screen->setInverse(true);
                else if (param == 22)
                    m_screen->setBold(false);
                else if (param == 27)
                    m_screen->setInverse(false);
                else if (param >= 30 && param <= 37) {
                    // Standard FG
                    const uint32_t colors[] = {0xFF000000, 0xFFCC0000, 0xFF4E9A06, 0xFFC4A000,
                                               0xFF3465A4, 0xFF75507B, 0xFF06989A, 0xFFD3D7CF};
                    m_screen->setFgColor(colors[param - 30]);
                } else if (param >= 40 && param <= 47) {
                    // Standard BG
                    const uint32_t colors[] = {0xFF000000, 0xFFCC0000, 0xFF4E9A06, 0xFFC4A000,
                                               0xFF3465A4, 0xFF75507B, 0xFF06989A, 0xFFD3D7CF};
                    m_screen->setBgColor(colors[param - 40]);
                } else if (param == 39)
                    m_screen->setFgColor(0xFFFFFFFF); // Default FG
                else if (param == 49)
                    m_screen->setBgColor(0xFF000000); // Default BG
                else if (param >= 90 && param <= 97) {
                    // Bright FG
                    const uint32_t colors[] = {0xFF555753, 0xFFEF2929, 0xFF8AE234, 0xFFFCE94F,
                                               0xFF729FCF, 0xFFAD7FA8, 0xFF34E2E2, 0xFFEEEEEC};
                    m_screen->setFgColor(colors[param - 90]);
                }
            }
        }
    } else if (seq == "A") { // Cursor Up
        m_screen->moveCursorRelative(0, -std::max(1, p1));
    } else if (seq == "B") { // Cursor Down
        m_screen->moveCursorRelative(0, std::max(1, p1));
    } else if (seq == "C") { // Cursor Forward
        m_screen->moveCursorRelative(std::max(1, p1), 0);
    } else if (seq == "D") { // Cursor Back
        m_screen->moveCursorRelative(-std::max(1, p1), 0);
    } else if (seq == "H" || seq == "f") { // Cursor Position
        int row = std::max(1, p1) - 1;
        int col = std::max(1, p2) - 1;
        m_screen->moveCursor(col, row);
    } else if (seq == "J") { // Erase in Display
        m_screen->clearScreen(p1);
    } else if (seq == "K") { // Erase in Line
        m_screen->clearLine(p1);
    } else if (seq == "P") { // Delete Characters
        m_screen->deleteChars(std::max(1, p1));
    } else if (seq == "@") { // Insert Characters
        m_screen->insertChars(std::max(1, p1));
    }
}

void TerminalEngine::handleOSC(const QString &seq) {
    if (seq.startsWith("0;") || seq.startsWith("2;")) {
        int semi = seq.indexOf(';');
        if (semi != -1) {
            m_title = seq.mid(semi + 1);
            emit titleChanged();
        }
    }
}

void TerminalEngine::sendInput(const QString &text) {
    if (m_masterFd != -1) {
        QByteArray data = text.toUtf8();
        write(m_masterFd, data.constData(), data.size());
    }
}

void TerminalEngine::sendKey(int key, const QString &text, int modifiers) {
    if (m_masterFd == -1)
        return;

    QByteArray data;

    if (modifiers & Qt::ControlModifier) {
        if (key >= Qt::Key_A && key <= Qt::Key_Z) {
            data.append((char)(key - Qt::Key_A + 1));
        } else if (key == Qt::Key_BracketLeft)
            data.append('\x1b');
        else if (key == Qt::Key_Backslash)
            data.append('\x1c');
        else if (key == Qt::Key_BracketRight)
            data.append('\x1d');
    } else {
        if (key == Qt::Key_Return || key == Qt::Key_Enter)
            data.append('\r');
        else if (key == Qt::Key_Backspace)
            data.append('\x7f');
        else if (key == Qt::Key_Tab)
            data.append('\t');
        else if (key == Qt::Key_Up)
            data.append("\x1b[A");
        else if (key == Qt::Key_Down)
            data.append("\x1b[B");
        else if (key == Qt::Key_Right)
            data.append("\x1b[C");
        else if (key == Qt::Key_Left)
            data.append("\x1b[D");
        else if (key == Qt::Key_Escape)
            data.append('\x1b');
        else if (key == Qt::Key_Home)
            data.append("\x1b[H");
        else if (key == Qt::Key_End)
            data.append("\x1b[F");
        else if (key == Qt::Key_PageUp)
            data.append("\x1b[5~");
        else if (key == Qt::Key_PageDown)
            data.append("\x1b[6~");
        else if (!text.isEmpty())
            data.append(text.toUtf8());
    }

    if (!data.isEmpty()) {
        write(m_masterFd, data.constData(), data.size());
    }
}

void TerminalEngine::terminate() {
    if (m_pid > 0) {
        if (m_notifier) {
            m_notifier->setEnabled(false);
            delete m_notifier;
            m_notifier = nullptr;
        }
        if (m_masterFd != -1) {
            close(m_masterFd);
            m_masterFd = -1;
        }
        kill(m_pid, SIGKILL);
        waitpid(m_pid, nullptr, 0);
        m_pid = -1;
        emit runningChanged();
        emit finished(-1);
    }
}

void TerminalEngine::resize(int cols, int rows) {
    if (m_masterFd != -1) {
        struct winsize winp;
        winp.ws_col    = cols;
        winp.ws_row    = rows;
        winp.ws_xpixel = 0;
        winp.ws_ypixel = 0;
        ioctl(m_masterFd, TIOCSWINSZ, &winp);

        m_screen->resize(cols, rows);
    }
}

void TerminalEngine::sendSignal(int signal) {
    if (m_pid > 0)
        kill(m_pid, signal);
}

void TerminalEngine::sendMousePress(int x, int y, int button) { /* TODO */ }
void TerminalEngine::sendMouseRelease(int x, int y, int button) { /* TODO */ }
void TerminalEngine::sendMouseMove(int x, int y, int buttons) { /* TODO */ }
