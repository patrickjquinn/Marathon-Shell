# Keel Framework 1a: Theme Pipeline Implementation Plan

**Goal:** The shell derives a Sailfish ambience from the wallpaper and drives it into its own Keel engine and into every Keel app through Keel's own host protocol; the shell draws the ambience behind Keel apps; a wallpaper change re-themes everything live.

**Architecture:** A pure derivation function turns the wallpaper into a base colour and colour scheme. An `AmbienceService` in the shell holds the published ambience map and exports it on D-Bus. A shell QML `AmbienceController` turns the base colour into Keel's highlight using Keel's own palette rule, applies it to the shell's Keel engine and publishes the map. `marathon-app-runner` becomes a Keel host (PROTOCOL.md v1: environment plus a peer D-Bus `org.shipwright.keel.Shell1`) for every app whose manifest is not `"toolkit": "marathonui"`, relaying ambience, active state and close requests. Because Keel apps under a host leave their background transparent (`Shell.phone`), the shell draws the ambience behind them, as Lipstick does.

**Tech Stack:** Qt 6.11 (C++17, QtDBus, QtQuick), Keel `Keel 1.0` / `Sailfish.Silica 1.0` (consumed, unmodified), QtTest, qmltestrunner.

**Spec:** `docs/design/2026-10-11-keel-for-marathon-design.md` (§1, §2; this plan also adds the shell-drawn ambience background required by Keel's `Shell.phone` behaviour, see Task 7).

## Global Constraints

- Keel is not modified. Nothing under `~/Developer/Shipwright` is edited.
- Host protocol: `keel/shell/PROTOCOL.md` version 1. Object path `/org/shipwright/keel/Shell`, interface `org.shipwright.keel.Shell1`.
- Ambience map keys are full dconf paths: `/desktop/jolla/theme/color/highlight`, `/desktop/jolla/theme/color_scheme` (`lightondark` | `darkonlight`), `/desktop/jolla/theme/wallpaper` (file URL). Environment snapshot: `KEEL_AMBIENCE_COLOR_HIGHLIGHT`, `KEEL_AMBIENCE_COLOR_SCHEME`, `KEEL_AMBIENCE_WALLPAPER`, `KEEL_AMBIENCE_KEYS` (`:`-joined full keys).
- `AmbienceChanged` is debounced to 250 ms.
- `KEEL_SHELL_COVER_ENABLED=0` (covers are sub-project 2). `Orientation` is 0.
- Apps with `"toolkit": "marathonui"` are untouched: no Keel environment, no ambience background.
- Follow `docs/CODING_RULES.md` A–G; terse comments only.
- No commits or pushes unless the user asks; each task ends with "Stop: diff review".
- Device: PinePhone `root@172.16.42.1`; restart via `systemctl restart greetd` only; never `pkill marathon-shell`; never drop_caches; deploy in ≤20 MB chunks with the shell stopped.

## Review Focus

1. Wallpaper unreadable (custom file deleted, corrupt image) — ambience keeps its last value; no crash, no black theme. Test in Task 3.
2. Shell's Ambience1 unavailable when the runner starts (pool spare adopted during shell restart) — app starts with Keel defaults and picks up the ambience when the signal arrives. Test in Task 6.
3. A Keel app disconnects from the peer bus (crash) — the runner's host keeps working and emits to remaining peers without crashing. Test in Task 5.
4. A legacy `marathonui` app gets no `KEEL_*` environment and no ambience background. Tests in Tasks 1 and 6.
5. Several wallpaper changes in quick succession — one `AmbienceChanged` with the final map. Test in Task 3.

---

## File map

- Modify `marathon-core/src/marathonappregistry.{h,cpp}`, `marathon-core/src/marathonappscanner.cpp` — `toolkit` field.
- Modify every `apps/*/manifest.json` except `apps/notes-silica` — `"toolkit": "marathonui"`.
- Create `shell/src/services/ambiencederivation.{h,cpp}` — wallpaper → base colour + scheme.
- Create `shell/src/services/ambienceservice.{h,cpp}` — holds and debounces the published map.
- Modify `shell/src/ipc/shellservices.{h,cpp}`, `shell/src/ipc/shellipcserver.cpp` — `org.marathonos.Shell.Ambience1`.
- Create `shell/qml/core/AmbienceController.qml`; modify `shell/qml/MarathonShell.qml`, `shell/main.cpp`, `shell/CMakeLists.txt`.
- Create `shell/qml/components/KeelAmbienceBackground.qml`; modify `shell/qml/components/MarathonAppWindow.qml`.
- Create `tools/marathon-app-runner/keelhost.{h,cpp}`; modify `tools/marathon-app-runner/main.cpp`, `tools/marathon-app-runner/CMakeLists.txt`, `tools/marathon-app-runner/ipc/shellipcclients.{h,cpp}`.
- Tests: `tests/core/test_apptoolkit.cpp`, `tests/shell/test_ambiencederivation.cpp`, `tests/shell/test_ambienceservice.cpp`, `tests/core/test_keelhost.cpp`, `tests/ui/tst_ambiencecontroller.qml`; CMake entries in `tests/core/CMakeLists.txt`, `tests/shell/CMakeLists.txt`.
- Modify `apps/notes-silica/SilicaApp.qml`, `apps/notes-silica/tests/tst_silicaapp.qml`.
- Modify `packaging/packages/marathon-shell/APKBUILD` — `keel-silica` back in runtime `depends` (the shell now imports Keel).

Test commands used below:
- C++: `cmake build-tests >/dev/null && cmake --build build-tests --target <target> && ./build-tests/tests/<dir>/<target>`
- QML: `KEEL_QML=$HOME/Developer/Shipwright/build/keel/qml sh tests/ui/run.sh`

---

### Task 1: `toolkit` in app manifests

**Files:**
- Modify: `marathon-core/src/marathonappregistry.h` (AppInfo, after `requiresQtModules`), `marathon-core/src/marathonappregistry.cpp` (`getApp` map), `marathon-core/src/marathonappscanner.cpp` (`parseManifest`, next to `requiresQtModules` at ~line 240)
- Modify: `apps/*/manifest.json` (all except notes-silica)
- Test: `tests/core/test_apptoolkit.cpp`, `tests/core/CMakeLists.txt`

**Interfaces:**
- Produces: `AppInfo::toolkit` (`QString`, `"keel"` when absent, else the manifest value); `getApp(id)["toolkit"]`.

- [ ] **Step 1: Write the failing test**

```cpp
#include <QtTest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>

#include "marathonappregistry.h"
#include "marathonappscanner.h"

class TestAppToolkit : public QObject {
    Q_OBJECT

    QTemporaryDir home;

    void writeApp(const QString &id, const QString &toolkit) {
        const QString dir = home.path() + "/.local/share/marathon-apps/" + id;
        QDir().mkpath(dir);
        QJsonObject m{{"id", id}, {"name", id}, {"version", "1.0"},
                      {"entryPoint", "Main.qml"}, {"icon", "icon.svg"}};
        if (!toolkit.isEmpty())
            m.insert("toolkit", toolkit);
        QFile f(dir + "/manifest.json");
        QVERIFY(f.open(QIODevice::WriteOnly));
        f.write(QJsonDocument(m).toJson());
        QFile qml(dir + "/Main.qml");
        QVERIFY(qml.open(QIODevice::WriteOnly));
        qml.write("import QtQuick\nItem {}\n");
    }

  private slots:
    void initTestCase() { qputenv("HOME", home.path().toUtf8()); }

    void defaultsToKeel() {
        writeApp("plain", QString());
        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);
        QVERIFY(scanner.scanSingleApp("plain"));
        QCOMPARE(registry.getApp("plain").value("toolkit").toString(), QStringLiteral("keel"));
    }

    void readsLegacyToolkit() {
        writeApp("legacy", "marathonui");
        MarathonAppRegistry registry;
        MarathonAppScanner  scanner(&registry);
        QVERIFY(scanner.scanSingleApp("legacy"));
        QCOMPARE(registry.getApp("legacy").value("toolkit").toString(),
                 QStringLiteral("marathonui"));
    }
};

QTEST_GUILESS_MAIN(TestAppToolkit)
#include "test_apptoolkit.moc"
```

Add to `tests/core/CMakeLists.txt`, using the same sources `test_core_appscanner` compiles (copy its `add_executable` source list and include dirs):

```cmake
add_executable(test_core_apptoolkit
    test_apptoolkit.cpp
    ../../marathon-core/src/marathonappregistry.cpp
    ../../marathon-core/src/marathonappscanner.cpp
)
target_link_libraries(test_core_apptoolkit Qt6::Test Qt6::Core)
target_include_directories(test_core_apptoolkit PRIVATE ${CMAKE_SOURCE_DIR}/marathon-core/src)
add_test(NAME Core_AppToolkit COMMAND test_core_apptoolkit)
```

If `test_core_appscanner` links more (e.g. Qt6::Gui), copy those too.

- [ ] **Step 2: Run it and see it fail**

Run: `cmake build-tests >/dev/null && cmake --build build-tests --target test_core_apptoolkit && ./build-tests/tests/core/test_core_apptoolkit`
Expected: FAIL — `toolkit` is an invalid QVariant, so `QCOMPARE` gets `""` vs `"keel"`.

- [ ] **Step 3: Implement**

`marathonappregistry.h`, in `AppInfo` after `requiresQtModules`:
```cpp
        QString     toolkit = QStringLiteral("keel");
```
`marathonappscanner.cpp`, in `parseManifest` after the `requiresQtModules` loop:
```cpp
    info.toolkit = obj.value("toolkit").toString(QStringLiteral("keel"));
```
`marathonappregistry.cpp`, in `getApp` with the other `result[...]` lines:
```cpp
        result["toolkit"]                = app->toolkit;
```

- [ ] **Step 4: Run it and see it pass**

Same command. Expected: `Totals: 4 passed, 0 failed`.

- [ ] **Step 5: Mark legacy apps**

For every `apps/*/manifest.json` except `apps/notes-silica/manifest.json`, add `"toolkit": "marathonui"` after `"entryPoint"`:
```bash
for f in $(ls apps/*/manifest.json | grep -v notes-silica); do
  python3 - "$f" <<'EOF'
import json, sys, collections
p = sys.argv[1]
m = json.load(open(p), object_pairs_hook=collections.OrderedDict)
out = collections.OrderedDict()
for k, v in m.items():
    out[k] = v
    if k == "entryPoint":
        out["toolkit"] = "marathonui"
json.dump(out, open(p, "w"), indent=2); open(p, "a").write("\n")
EOF
done
grep -L '"toolkit"' apps/*/manifest.json
```
Expected: only `apps/notes-silica/manifest.json` is listed.

- [ ] **Step 6: Run the core suite**

Run: `cd build-tests && ctest -R '^Core_' 2>&1 | tail -3`
Expected: `100% tests passed`.

- [ ] **Step 7: Stop: diff review**

---

### Task 2: Ambience derivation

**Files:**
- Create: `shell/src/services/ambiencederivation.h`, `shell/src/services/ambiencederivation.cpp`
- Modify: `shell/CMakeLists.txt` (add both files next to `src/services/router.cpp` in each source list that has it, lines ~136 and ~448)
- Test: `tests/shell/test_ambiencederivation.cpp`, `tests/shell/CMakeLists.txt`

**Interfaces:**
- Produces:
```cpp
struct AmbienceSeed {
    QColor base;
    bool   light = false;   // true → DarkOnLight
};
AmbienceSeed deriveAmbienceSeed(const QImage &wallpaper);
```

- [ ] **Step 1: Write the failing tests**

```cpp
#include <QtTest>
#include <QImage>
#include <QPainter>

#include "ambiencederivation.h"

class TestAmbienceDerivation : public QObject {
    Q_OBJECT

    static QImage solid(const QColor &c) {
        QImage img(200, 400, QImage::Format_RGB32);
        img.fill(c);
        return img;
    }

  private slots:
    void darkSaturatedWallpaperGivesItsHueAndDarkScheme() {
        const AmbienceSeed s = deriveAmbienceSeed(solid(QColor(10, 40, 120)));
        QVERIFY(qAbs(s.base.hslHue() - QColor(10, 40, 120).hslHue()) <= 15);
        QVERIFY(!s.light);
    }

    void brightWallpaperGivesLightScheme() {
        QVERIFY(deriveAmbienceSeed(solid(QColor(235, 240, 245))).light);
    }

    void greyWallpaperFallsBackToMeanColour() {
        const AmbienceSeed s = deriveAmbienceSeed(solid(QColor(90, 90, 90)));
        QCOMPARE(s.base.red(), 90);
        QVERIFY(!s.light);
    }

    void saturatedRegionWinsOverLargerGreyArea() {
        QImage img = solid(QColor(60, 60, 60));
        QPainter p(&img);
        p.fillRect(0, 0, 200, 120, QColor(200, 30, 30));
        p.end();
        const AmbienceSeed s = deriveAmbienceSeed(img);
        QVERIFY(s.base.hslHue() <= 15 || s.base.hslHue() >= 345);
    }

    void nullImageGivesDefault() {
        const AmbienceSeed s = deriveAmbienceSeed(QImage());
        QVERIFY(!s.base.isValid());
    }
};

QTEST_GUILESS_MAIN(TestAmbienceDerivation)
#include "test_ambiencederivation.moc"
```

`tests/shell/CMakeLists.txt`:
```cmake
add_executable(test_shell_ambiencederivation
    test_ambiencederivation.cpp
    ../../shell/src/services/ambiencederivation.cpp
)
target_link_libraries(test_shell_ambiencederivation Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_ambiencederivation PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_AmbienceDerivation COMMAND test_shell_ambiencederivation)
```
(`Gui` must be in the `find_package(Qt6 ...)` list at the top of `tests/shell/CMakeLists.txt`; it is.)

- [ ] **Step 2: Run them and see them fail**

Run: `cmake build-tests >/dev/null && cmake --build build-tests --target test_shell_ambiencederivation`
Expected: build fails — `ambiencederivation.h` not found.

- [ ] **Step 3: Implement**

`shell/src/services/ambiencederivation.h`:
```cpp
#pragma once

#include <QColor>
#include <QImage>

struct AmbienceSeed {
    QColor base;
    bool   light = false;
};

// The colour an ambience is built from, as Sailfish derives one from a
// wallpaper: the most saturated well-populated hue, else the mean colour.
AmbienceSeed deriveAmbienceSeed(const QImage &wallpaper);
```

`shell/src/services/ambiencederivation.cpp`:
```cpp
#include "ambiencederivation.h"

#include <array>

AmbienceSeed deriveAmbienceSeed(const QImage &wallpaper) {
    AmbienceSeed seed;
    if (wallpaper.isNull())
        return seed;

    const QImage img =
        wallpaper.scaled(64, 64, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
            .convertToFormat(QImage::Format_RGB32);

    constexpr int kBuckets = 12;
    struct Bucket {
        double weight = 0;
        double r = 0, g = 0, b = 0;
        int    count = 0;
    };
    std::array<Bucket, kBuckets> buckets{};
    double sumR = 0, sumG = 0, sumB = 0, sumLum = 0;
    const int pixels = img.width() * img.height();

    for (int y = 0; y < img.height(); ++y) {
        const auto *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const QColor c = QColor::fromRgb(line[x]);
            sumR += c.red();
            sumG += c.green();
            sumB += c.blue();
            sumLum += 0.2126 * c.red() + 0.7152 * c.green() + 0.0722 * c.blue();
            const double s = c.hsvSaturationF();
            const double v = c.valueF();
            if (s < 0.25 || v < 0.15 || c.hsvHue() < 0)
                continue;
            Bucket &bk = buckets[c.hsvHue() * kBuckets / 360];
            bk.weight += s;
            bk.r += c.red();
            bk.g += c.green();
            bk.b += c.blue();
            ++bk.count;
        }
    }

    const Bucket *best = nullptr;
    for (const Bucket &bk : buckets)
        if (bk.count >= pixels / 20 && (!best || bk.weight > best->weight))
            best = &bk;

    seed.base = best ? QColor(qRound(best->r / best->count), qRound(best->g / best->count),
                              qRound(best->b / best->count))
                     : QColor(qRound(sumR / pixels), qRound(sumG / pixels), qRound(sumB / pixels));
    seed.light = sumLum / pixels / 255.0 > 0.6;
    return seed;
}
```

- [ ] **Step 4: Run them and see them pass**

Run: `cmake --build build-tests --target test_shell_ambiencederivation && ./build-tests/tests/shell/test_shell_ambiencederivation`
Expected: `Totals: 7 passed, 0 failed`.

- [ ] **Step 5: Stop: diff review**

---

### Task 3: AmbienceService and `org.marathonos.Shell.Ambience1`

**Files:**
- Create: `shell/src/services/ambienceservice.h`, `shell/src/services/ambienceservice.cpp`
- Modify: `shell/CMakeLists.txt` (same two lists as Task 2), `shell/src/ipc/shellservices.h` / `.cpp` (new `AmbienceObject`), `shell/src/ipc/shellipcserver.cpp` (create + `registerObject("/org/marathonos/Shell/Ambience", ...)`), `shell/main.cpp` (`qmlRegisterSingletonInstance<AmbienceService>("MarathonOS.Shell", 1, 0, "AmbienceService", ambienceService)` next to `SettingsManagerCpp`, and pass it to the IPC server the same way `SettingsManager` is)
- Test: `tests/shell/test_ambienceservice.cpp`, `tests/shell/CMakeLists.txt`

**Interfaces:**
- Consumes: `deriveAmbienceSeed` (Task 2).
- Produces:
```cpp
class AmbienceService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QColor baseColor READ baseColor NOTIFY seedChanged)
    Q_PROPERTY(bool light READ light NOTIFY seedChanged)
    Q_PROPERTY(QString wallpaperUrl READ wallpaperUrl NOTIFY seedChanged)
    Q_PROPERTY(QVariantMap ambience READ ambience NOTIFY ambienceChanged)
  public:
    explicit AmbienceService(QObject *parent = nullptr);
    void setWallpaper(const QString &path);          // qrc:/, file:// or absolute
    Q_INVOKABLE void publish(const QVariantMap &map); // debounced 250 ms
    ...
  signals:
    void seedChanged();
    void ambienceChanged(const QVariantMap &ambience);
};
```
- D-Bus `org.marathonos.Shell.Ambience1` at `/org/marathonos/Shell/Ambience`: method `GetAmbience() → a{sv}`, signal `AmbienceChanged(a{sv})`. No permission gate.

- [ ] **Step 1: Write the failing tests**

```cpp
#include <QtTest>
#include <QImage>
#include <QTemporaryDir>

#include "ambienceservice.h"

class TestAmbienceService : public QObject {
    Q_OBJECT

    QTemporaryDir dir;

    QString writeImage(const QString &name, const QColor &c) {
        QImage img(64, 64, QImage::Format_RGB32);
        img.fill(c);
        const QString path = dir.path() + "/" + name;
        img.save(path);
        return path;
    }

  private slots:
    void wallpaperSetsSeed() {
        AmbienceService svc;
        QSignalSpy      spy(&svc, &AmbienceService::seedChanged);
        svc.setWallpaper(writeImage("blue.png", QColor(20, 40, 160)));
        QCOMPARE(spy.count(), 1);
        QVERIFY(svc.baseColor().blue() > svc.baseColor().red());
        QCOMPARE(svc.wallpaperUrl(), QUrl::fromLocalFile(dir.path() + "/blue.png").toString());
    }

    void unreadableWallpaperKeepsPreviousSeed() {
        AmbienceService svc;
        svc.setWallpaper(writeImage("red.png", QColor(180, 20, 20)));
        const QColor before = svc.baseColor();
        QSignalSpy spy(&svc, &AmbienceService::seedChanged);
        svc.setWallpaper(dir.path() + "/missing.png");
        QCOMPARE(spy.count(), 0);
        QCOMPARE(svc.baseColor(), before);
    }

    void publishIsDebounced() {
        AmbienceService svc;
        QSignalSpy      spy(&svc, &AmbienceService::ambienceChanged);
        svc.publish({{"/desktop/jolla/theme/color/highlight", "#111111"}});
        svc.publish({{"/desktop/jolla/theme/color/highlight", "#222222"}});
        svc.publish({{"/desktop/jolla/theme/color/highlight", "#333333"}});
        QCOMPARE(spy.count(), 0);
        QVERIFY(spy.wait(1000));
        QCOMPARE(spy.count(), 1);
        QCOMPARE(svc.ambience().value("/desktop/jolla/theme/color/highlight").toString(),
                 QStringLiteral("#333333"));
    }

    void identicalPublishDoesNotSignal() {
        AmbienceService svc;
        const QVariantMap m{{"/desktop/jolla/theme/color_scheme", "lightondark"}};
        QSignalSpy        spy(&svc, &AmbienceService::ambienceChanged);
        svc.publish(m);
        QVERIFY(spy.wait(1000));
        svc.publish(m);
        QVERIFY(!spy.wait(500));
        QCOMPARE(spy.count(), 1);
    }
};

QTEST_MAIN(TestAmbienceService)
#include "test_ambienceservice.moc"
```

`tests/shell/CMakeLists.txt`:
```cmake
add_executable(test_shell_ambienceservice
    test_ambienceservice.cpp
    ../../shell/src/services/ambienceservice.cpp
    ../../shell/src/services/ambiencederivation.cpp
)
target_link_libraries(test_shell_ambienceservice Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_ambienceservice PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_AmbienceService COMMAND test_shell_ambienceservice)
```

- [ ] **Step 2: Run them and see them fail**

Run: `cmake build-tests >/dev/null && cmake --build build-tests --target test_shell_ambienceservice`
Expected: build fails — `ambienceservice.h` not found.

- [ ] **Step 3: Implement the service**

`shell/src/services/ambienceservice.h`:
```cpp
#pragma once

#include <QColor>
#include <QObject>
#include <QTimer>
#include <QVariantMap>

class AmbienceService : public QObject {
    Q_OBJECT
    Q_PROPERTY(QColor baseColor READ baseColor NOTIFY seedChanged)
    Q_PROPERTY(bool light READ light NOTIFY seedChanged)
    Q_PROPERTY(QString wallpaperUrl READ wallpaperUrl NOTIFY seedChanged)
    Q_PROPERTY(QVariantMap ambience READ ambience NOTIFY ambienceChanged)

  public:
    explicit AmbienceService(QObject *parent = nullptr);

    QColor      baseColor() const { return m_base; }
    bool        light() const { return m_light; }
    QString     wallpaperUrl() const { return m_wallpaperUrl; }
    QVariantMap ambience() const { return m_ambience; }

    void             setWallpaper(const QString &path);
    Q_INVOKABLE void publish(const QVariantMap &map);

  signals:
    void seedChanged();
    void ambienceChanged(const QVariantMap &ambience);

  private:
    QColor      m_base;
    bool        m_light = false;
    QString     m_wallpaperUrl;
    QVariantMap m_ambience;
    QVariantMap m_pending;
    QTimer      m_debounce;
};
```

`shell/src/services/ambienceservice.cpp`:
```cpp
#include "ambienceservice.h"
#include "ambiencederivation.h"

#include <QImageReader>
#include <QUrl>

AmbienceService::AmbienceService(QObject *parent)
    : QObject(parent) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(250);
    connect(&m_debounce, &QTimer::timeout, this, [this]() {
        if (m_pending == m_ambience)
            return;
        m_ambience = m_pending;
        emit ambienceChanged(m_ambience);
    });
}

void AmbienceService::setWallpaper(const QString &path) {
    const QUrl    url   = QUrl(path);
    const QString local = url.scheme() == QLatin1String("qrc") ? QLatin1Char(':') + url.path()
                          : url.isLocalFile()                  ? url.toLocalFile()
                                                               : path;
    QImageReader reader(local);
    reader.setScaledSize(QSize(64, 64));
    const QImage img = reader.read();
    if (img.isNull())
        return;
    const AmbienceSeed seed = deriveAmbienceSeed(img);
    m_base                  = seed.base;
    m_light                 = seed.light;
    m_wallpaperUrl          = local.startsWith(QLatin1Char(':')) ? QStringLiteral("qrc") + local
                                                                 : QUrl::fromLocalFile(local).toString();
    emit seedChanged();
}

void AmbienceService::publish(const QVariantMap &map) {
    m_pending = map;
    m_debounce.start();
}
```

- [ ] **Step 4: Run the tests**

Run: `cmake --build build-tests --target test_shell_ambienceservice && ./build-tests/tests/shell/test_shell_ambienceservice`
Expected: `Totals: 6 passed, 0 failed`.

- [ ] **Step 5: D-Bus object and wiring**

`shell/src/ipc/shellservices.h`, next to the other objects:
```cpp
class AmbienceObject : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.marathonos.Shell.Ambience1")

  public:
    explicit AmbienceObject(AmbienceService *ambience, QObject *parent = nullptr);

  public slots:
    QVariantMap GetAmbience();

  signals:
    void AmbienceChanged(const QVariantMap &ambience);

  private:
    AmbienceService *m_ambience;
};
```
`shellservices.cpp`:
```cpp
AmbienceObject::AmbienceObject(AmbienceService *ambience, QObject *parent)
    : QObject(parent)
    , m_ambience(ambience) {
    connect(ambience, &AmbienceService::ambienceChanged, this, &AmbienceObject::AmbienceChanged);
}

QVariantMap AmbienceObject::GetAmbience() {
    return m_ambience->ambience();
}
```
`shellipcserver.cpp`: construct `new AmbienceObject(m_ambienceService, this)` with the others and add
`ok &= bus.registerObject("/org/marathonos/Shell/Ambience", ambienceObj, QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals);`
following the existing objects' pattern. Add an `AmbienceService *` member and constructor/setter parameter exactly as `m_settingsManager` is passed.

`shell/main.cpp`: create `auto *ambienceService = new AmbienceService(&app);`, call `ambienceService->setWallpaper(settingsManager->wallpaperPath())`, connect `SettingsManager::wallpaperPathChanged` to re-call it, register the QML singleton, and hand it to the IPC server.

- [ ] **Step 6: Build the shell**

Run: `cmake --build build --target marathon-shell-bin 2>&1 | grep -E "error|Linking"`
Expected: `Linking CXX executable shell/marathon-shell-bin`, no errors.

- [ ] **Step 7: Stop: diff review**

---

### Task 4: Shell AmbienceController (shell's own Keel engine)

**Files:**
- Create: `shell/qml/core/AmbienceController.qml`
- Modify: `shell/CMakeLists.txt` (`QML_FILES`, next to `qml/core/Logger.qml`, both lists), `shell/qml/MarathonShell.qml` (instantiate once), `packaging/packages/marathon-shell/APKBUILD` (`keel-silica` in runtime `depends`; bump `pkgrel`)
- Modify: `tests/ui/run.sh` (add `-import "$KEEL_QML"` when set)
- Test: `tests/ui/tst_ambiencecontroller.qml`

**Interfaces:**
- Consumes: `AmbienceService` (`baseColor`, `light`, `wallpaperUrl`, `publish(map)`, `seedChanged`) from Task 3; Keel's `Ambience.highlightFromColor(color, scheme)` and `Ambience.applyForwarded(lines)`.
- Produces: `AmbienceController { property var service; function buildMap(): var }`.

- [ ] **Step 1: Write the failing test**

```qml
import QtQuick
import QtTest
import Keel 1.0
import "../../shell/qml/core"

TestCase {
    name: "AmbienceController"

    QtObject {
        id: fakeService
        property color baseColor: "#1040a0"
        property bool light: false
        property string wallpaperUrl: "file:///usr/share/marathon-shell/wallpapers/dawn.svg"
        property var published: null
        signal seedChanged
        function publish(map) { published = map; }
    }

    AmbienceController { id: controller; service: fakeService }

    function test_publishesKeelKeys() {
        fakeService.seedChanged();
        const m = fakeService.published;
        verify(m);
        compare(m["/desktop/jolla/theme/color/highlight"],
                Ambience.highlightFromColor("#1040a0", 0));
        compare(m["/desktop/jolla/theme/color_scheme"], "lightondark");
        compare(m["/desktop/jolla/theme/wallpaper"], fakeService.wallpaperUrl);
    }

    function test_lightScheme() {
        fakeService.light = true;
        fakeService.seedChanged();
        compare(fakeService.published["/desktop/jolla/theme/color_scheme"], "darkonlight");
        fakeService.light = false;
    }
}
```

`tests/ui/run.sh`: add `${KEEL_QML:+-import "$KEEL_QML"}` before `-input`.

- [ ] **Step 2: Run it and see it fail**

Run: `KEEL_QML=$HOME/Developer/Shipwright/build/keel/qml sh tests/ui/run.sh 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: FAIL — `AmbienceController is not a type`.

- [ ] **Step 3: Implement**

`shell/qml/core/AmbienceController.qml`:
```qml
import QtQuick
import Keel 1.0

QtObject {
    id: root

    property var service

    function buildMap() {
        const scheme = service.light ? 1 : 0;
        return {
            "/desktop/jolla/theme/color/highlight": Ambience.highlightFromColor(service.baseColor, scheme),
            "/desktop/jolla/theme/color_scheme": service.light ? "darkonlight" : "lightondark",
            "/desktop/jolla/theme/wallpaper": service.wallpaperUrl
        };
    }

    function apply() {
        if (!service || !service.baseColor.valid)
            return;
        const map = buildMap();
        Ambience.applyForwarded(Object.keys(map).map(k => k + "=" + map[k]).join("\n"));
        service.publish(map);
    }

    property Connections _seed: Connections {
        target: root.service
        function onSeedChanged() {
            root.apply();
        }
    }

    Component.onCompleted: apply()
}
```

In `MarathonShell.qml`, alongside the other top-level helpers: `AmbienceController { service: AmbienceService }`.

- [ ] **Step 4: Run it and see it pass**

Same command. Expected: `AmbienceController` tests pass; whole suite `0 failed`.

- [ ] **Step 5: Build the shell and run it on the host**

Run: `cmake --build build --target marathon-shell-bin 2>&1 | grep -E "error|Linking"`
Expected: links. (The shell QML now imports `Keel 1.0`; on the device `keel-silica` provides it.)

- [ ] **Step 6: Stop: diff review**

---

### Task 5: Keel host server in the runner

**Files:**
- Create: `tools/marathon-app-runner/keelhost.h`, `tools/marathon-app-runner/keelhost.cpp`
- Modify: `tools/marathon-app-runner/CMakeLists.txt` (add `keelhost.cpp` to `SOURCES`)
- Test: `tests/core/test_keelhost.cpp`, `tests/core/CMakeLists.txt` (add `DBus` to that file's `find_package(Qt6 ...)`)

**Interfaces:**
- Produces:
```cpp
class KeelHost : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.shipwright.keel.Shell1")
    Q_PROPERTY(int ProtocolVersion READ protocolVersion)
    Q_PROPERTY(int Orientation READ orientation)
    Q_PROPERTY(int ContentOrientation READ contentOrientation)
    Q_PROPERTY(bool Active READ active)
    Q_PROPERTY(int CoverStatus READ coverStatus)
    Q_PROPERTY(QVariantMap Ambience READ ambience)
    Q_PROPERTY(int Dpi READ dpi)
  public:
    explicit KeelHost(int dpi, QObject *parent = nullptr);
    bool start(const QString &runtimeDir);                // creates the peer server
    QString address() const;
    QHash<QString, QString> environment() const;          // KEEL_* vars to export
    void setAmbience(const QVariantMap &ambience);
    void setActive(bool active);
    void requestClose();
  public slots:  // D-Bus
    QString Ping();
    QVariantMap GetAmbience();
    void Activate();
    void SetContentOrientation(int degrees);
  signals:  // D-Bus
    void OrientationChanged(int);
    void ContentOrientationChanged(int);
    void ActiveChanged(bool);
    void CoverStatusChanged(int);
    void AmbienceChanged(const QVariantMap &);
    void DpiChanged(int);
    void CloseRequested();
    std::function<void()> onActivate;                     // Activate() from the app
};
```

- [ ] **Step 1: Write the failing tests**

```cpp
#include <QtTest>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QTemporaryDir>

