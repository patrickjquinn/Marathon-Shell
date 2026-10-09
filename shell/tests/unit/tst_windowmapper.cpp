// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include <QtTest>

#include "core/windowmapper.h"

using namespace keel;

namespace {

SurfaceInfo toplevel(const QString &title = QString(), const QString &appId = QString())
{
    SurfaceInfo i;
    i.title = title;
    i.appId = appId;
    i.kind = SurfaceKind::Toplevel;
    return i;
}

SurfaceInfo child(SurfaceKind kind, SurfaceKey parent)
{
    SurfaceInfo i;
    i.kind = kind;
    i.parent = parent;
    return i;
}

const QString cover = QStringLiteral("keel:cover");

} // namespace

class TestWindowMapper : public QObject
{
    Q_OBJECT
private slots:
    void initialState()
    {
        WindowMapper m;
        QCOMPARE(m.windows(), QList<int>() << WindowMapper::MainWindowId);
        QCOMPARE(m.roleOf(WindowMapper::MainWindowId), WindowRole::Main);
        QCOMPARE(m.primarySurface(WindowMapper::MainWindowId), SurfaceKey(0));
        QCOMPARE(m.coverWindow(), 0);
    }

    void mainAndCover()
    {
        WindowMapper m;
        QSignalSpy created(&m, &WindowMapper::windowCreated);
        QSignalSpy assigned(&m, &WindowMapper::surfaceAssigned);

        QCOMPARE(m.mapSurface(10, toplevel(QStringLiteral("My App"))), int(WindowMapper::MainWindowId));
        QCOMPARE(created.count(), 0);   // main window pre-exists

        const int c = m.mapSurface(20, toplevel(cover));
        QVERIFY(c != 0);
        QVERIFY(c != WindowMapper::MainWindowId);
        QCOMPARE(m.roleOf(c), WindowRole::Cover);
        QCOMPARE(m.coverWindow(), c);
        QCOMPARE(created.count(), 1);
        QCOMPARE(created.at(0).at(0).toInt(), c);
        QCOMPARE(created.at(0).at(1).value<keel::WindowRole>(), WindowRole::Cover);
        QCOMPARE(assigned.count(), 2);
        QCOMPARE(m.primarySurface(c), SurfaceKey(20));
        QCOMPARE(m.windows().size(), 2);
    }

    void coverBeforeMain()
    {
        WindowMapper m;
        const int c = m.mapSurface(20, toplevel(cover));
        QCOMPARE(m.roleOf(c), WindowRole::Cover);
        QCOMPARE(m.primarySurface(WindowMapper::MainWindowId), SurfaceKey(0));
        QCOMPARE(m.mapSurface(10, toplevel()), int(WindowMapper::MainWindowId));
    }

    void coverByAppId()
    {
        WindowMapper m;
        m.mapSurface(10, toplevel(QString(), QStringLiteral("org.example.app")));
        const int c = m.mapSurface(20, toplevel(QString(), QStringLiteral("org.example.app.keel-cover")));
        QCOMPARE(m.roleOf(c), WindowRole::Cover);
    }

    void secondaryToplevels()
    {
        WindowMapper m;
        m.mapSurface(10, toplevel());
        const int s1 = m.mapSurface(11, toplevel(QStringLiteral("Settings")));
        const int s2 = m.mapSurface(12, toplevel(QStringLiteral("About")));
        QVERIFY(s1 != s2);
        QCOMPARE(m.roleOf(s1), WindowRole::Secondary);
        QCOMPARE(m.roleOf(s2), WindowRole::Secondary);

        QSignalSpy destroyed(&m, &WindowMapper::windowDestroyed);
        m.unmapSurface(11);
        QCOMPARE(destroyed.count(), 1);
        QCOMPARE(destroyed.at(0).at(0).toInt(), s1);
        QVERIFY(!m.hasWindow(s1));
        QVERIFY(m.hasWindow(s2));
    }

