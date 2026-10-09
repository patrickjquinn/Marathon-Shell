// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "unixsignals.h"

#include <QSocketNotifier>

#include <cerrno>
#include <csignal>
#include <cstring>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

namespace keel {

int UnixSignals::s_fds[2] = { -1, -1 };

UnixSignals::UnixSignals(QObject *parent)
    : QObject(parent)
{
    if (::socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, s_fds) != 0) {
        m_error = QString::fromLocal8Bit(std::strerror(errno));
        s_fds[0] = s_fds[1] = -1;
        return;
    }
    ::fcntl(s_fds[0], F_SETFL, O_NONBLOCK);
    ::fcntl(s_fds[1], F_SETFL, O_NONBLOCK);
    m_notifier = new QSocketNotifier(s_fds[1], QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &UnixSignals::onActivated);

    struct sigaction sa {};
    sa.sa_handler = &UnixSignals::handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART;
    ::sigaction(SIGTERM, &sa, nullptr);
    ::sigaction(SIGINT, &sa, nullptr);
    ::sigaction(SIGHUP, &sa, nullptr);
}

UnixSignals::~UnixSignals()
{
    ::signal(SIGTERM, SIG_DFL);
    ::signal(SIGINT, SIG_DFL);
    ::signal(SIGHUP, SIG_DFL);
    if (s_fds[0] >= 0) {
        ::close(s_fds[0]);
        ::close(s_fds[1]);
        s_fds[0] = s_fds[1] = -1;
    }
}

void UnixSignals::handler(int signalNumber)
{
    const char c = static_cast<char>(signalNumber);
    if (s_fds[0] >= 0) {
        ssize_t ignored = ::write(s_fds[0], &c, 1);
        (void)ignored;
    }
}

void UnixSignals::onActivated()
{
    char c = 0;
    while (::read(s_fds[1], &c, 1) == 1)
        emit terminateRequested(static_cast<int>(c));
}

} // namespace keel