#include "keelhost.h"

static const char *kPath  = "/org/shipwright/keel/Shell";
static const char *kIface = "org.shipwright.keel.Shell1";

class TestKeelHost : public QObject {
    Q_OBJECT

    QTemporaryDir runtime;

    static QDBusConnection peer(const QString &address, const QString &name) {
        return QDBusConnection::connectToPeer(address, name);
    }

  private slots:
    void environmentFollowsProtocol() {
        KeelHost host(144);
        host.setAmbience({{"/desktop/jolla/theme/color/highlight", "#00ffaa"},
                          {"/desktop/jolla/theme/color_scheme", "lightondark"}});
        QVERIFY(host.start(runtime.path()));
        const auto env = host.environment();
        QCOMPARE(env.value("KEEL_SHELL"), QStringLiteral("1"));
        QCOMPARE(env.value("KEEL_SHELL_PROTOCOL"), QStringLiteral("1"));
        QCOMPARE(env.value("KEEL_SHELL_DBUS"), host.address());
        QCOMPARE(env.value("KEEL_SHELL_COVER_ENABLED"), QStringLiteral("0"));
        QCOMPARE(env.value("KEEL_SHELL_DPI"), QStringLiteral("144"));
        QCOMPARE(env.value("KEEL_AMBIENCE_COLOR_HIGHLIGHT"), QStringLiteral("#00ffaa"));
        QCOMPARE(env.value("KEEL_AMBIENCE_COLOR_SCHEME"), QStringLiteral("lightondark"));
        QVERIFY(env.value("KEEL_AMBIENCE_KEYS").split(':').contains(
            QStringLiteral("/desktop/jolla/theme/color/highlight")));
    }

