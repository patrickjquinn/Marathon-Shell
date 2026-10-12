#pragma once

#include <QList>
#include <QPair>

using PageRange = QPair<quintptr, quintptr>;

// Readable private mappings of this process, from /proc/self/maps, minus
// device maps (/dev, e.g. GPU BOs) and kernel pseudo regions.
QList<PageRange> ownResidentRanges();

// Reads one byte of every 4 KiB page in [first, second) so the kernel keeps
// it resident. Returns the number of pages read.
int touchPages(const QList<PageRange> &ranges);

// Re-touches the whole resident private working set: the pool's keepalive
// when mlockall is unavailable.
void touchOwnResidentPages();