    void childrenFollowParent()
    {
        WindowMapper m;
        m.mapSurface(10, toplevel());
        const int c = m.mapSurface(20, toplevel(cover));
        QCOMPARE(m.mapSurface(30, child(SurfaceKind::Popup, 10)), int(WindowMapper::MainWindowId));
        QCOMPARE(m.mapSurface(31, child(SurfaceKind::SubSurface, 20)), c);
        QCOMPARE(m.mapSurface(32, child(SurfaceKind::Transient, 31)), c);
        // Unknown parent: main window.
        QCOMPARE(m.mapSurface(33, child(SurfaceKind::Popup, 999)), int(WindowMapper::MainWindowId));
        QCOMPARE(m.surfacesInWindow(c), QList<SurfaceKey>() << 20 << 31 << 32);
    }

    void childMappedBeforeParentFollowsIt()
    {
        WindowMapper m;
        m.mapSurface(10, toplevel());
        // Subsurface commits before its parent has content.
        QCOMPARE(m.mapSurface(31, child(SurfaceKind::SubSurface, 20)), int(WindowMapper::MainWindowId));
        const int c = m.mapSurface(20, toplevel(cover));
        QCOMPARE(m.windowForSurface(31), c);
    }

    void coverUnmapDestroysCoverWindow()
    {
        WindowMapper m;
        m.mapSurface(10, toplevel());
        const int c = m.mapSurface(20, toplevel(cover));
        m.mapSurface(21, child(SurfaceKind::SubSurface, 20));
        QSignalSpy removed(&m, &WindowMapper::surfaceRemoved);
        QSignalSpy destroyed(&m, &WindowMapper::windowDestroyed);
        m.unmapSurface(20);
        QCOMPARE(destroyed.count(), 1);
        QCOMPARE(m.coverWindow(), 0);
        QCOMPARE(removed.count(), 2);   // the cover and its subsurface
        QCOMPARE(m.windowForSurface(21), 0);
        Q_UNUSED(c);
    }

    void mainUnmapKeepsMainWindow()
    {
        WindowMapper m;
        m.mapSurface(10, toplevel());
        QSignalSpy destroyed(&m, &WindowMapper::windowDestroyed);
        m.unmapSurface(10);
        QCOMPARE(destroyed.count(), 0);
        QVERIFY(m.hasWindow(WindowMapper::MainWindowId));
        QCOMPARE(m.primarySurface(WindowMapper::MainWindowId), SurfaceKey(0));
        // The next toplevel becomes the main surface again.
        QCOMPARE(m.mapSurface(11, toplevel()), int(WindowMapper::MainWindowId));
    }

    void newerCoverReplacesOlder()
    {
        WindowMapper m;
        const int c = m.mapSurface(20, toplevel(cover));
        QSignalSpy created(&m, &WindowMapper::windowCreated);
        QCOMPARE(m.mapSurface(21, toplevel(cover)), c);
        QCOMPARE(created.count(), 0);
        QCOMPARE(m.primarySurface(c), SurfaceKey(21));
        QCOMPARE(m.parkedSurfaces(), QList<SurfaceKey>() << 20);

        // When the newer one goes, the parked one comes back.
        m.unmapSurface(21);
        const int c2 = m.coverWindow();
        QVERIFY(c2 != 0);
        QCOMPARE(m.primarySurface(c2), SurfaceKey(20));
        QVERIFY(m.parkedSurfaces().isEmpty());
    }

    void lateCoverTitleMovesSurface()
    {
        WindowMapper m;
        m.mapSurface(10, toplevel(QStringLiteral("Main")));
        const int s = m.mapSurface(11, toplevel(QStringLiteral("untitled")));
        m.mapSurface(12, child(SurfaceKind::SubSurface, 11));
        QCOMPARE(m.roleOf(s), WindowRole::Secondary);

        QSignalSpy destroyed(&m, &WindowMapper::windowDestroyed);
        m.updateSurface(11, toplevel(cover));
        QCOMPARE(destroyed.count(), 1);
        const int c = m.coverWindow();
        QVERIFY(c);
        QCOMPARE(m.windowForSurface(11), c);
        QCOMPARE(m.windowForSurface(12), c);   // descendants follow

        // And back again.
        m.updateSurface(11, toplevel(QStringLiteral("not a cover any more")));
        QCOMPARE(m.coverWindow(), 0);
        QCOMPARE(m.roleOf(m.windowForSurface(11)), WindowRole::Secondary);
        QCOMPARE(m.windowForSurface(12), m.windowForSurface(11));
    }