    void emptyAmbienceExportsNoAmbienceKeys() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        QVERIFY(!host.environment().contains("KEEL_AMBIENCE_KEYS"));
    }

    void peerCanPingAndReadProperties() {
        KeelHost host(144);
        host.setActive(true);
        QVERIFY(host.start(runtime.path()));
        QDBusConnection bus = peer(host.address(), "t1");
        QTRY_VERIFY(bus.isConnected());
        QDBusInterface shell(QString(), kPath, kIface, bus);
        QCOMPARE(shell.call("Ping").arguments().value(0).toString(), QStringLiteral("marathon"));
        QCOMPARE(shell.property("ProtocolVersion").toInt(), 1);
        QCOMPARE(shell.property("Active").toBool(), true);
        QDBusConnection::disconnectFromPeer("t1");
    }

    void ambienceChangeReachesPeer() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        QDBusConnection bus = peer(host.address(), "t2");
        QTRY_VERIFY(bus.isConnected());
        QVERIFY(bus.connect(QString(), kPath, kIface, "AmbienceChanged", this,
                            SLOT(onAmbience(QVariantMap))));
        host.setAmbience({{"/desktop/jolla/theme/color/highlight", "#123456"}});
        QTRY_COMPARE(m_last.value("/desktop/jolla/theme/color/highlight").toString(),
                     QStringLiteral("#123456"));
        QDBusConnection::disconnectFromPeer("t2");
    }

    void survivesPeerDisconnect() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        {
            QDBusConnection bus = peer(host.address(), "t3");
            QTRY_VERIFY(bus.isConnected());
            QDBusConnection::disconnectFromPeer("t3");
        }
        QTest::qWait(100);
        host.setActive(true);
        host.setAmbience({{"/desktop/jolla/theme/color_scheme", "darkonlight"}});
        host.requestClose();
        QVERIFY(true);
    }

    void activateCallEmitsLocalSignal() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        QDBusConnection bus = peer(host.address(), "t4");
        QTRY_VERIFY(bus.isConnected());
        int activations = 0;
        host.onActivate = [&activations]() { ++activations; };
        QDBusInterface(QString(), kPath, kIface, bus).call("Activate");
        QTRY_COMPARE(activations, 1);
        QDBusConnection::disconnectFromPeer("t4");
    }

  public slots:
    void onAmbience(const QVariantMap &m) { m_last = m; }

  private:
    QVariantMap m_last;
};

