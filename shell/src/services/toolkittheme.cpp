#include "toolkittheme.h"

#include <QList>
#include <QtMath>

#include <algorithm>
#include <cmath>

namespace {
    double linear(double c) {
        return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4);
    }

    double luminance(const QColor &c) {
        return 0.2126 * linear(c.redF()) + 0.7152 * linear(c.greenF()) + 0.0722 * linear(c.blueF());
    }

    double worstContrast(const QColor &c, const QList<QColor> &backgrounds) {
        double worst = 21;
        for (const QColor &bg : backgrounds)
            worst = std::min(worst, ToolkitTheme::contrast(c, bg));
        return worst;
    }

    // Moves a colour's lightness away from the backgrounds until it reads on
    // all of them, keeping its hue.
    QColor readable(QColor c, const QList<QColor> &backgrounds, bool dark) {
        constexpr double kAA = 4.5;
        while (worstContrast(c, backgrounds) < kAA) {
            float h = 0, s = 0, l = 0;
            c.getHslF(&h, &s, &l);
            l = dark ? std::min(1.0F, l + 0.01F) : std::max(0.0F, l - 0.01F);
            c = QColor::fromHslF(std::max(0.0F, h), s, l);
            if (l <= 0.0F || l >= 1.0F)
                break;
        }
        return c;
    }

    QColor mix(const QColor &a, const QColor &b, double t) {
        return QColor::fromRgbF(float(a.redF() + (b.redF() - a.redF()) * t),
                                float(a.greenF() + (b.greenF() - a.greenF()) * t),
                                float(a.blueF() + (b.blueF() - a.blueF()) * t));
    }

    QColor textOn(const QColor &bg) {
        return ToolkitTheme::contrast(bg, Qt::black) > ToolkitTheme::contrast(bg, Qt::white) ?
            QColor(Qt::black) :
            QColor(Qt::white);
    }

    QString kde(const QColor &c) {
        return QStringLiteral("%1,%2,%3")
            .arg(QString::number(c.red()), QString::number(c.green()), QString::number(c.blue()));
    }

    QString hex(const QColor &c) {
        return c.name(QColor::HexRgb);
    }

    QMap<QString, QString> kdeGroup(const ToolkitPalette &p, const QColor &bg, const QColor &alt) {
        return {
            {QStringLiteral("BackgroundNormal"), kde(bg)},
            {QStringLiteral("BackgroundAlternate"), kde(alt)},
            {QStringLiteral("ForegroundNormal"), kde(p.fg)},
            {QStringLiteral("ForegroundInactive"), kde(p.inactiveFg)},
            {QStringLiteral("ForegroundActive"), kde(p.link)},
            {QStringLiteral("ForegroundLink"), kde(p.link)},
            {QStringLiteral("ForegroundVisited"), kde(p.visited)},
            {QStringLiteral("ForegroundNegative"), kde(p.negative)},
            {QStringLiteral("ForegroundNeutral"), kde(p.neutral)},
            {QStringLiteral("ForegroundPositive"), kde(p.positive)},
            {QStringLiteral("DecorationFocus"), kde(p.accent)},
            {QStringLiteral("DecorationHover"), kde(p.accent)},
        };
    }

    QString adwColors(const ToolkitPalette &p, const QString &indent) {
        const QList<std::pair<const char *, QString>> colors = {
            {"accent_color", hex(p.link)},
            {"accent_bg_color", hex(p.accent)},
            {"accent_fg_color", hex(p.accentFg)},
            {"destructive_color", hex(p.negative)},
            {"destructive_bg_color", hex(p.negative)},
            {"destructive_fg_color", hex(textOn(p.negative))},
            {"success_color", hex(p.positive)},
            {"warning_color", hex(p.neutral)},
            {"error_color", hex(p.negative)},
            {"window_bg_color", hex(p.window)},
            {"window_fg_color", hex(p.fg)},
            {"view_bg_color", hex(p.view)},
            {"view_fg_color", hex(p.fg)},
            {"headerbar_bg_color", hex(p.header)},
            {"headerbar_fg_color", hex(p.fg)},
            {"headerbar_backdrop_color", hex(p.window)},
            {"sidebar_bg_color", hex(p.header)},
            {"sidebar_fg_color", hex(p.fg)},
            {"sidebar_backdrop_color", hex(p.window)},
            {"secondary_sidebar_bg_color", hex(p.window)},
            {"secondary_sidebar_fg_color", hex(p.fg)},
            {"card_bg_color", hex(p.button)},
            {"card_fg_color", hex(p.fg)},
            {"dialog_bg_color", hex(p.header)},
            {"dialog_fg_color", hex(p.fg)},
            {"popover_bg_color", hex(p.header)},
            {"popover_fg_color", hex(p.fg)},
            {"thumbnail_bg_color", hex(p.button)},
            {"thumbnail_fg_color", hex(p.fg)},
        };
        QString out;
        for (const auto &[name, value] : colors)
            out +=
                QStringLiteral("%1@define-color %2 %3;\n").arg(indent, QLatin1String(name), value);
        out += indent + QStringLiteral(":root {\n");
        for (const auto &[name, value] : colors) {
            const QString var =
                QString::fromLatin1(name).replace(QLatin1Char('_'), QLatin1Char('-'));
            out += QStringLiteral("%1  --%2: %3;\n").arg(indent, var, value);
        }
        out += indent + QStringLiteral("}\n");
        return out;
    }
} // namespace