    void lateCoverTitleOnMainSurface()
    {
        // A client that shows the cover window first with an ordinary title
        // and renames it: the main slot is freed and taken by the next one.
        WindowMapper m;
        m.mapSurface(10, toplevel(QStringLiteral("untitled")));
        QCOMPARE(m.primarySurface(WindowMapper::MainWindowId), SurfaceKey(10));
        m.updateSurface(10, toplevel(cover));
        QCOMPARE(m.primarySurface(WindowMapper::MainWindowId), SurfaceKey(0));
        QCOMPARE(m.roleOf(m.windowForSurface(10)), WindowRole::Cover);
        QCOMPARE(m.mapSurface(11, toplevel()), int(WindowMapper::MainWindowId));
    }

    void titleChangeWithoutRoleChangeIsQuiet()
    {
        WindowMapper m;
        m.mapSurface(10, toplevel(QStringLiteral("a")));
        QSignalSpy assigned(&m, &WindowMapper::surfaceAssigned);
        QSignalSpy removed(&m, &WindowMapper::surfaceRemoved);
        m.updateSurface(10, toplevel(QStringLiteral("b")));
        QCOMPARE(assigned.count(), 0);
        QCOMPARE(removed.count(), 0);
        QCOMPARE(m.surfaceInfo(10).title, QStringLiteral("b"));
    }

    void coverDisabled()
    {
        WindowMapper m;
        m.setCoverEnabled(false);
        m.mapSurface(10, toplevel());
        const int w = m.mapSurface(20, toplevel(cover));
        QCOMPARE(m.roleOf(w), WindowRole::Secondary);
        QCOMPARE(m.coverWindow(), 0);
    }

    void updateUnknownSurfaceIsNoop()
    {
        WindowMapper m;
        QSignalSpy assigned(&m, &WindowMapper::surfaceAssigned);
        m.updateSurface(42, toplevel(cover));
        m.unmapSurface(42);
        QCOMPARE(assigned.count(), 0);
        QVERIFY(!m.isMapped(42));
    }

    void mapTwiceActsAsUpdate()
    {
        WindowMapper m;
        m.mapSurface(10, toplevel());
        QCOMPARE(m.mapSurface(10, toplevel()), int(WindowMapper::MainWindowId));
        QCOMPARE(m.surfacesInWindow(WindowMapper::MainWindowId).size(), 1);
    }

    void signalOrder()
    {
        // windowCreated must precede surfaceAssigned for the new window so
        // backends can create the QWindow first.
        WindowMapper m;
        QStringList log;
        connect(&m, &WindowMapper::windowCreated, this, [&](int id, WindowRole) {
            log << QStringLiteral("created %1").arg(id);
        });
        connect(&m, &WindowMapper::surfaceAssigned, this, [&](SurfaceKey s, int id) {
            log << QStringLiteral("assigned %1 %2").arg(s).arg(id);
        });
        connect(&m, &WindowMapper::surfaceRemoved, this, [&](SurfaceKey s, int id) {
            log << QStringLiteral("removed %1 %2").arg(s).arg(id);
        });
        connect(&m, &WindowMapper::windowDestroyed, this, [&](int id) {
            log << QStringLiteral("destroyed %1").arg(id);
        });
        m.mapSurface(20, toplevel(cover));
        m.unmapSurface(20);
        QCOMPARE(log, QStringList() << "created 2" << "assigned 20 2" << "removed 20 2"
                                    << "destroyed 2");
    }
};

QTEST_GUILESS_MAIN(TestWindowMapper)
#include "tst_windowmapper.moc"