QTEST_MAIN(TestKeelHost)
#include "test_keelhost.moc"
```

`tests/core/CMakeLists.txt`:
```cmake
add_executable(test_core_keelhost
    test_keelhost.cpp
    ../../tools/marathon-app-runner/keelhost.cpp
)
target_link_libraries(test_core_keelhost Qt6::Test Qt6::Core Qt6::DBus)
target_include_directories(test_core_keelhost PRIVATE ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner)
add_test(NAME Core_KeelHost COMMAND test_core_keelhost)
```

- [ ] **Step 2: Run them and see them fail**

Run: `cmake build-tests >/dev/null && cmake --build build-tests --target test_core_keelhost`
Expected: build fails — `keelhost.h` not found.

- [ ] **Step 3: Implement**

`tools/marathon-app-runner/keelhost.h`: the class from Interfaces, plus private members `QDBusServer *m_server = nullptr; QList<QDBusConnection> m_peers; QVariantMap m_ambience; bool m_active = false; int m_contentOrientation = 0; int m_dpi;` and trivial getters (`protocolVersion()` returns 1, `orientation()` and `coverStatus()` return 0).

`tools/marathon-app-runner/keelhost.cpp`:
```cpp
#include "keelhost.h"

#include <QDBusServer>
#include <QDir>
#include <QRegularExpression>