namespace ToolkitTheme {

    double contrast(const QColor &a, const QColor &b) {
        const double la = luminance(a);
        const double lb = luminance(b);
        return (std::max(la, lb) + 0.05) / (std::min(la, lb) + 0.05);
    }

    ToolkitPalette palette(const QColor &highlight, bool dark) {
        const float hue  = std::max(0.0F, highlight.hslHueF());
        const float tint = std::min(0.22F, highlight.hslSaturationF() * 0.35F);
        auto        tone = [hue, tint](float lightness, float sat = 1.0F) {
            return QColor::fromHslF(hue, tint * sat, lightness);
        };

        ToolkitPalette p;
        p.dark = dark;
        if (dark) {
            p.window     = tone(0.12F);
            p.view       = tone(0.09F);
            p.header     = tone(0.15F);
            p.button     = tone(0.18F);
            p.tooltip    = tone(0.16F);
            p.fg         = tone(0.94F, 0.5F);
            p.inactiveFg = tone(0.68F, 0.5F);
        } else {
            p.window     = tone(0.95F);
            p.view       = tone(0.99F);
            p.header     = tone(0.91F);
            p.button     = tone(0.97F);
            p.tooltip    = tone(0.97F);
            p.fg         = tone(0.13F, 0.6F);
            p.inactiveFg = tone(0.38F, 0.5F);
        }
        const QList<QColor> backgrounds = {p.window, p.view, p.header, p.button, p.tooltip};
        p.fg                            = readable(p.fg, backgrounds, dark);
        p.inactiveFg                    = readable(p.inactiveFg, backgrounds, dark);

        p.accent   = highlight.toRgb();
        p.accentFg = textOn(p.accent);
        p.link     = readable(p.accent, backgrounds, dark);
        p.visited  = readable(mix(p.link, QColor(0x9b, 0x59, 0xb6), 0.6), backgrounds, dark);
        p.negative = readable(QColor(0xda, 0x44, 0x53), backgrounds, dark);
        p.neutral  = readable(QColor(0xf6, 0x74, 0x00), backgrounds, dark);
        p.positive = readable(QColor(0x27, 0xae, 0x60), backgrounds, dark);
        return p;
    }

