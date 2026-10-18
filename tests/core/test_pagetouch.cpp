#include <QTest>

#include <sys/mman.h>
#include <unistd.h>

#include "pagetouch.h"

class TestPageTouch : public QObject {
    Q_OBJECT

  private slots:
    void skipsPagesUnmappedAfterTheSnapshot() {
        const long page = ::sysconf(_SC_PAGESIZE);
        auto      *base = static_cast<char *>(
            ::mmap(nullptr, 3 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0));
        QVERIFY(base != MAP_FAILED);
        const PageRange snapshot{reinterpret_cast<quintptr>(base),
                                 reinterpret_cast<quintptr>(base + 3 * page)};
        QVERIFY(::munmap(base + page, page) == 0);

        QCOMPARE(touchPages({snapshot}), static_cast<int>(2 * page / 4096));

        ::munmap(base, page);
        ::munmap(base + 2 * page, page);
    }

    void listsOwnAnonymousMappings() {
        const long page = ::sysconf(_SC_PAGESIZE);
        void *p = ::mmap(nullptr, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        QVERIFY(p != MAP_FAILED);
        const auto a     = reinterpret_cast<quintptr>(p);
        bool       found = false;
        const QList<PageRange> ranges = ownResidentRanges();
        for (const PageRange &r : ranges)
            found = found || (r.first <= a && a < r.second);
        QVERIFY(found);
        ::munmap(p, page);
    }
};

QTEST_GUILESS_MAIN(TestPageTouch)
#include "test_pagetouch.moc"