static const QString kPath = QStringLiteral("/org/shipwright/keel/Shell");
static const QString kThemeDir = QStringLiteral("/desktop/jolla/theme/");

KeelHost::KeelHost(int dpi, QObject *parent)
    : QObject(parent)
    , m_dpi(dpi) {}

bool KeelHost::start(const QString &runtimeDir) {
    const QString dir = runtimeDir + QStringLiteral("/marathon-keel-%1").arg(QCoreApplication::applicationPid());
    QDir().mkpath(dir);
    m_server = new QDBusServer(QStringLiteral("unix:dir=") + dir, this);
    if (!m_server->isConnected())
        return false;
    m_server->setAnonymousAuthenticationAllowed(false);
    connect(m_server, &QDBusServer::newConnection, this, [this](const QDBusConnection &c) {
        QDBusConnection conn(c);
        conn.registerObject(kPath, this,
                            QDBusConnection::ExportAllSlots | QDBusConnection::ExportAllSignals |
                                QDBusConnection::ExportAllProperties);
        m_peers.append(conn);
    });
    return true;
}

QString KeelHost::address() const {
    return m_server ? m_server->address() : QString();
}

QHash<QString, QString> KeelHost::environment() const {
    QHash<QString, QString> env{
        {QStringLiteral("KEEL_SHELL"), QStringLiteral("1")},
        {QStringLiteral("KEEL_SHELL_PROTOCOL"), QStringLiteral("1")},
        {QStringLiteral("KEEL_SHELL_DBUS"), address()},
        {QStringLiteral("KEEL_SHELL_COVER_TITLE"), QStringLiteral("keel:cover")},
        {QStringLiteral("KEEL_SHELL_COVER_ENABLED"), QStringLiteral("0")},
        {QStringLiteral("KEEL_SHELL_DPI"), QString::number(m_dpi)},
    };
    QStringList keys;
    static const QRegularExpression nonAlnum(QStringLiteral("[^A-Z0-9]"));
    for (auto it = m_ambience.cbegin(); it != m_ambience.cend(); ++it) {
        if (!it.key().startsWith(kThemeDir))
            continue;
        QString name = it.key().mid(kThemeDir.size()).toUpper();
        name.replace(nonAlnum, QStringLiteral("_"));
        env.insert(QStringLiteral("KEEL_AMBIENCE_") + name, it.value().toString());
        keys << it.key();
    }
    if (!keys.isEmpty())
        env.insert(QStringLiteral("KEEL_AMBIENCE_KEYS"), keys.join(QLatin1Char(':')));
    return env;
}