    QString gnomeAccent(const QColor &color) {
        const double r      = linear(color.redF());
        const double g      = linear(color.greenF());
        const double b      = linear(color.blueF());
        const double l      = std::cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
        const double m      = std::cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
        const double s      = std::cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
        const double A      = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
        const double B      = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
        const double chroma = std::hypot(A, B);
        double       h      = qRadiansToDegrees(std::atan2(B, A));
        if (h < 0)
            h += 360;
        // adw_accent_color_nearest_from_rgba's thresholds.
        if (chroma < 0.04)
            return QStringLiteral("slate");
        if (h > 345)
            return QStringLiteral("pink");
        if (h > 280)
            return QStringLiteral("purple");
        if (h > 230)
            return QStringLiteral("blue");
        if (h > 175)
            return QStringLiteral("teal");
        if (h > 115)
            return QStringLiteral("green");
        if (h > 75.5)
            return QStringLiteral("yellow");
        if (h > 35)
            return QStringLiteral("orange");
        if (h > 10)
            return QStringLiteral("red");
        return QStringLiteral("pink");
    }

    KdeGroups kdeColors(const ToolkitPalette &p) {
        KdeGroups groups;
        groups.insert(QStringLiteral("Colors:Window"), kdeGroup(p, p.window, p.header));
        groups.insert(QStringLiteral("Colors:View"), kdeGroup(p, p.view, mix(p.view, p.fg, 0.05)));
        groups.insert(QStringLiteral("Colors:Button"),
                      kdeGroup(p, p.button, mix(p.button, p.accent, 0.3)));
        groups.insert(QStringLiteral("Colors:Header"), kdeGroup(p, p.header, p.window));
        groups.insert(QStringLiteral("Colors:Tooltip"), kdeGroup(p, p.tooltip, p.window));

        const ToolkitPalette comp = p.dark ? p : palette(p.accent, true);
        groups.insert(QStringLiteral("Colors:Complementary"),
                      kdeGroup(comp, comp.window, mix(comp.window, comp.accent, 0.3)));

        QMap<QString, QString> selection = kdeGroup(p, p.accent, mix(p.accent, p.window, 0.4));
        for (auto it = selection.begin(); it != selection.end(); ++it) {
            if (it.key().startsWith(QLatin1String("Foreground")))
                it.value() = kde(p.accentFg);
        }
        groups.insert(QStringLiteral("Colors:Selection"), selection);

        groups.insert(QStringLiteral("WM"),
                      {
                          {QStringLiteral("activeBackground"), kde(p.header)},
                          {QStringLiteral("activeForeground"), kde(p.fg)},
                          {QStringLiteral("activeBlend"), kde(p.fg)},
                          {QStringLiteral("inactiveBackground"), kde(p.window)},
                          {QStringLiteral("inactiveForeground"), kde(p.inactiveFg)},
                          {QStringLiteral("inactiveBlend"), kde(p.inactiveFg)},
                      });
        return groups;
    }

    QString kdeColorScheme(const ToolkitPalette &p) {
        KdeGroups groups = kdeColors(p);
        groups.insert(QStringLiteral("General"),
                      {{QStringLiteral("ColorScheme"), QStringLiteral("Marathon")},
                       {QStringLiteral("Name"), QStringLiteral("Marathon")}});
        QString out =
            QStringLiteral("# Generated by Marathon (ToolkitTheme::kdeColorScheme) for its "
                           "default ambience;\n# apps in the KDE runtime get the live one "
                           "through the Settings portal.\n");
        for (auto g = groups.cbegin(); g != groups.cend(); ++g) {
            out += QStringLiteral("\n[%1]\n").arg(g.key());
            for (auto k = g->cbegin(); k != g->cend(); ++k)
                out += QStringLiteral("%1=%2\n").arg(k.key(), k.value());
        }
        return out;
    }

