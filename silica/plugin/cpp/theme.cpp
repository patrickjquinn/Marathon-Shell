// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

#include "theme.h"

#include <QPointer>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QScreen>
#include <QtMath>

KeelTheme::KeelTheme(QQmlEngine *engine, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
{
    // Light-on-dark defaults until the ambience is found (Ambience's own).
    for (QColor &c : m_colors)
        c = QColor(Qt::white);
    trackScreen(QGuiApplication::primaryScreen());
    if (auto *app = qobject_cast<QGuiApplication *>(QGuiApplication::instance()))
        connect(app, &QGuiApplication::primaryScreenChanged, this, [this](QScreen *s) {
            trackScreen(s);
            update();
        });
    update();
    attach();
}

KeelTheme *KeelTheme::create(QQmlEngine *engine, QJSEngine *)
{
    return new KeelTheme(engine);
}

void KeelTheme::attach()
{
    if (!m_engine)
        return;
    // A C++ singleton has no imports of its own (Theme.qml imported Keel):
    // qmlTypeId() loads the Keel module when this process has not yet, once.
    static const int ambienceId = qmlTypeId("Keel", 1, 0, "Ambience");
    static const int shellId = qmlTypeId("Keel", 1, 0, "Shell");
    QObject *ambience = ambienceId >= 0 ? m_engine->singletonInstance<QObject *>(ambienceId) : nullptr;
    if (!ambience) {
        qWarning("Sailfish.Silica Theme: Keel.Ambience not found");
        return;
    }
    m_ambience = ambience;
    if (QObject *shell = shellId >= 0 ? m_engine->singletonInstance<QObject *>(shellId) : nullptr)
        m_shellPhone = shell->property("phone").toBool();
    connect(ambience, SIGNAL(ambienceChanged()), this, SLOT(update()));
    update();
}

void KeelTheme::update()
{
    bool changed = false;
    auto set = [&changed](auto &member, const auto &value) {
        if (member != value) {
            member = value;
            changed = true;
        }
    };

    if (QObject *a = m_ambience.data()) {
        static const char *const names[8] = {
            "highlightColor", "primaryColor", "secondaryColor", "secondaryHighlightColor",
            "highlightBackgroundColor", "highlightDimmerColor", "overlayBackgroundColor", "errorColor",
        };
        for (int i = 0; i < 8; ++i)
            set(m_colors[i], toColor(a->property(names[i])));
        set(m_colorScheme, a->property("colorScheme").toInt());
        set(m_highlightBackgroundOpacity, a->property("highlightBackgroundOpacity").toReal());
        set(m_fontFamily, a->property("fontFamily").toString());
        set(m_fontFamilyHeading, a->property("fontFamilyHeading").toString());
        set(m_backgroundImage, a->property("backgroundImage").toString());
    }

    set(m_screenWidth, static_cast<qreal>(screenWidth(m_screen)));
    set(m_phoneScreen, phoneSized(m_screen));

    // From the ambience when dconf has it; otherwise, on a phone (Keel runs
    // without Qt's own high-DPI scaling), the screen width relative to 540 px
    // in quarter steps; 1.0 on a plain desktop run.
    const qreal ambienceRatio = m_ambience ? m_ambience->property("pixelRatio").toReal() : 0;
    qreal ratio = 1.0;
    if (ambienceRatio > 0)
        ratio = ambienceRatio;
    else if (m_shellPhone)
        ratio = qMax(1.0, jsRound(m_screenWidth / 540 * 4) / 4.0);
    set(m_pixelRatio, ratio);

    if (changed)
        emitChanged();
}

void KeelTheme::emitChanged()
{
    emit colorSchemeChanged();
    emit highlightColorChanged();
    emit primaryColorChanged();
    emit secondaryColorChanged();
    emit secondaryHighlightColorChanged();
    emit highlightBackgroundColorChanged();
    emit highlightDimmerColorChanged();
    emit overlayBackgroundColorChanged();
    emit errorColorChanged();
    emit highlightBackgroundOpacityChanged();
    emit fontFamilyChanged();
    emit fontFamilyHeadingChanged();
    emit fontSizeTinyBaseChanged();
    emit fontSizeExtraSmallBaseChanged();
    emit fontSizeSmallBaseChanged();
    emit fontSizeMediumBaseChanged();
    emit fontSizeLargeBaseChanged();
    emit fontSizeExtraLargeBaseChanged();
    emit fontSizeHugeBaseChanged();
    emit fontSizeTinyChanged();
    emit fontSizeExtraSmallChanged();
    emit fontSizeSmallChanged();
    emit fontSizeMediumChanged();
    emit fontSizeLargeChanged();
    emit fontSizeExtraLargeChanged();
    emit fontSizeHugeChanged();
    emit pixelRatioChanged();
    emit paddingSmallChanged();
    emit paddingMediumChanged();
    emit paddingLargeChanged();
    emit _phoneScreenChanged();
    emit _widthScaleChanged();
    emit horizontalPageMarginChanged();
    emit itemSizeExtraSmallChanged();
    emit itemSizeSmallChanged();
    emit itemSizeMediumChanged();
    emit itemSizeLargeChanged();
    emit itemSizeExtraLargeChanged();
    emit itemSizeHugeChanged();
    emit iconSizeExtraSmallChanged();
    emit iconSizeSmallChanged();
    emit iconSizeSmallPlusChanged();
    emit iconSizeMediumChanged();
    emit iconSizeLargeChanged();
    emit iconSizeExtraLargeChanged();
    emit iconSizeLauncherChanged();
    emit buttonWidthTinyChanged();
    emit buttonWidthExtraSmallChanged();
    emit buttonWidthSmallChanged();
    emit buttonWidthMediumChanged();
    emit buttonWidthLargeChanged();
    emit coverSizeLargeChanged();
    emit coverSizeSmallChanged();
    emit flickDecelerationChanged();
    emit maximumFlickVelocityChanged();
    emit startDragDistanceChanged();
    emit pageStackIndicatorWidthChanged();
    emit _lineWidthChanged();
    emit _backgroundImageChanged();
}

void KeelTheme::trackScreen(QScreen *screen)
{
    if (m_screen)
        disconnect(m_screen, nullptr, this, nullptr);
    m_screen = screen;
    if (screen) {
        connect(screen, &QScreen::geometryChanged, this, &KeelTheme::update);
        connect(screen, &QScreen::physicalSizeChanged, this, &KeelTheme::update);
    }
}

// Screen.width (screen.cpp): the short side, 540 without a screen.
int KeelTheme::screenWidth(const QScreen *screen)
{
    return screen ? qMin(screen->size().width(), screen->size().height()) : 540;
}

// Screen.sizeCategory <= Screen.Medium (screen.cpp): a diagonal under 7",
// or unknown; KEEL_SCREEN_DIAGONAL (inches) stands in for the panel's size.
bool KeelTheme::phoneSized(const QScreen *screen)
{
    bool ok = false;
    qreal inches = qEnvironmentVariable("KEEL_SCREEN_DIAGONAL").toDouble(&ok);
    if (!ok || inches <= 0) {
        const QSizeF mm = screen ? screen->physicalSize() : QSizeF();
        inches = mm.width() > 0 && mm.height() > 0
            ? qSqrt(mm.width() * mm.width() + mm.height() * mm.height()) / 25.4 : 0;
    }
    return inches < 7.0;
}

QColor KeelTheme::toColor(const QVariant &color)
{
    if (!color.isValid() || color.isNull())
        return QColor(Qt::transparent);
    if (color.metaType() == QMetaType::fromType<QColor>())
        return color.value<QColor>();
    // Strings ("#rrggbb", "#aarrggbb", SVG names) and anything else QML
    // converts to a colour.
    const QColor c = QColor::fromString(color.toString());
    return c.isValid() ? c : color.value<QColor>();
}

QColor KeelTheme::rgba(const QColor &color, qreal opacity) const
{
    QColor c = orTransparent(color);
    c.setAlphaF(static_cast<float>(opacity));
    return c;
}

QString KeelTheme::_colorString(const QVariant &color) const
{
    // #aarrggbb, as Ambience's colour helpers take it.
    return toColor(color).name(QColor::HexArgb);
}

QColor KeelTheme::fromColor(const char *method, const QColor &color, int scheme) const
{
    QString result;
    if (m_ambience)
        QMetaObject::invokeMethod(m_ambience.data(), method, Qt::DirectConnection,
                                  Q_RETURN_ARG(QString, result),
                                  Q_ARG(QString, orTransparent(color).name(QColor::HexArgb)), Q_ARG(int, scheme));
    return toColor(result);
}

QColor KeelTheme::highlightFromColor(const QColor &color, int scheme) const
{
    return fromColor("highlightFromColor", color, scheme);
}

QColor KeelTheme::secondaryHighlightFromColor(const QColor &color, int scheme) const
{
    return fromColor("secondaryHighlightFromColor", color, scheme);
}

QColor KeelTheme::highlightBackgroundFromColor(const QColor &color, int scheme) const
{
    return fromColor("highlightBackgroundFromColor", color, scheme);
}

QColor KeelTheme::highlightDimmerFromColor(const QColor &color, int scheme) const
{
    return fromColor("highlightDimmerFromColor", color, scheme);
}

static QString escaped(QStringView s)
{
    QString out;
    out.reserve(s.size());
    for (QChar c : s) {
        switch (c.unicode()) {
        case '&': out += QLatin1String("&amp;"); break;
        case '<': out += QLatin1String("&lt;"); break;
        case '>': out += QLatin1String("&gt;"); break;
        case '"': out += QLatin1String("&quot;"); break;
        default: out += c;
        }
    }
    return out;
}

static QString textOf(const QVariant &v)
{
    return !v.isValid() || v.isNull() ? QString() : v.toString();
}

QString KeelTheme::highlightText(const QVariant &text, const QVariant &pattern, const QVariant &color) const
{
    const QString t = textOf(text);
    const QString p = textOf(pattern);
    if (p.isEmpty())
        return escaped(t);
    // QML's String(color): #rrggbb when opaque, #aarrggbb otherwise.
    const QColor c = color.isValid() ? toColor(color) : highlightColor();
    const QString colorName = c.name(c.alpha() == 255 ? QColor::HexRgb : QColor::HexArgb);
    // Matched on lower-cased copies, as JavaScript's toLowerCase() and
    // indexOf() (the lengths of t and its lower case are the same for the
    // BMP text this sees).
    const QString lower = t.toLower();
    const QString lp = p.toLower();
    QString out;
    qsizetype pos = 0;
    while (true) {
        const qsizetype i = lower.indexOf(lp, pos);
        if (i < 0)
            break;
        out += escaped(QStringView(t).mid(pos, i - pos));
        out += QLatin1String("<font color=\"") + colorName + QLatin1String("\">")
            + escaped(QStringView(t).mid(i, p.size())) + QLatin1String("</font>");
        pos = i + p.size();
    }
    return out + escaped(QStringView(t).mid(pos));
}

QString KeelTheme::iconForMimeType(const QVariant &mimeType) const
{
    const QString m = textOf(mimeType).toLower();
    const QString base = QStringLiteral("image://theme/icon-m-file-");
    auto has = [&m](std::initializer_list<const char *> parts) {
        for (const char *p : parts)
            if (m.contains(QLatin1String(p)))
                return true;
        return false;
    };
    if (m == QLatin1String("inode/directory"))
        return base + QLatin1String("folder");
    if (m == QLatin1String("application/vnd.android.package-archive"))
        return base + QLatin1String("apk");
    if (m == QLatin1String("application/x-rpm") || m == QLatin1String("application/x-redhat-package-manager"))
        return base + QLatin1String("rpm");
    if (m == QLatin1String("application/pdf"))
        return base + QLatin1String("pdf");
    if (m == QLatin1String("text/vcard") || m == QLatin1String("text/x-vcard") || m == QLatin1String("text/directory"))
        return base + QLatin1String("vcard");
    if (m == QLatin1String("text/plain"))
        return base + QLatin1String("note");
    if (m.startsWith(QLatin1String("audio/")))
        return base + QLatin1String("audio");
    if (m.startsWith(QLatin1String("image/")))
        return base + QLatin1String("image");
    if (m.startsWith(QLatin1String("video/")))
        return base + QLatin1String("video");
    if (has({"spreadsheet", "ms-excel", "text/csv"}))
        return base + QLatin1String("spreadsheet");
    if (has({"presentation", "powerpoint"}))
        return base + QLatin1String("presentation");
    if (has({"msword", "wordprocessing", "opendocument.text", "rtf", "text/html"}))
        return base + QLatin1String("formatted");
    return base + QLatin1String("other");
}

QString KeelTheme::presenceColor(int presenceMode) const
{
    switch (presenceMode) {
    case PresenceAvailable: return QStringLiteral("#41c55a");
    case PresenceAway: return QStringLiteral("#ffbd33");
    case PresenceBusy: return QStringLiteral("#ff4d4d");
    default: return QStringLiteral("#8c8c8c");
    }
}