void KeelHost::setAmbience(const QVariantMap &ambience) {
    if (ambience == m_ambience)
        return;
    m_ambience = ambience;
    emit AmbienceChanged(m_ambience);
}

void KeelHost::setActive(bool active) {
    if (active == m_active)
        return;
    m_active = active;
    emit ActiveChanged(m_active);
}

void KeelHost::requestClose() {
    emit CloseRequested();
}

QString KeelHost::Ping() {
    return QStringLiteral("marathon");
}

QVariantMap KeelHost::GetAmbience() {
    return m_ambience;
}

void KeelHost::Activate() {
    if (onActivate)
        onActivate();
}

void KeelHost::SetContentOrientation(int degrees) {
    if (degrees == m_contentOrientation)
        return;
    m_contentOrientation = degrees;
    emit ContentOrientationChanged(degrees);
}
```
Add `#include <QCoreApplication>` and `#include <functional>` (header). `onActivate` is a plain callback so nothing local shows up on the D-Bus interface.

- [ ] **Step 4: Run them and see them pass**

Run: `cmake --build build-tests --target test_core_keelhost && ./build-tests/tests/core/test_core_keelhost`
Expected: `Totals: 8 passed, 0 failed`.

- [ ] **Step 5: Stop: diff review**

---

### Task 6: Runner hosts Keel apps

**Files:**
- Modify: `tools/marathon-app-runner/ipc/shellipcclients.h` / `.cpp` (new `AmbienceClient`), `tools/marathon-app-runner/main.cpp`