    QString gtk3Css(const ToolkitPalette &p) {
        const QString adwaita =
            p.dark ? QStringLiteral("gtk-contained-dark.css") : QStringLiteral("gtk-contained.css");
        const QString border = hex(mix(p.window, p.fg, 0.18));
        QString       css    = QString::fromLatin1(kMarker) + QLatin1Char('\n');
        css += QStringLiteral("@import url(\"resource:///org/gtk/libgtk/theme/Adwaita/%1\");\n\n")
                   .arg(adwaita);
        const QList<std::pair<const char *, QString>> colors = {
            {"theme_bg_color", hex(p.window)},
            {"theme_fg_color", hex(p.fg)},
            {"theme_base_color", hex(p.view)},
            {"theme_text_color", hex(p.fg)},
            {"theme_selected_bg_color", hex(p.accent)},
            {"theme_selected_fg_color", hex(p.accentFg)},
            {"insensitive_bg_color", hex(p.window)},
            {"insensitive_fg_color", hex(p.inactiveFg)},
            {"insensitive_base_color", hex(p.view)},
            {"theme_unfocused_bg_color", hex(p.window)},
            {"theme_unfocused_fg_color", hex(p.fg)},
            {"theme_unfocused_base_color", hex(p.view)},
            {"theme_unfocused_text_color", hex(p.fg)},
            {"theme_unfocused_selected_bg_color", hex(p.accent)},
            {"theme_unfocused_selected_fg_color", hex(p.accentFg)},
            {"borders", border},
            {"unfocused_borders", border},
            {"warning_color", hex(p.neutral)},
            {"error_color", hex(p.negative)},
            {"success_color", hex(p.positive)},
            {"marathon_header_color", hex(p.header)},
            {"marathon_button_color", hex(p.button)},
            {"marathon_link_color", hex(p.link)},
            {"marathon_visited_color", hex(p.visited)},
        };
        for (const auto &[name, value] : colors)
            css += QStringLiteral("@define-color %1 %2;\n").arg(QLatin1String(name), value);

        // Adwaita's GTK 3 stylesheet bakes its colours in, so the widgets that
        // carry most of an app's surface are restyled with the named colours.
        css += QStringLiteral(R"(
window, .background, dialog, popover, menu, .menu {
  background-color: @theme_bg_color;
  color: @theme_fg_color;
}
headerbar, .titlebar, headerbar:backdrop, .titlebar:backdrop {
  background: @marathon_header_color;
  color: @theme_fg_color;
  border-color: @borders;
  box-shadow: none;
}
.view, iconview, textview text, treeview, list, row, entry, spinbutton {
  background-color: @theme_base_color;
  color: @theme_text_color;
}
button {
  background: @marathon_button_color;
  color: @theme_fg_color;
  border-color: @borders;
  box-shadow: none;
  text-shadow: none;
  -gtk-icon-shadow: none;
}
button:hover {
  background: shade(@marathon_button_color, 1.1);
}
button.suggested-action, button:checked {
  background: @theme_selected_bg_color;
  color: @theme_selected_fg_color;
  border-color: @theme_selected_bg_color;
}
entry:focus, spinbutton:focus {
  border-color: @theme_selected_bg_color;
  box-shadow: inset 0 0 0 1px @theme_selected_bg_color;
}
*:selected, selection, .view:selected, row:selected {
  background-color: @theme_selected_bg_color;
  color: @theme_selected_fg_color;
}
*:link {
  color: @marathon_link_color;
}
*:visited {
  color: @marathon_visited_color;
}
scale highlight, progressbar progress, levelbar block.filled, switch:checked {
  background: @theme_selected_bg_color;
  border-color: @theme_selected_bg_color;
}
)");
        return css;
    }

    QString gtk4Css(const QColor &highlight, bool dark) {
        QString css = QString::fromLatin1(kMarker) + QLatin1Char('\n');
        css += adwColors(palette(highlight, dark), {});
        css += QStringLiteral("\n@media (prefers-color-scheme: dark) {\n");
        css += adwColors(palette(highlight, true), QStringLiteral("  "));
        css += QStringLiteral("}\n\n@media (prefers-color-scheme: light) {\n");
        css += adwColors(palette(highlight, false), QStringLiteral("  "));
        css += QStringLiteral("}\n");
        return css;
    }

} // namespace ToolkitTheme
