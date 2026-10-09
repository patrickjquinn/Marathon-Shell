<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT
-->

# Visual references for Keel's Silica

What Keel's look is compared with, and the values measured from it. The
images themselves are third-party (Jolla Ltd. and the Sailfish OS
documentation contributors) and are **not** in this repository: download
them from the URLs below into a scratch directory. Only facts measured from
them (sizes, colours, falloff curves) are used in Keel, with Keel's own code
and artwork.

## Sources

- **Sailfish OS documentation**, user guide screenshots of the stock apps on
  an Xperia 10 II-IV (1080x2520, Sailfish OS 4.4-5.0, the stock "water"
  ambience): git repository https://github.com/sailfishos/docs.sailfishos.org,
  files under `Support/Help_Articles/` (Clock, Email, Messages/Messages_App,
  People_App_and_Contacts, Gallery, Camera, Phone, Calendar, Ambiences,
  Device_Lock_and_Security_Code) and `Develop/Apps/UI/`. Licence:
  CC BY-NC-SA 4.0 (`LICENSE-documentation.txt`); reference only. The ones
  measured below:
  - `Support/Help_Articles/Messages/Messages_App/Settings_Apps_Messages.png`
    (PageHeader, SectionHeader, TextField, TextSwitch, ValueButton)
  - `Support/Help_Articles/People_App_and_Contacts/People_home_view.png`,
    `People_contact_search.png` (list items, SearchField)
  - `Support/Help_Articles/Email/Email_inbox_pulley.png` (PullDownMenu),
    `Email_selected_delete_or_read.png`
  - `Support/Help_Articles/Clock/Clock_alarm_snooze_duration.png` (ComboBox
    menu), `Clock_new_alarm_weekdays_name.png` (DialogHeader, TimePicker),
    `Clock_alarm_modify.png` (ContextMenu), `Clock_default.png` (background)
  - `Support/Help_Articles/Gallery/Gallery_remorse_timer_running.png` (remorse)
- **Jolla blog** (https://blog.jolla.com, (c) Jolla Ltd.), release
  announcements with device screenshots, e.g.
  `content/uploads/2025/02/appsupport-13.png` (Jolla C2, 720x1600, Sailfish
  5: Button, TextSwitch, SectionHeader), `2022/03/VanhaRauma_UIScreens_2.jpg`,
  `2023/02/Struven_Screens_{1,2,3}.jpg`, `2021/09/Verla_Screens_1_.jpg`,
  `2018/10/wlan_enterprise_wpaeap_dark.png` (Xperia XA2, 1080x1920),
  `2019/01/light-ambience*.jpg`, `2018/10/usbotg_light.png` (light ambiences).
- **Silica documentation images** (https://sailfishos.org/content/sailfishos-docs/sailfishsilica-qt5/latest/images/,
  (c) Jolla Ltd.): `theme.jpg` (Theme cheat sheet, Jolla 1 at half size),
  `pulldownmenu.png`, `dialog.png`, `padding.png`.
- **Sailfish OS 5.0.0.62 packages** from https://releases.jolla.com/releases/5.0.0.62/jolla/aarch64/:
  `oss/noarch/sailfish-fonts-0.3.1-1.1.1.jolla.noarch.rpm` (Sail Sans Pro,
  SIL OFL 1.1; tools/screenshots uses it), and, read for their values only,
  `non-oss/noarch/sailfish-content-ambiences-default-{water,airy,glacial,silent,sailfish3,sailfish5}-1.0.14-1.5.1.jolla.noarch.rpm`
  (proprietary: `.ambience` colour values; the wallpapers are used only for
  local side-by-side renders, never shipped).

## Measurements

Xperia 10 (1080x2520) is pixelRatio 1.75: MenuItem pitch 122 px
(itemSizeExtraSmall 70), list item pitch 140 px (itemSizeSmall 80).

| What | Measured | Keel |
|---|---|---|
| fontSizeMedium | list text cap height 38 px at 1.75; Sail Sans Pro cap 0.659 em: 57.7 px | 32 at 1.0 (56 at 1.75) |
| fontSizeLarge | page header cap 48 px: 73 px | 40 (70) |
| fontSizeSmall | section header cap 33 px: 50 px | 28 (49) |
| fontSizeExtraSmall | description line pitch 54 px, 1.257 em: 43 px; 31 px on a Jolla C2 at 1.0 | 24 (42) |
| font weight | page/dialog header stems 4 px at 70 px (Light: 4, ExtraLight: 2) | headings in Sail Sans Pro Light |
| horizontalPageMargin | 48 px on 1080 (1.75), 32 px on 720 (C2, 1.0), 24 on 540 (Jolla 1) | 24 per 540 px of width on phones |
| paddingLarge | TextSwitch label at hpm - paddingLarge + itemSizeExtraSmall = 129 px: 42 at 1.75 | 24 x ratio |
| Button width | 316 px on a C2 (720, 1.0), 473 px on an XA2 (1080) | buttonWidth* x width/540 on phones |
| secondaryColor | #bababa (dark ambiences), #454545 (light): `.ambience` files | same |
| secondaryHighlightColor | water #7ff0fe -> #62b9c4, sailfish5 #ffad80 -> #c58562 (x0.77); airy #004c99 -> #003d76 (x0.8) | highlight x0.77 / x0.8 |
| highlightBackgroundColor | ComboBox menu over the page and its highlight bar, both at opacity 0.3: about #00cde7 for #7ff0fe (same hue, full saturation) | saturated hue at 0.9 value (dark ambiences) |
| App background | wallpaper cropped to the screen (full height), Gaussian blur of about 80 px at 1080 px width, about 0.3 x brightness | image://keelambience (7.5 % of width), black 0.62, highlight dimmer 0.12 |
| Glass dither | 8x8 tile, two staggered specks fading over 4 rows: +24, +15, +7.5, +3.7 grey levels, additive, at device pixels | Keel's own tile, ambience/glass-dither.png |
| GlassItem glow | checked TextSwitch (radius 0.22, falloff 0.17, 122 px item): full to 0.06 h, half at 0.13 h, tenth at 0.30 h, exponential; dithered (pixel max about 3.5 x mean outside the core) | core 0.27 radius, exponential length 0.62 falloff, same dither |
| TimePicker dot | half intensity at 23 px, tenth at 66 px: about 1.4 x a switch's glow | TimePickerGlassItem 1.4 x itemSizeExtraSmall |

## Rendering the comparison

```
# Keel's own ambiences, at the Xperia 10 profile:
tools/screenshots/run.sh --only keel-gallery --device xperia10 --out /tmp/shots
# In the reference's own ambience (the wallpaper stays a local file):
SHOT_AMBIENCE_DARK="highlightColor=#7ff0fe;secondaryHighlightColor=#62b9c4;backgroundImage=/path/to/ambience_water.jpg" \
  tools/screenshots/run.sh --only keel-gallery --device xperia10 --out /tmp/shots-water
```