**Interfaces:**
- Consumes: `KeelHost` (Task 5), `AppInfo::toolkit` (Task 1), D-Bus `org.marathonos.Shell.Ambience1` (Task 3).
- Produces: `AmbienceClient { QVariantMap ambience() const; signal ambienceChanged(QVariantMap); }` fetching `GetAmbience` asynchronously and following `AmbienceChanged`.

- [ ] **Step 1: Write the failing test** (Review Focus 2 and 4)

Extend `tests/core/test_keelhost.cpp` with the decision helper the runner uses:
```cpp
    void hostOnlyForKeelApps() {
        QVERIFY(KeelHost::wantedFor(QStringLiteral("keel")));
        QVERIFY(!KeelHost::wantedFor(QStringLiteral("marathonui")));
    }

    void lateAmbienceStillReachesPeers() {
        KeelHost host(144);
        QVERIFY(host.start(runtime.path()));
        QVERIFY(!host.environment().contains("KEEL_AMBIENCE_KEYS"));
        QDBusConnection bus = peer(host.address(), "t5");
        QTRY_VERIFY(bus.isConnected());
        QVERIFY(bus.connect(QString(), kPath, kIface, "AmbienceChanged", this,
                            SLOT(onAmbience(QVariantMap))));
        host.setAmbience({{"/desktop/jolla/theme/color/highlight", "#abcdef"}});
        QTRY_COMPARE(m_last.value("/desktop/jolla/theme/color/highlight").toString(),
                     QStringLiteral("#abcdef"));
        QDBusConnection::disconnectFromPeer("t5");
    }
```
Run: `cmake --build build-tests --target test_core_keelhost`
Expected: build fails — `wantedFor` is not a member.

- [ ] **Step 2: Implement `wantedFor`**

`keelhost.h`: `static bool wantedFor(const QString &toolkit) { return toolkit != QLatin1String("marathonui"); }`
Run the test: expected all pass.

- [ ] **Step 3: AmbienceClient**

Follow the existing client pattern in `shellipcclients.cpp` (e.g. `SettingsClient`: a `QDBusInterface` on `org.marathonos.Shell`, async call, `QDBusConnection::sessionBus().connect(...)` for the signal):
```cpp
class AmbienceClient : public QObject {
    Q_OBJECT
  public:
    explicit AmbienceClient(QObject *parent = nullptr);
    QVariantMap ambience() const { return m_ambience; }
  signals:
    void ambienceChanged(const QVariantMap &ambience);
  private slots:
    void onAmbienceChanged(const QVariantMap &ambience);
  private:
    QVariantMap m_ambience;
};
```
```cpp
AmbienceClient::AmbienceClient(QObject *parent)
    : QObject(parent) {
    auto bus = QDBusConnection::sessionBus();
    bus.connect(QStringLiteral("org.marathonos.Shell"), QStringLiteral("/org/marathonos/Shell/Ambience"),
                QStringLiteral("org.marathonos.Shell.Ambience1"), QStringLiteral("AmbienceChanged"), this,
                SLOT(onAmbienceChanged(QVariantMap)));
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.marathonos.Shell"), QStringLiteral("/org/marathonos/Shell/Ambience"),
        QStringLiteral("org.marathonos.Shell.Ambience1"), QStringLiteral("GetAmbience"));
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(msg, 2000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *w) {
        QDBusPendingReply<QVariantMap> reply = *w;
        if (reply.isValid())
            onAmbienceChanged(reply.value());
        w->deleteLater();
    });
}

void AmbienceClient::onAmbienceChanged(const QVariantMap &ambience) {
    if (ambience == m_ambience)
        return;
    m_ambience = ambience;
    emit ambienceChanged(m_ambience);
}
```

- [ ] **Step 4: Wire into `main.cpp`**

After `info` is resolved and before the root component is created (both pool and cold paths reach this point; it is after the `QQuickView &view` line and before `QTimer::singleShot(0, &view, ...)` that creates the component):
```cpp
    std::unique_ptr<KeelHost>       keelHost;
    std::unique_ptr<AmbienceClient> ambienceClient;
    if (KeelHost::wantedFor(info->toolkit)) {
        ambienceClient = std::make_unique<AmbienceClient>();
        keelHost       = std::make_unique<KeelHost>(qRound(view.screen()->physicalDotsPerInch()));
        keelHost->setAmbience(ambienceClient->ambience());
        if (keelHost->start(qEnvironmentVariable("XDG_RUNTIME_DIR"))) {
            const auto env = keelHost->environment();
            for (auto it = env.cbegin(); it != env.cend(); ++it)
                qputenv(it.key().toUtf8(), it.value().toUtf8());
            QObject::connect(ambienceClient.get(), &AmbienceClient::ambienceChanged, keelHost.get(),
                             &KeelHost::setAmbience);
            QObject::connect(&view, &QWindow::activeChanged, keelHost.get(),
                             [&view, host = keelHost.get()]() { host->setActive(view.isActive()); });
            keelHost->onActivate = [appId]() { NavigationClient().launchApp(appId); };
        } else {
            qWarning() << "[marathon-app-runner] Keel host failed to start for" << appId;
            keelHost.reset();
        }
    }
```
`NavigationClient::launchApp` (ipc/shellipcclients.h) is the same call the app's own `NavigationService` uses; a short-lived instance avoids depending on construction order. `env` must be exported before Keel's `Shell` singleton is first touched, which is when the app QML is created: this placement guarantees it.

Close: SIGTERM through a self-pipe, so the app gets `CloseRequested` and a 1 s grace to save. File-scope:
```cpp
static int g_termFds[2] = {-1, -1};
static void onTerm(int) {
    const char c = 1;
    (void)::write(g_termFds[0], &c, 1);
}
```
After the host block:
```cpp
    if (::socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, g_termFds) == 0) {
        auto *termNotifier = new QSocketNotifier(g_termFds[1], QSocketNotifier::Read, &app);
        QObject::connect(termNotifier, &QSocketNotifier::activated, &app, [&keelHost]() {
            char c;
            (void)::read(g_termFds[1], &c, 1);
            if (keelHost) {
                keelHost->requestClose();
                QTimer::singleShot(1000, qApp, &QCoreApplication::quit);
            } else {
                QCoreApplication::quit();
            }
        });
        struct sigaction sa {};
        sa.sa_handler = onTerm;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = SA_RESTART;
        ::sigaction(SIGTERM, &sa, nullptr);
    }
```
Includes: `<csignal>`, `<sys/socket.h>`, `<unistd.h>`, `<QSocketNotifier>` (check which are already present).

- [ ] **Step 5: Build and run the existing suites**

Run: `cmake --build build --target marathon-app-runner 2>&1 | grep -E "error|Linking"; cd build-tests && ctest 2>&1 | tail -3`
Expected: links; `100% tests passed`.

- [ ] **Step 6: Stop: diff review**

---

### Task 7: Shell draws the ambience behind Keel apps

Keel apps under a host leave their background transparent (`ApplicationWindow.qml`: `visible: !Shell.phone`), as on Sailfish where Lipstick draws the ambience.

