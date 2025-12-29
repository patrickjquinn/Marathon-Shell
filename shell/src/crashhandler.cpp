#include "crashhandler.h"
#include <QCoreApplication>
#include <QDebug>
#include <csignal>
#include <cstdlib>
#ifdef __GLIBC__
#include <execinfo.h>
#endif
#include <cstring>
#include <unistd.h>
#include <unistd.h>

CrashHandler *CrashHandler::s_instance       = nullptr;
bool          CrashHandler::s_inCrashHandler = false;

static void   writeStr(int fd, const char *s) {
    if (!s)
        return;
    ::write(fd, s, static_cast<size_t>(std::strlen(s)));
}

CrashHandler *CrashHandler::instance() {
    if (!s_instance) {
        s_instance = new CrashHandler();
    }
    return s_instance;
}

CrashHandler::CrashHandler(QObject *parent)
    : QObject(parent) {
    qDebug() << "[CrashHandler] Initializing crash protection";
}

CrashHandler::~CrashHandler() {
    s_instance = nullptr;
}

void CrashHandler::install() {
    qDebug() << "[CrashHandler] Installing signal handlers";
    setupSignalHandlers();

    // Set terminate handler for uncaught exceptions
    std::set_terminate([]() {
        qCritical() << "[CrashHandler] Uncaught exception detected!";
        qCritical() << "[CrashHandler] This is a critical error - the app may be unstable";

        if (s_instance) {
            emit s_instance->crashDetected("EXCEPTION", "Uncaught C++ exception");
        }

        // Try to print backtrace
#ifdef __GLIBC__
        void  *array[50];
        size_t size = backtrace(array, 50);
        qCritical() << "[CrashHandler] Backtrace:";
        backtrace_symbols_fd(array, static_cast<int>(size), STDERR_FILENO);
#else
        qCritical() << "[CrashHandler] Backtrace not available (musl libc)";
#endif

        // Don't call the default terminate handler (which would abort)
        // Instead, try to continue (may not always work)
        qCritical() << "[CrashHandler] Attempting to continue (shell may be unstable)";
    });

    qDebug()
        << "[CrashHandler] Crash protection installed (WARNING: This is a mitigation, not a fix)";
    qDebug() << "[CrashHandler] TODO: Implement proper multi-process app isolation";
}

void CrashHandler::setCrashCallback(std::function<void(const QString &)> callback) {
    m_crashCallback = callback;
}

bool CrashHandler::isInCrashHandler() {
    return s_inCrashHandler;
}

void CrashHandler::signalHandler(int signum) {
    // Prevent recursive crash handling
    if (s_inCrashHandler) {
        const char *msg = "[CrashHandler] Recursive crash detected - aborting\n";
        ::write(STDERR_FILENO, msg, std::strlen(msg));
        std::_Exit(127);
    }

    s_inCrashHandler = true;

    const char *signame     = "UNKNOWN";
    const char *description = "Unknown signal";

    switch (signum) {
        case SIGSEGV:
            signame     = "SIGSEGV";
            description = "Segmentation fault (invalid memory access)";
            break;
        case SIGABRT:
            signame     = "SIGABRT";
            description = "Abort signal (assertion failed or abort() called)";
            break;
        case SIGFPE:
            signame     = "SIGFPE";
            description = "Floating point exception";
            break;
        case SIGILL:
            signame     = "SIGILL";
            description = "Illegal instruction";
            break;
        case SIGBUS:
            signame     = "SIGBUS";
            description = "Bus error (invalid memory alignment)";
            break;
    }

    // IMPORTANT: This is a signal handler. Avoid Qt/QString allocations here.
    writeStr(STDERR_FILENO, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    writeStr(STDERR_FILENO, "[CrashHandler] CRASH DETECTED!\n");
    writeStr(STDERR_FILENO, "[CrashHandler] Signal: ");
    writeStr(STDERR_FILENO, signame);
    writeStr(STDERR_FILENO, "\n");
    writeStr(STDERR_FILENO, "[CrashHandler] Description: ");
    writeStr(STDERR_FILENO, description);
    writeStr(STDERR_FILENO, "\n");
    writeStr(STDERR_FILENO, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

    // Print backtrace (best-effort). Use symbols_fd to avoid heap allocations.
#ifdef __GLIBC__
    void  *array[50];
    size_t size = backtrace(array, 50);
    writeStr(STDERR_FILENO, "[CrashHandler] Backtrace:\n");
    backtrace_symbols_fd(array, static_cast<int>(size), STDERR_FILENO);
#else
    writeStr(STDERR_FILENO, "[CrashHandler] Backtrace not available (musl libc)\n");
#endif

    writeStr(STDERR_FILENO, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    writeStr(STDERR_FILENO, "[CrashHandler] Shell will now exit (cannot safely continue)\n");
    writeStr(STDERR_FILENO, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

    // Restore default handler and re-raise to get core dump
    signal(signum, SIG_DFL);
    raise(signum);
}

void CrashHandler::setupSignalHandlers() {
    // Install handlers for various crash signals
    signal(SIGSEGV, signalHandler); // Segmentation fault
    signal(SIGABRT, signalHandler); // Abort
    signal(SIGFPE, signalHandler);  // Floating point exception
    signal(SIGILL, signalHandler);  // Illegal instruction
    signal(SIGBUS, signalHandler);  // Bus error

    qDebug()
        << "[CrashHandler] Installed signal handlers for: SIGSEGV, SIGABRT, SIGFPE, SIGILL, SIGBUS";
}
