#include "pagetouch.h"

#include <QFile>

#include <cerrno>
#include <sys/uio.h>
#include <unistd.h>
#include <vector>

QList<PageRange> ownResidentRanges() {
    QList<PageRange> ranges;
    QFile            maps(QStringLiteral("/proc/self/maps"));
    if (!maps.open(QIODevice::ReadOnly))
        return ranges;
    const QList<QByteArray> lines = maps.readAll().split('\n');
    for (const QByteArray &l : lines) {
        // Fields: address perms offset dev inode pathname
        const QList<QByteArray> f = l.simplified().split(' ');
        if (f.size() < 2)
            continue;
        const QByteArray &perms = f.at(1);
        if (perms.size() < 4 || perms.at(0) != 'r' || perms.at(3) != 'p')
            continue;
        const QByteArray path = f.size() >= 6 ? f.at(5) : QByteArray();
        if (path.startsWith("/dev") || path.startsWith("[vsyscall]") || path.startsWith("[vvar]"))
            continue;
        const QList<QByteArray> range = f.at(0).split('-');
        if (range.size() != 2)
            continue;
        bool                startOk = false, endOk = false;
        const unsigned long start = range.at(0).toULong(&startOk, 16);
        const unsigned long end   = range.at(1).toULong(&endOk, 16);
        if (!startOk || !endOk || end <= start)
            continue;
        ranges.append({start, end});
    }
    return ranges;
}

// Through process_vm_readv rather than a pointer read: other threads map
// and unmap while we walk a snapshot of /proc/self/maps, and a page gone in
// between faults the read (EFAULT) instead of the process (SIGSEGV).
int touchPages(const QList<PageRange> &ranges) {
    constexpr quintptr kStep  = 4096;
    constexpr size_t   kBatch = 512;
    unsigned char      sink[kBatch];
    std::vector<iovec> remote;
    remote.reserve(kBatch);
    int  touched = 0;

    auto flush = [&]() {
        size_t i = 0;
        while (i < remote.size()) {
            const size_t  left = remote.size() - i;
            iovec         local{sink, left};
            const ssize_t n = ::process_vm_readv(::getpid(), &local, 1, remote.data() + i, left, 0);
            if (n < 0) {
                if (errno != EFAULT)
                    break;
                ++i;
                continue;
            }
            touched += static_cast<int>(n);
            i += static_cast<size_t>(n);
            if (static_cast<size_t>(n) < left)
                ++i;
        }
        remote.clear();
    };

    for (const PageRange &r : ranges) {
        for (quintptr a = r.first; a < r.second; a += kStep) {
            remote.push_back({reinterpret_cast<void *>(a), 1});
            if (remote.size() == kBatch)
                flush();
        }
    }
    flush();
    return touched;
}

void touchOwnResidentPages() {
    touchPages(ownResidentRanges());
}