**Files:**
- Create: `shell/qml/components/KeelAmbienceBackground.qml`
- Modify: `shell/qml/components/MarathonAppWindow.qml`, `shell/CMakeLists.txt` (`QML_FILES`)
- Test: `tests/ui/tst_keelambiencebackground.qml`

**Interfaces:**
- Consumes: `AmbienceService.wallpaperUrl`, `AmbienceService.light` (Task 3); Keel's `image://keelambience/` provider (installed on import of `Keel 1.0`); `Theme.highlightDimmerColor`; `MarathonAppRegistry.getApp(appId).toolkit` (Task 1).
- Produces: `KeelAmbienceBackground { property string wallpaper; property bool light }`.

- [ ] **Step 1: Write the failing test**

```qml
import QtQuick
import QtTest
import Keel 1.0
import Sailfish.Silica 1.0
import "../../shell/qml/components"

TestCase {
    name: "KeelAmbienceBackground"
    when: windowShown

    KeelAmbienceBackground {
        id: bg
        width: 360; height: 720
        wallpaper: Qt.resolvedUrl("../../shell/resources/wallpapers/dawn.svg")
        light: false
    }

    function test_rendersDimmedWallpaper() {
        tryVerify(() => bg.ready, 3000);
        const img = grabImage(bg);
        const c = img.pixel(180, 360);
        verify(c.r < 0.5 && c.g < 0.5 && c.b < 0.5);   // dimmed, dark scheme
    }

    function test_lightSchemeWashesTowardsWhite() {
        bg.light = true;
        tryVerify(() => bg.ready, 3000);
        const c = grabImage(bg).pixel(180, 360);
        verify(c.r > 0.4 || c.g > 0.4 || c.b > 0.4);
        bg.light = false;
    }
}
```

- [ ] **Step 2: Run it and see it fail**

Run: `KEEL_QML=$HOME/Developer/Shipwright/build/keel/qml sh tests/ui/run.sh 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: FAIL — `KeelAmbienceBackground is not a type`.

- [ ] **Step 3: Implement**

`shell/qml/components/KeelAmbienceBackground.qml` (the same treatment Keel applies in its own window, so a Keel app looks the same on Marathon as off-host):
```qml
import QtQuick
import Sailfish.Silica 1.0

Item {
    id: root

    property string wallpaper
    property bool light: false
    readonly property bool ready: image.status === Image.Ready

    layer.enabled: ready

    Rectangle {
        anchors.fill: parent
        color: root.light ? "#e9eff2" : "#060b12"
    }
    Image {
        id: image
        anchors.fill: parent
        smooth: true
        cache: true
        source: root.wallpaper !== "" && width > 0 && height > 0
                ? "image://keelambience/" + encodeURIComponent(root.wallpaper)
                  + "?w=" + Math.round(width) + "&h=" + Math.round(height)
                : ""
    }
    Rectangle {
        anchors.fill: parent
        visible: root.ready
        color: root.light ? "white" : "black"
        opacity: root.light ? 0.45 : 0.62
    }
    Rectangle {
        anchors.fill: parent
        visible: root.ready && !root.light
        color: Theme.highlightDimmerColor
        opacity: 0.12
    }
}
```
`layer.enabled` flattens the static stack into one texture so the compositor blends one layer, not four.

In `MarathonAppWindow.qml`, under the app surface item (lowest z inside the window, above the window's own background), add:
```qml
    readonly property bool keelApp: {
        const info = typeof MarathonAppRegistry !== "undefined" ? MarathonAppRegistry.getApp(appId) : null;
        return !!info && info.toolkit !== "marathonui";
    }

    KeelAmbienceBackground {
        anchors.fill: parent
        visible: appWindow.keelApp
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
    }
```
Read the file first and place it below the surface item that holds the app's Wayland surface; keep the existing splash logic unchanged.

- [ ] **Step 4: Run the test**

Same command. Expected: both `KeelAmbienceBackground` tests pass; suite `0 failed`.

- [ ] **Step 5: Stop: diff review**

---

### Task 8: notes-silica on the pipeline, device verification

**Files:**
- Modify: `apps/notes-silica/SilicaApp.qml` (remove `wallpaperUrl`, `applyAmbience`, the `Connections`, the `Keel` and `MarathonUI.Theme` imports), `apps/notes-silica/tests/tst_silicaapp.qml` (remove `test_wallpaperUrl`)

- [ ] **Step 1: Trim SilicaApp and its tests**

`SilicaApp.qml` becomes:
```qml
import QtQuick
import Sailfish.Silica 1.0

ApplicationWindow {
    id: app

    property string appId: ""

    signal minimizeRequested

    function handleBack() {
        if (pageStack.depth > 1) {
            pageStack.pop();
            return true;
        }
        minimizeRequested();
        return true;
    }
}
```
Delete `test_wallpaperUrl` from `tst_silicaapp.qml`.

Run: `KEEL_QML=$HOME/Developer/Shipwright/build/keel/qml sh apps/notes-silica/tests/run.sh 2>&1 | grep -E "^(FAIL|Totals)"`
Expected: `0 failed`.

- [ ] **Step 2: Build and deploy**

Build `keel-silica` only if `packaging/packages/keel-silica/APKBUILD` changed, then `bash scripts/qemu/lib/build-marathon-shell-apk.sh`. Deploy the marathon-shell and marathon-shell-silica apks to the PinePhone in ≤20 MB chunks with greetd stopped, `rm -rf /home/user/.cache/marathon-qml`, start greetd, unlock over D-Bus (`Security1.AuthenticateQuickPIN 027602`).

- [ ] **Step 3: Verify on the device**

1. `busctl --user call org.marathonos.Shell /org/marathonos/Shell/Ambience org.marathonos.Shell.Ambience1 GetAmbience` returns the three keys.
2. Launch notes-silica: its environment (`/proc/<pid>/environ`) has `KEEL_SHELL=1` and `KEEL_AMBIENCE_*`; a legacy app (clock) has neither.
3. Screenshot: notes-silica shows the dimmed Marathon wallpaper behind it (shell-drawn) and the derived highlight, not teal.
4. Change the wallpaper (Settings → Wallpaper, or `Settings1.SetProperty wallpaperPath` from the Settings app): notes-silica and the shell's Keel engine re-theme within 1 s (two screenshots, timestamps).
5. Background notes-silica and resume: Silica's `applicationActive` follows (pulley works after resume).
6. Close notes-silica from the task switcher: the note being edited is saved (autosave plus `CloseRequested` grace).
7. Frame timing: with `MARATHON_FRAME_TIMING=1`, flick the notes list 10 times with the ambience background on, and compare median frame time against the same with `KeelAmbienceBackground.visible: false` (temporary local edit, reverted). Acceptance: ≤ 110% of the baseline.
8. Launch timing: notes-silica first-frame median of 3 stays within 10% of 1.7 s.

- [ ] **Step 4: Stop: diff review and report**

Report each check with evidence (screenshots, timings). Anything failing goes back to the user before fixing.
