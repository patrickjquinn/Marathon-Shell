#include "crashhandler.h"
#include <QDebug>
#include <QCoreApplication>
#include <csignal>
#include <cstdlib>
#ifdef __GLIBC__
#include <execinfo.h>
#endif
#include <unistd.h>

CrashHandler* CrashHandler::s_instance = nullptr;
bool CrashHandler::s_inCrashHandler = false;

CrashHandler* CrashHandler::instance()
{
    if (!s_instance) {
        s_instance = new CrashHandler();
    }
    return s_instance;
}

CrashHandler::CrashHandler(QObject *parent)
    : QObject(parent)
{
    qDebug() << "[CrashHandler] Initializing crash protection";
}

CrashHandler::~CrashHandler()
{
    s_instance = nullptr;
}

void CrashHandler::install()
{
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
        // Try to print backtrace
#ifdef __GLIBC__
        void* array[50];
        size_t size = backtrace(array, 50);
        qCritical() << "[CrashHandler] Backtrace:";
        char** messages = backtrace_symbols(array, size);
        for (size_t i = 0; i < size; i++) {
            qCritical() << "  " << messages[i];
        }
        free(messages);
#else
        qCritical() << "[CrashHandler] Backtrace not available (musl libc)";
#endif
        
        // Don't call the default terminate handler (which would abort)
        // Instead, try to continue (may not always work)
        qCritical() << "[CrashHandler] Attempting to continue (shell may be unstable)";
    });
    
    qDebug() << "[CrashHandler] Crash protection installed (WARNING: This is a mitigation, not a fix)";
    qDebug() << "[CrashHandler] TODO: Implement proper multi-process app isolation";
}

void CrashHandler::setCrashCallback(std::function<void(const QString&)> callback)
{
    m_crashCallback = callback;
}

bool CrashHandler::isInCrashHandler()
{
    return s_inCrashHandler;
}

void CrashHandler::signalHandler(int signum)
{
    // Prevent recursive crash handling
    if (s_inCrashHandler) {
        qCritical() << "[CrashHandler] Recursive crash detected - aborting";
        std::abort();
    }
    
    s_inCrashHandler = true;
    
    const char* signame = "UNKNOWN";
    const char* description = "Unknown signal";
    
    switch (signum) {
        case SIGSEGV:
            signame = "SIGSEGV";
            description = "Segmentation fault (invalid memory access)";
            break;
        case SIGABRT:
            signame = "SIGABRT";
            description = "Abort signal (assertion failed or abort() called)";
            break;
        case SIGFPE:
            signame = "SIGFPE";
            description = "Floating point exception";
            break;
        case SIGILL:
            signame = "SIGILL";
            description = "Illegal instruction";
            break;
        case SIGBUS:
            signame = "SIGBUS";
            description = "Bus error (invalid memory alignment)";
            break;
    }
    
    qCritical() << "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    qCritical() << "[CrashHandler] CRASH DETECTED!";
    qCritical() << "[CrashHandler] Signal:" << signame << "(" << signum << ")";
    qCritical() << "[CrashHandler] Description:" << description;
    qCritical() << "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    
    // Print backtrace
    // Print backtrace
#ifdef __GLIBC__
    void* array[50];
    size_t size = backtrace(array, 50);
    qCritical() << "[CrashHandler] Backtrace:";
    char** messages = backtrace_symbols(array, size);
    for (size_t i = 0; i < size; i++) {
        qCritical() << "  " << messages[i];
    }
    free(messages);
#else
    qCritical() << "[CrashHandler] Backtrace not available (musl libc)";
#endif
    
    qCritical() << "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    qCritical() << "[CrashHandler] CRITICAL ARCHITECTURAL ISSUE:";
    qCritical() << "[CrashHandler] Apps are running in the same process as the shell!";
    qCritical() << "[CrashHandler] This crash likely came from an app, but it's taking down";
    qCritical() << "[CrashHandler] the entire shell because of poor isolation.";
    qCritical() << "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    qCritical() << "[CrashHandler] RECOMMENDED FIX:";
    qCritical() << "[CrashHandler] 1. Implement multi-process architecture";
    qCritical() << "[CrashHandler] 2. Run each app in its own QProcess";
    qCritical() << "[CrashHandler] 3. Use Qt Application Manager's multi-process mode";
    qCritical() << "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    
    // Notify instance
    if (s_instance) {
        QString msg = QString("%1: %2").arg(signame).arg(description);
        emit s_instance->crashDetected(signame, msg);
        
        if (s_instance->m_crashCallback) {
            s_instance->m_crashCallback(msg);
        }
    }
    
    qCritical() << "[CrashHandler] Shell will now exit (cannot safely continue)";
    qCritical() << "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━";
    
    // Restore default handler and re-raise to get core dump
    signal(signum, SIG_DFL);
    raise(signum);
}

void CrashHandler::setupSignalHandlers()
{
    // Install handlers for various crash signals
    signal(SIGSEGV, signalHandler);  // Segmentation fault
    signal(SIGABRT, signalHandler);  // Abort
    signal(SIGFPE, signalHandler);   // Floating point exception
    signal(SIGILL, signalHandler);   // Illegal instruction
    signal(SIGBUS, signalHandler);   // Bus error
    
    qDebug() << "[CrashHandler] Installed signal handlers for: SIGSEGV, SIGABRT, SIGFPE, SIGILL, SIGBUS";
}


