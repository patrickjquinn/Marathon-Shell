<!--
SPDX-FileCopyrightText: 2026 Patrick Quinn
SPDX-License-Identifier: MIT
-->

# keel/silica provenance

Keel's `Sailfish.Silica` is Silica's own BSD-licensed QML, ported to Qt 6,
running on clean-room reimplementations of the proprietary parts it needs
(docs/plan.md, "Licensing and provenance", constraint 2).

## Sources and the licence check

**Current release (what the ports are made from).** `sailfishsilica-qt5`
1.2.156-1.37.1 (aarch64) of Sailfish OS 5.2.0.15, downloaded in the Sailfish
SDK on 2026-10-01 with
`sb2 -t SailfishOS-5.2.0.15-aarch64 -m sdk-install -R zypper download sailfishsilica-qt5`.
Only the file list, the package's licence notices and the licence header of
each QML/JS file were read to classify the files; the proprietary plugin
(`libsailfishsilicaplugin.so`), `qmldir`, `plugins.qmltypes` and the non-BSD
QML were not opened beyond their headers and are not in this repository.

- The package's own `LICENSE` says: "Sailfish.Silica module's QML code and QML
  examples have been licensed under BSD. [...] Rest of Silica is under
  proprietary license." It and `LICENSE.BSD` are kept with the pristine copies.
- 176 QML/JS files under `usr/lib/qt5/qml/Sailfish/Silica/`: **139 carry the
  BSD licence header**, 37 do not (proprietary; never used, names only below).
- The 139 BSD files are kept byte for byte in
  `upstream/sailfishsilica-qt5-1.2.156/` (REUSE annotation in
  `upstream/REUSE.toml`), so that `upstream/port.py check` can verify every
  port against its original.

Files without a BSD header in 1.2.156 (not used; where Silica's BSD QML needs
one, Keel has a clean-room stand-in, see "Keel stand-ins" below):
`Background/BlurMaterial.qml`, `Background/ColorBackground.qml`, `Background/CommonFilters.qml`, `Background/CommonMaterials.qml`, `Background/ConvolutionFilter.qml`, `Background/Filters.qml`, `Background/GlassBlur.qml`, `Background/GlassBlurDark.qml`, `Background/GlassBlurLight.qml`, `Background/GlassMaterial.qml`, `Background/ImageWallpaper.qml`, `Background/Material.qml`, `Background/Materials.qml`, `Background/PlatformFilters.qml`, `Background/PlatformMaterials.qml`, `Background/RepeatFilter.qml`, `Background/ResizeFilter.qml`, `Background/SequenceFilter.qml`, `Background/ShaderFilter.qml`, `Background/ThemeBackground.qml`, `Background/ThemeImageWallpaper.qml`, `Background/ThemeWallpaper.qml`, `Background/WallpaperLoader.qml`, `TextEditorLabel.qml`, `private/ClockItem.qml`, `private/CoverWindow.qml`, `private/Expander.qml`, `private/FadeGradient.qml`, `private/GestureHintAnimation.qml`, `private/GridItemRemorseContainer.qml`, `private/IconGridViewBase.qml`, `private/LayoutGrid.qml`, `private/ShowMoreButton.qml`, `private/Slideable.qml`, `private/TimePickerGlassItem.qml`, `private/WindowGestureOverride.qml`, `private/ZoomableFlickable.qml`.

**Historical mirror (fallback only).** github.com/dm8tbr/sailfishsilica-qt5,
commit `10d400ee42d66dc4e787159f12dde7dd6d29b6e2` (an unpacked 2014 package),
95 QML/JS files. Compared with 1.2.156: 81 mirror files are BSD in both; 6
that the mirror replaced with a placeholder (not clearly BSD in 2014) are BSD
in 1.2.156 (`Keypad.qml`, `ListItem.qml`, `OpacityRampEffect.qml`,
`PanelBackground.qml`, `private/KeypadButton.qml`,
`private/ReturnToHomeHintCounter.qml`); 8 are absent from 1.2.156
(`BackButton.qml`, `SilicaWebView.qml`, `private/HighlightBar.qml`,
`private/HighlightImage.qml`, `private/MenuIndicator.qml`,
`private/TextAutoScroller.js`, `private/TextAutoScroller.qml`,
`private/Wallpaper.qml`). **No mirror file became non-BSD** in 1.2.156. Every
port below is made from the 1.2.156 file; no mirror file is used (Keel 0.1's
adaptations of 2014 files were replaced by ports of the current ones).

**[VERIFY] before each commercial release**: rerun the header check on the
`sailfishsilica-qt5` of the target release (the commands above, then
`upstream/port.py check`); a file whose header is no longer BSD must be
removed from `upstream/` and its port replaced by a clean-room stand-in.

## Ports

`upstream/port.py import <file>` starts a port; `upstream/port.py check`
verifies all of them. A port is the 1.2.156 file with, in order: SPDX lines
(the file's copyright holders, BSD-3-Clause, and `2026 Shipwright` when
modified); the upstream licence header **byte for byte**; a
`// Upstream: sailfishsilica-qt5-1.2.156 (Sailfish OS 5.2.0.15) <file>` line;
one `// Modified by Shipwright for Qt 6: <summary>` line per kind of change;
then the upstream body, where every edit is marked with a comment containing
"Modified by Shipwright for Qt 6".

- **133 of the 139 BSD files are ported: 39 verbatim, 94 modified** (Qt 6
  edits only). Public files are in `qml/` (module `Sailfish.Silica`), private
  ones in `qml/private/` (module `Sailfish.Silica.private`).
- Not ported (6): `ApplicationWindow.qml` (Keel keeps its own window, which
  implements the keel-shell contract, keel/shell/PROTOCOL.md, and the cover
  window; it carries the members Silica's BSD QML reads from
  `__silica_applicationwindow_instance`), `CoverLoader.js` (part of that
  window), and `Background/CommonKeyboardMaterials.qml`,
  `Background/KeyboardBackground.qml`, `Background/KeyboardMaterials.qml`,
  `Background/PlatformKeyboardMaterials.qml` (virtual keyboard materials;
  they need the proprietary Background module and no app uses them).
- The recurring Qt 5 to Qt 6 edits: signal handlers in `Connections` written
  as functions, and handlers that use signal parameters declare them (Qt 6
  no longer injects them); `import "private"` / `import ".."` replaced by
  module imports (the files are served from resources); `Screen.` qualified
  as `KeelSilica.Screen.` (Qt 6 resolves an unqualified `Screen` to Qt
  Quick's attached type); inline GLSL `ShaderEffect` shaders replaced by
  compiled Qt 6 shaders (below), with no shader layer on the software scene
  graph; bindings that read a still-null `flickable` or page stack indicator
  at creation guarded; a few bindings that Qt 6 reports as loops (Button's
  background margins, Slider's padding, TextField's single-line width)
  updated after the change instead.
- `qml/shaders/*.frag`, `*.vert`: the inline GLSL of `private/PulleyMenuBase.qml`,
  `ContextMenu.qml`, `DockedPanel.qml`, `TimePicker.qml`,
  `ProgressCircleBase.qml` and `OpacityRampEffectBase.qml`, rewritten in Qt 6
  shader syntax (same computation; BSD-3-Clause with the source file's
  copyright). `build-shaders.sh` compiles them with Qt's `qsb` into the
  committed `.qsb` files (GLSL ES 100/300 es, GLSL 120/150).
- `plugin/cpp/private/silicastrings.inc` is generated by `upstream/port.py
  strings` from the `//%` engineering-English comments of the BSD QML
  (BSD-3-Clause); Keel's fallback translator uses it so that `qsTrId()` ids
  never show (the device's own Silica translations are loaded first when
  installed).

## Catalogue of the BSD files

Generated by `upstream/port.py catalogue` (regenerate after changing a port).
"Private module types" are names the file uses from `Sailfish.Silica.private`:
the native types (Keel's clean-room C++ or Rust), Keel's stand-ins for non-BSD
private files ("private Keel QML") and Silica's own private BSD QML (no
label). "Other non-BSD types" are public Silica types whose implementation
is proprietary in Silica and clean-room in Keel. Name matching is textual,
so a type named in a string can appear.

### Licence header variants

Every BSD file's header is one of these, apart from its `Copyright (C)` lines (which
name Jolla Ltd., Open Mobile Platform LLC or Nokia Corporation and the years). Each
port keeps its own file's header byte for byte; the full texts are also in
`upstream/sailfishsilica-qt5-1.2.156/`.

Variant 1 (106 files), as in `ComboBox.qml`:

```
/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** All rights reserved.
** 
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
** 
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 2 (4 files), as in `PasswordField.qml`:

```
/****************************************************************************************
**
** Copyright (C) 2013-2015 Jolla Ltd.
** Copyright (C) 2020 Open Mobile Platform LLC.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 3 (4 files), as in `ApplicationWindow.qml`:

```
/****************************************************************************************
**
** Copyright (c) 2013-2020 Jolla Ltd.
** Copyright (c) 2020 Open Mobile Platform LLC.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 4 (4 files), as in `RemorseItem.qml`:

```
/****************************************************************************************
**
** Copyright (C) 2013 - 2020 Jolla Ltd.
** Copyright (c) 2019 - 2020 Open Mobile Platform LLC.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 5 (3 files), as in `Background/KeyboardMaterials.qml`:

```
/****************************************************************************************
**
** Copyright (c) 2020 Open Mobile Platform LLC.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 6 (2 files), as in `IconMenuItem.qml`:

```
/****************************************************************************************
**
** Copyright (c) 2020 Open Mobile Platform LLC.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 7 (2 files), as in `DetailItem.qml`:

```
/****************************************************************************************
**
** Copyright (C) 2014-2015 Jolla Ltd.
** Copyright (c) 2019 Open Mobile Platform LLC.
** All rights reserved.
** 
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
** 
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 8 (2 files), as in `TextField.qml`:

```
/****************************************************************************************
**
** Copyright (C) 2013-2019 Jolla Ltd.
** Copyright (C) 2020 Open Mobile Platform LLC.
**
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 9 (2 files), as in `Background/KeyboardBackground.qml`:

```
/****************************************************************************************
**
** Copyright (C) 2015-2016 Jolla Ltd.
** Copyright (c) 2020 Open Mobile Platform LLC.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 10 (2 files), as in `private/DismissButton.qml`:

```
/****************************************************************************************
**
** Copyright (C) 2018 Jolla Ltd.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 11 (1 files), as in `Button.qml`:

```
/****************************************************************************************
**
** Copyright (c) 2020 Open Mobile Platform LLC.
** Copyright (C) 2013 Jolla Ltd.
** All rights reserved.
** 
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
** 
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 12 (1 files), as in `ValueButton.qml`:

```
/****************************************************************************************
**
** Copyright (C) 2013 - 2019 Jolla Ltd.
** Copyright (c) 2020 Open Mobile Platform LLC.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 13 (1 files), as in `LinkedLabel.qml`:

```
/****************************************************************************************
**
** Copyright (C) 2013-2016 Jolla Ltd.
**          Joona Petrell <joona.petrell@jollamobile.com>
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 14 (1 files), as in `PageStack.js`:

```
/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** Contact: Joona Petrell <joona.petrell@jollamobile.com>
** All rights reserved.
** 
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
** 
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 15 (1 files), as in `FullscreenContentPage.qml`:

```
/****************************************************************************************
**
** Copyright (c) 2018-2020 Jolla Ltd.
** Copyright (c) 2020 Open Mobile Platform LLC.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 16 (1 files), as in `private/BannerBackground.qml`:

```
/****************************************************************************************
**
** Copyright (c) 2020 Open Mobile Platform LLC.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 17 (1 files), as in `private/RemorseItem.js`:

```
/****************************************************************************************
**
** Copyright (c) 2021 Open Mobile Platform LLC.
** Copyright (C) 2013 Jolla Ltd.
** All rights reserved.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

Variant 18 (1 files), as in `private/ComboBoxController.qml`:

```
/****************************************************************************************
**
** Copyright (c) 2013 - 2019 Jolla Ltd.
** Copyright (c) 2019 - 2020 Open Mobile Platform LLC.
**
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/
```

### Files

Columns: the Keel port; port kind (verbatim, or modified with the edits marked
"Modified by Shipwright for Qt 6"); header variant; types from `Sailfish.Silica.private`
(native types, Keel's stand-ins for non-BSD files, and Silica's own private BSD QML);
other non-BSD Silica types (Keel's clean-room C++ or QML); the Qt 5 to Qt 6 edits.

| Upstream file | Keel file | Port | Header | Private module types | Other non-BSD types | Qt 6 edits |
| --- | --- | --- | --- | --- | --- | --- |
| `AddAnimation.qml` | `qml/AddAnimation.qml` | verbatim | 1 | - | - | - |
| `ApplicationWindow.qml` | - | not ported | 2 | CoverLoader.js | Cover (Keel QML), Screen (C++), Theme (C++), TouchBlocker (Keel QML) | - |
| `BackgroundItem.qml` | `qml/BackgroundItem.qml` | modified | 1 | DragFilter (private C++), SilicaMouseArea (private C++) | Screen (C++), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6); compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `BusyIndicator.qml` | `qml/BusyIndicator.qml` | verbatim | 1 | - | SilicaItem (Keel QML) | - |
| `BusyLabel.qml` | `qml/BusyLabel.qml` | modified | 1 | Util.js | Screen (C++), Theme (C++) | `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `Button.qml` | `qml/Button.qml` | modified | 11 | ButtonBorderColors, DragFilter (private C++), SilicaMouseArea (private C++) | Theme (C++) | the background's vertical margins are updated after height changes settle (Qt 6 reports a binding loop for a binding that reads both height and implicitHeight); signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `ColorPicker.qml` | `qml/ColorPicker.qml` | verbatim | 1 | - | Theme (C++) | - |
| `ColorPickerDialog.qml` | `qml/ColorPickerDialog.qml` | verbatim | 1 | - | Theme (C++) | - |
| `ColorPickerPage.qml` | `qml/ColorPickerPage.qml` | verbatim | 1 | - | Theme (C++) | - |
| `ColumnView.qml` | `qml/ColumnView.qml` | modified | 1 | Util.js | Screen (C++) | `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `ComboBox.qml` | `qml/ComboBox.qml` | modified | 1 | ComboBoxController | - | directory imports ("private", "..") import the module by name |
| `ContextMenu.qml` | `qml/ContextMenu.qml` | modified | 1 | InverseMouseArea (private C++), SilicaMouseArea (private C++), VerticalAutoScroll (private C++), Util.js, RemorseItem.js | Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (5 places); directory imports ("private", "..") import the module by name; the inline GLSL is a compiled Qt 6 shader (qml/shaders/opaque.frag); no layer on the software scene graph, where the window around the menu's item is shaded instead of dimmed |
| `CoverBackground.qml` | `qml/CoverBackground.qml` | verbatim | 1 | - | Cover (Keel QML), Theme (C++) | - |
| `CoverLoader.js` | - | not ported | 1 | - | - | - |
| `CoverPlaceholder.qml` | `qml/CoverPlaceholder.qml` | modified | 1 | Util.js | Cover (Keel QML), Screen (C++), SilicaItem (Keel QML), Theme (C++) | `icon.source` set by the app resolves against the app's file (Qt 6 resolves it against this one); `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `DatePicker.qml` | `qml/DatePicker.qml` | modified | 1 | DateGrid, DatePicker.js | Screen (C++), SilicaControl (Keel QML), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (4 places; Qt Quick's attached Screen shadows Silica's in Qt 6); the day delegate's colour tolerates a null `model` or `datePicker` (Qt 6 re-evaluates it while the delegate is destroyed) |
| `DatePickerDialog.qml` | `qml/DatePickerDialog.qml` | modified | 1 | YearMonthMenu | Format (C++), Screen (C++), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (2 places); directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `DetailItem.qml` | `qml/DetailItem.qml` | modified | 6 | - | SilicaItem (Keel QML), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); the label's colour qualified with the id |
| `Dialog.qml` | `qml/Dialog.qml` | modified | 1 | - | - | compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `DialogHeader.qml` | `qml/DialogHeader.qml` | modified | 1 | Util.js | Screen (C++), Theme (C++) | reads of pageStack._pageStackIndicator go through _keelIndicator (null until the indicator exists, or without a page stack); `dialog` is bound to _findDialog() so that bindings do not read null at creation; directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (4 places; Qt Quick's attached Screen shadows Silica's in Qt 6); compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `DockedPanel.qml` | `qml/DockedPanel.qml` | modified | 1 | InverseMouseArea (private C++) | Theme (C++) | imports Sailfish.Silica.private for InverseMouseArea, which Keel's Sailfish.Silica qmldir does not export; the inline GLSL is a compiled Qt 6 shader (qml/shaders/opaque.frag); no layer on the software scene graph |
| `Drawer.qml` | `qml/Drawer.qml` | modified | 1 | - | SilicaItem (Keel QML), Theme (C++) | children go to the foreground through `_foregroundData` (upstream: `data`, which shadows Item.data) |
| `ExpandingSection.qml` | `qml/ExpandingSection.qml` | modified | 1 | Util.js | Theme (C++) | directory imports ("private", "..") import the module by name |
| `ExpandingSectionGroup.qml` | `qml/ExpandingSectionGroup.qml` | modified | 1 | Util.js | Screen (C++), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `FadeAnimation.qml` | `qml/FadeAnimation.qml` | verbatim | 1 | - | - | - |
| `FadeAnimator.qml` | `qml/FadeAnimator.qml` | verbatim | 1 | - | - | - |
| `FirstTimeUseCounter.qml` | `qml/FirstTimeUseCounter.qml` | verbatim | 1 | Config (private C++) | - | - |
| `FullscreenContentPage.qml` | `qml/FullscreenContentPage.qml` | modified | 12 | - | Theme (C++) | directory imports ("private", "..") import the module by name |
| `GridItem.qml` | `qml/GridItem.qml` | modified | 1 | ViewItem, Util.js | Screen (C++), Theme (C++) | directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (3 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `HighlightBar.qml` | `qml/HighlightBar.qml` | modified | 1 | - | Theme (C++) | optional modules (QtFeedback, Nemo.Ngf, Nemo.Configuration) may be missing: their objects are made by Util._keelOptionalObject() (C++, one compiled component per engine), which returns null when they are; signal handlers in Connections written as functions, and handlers that use signal parameters declare them (3 places); compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `HighlightImage.qml` | `qml/HighlightImage.qml` | verbatim | 1 | HighlightImageBase (private Keel QML) | - | - |
| `HorizontalScrollDecorator.qml` | `qml/HorizontalScrollDecorator.qml` | modified | 1 | Util.js | Theme (C++) | `flickable` is bound to the nearest flickable so that bindings do not read null at creation |
| `Icon.qml` | `qml/Icon.qml` | verbatim | 1 | - | - | - |
| `IconButton.qml` | `qml/IconButton.qml` | modified | 1 | - | Theme (C++) | directory imports ("private", "..") import the module by name |
| `IconComboBox.qml` | `qml/IconComboBox.qml` | modified | 7 | - | Theme (C++) | directory imports ("private", "..") import the module by name |
| `IconMenuItem.qml` | `qml/IconMenuItem.qml` | verbatim | 7 | - | Theme (C++) | - |
| `IconTextSwitch.qml` | `qml/IconTextSwitch.qml` | modified | 1 | - | Theme (C++) | directory imports ("private", "..") import the module by name |
| `InfoLabel.qml` | `qml/InfoLabel.qml` | verbatim | 1 | - | Theme (C++) | - |
| `InteractionHintLabel.qml` | `qml/InteractionHintLabel.qml` | modified | 1 | - | Theme (C++) | `palette` is a read-only property for the label's palette (upstream: an alias, which cannot be marked override) |
| `Keypad.qml` | `qml/Keypad.qml` | modified | 1 | KeypadButton | Screen (C++), SilicaControl (Keel QML), Theme (C++) | optional modules (QtFeedback, Nemo.Ngf, Nemo.Configuration) may be missing: their objects are made by Util._keelOptionalObject() (C++, one compiled component per engine), which returns null when they are; directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `Label.qml` | `qml/Label.qml` | modified | 1 | - | Screen (C++), Theme (C++) | `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6); no fade layer on the software scene graph (it runs no shaders); the text is elided there instead, and laid out again when it grows; compiled to C++ by qmlcachegen: names qualified with their object's id, `pragma ComponentBehavior: Bound` (its inner components are made only in this file), functions typed `var` (unchanged behaviour) |
| `LinkedLabel.qml` | `qml/LinkedLabel.qml` | modified | 13 | LinkParser (private Rust (CXX-Qt)), SilicaText (private C++) | Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places) |
| `ListItem.qml` | `qml/ListItem.qml` | modified | 1 | ViewItem | - | directory imports ("private", "..") import the module by name; compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `MenuItem.qml` | `qml/MenuItem.qml` | modified | 1 | - | Screen (C++), Theme (C++) | `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6); compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `MenuLabel.qml` | `qml/MenuLabel.qml` | modified | 1 | - | Screen (C++), SilicaItem (Keel QML), Theme (C++) | `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `MiniComboBox.qml` | `qml/MiniComboBox.qml` | modified | 1 | ComboBoxController, Util.js | Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); directory imports ("private", "..") import the module by name |
| `NestedGridView.qml` | `qml/NestedGridView.qml` | modified | 1 | Util.js | Screen (C++) | `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `OpacityRampEffect.qml` | `qml/OpacityRampEffect.qml` | modified | 1 | - | - | no effect on the software scene graph (it runs no shaders): the source is shown unfaded there |
| `OpacityRampEffectBase.qml` | `qml/OpacityRampEffectBase.qml` | modified | 3 | - | - | the inline GLSL is compiled Qt 6 shaders (qml/shaders/opacityramp.*) |
| `Page.qml` | `qml/Page.qml` | modified | 2 | - | Screen (C++), Theme (C++) | `Screen.` qualified as `KeelSilica.Screen.` (3 places; Qt Quick's attached Screen shadows Silica's in Qt 6); compiled to C++ by qmlcachegen: names qualified with their object's id, `pragma ComponentBehavior: Bound` (its inner components are made only in this file), functions typed `var` (unchanged behaviour) |
| `PageBusyIndicator.qml` | `qml/PageBusyIndicator.qml` | modified | 1 | Util.js | Screen (C++) | `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `PageHeader.qml` | `qml/PageHeader.qml` | modified | 1 | Util.js | Screen (C++), SilicaControl (Keel QML), Theme (C++) | the description's wrapMode binding is set after createObject(); imports Sailfish.Silica.private for PageHeaderDescription, PageHeaderMouseArea, which Keel's Sailfish.Silica qmldir does not export; `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6); compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `PageStack.js` | `qml/PageStack.js` | verbatim | 14 | - | - | - |
| `PageStack.qml` | `qml/PageStack.qml` | modified | 2 | PageEdgeTransition, PageStackBase (private Keel QML), PageStack.js | Screen (C++), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (4 places; Qt Quick's attached Screen shadows Silica's in Qt 6); on headless platforms (offscreen, minimal) animated operations complete at once unless KEEL_PAGE_TRANSITIONS=1; compiled to C++ by qmlcachegen: names qualified with their object's id, `pragma ComponentBehavior: Bound` (the inner components are made only here), functions typed `var` (unchanged behaviour) |
| `PanelBackground.qml` | `qml/PanelBackground.qml` | verbatim | 1 | - | SilicaItem (Keel QML), Theme (C++) | - |
| `PasswordField.qml` | `qml/PasswordField.qml` | modified | 3 | - | Screen (C++), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `ProgressBar.qml` | `qml/ProgressBar.qml` | modified | 1 | GlassItem (private C++) | Screen (C++), SilicaItem (Keel QML), Theme (C++) | `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `ProgressCircle.qml` | `qml/ProgressCircle.qml` | verbatim | 1 | - | - | - |
| `ProgressCircleBase.qml` | `qml/ProgressCircleBase.qml` | modified | 1 | - | SilicaItem (Keel QML), Theme (C++) | the inline GLSL is compiled Qt 6 shaders (qml/shaders/progresscircle.*) |
| `PullDownMenu.qml` | `qml/PullDownMenu.qml` | modified | 1 | PulleyMenuBase, Util.js | Screen (C++), Theme (C++) | geometry bindings guarded while `flickable` is still null (set in Component.onCompleted), which warned at creation; directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6); compiled to C++ by qmlcachegen: names qualified with their object's id, `pragma ComponentBehavior: Bound` (its inner components are made only in this file), functions typed `var` (unchanged behaviour) |
| `PulleyAnimationHint.qml` | `qml/PulleyAnimationHint.qml` | verbatim | 1 | Util.js | Theme (C++) | - |
| `PushUpMenu.qml` | `qml/PushUpMenu.qml` | modified | 1 | PulleyMenuBase, Util.js | Theme (C++) | geometry bindings guarded while `flickable` is still null (set in Component.onCompleted), which warned at creation; directory imports ("private", "..") import the module by name |
| `Remorse.qml` | `qml/Remorse.qml` | verbatim | 6 | - | - | - |
| `RemorseItem.qml` | `qml/RemorseItem.qml` | modified | 4 | RemorseBase, RemorsePopup.js, RemorseItem.js, Util.js | Screen (C++), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `RemorsePopup.qml` | `qml/RemorsePopup.qml` | modified | 4 | RemorseBase, RemorsePopup.js, Util.js | Screen (C++), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (7 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `RemoveAnimation.qml` | `qml/RemoveAnimation.qml` | verbatim | 1 | - | - | - |
| `ScrollDecorator.qml` | `qml/ScrollDecorator.qml` | modified | 1 | - | - | unless `flickable` is set, the decorators get the nearest flickable from the start (null warned at creation) |
| `SearchField.qml` | `qml/SearchField.qml` | verbatim | 1 | - | Theme (C++) | - |
| `SecondaryButton.qml` | `qml/SecondaryButton.qml` | verbatim | 1 | - | Theme (C++) | - |
| `SectionHeader.qml` | `qml/SectionHeader.qml` | modified | 1 | - | Screen (C++), Theme (C++) | `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `Separator.qml` | `qml/Separator.qml` | verbatim | 1 | Underline (private Keel QML) | Theme (C++) | - |
| `SilicaFlickable.qml` | `qml/SilicaFlickable.qml` | modified | 1 | BoundsBehavior, QuickScroll, FastScrollAnimation.js | Theme (C++) | directory imports ("private", "..") import the module by name; compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `SilicaGridView.qml` | `qml/SilicaGridView.qml` | modified | 1 | BoundsBehavior, QuickScroll, FastScrollAnimation.js | Theme (C++) | directory imports ("private", "..") import the module by name |
| `SilicaListView.qml` | `qml/SilicaListView.qml` | modified | 1 | BoundsBehavior, QuickScroll, FastScrollAnimation.js | Theme (C++) | directory imports ("private", "..") import the module by name; without a highlight component, the highlight moves and resizes at once (Qt 6 animates an invisible highlight item) |
| `Slider.qml` | `qml/Slider.qml` | verbatim | 1 | GlassItem (private C++), SliderBase | Theme (C++) | - |
| `SlideshowView.qml` | `qml/SlideshowView.qml` | modified | 1 | - | Screen (C++), Theme (C++) | `Screen.` qualified as `KeelSilica.Screen.` (3 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `Switch.qml` | `qml/Switch.qml` | modified | 1 | DragFilter (private C++), GlassItem (private C++), SilicaMouseArea (private C++) | Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); directory imports ("private", "..") import the module by name; compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `TapInteractionHint.qml` | `qml/TapInteractionHint.qml` | verbatim | 1 | - | - | - |
| `TextArea.qml` | `qml/TextArea.qml` | modified | 1 | Cursor, PreeditText (private C++), TextBase | Theme (C++) | directory imports ("private", "..") import the module by name |
| `TextField.qml` | `qml/TextField.qml` | modified | 8 | Cursor, PreeditText (private C++), ProxyValidator (private C++), TextBase | Theme (C++) | directory imports ("private", "..") import the module by name; the single-line width binds to an implicit width updated after the change (binding loop in password fields); compiled to C++ by qmlcachegen: names qualified with their object's id, `pragma ComponentBehavior: Bound` (its inner components are made only in this file), functions typed `var` (unchanged behaviour) |
| `TextSwitch.qml` | `qml/TextSwitch.qml` | modified | 1 | DragFilter (private C++), GlassItem (private C++), SilicaMouseArea (private C++) | Screen (C++), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6); compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `TimePicker.qml` | `qml/TimePicker.qml` | modified | 1 | TimePickerGlassItem (private Keel QML), TimePickerMode (private C++) | Format (C++), Formatter (C++), Screen (C++), SilicaItem (Keel QML), Theme (C++) | directory imports ("private", "..") import the module by name; `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6); the inline GLSL is a compiled Qt 6 shader (qml/shaders/timepickerring.frag) |
| `TimePickerDialog.qml` | `qml/TimePickerDialog.qml` | modified | 1 | ClockItem (private Keel QML) | Theme (C++) | directory imports ("private", "..") import the module by name |
| `TouchInteractionHint.qml` | `qml/TouchInteractionHint.qml` | modified | 1 | HintReferenceCounter.js | Screen (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); `Screen.` qualified as `KeelSilica.Screen.` (6 places; Qt Quick's attached Screen shadows Silica's in Qt 6); the first PauseAnimation's duration is set only while the group is stopped (_startGroup), not bound to _interrupted, which the group's own ScriptActions change while it runs (Qt 6.4 crashed in QAnimationGroupJob::ungroupChild) |
| `ValueButton.qml` | `qml/ValueButton.qml` | verbatim | 15 | - | Theme (C++) | - |
| `VerticalScrollDecorator.qml` | `qml/VerticalScrollDecorator.qml` | modified | 1 | VerticalScrollBase | Theme (C++) | directory imports ("private", "..") import the module by name |
| `ViewPlaceholder.qml` | `qml/ViewPlaceholder.qml` | verbatim | 1 | Util.js | SilicaItem (Keel QML), Theme (C++) | - |
| `Background/CommonKeyboardMaterials.qml` | - | not ported | 9 | - | Screen (C++) | - |
| `Background/KeyboardBackground.qml` | - | not ported | 9 | - | Theme (C++) | - |
| `Background/KeyboardMaterials.qml` | - | not ported | 5 | - | - | - |
| `Background/PlatformKeyboardMaterials.qml` | - | not ported | 5 | - | - | - |
| `private/AutoScrollController.qml` | `qml/private/AutoScrollController.qml` | modified | 1 | - | - | imports Sailfish.Silica.private for the module's native types |
| `private/BannerBackground.qml` | `qml/private/BannerBackground.qml` | modified | 16 | - | ColorBackground (Background Keel QML), Corners (Background Keel QML), Theme (C++) | imports Sailfish.Silica.private for the module's native types |
| `private/BoundsBehavior.qml` | `qml/private/BoundsBehavior.qml` | modified | 1 | BounceEffect (private C++) | Theme (C++) | imports Sailfish.Silica.private for the module's native types |
| `private/ButtonBorderColors.qml` | `qml/private/ButtonBorderColors.qml` | modified | 1 | - | - | imports Sailfish.Silica.private for the module's native types |
| `private/ComboBoxController.qml` | `qml/private/ComboBoxController.qml` | modified | 17 | Util.js | Screen (C++), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (3 places); imports Sailfish.Silica.private for the module's native types; `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `private/Cursor.qml` | `qml/private/Cursor.qml` | modified | 1 | - | Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (3 places); imports Sailfish.Silica.private for the module's native types |
| `private/DateGrid.qml` | `qml/private/DateGrid.qml` | verbatim | 1 | DatePicker.js | Format (C++), SilicaControl (Keel QML), Theme (C++) | - |
| `private/DatePicker.js` | `qml/private/DatePicker.js` | verbatim | 1 | - | - | - |
| `private/DefaultCover.qml` | `qml/private/DefaultCover.qml` | modified | 1 | - | - | imports Sailfish.Silica.private for the module's native types |
| `private/DismissAnimation.qml` | `qml/private/DismissAnimation.qml` | modified | 10 | - | Theme (C++) | imports Sailfish.Silica.private for the module's native types |
| `private/DismissButton.qml` | `qml/private/DismissButton.qml` | modified | 10 | - | Theme (C++) | imports Sailfish.Silica.private for the module's native types |
| `private/FastScrollAnimation.js` | `qml/private/FastScrollAnimation.js` | verbatim | 1 | - | - | - |
| `private/FastScrollAnimation.qml` | `qml/private/FastScrollAnimation.qml` | modified | 1 | QuickScroll | Screen (C++) | imports Sailfish.Silica.private for the module's native types; `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `private/FramerateMonitor.qml` | `qml/private/FramerateMonitor.qml` | modified | 1 | - | Theme (C++) | imports Sailfish.Silica.private for the module's native types |
| `private/HintReferenceCounter.js` | `qml/private/HintReferenceCounter.js` | verbatim | 1 | - | - | - |
| `private/KeypadButton.qml` | `qml/private/KeypadButton.qml` | modified | 1 | - | Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (2 places) |
| `private/NoticeItem.qml` | `qml/private/NoticeItem.qml` | modified | 5 | - | ApplicationWindow (Keel QML), Screen (C++), SilicaControl (Keel QML), Theme (C++) | imports Sailfish.Silica.private for the module's native types; `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6); the landscape cutout margin tests Orientation.LandscapeMask (upstream read LandscapeMask from the int `orientation`, which is undefined, so the margin never applied) |
| `private/OverlayGradient.qml` | `qml/private/OverlayGradient.qml` | modified | 1 | - | Theme (C++) | imports Sailfish.Silica.private for the module's native types |
| `private/PageEdgeTransition.qml` | `qml/private/PageEdgeTransition.qml` | modified | 1 | - | SilicaItem (Keel QML), Theme (C++) | imports Sailfish.Silica.private for the module's native types; compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `private/PageHeaderDescription.qml` | `qml/private/PageHeaderDescription.qml` | modified | 1 | - | Theme (C++) | imports Sailfish.Silica.private for the module's native types |
| `private/PageHeaderMouseArea.qml` | `qml/private/PageHeaderMouseArea.qml` | modified | 1 | - | Theme (C++) | imports Sailfish.Silica.private for the module's native types |
| `private/PageOrientationTransition.qml` | `qml/private/PageOrientationTransition.qml` | modified | 2 | - | - | imports Sailfish.Silica.private for the module's native types |
| `private/PageStackGlassIndicator.qml` | `qml/private/PageStackGlassIndicator.qml` | modified | 1 | GlassItem (private C++) | Theme (C++) | imports Sailfish.Silica.private for the module's native types |
| `private/PageStackIndicator.qml` | `qml/private/PageStackIndicator.qml` | modified | 1 | PageStackGlassIndicator | SilicaItem (Keel QML), Theme (C++) | imports Sailfish.Silica.private for the module's native types; directory imports ("private", "..") import the module by name; compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `private/PulleyMenuBase.qml` | `qml/private/PulleyMenuBase.qml` | modified | 1 | InverseMouseArea (private C++), PulleyMenuLogic (private C++), SilicaMouseArea (private C++), Util.js | Screen (C++), Theme (C++) | geometry bindings guarded while `flickable` is still null (set in Component.onCompleted), which warned at creation; optional modules (QtFeedback, Nemo.Ngf, Nemo.Configuration) may be missing: their objects are made by Util._keelOptionalObject() (C++, one compiled component per engine), which returns null when they are; signal handlers in Connections written as functions, and handlers that use signal parameters declare them (11 places); `Screen.` qualified as `KeelSilica.Screen.` (9 places; Qt Quick's attached Screen shadows Silica's in Qt 6); the inline GLSL is a compiled Qt 6 shader (qml/shaders/pulley.frag); no layer on the software scene graph; compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `private/QuickScroll.qml` | `qml/private/QuickScroll.qml` | modified | 1 | QuickScrollArea, QuickScrollDirection (private C++) | Screen (C++) | `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6); an incubation still running when the item is destroyed is completed first (Qt 6 raises a ReferenceError when its status callback reads the destroyed item's properties); compiled to C++ by qmlcachegen: names qualified with their object's id, `pragma ComponentBehavior: Bound` (its inner components are made only in this file), functions typed `var` (unchanged behaviour) |
| `private/QuickScrollArea.qml` | `qml/private/QuickScrollArea.qml` | modified | 1 | QuickScrollButton, QuickScrollDirection (private C++) | Screen (C++), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `private/QuickScrollButton.qml` | `qml/private/QuickScrollButton.qml` | verbatim | 1 | QuickScrollButtonBase (private Keel QML), QuickScrollDirection (private C++) | Theme (C++) | - |
| `private/RemorseBase.qml` | `qml/private/RemorseBase.qml` | modified | 4 | BannerBackground, SwipeItem | ColorBackground (Background Keel QML), Corners (Background Keel QML), Screen (C++), Theme (C++) | `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6); `signal canceled` removed, MouseArea's is used (a redeclared superclass signal is an invalid override in Qt 6) |
| `private/RemorseItem.js` | `qml/private/RemorseItem.js` | verbatim | 18 | - | - | - |
| `private/RemorsePopup.js` | `qml/private/RemorsePopup.js` | verbatim | 1 | - | - | - |
| `private/ReturnToHomeHint.qml` | `qml/private/ReturnToHomeHint.qml` | modified | 1 | HintReferenceCounter.js | Screen (C++) | imports Sailfish.Silica.private for the module's native types; `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `private/ReturnToHomeHintCounter.qml` | `qml/private/ReturnToHomeHintCounter.qml` | modified | 1 | - | - | optional modules (QtFeedback, Nemo.Ngf, Nemo.Configuration) loaded with Qt.createQmlObject() may be missing; failures are caught; imports Sailfish.Silica.private for the module's native types |
| `private/Scrollbar.qml` | `qml/private/Scrollbar.qml` | modified | 1 | VerticalScrollBase | ColorBackground (Background Keel QML), Corners (Background Keel QML), Theme (C++) | signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); imports Sailfish.Silica.private for the module's native types |
| `private/SliderBase.qml` | `qml/private/SliderBase.qml` | modified | 1 | DragFilter (private C++), SilicaMouseArea (private C++) | Screen (C++), Theme (C++) | _backgroundTopPadding tests _valueLabel by truthiness; _extraPadding is updated after height changes settle (binding loop under Qt 6); signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); `Screen.` qualified as `KeelSilica.Screen.` (2 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `private/SliderValueLabel.qml` | `qml/private/SliderValueLabel.qml` | modified | 1 | - | Theme (C++) | imports Sailfish.Silica.private for the module's native types |
| `private/SwipeItem.qml` | `qml/private/SwipeItem.qml` | verbatim | 4 | DismissAnimation, GestureHintAnimation (private Keel QML) | - | - |
| `private/TabBar.qml` | `qml/private/TabBar.qml` | modified | 1 | TabButton, Util.js | Screen (C++), SilicaControl (Keel QML), Theme (C++) | optional modules (QtFeedback, Nemo.Ngf, Nemo.Configuration) may be missing: their objects are made by Util._keelOptionalObject() (C++, one compiled component per engine), which returns null when they are; `Screen.` qualified as `KeelSilica.Screen.` (4 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |
| `private/TabButton.qml` | `qml/private/TabButton.qml` | verbatim | 1 | SilicaMouseArea (private C++), VariantInterpolator (private Keel QML), Util.js | Theme (C++) | - |
| `private/TabItem.qml` | `qml/private/TabItem.qml` | modified | 1 | Util.js | SilicaControl (Keel QML) | imports Sailfish.Silica.private for the module's native types |
| `private/TabView.qml` | `qml/private/TabView.qml` | modified | 3 | AnimatedLoader (private C++), BackgroundRectangle (private Keel QML), Util.js | Theme (C++) | onInitializeItem declares its signal parameter |
| `private/TextBase.qml` | `qml/private/TextBase.qml` | modified | 8 | HorizontalAutoScroll (private C++), InverseMouseArea (private C++), TextBaseExtensionContainer, TextBaseItem (private Keel QML), TextEditorLabel (private Keel QML), VerticalAutoScroll (private C++), Util.js | Screen (C++), TextEditor (Keel QML), Theme (C++) | optional modules (QtFeedback, Nemo.Ngf, Nemo.Configuration) may be missing: their objects are made by Util._keelOptionalObject() (C++, one compiled component per engine), which returns null when they are; signal handlers in Connections written as functions, and handlers that use signal parameters declare them (3 places); `Screen.` qualified as `KeelSilica.Screen.` (3 places; Qt Quick's attached Screen shadows Silica's in Qt 6); the editor regaining active focus stops focusLossTimer, so a loss and refocus within its 1 ms interval no longer clears focus a moment later (lost keystrokes); compiled to C++ by qmlcachegen: names qualified with their object's id, `pragma ComponentBehavior: Bound` (its inner components are made only in this file), functions typed `var` (unchanged behaviour) |
| `private/TextBaseExtensionContainer.qml` | `qml/private/TextBaseExtensionContainer.qml` | modified | 3 | - | - | imports Sailfish.Silica.private for the module's native types |
| `private/Util.js` | `qml/private/Util.js` | verbatim | 1 | - | - | - |
| `private/VerticalScrollBase.qml` | `qml/private/VerticalScrollBase.qml` | modified | 1 | Util.js | Screen (C++), SilicaItem (Keel QML) | `flickable` is bound to the nearest flickable so that bindings do not read null at creation; signal handlers in Connections written as functions, and handlers that use signal parameters declare them (1 places); imports Sailfish.Silica.private for the module's native types; `Screen.` qualified as `KeelSilica.Screen.` (6 places; Qt Quick's attached Screen shadows Silica's in Qt 6); compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `private/ViewItem.qml` | `qml/private/ViewItem.qml` | modified | 1 | - | Theme (C++) | imports Sailfish.Silica.private for the module's native types; compiled to C++ by qmlcachegen: names qualified with their object's id, functions typed `var` (unchanged behaviour) |
| `private/VirtualKeyboardObserver.qml` | `qml/private/VirtualKeyboardObserver.qml` | modified | 1 | - | - | imports Sailfish.Silica.private for the module's native types |
| `private/YearMonthMenu.qml` | `qml/private/YearMonthMenu.qml` | modified | 1 | - | Format (C++), Screen (C++), Theme (C++) | imports Sailfish.Silica.private for the module's native types; `Screen.` qualified as `KeelSilica.Screen.` (1 places; Qt Quick's attached Screen shadows Silica's in Qt 6) |

## Native types (clean-room)

API names only, inferred from how Silica's BSD QML (and the public Silica
documentation) uses them; implementations are Keel's own. Each file's header
says where its names come from.

| Type | Module | Implementation | API names from |
| --- | --- | --- | --- |
| `AnimatedLoader` | private | C++ `plugin/cpp/private/animatedloader.*` | BSD PageStack.qml, TabView.qml, ApplicationWindow.qml |
| `BounceEffect` | private | C++ `plugin/cpp/private/pulleymenulogic.*` | BSD private/BoundsBehavior.qml |
| `Config` (singleton) | private | C++ `plugin/cpp/private/misc.*` | BSD QML (`desktop`, `wayland`, `layoutGrid`, `demoMode`); `_keelImmediatePageTransitions` is Keel's |
| `DragFilter` (attached) | private | C++ `plugin/cpp/private/dragfilter.*` | BSD BackgroundItem, Button, Switch, TextSwitch, SliderBase |
| `GlassItem` | private | C++ `plugin/cpp/private/glassitem.*` (QPainter) | BSD Switch, TextSwitch, ProgressBar, PageStackGlassIndicator |
| `HorizontalAutoScroll`, `VerticalAutoScroll` (attached) | private | C++ `plugin/cpp/private/textsupport.*` | BSD TextBase.qml, ContextMenu.qml |
| `InverseMouseArea` | private | C++ `plugin/cpp/private/inversemousearea.*` | BSD ContextMenu, DockedPanel, PulleyMenuBase, TextBase |
| `LinkParser` | private | Rust (CXX-Qt) `plugin/src/linkparser.rs`, `linkify.rs`; QML `qml/private/LinkParser.qml` | BSD LinkedLabel.qml |
| `PageStackGestureArea` | private (Keel's name) | C++ `plugin/cpp/private/pagestackgesture.*`, QML `qml/private/PageStackBase.qml` | BSD PageStack.qml (what it reads from its base) |
| `Palette` | private; public | C++ `plugin/cpp/private/palette.*`; public `qml/Palette.qml` derives from it | Silica documentation ("Palette QML Type"); BSD QML (`palette.*`) |
| `PagedView` | public | QML `qml/PagedView.qml` on C++ `plugin/cpp/private/pagedview.*` (`PagedViewBase`, the attached properties) | Silica documentation ("PagedView QML Type", read 2026-10-02: members, enums, attached `view`, `contentWidth`, `contentHeight`); BSD private/TabView.qml and TabItem.qml (attached `isCurrentItem`, `exposed`) |
| `PreeditText`, `ProxyValidator` | private | C++ `plugin/cpp/private/textsupport.*` | BSD TextField.qml, TextArea.qml, TextBase.qml |
| `SilicaItemBase`, `SilicaMouseArea`, `SilicaRectangle` | private (`SilicaItemBase`: Keel's name; public `SilicaItem` and `SilicaControl` derive from it) | C++ `plugin/cpp/private/silicaitems.*`: Qt Quick's Item, MouseArea and Rectangle with `highlighted` and `palette` | BSD QML (what it reads from these bases); Silica documentation (SilicaItem, SilicaControl) |
| `SilicaText` | private (Keel's name) | C++ `plugin/cpp/private/silicatext.*`, a Qt Quick `Text` with `highlighted` and `palette` | BSD Label.qml and LinkedLabel.qml (what they read from their base) |
| `PulleyMenuLogic` | private | C++ `plugin/cpp/private/pulleymenulogic.*` | BSD private/PulleyMenuBase.qml |
| `QuickScrollDirection`, `TimePickerMode` (enums) | private | C++ `plugin/cpp/private/misc.*` | BSD QuickScroll*.qml, TimePicker.qml |
| `RemorseCache` (attached) | private | C++ `plugin/cpp/private/misc.*` | BSD Remorse.qml |
| `Util` (singleton) | private | C++ `plugin/cpp/private/misc.*` | BSD QML (`asyncInvoke`, `instanceOf`, `weekNumberList`) |
| Silica translations | - | C++ `plugin/cpp/private/translator.*` | `qsTrId()` in BSD QML |
| `Screen` | public | C++ `plugin/cpp/screen.*` | Silica documentation; BSD QML (`topCutout`, corners) |
| `Format`, `Formatter` | public | C++ `plugin/cpp/format.*` | public API listing (2014) |
| `Clipboard`, `StandardPaths`, `EnterKey`, `ButtonLayout` | public | C++ `plugin/cpp/*.h` | Silica documentation |
| `Theme` | public | C++ `plugin/cpp/theme.h`, `theme.cpp`, colours from Rust `plugin/src/ambience.rs`, `config.rs`, `palette.rs` | Silica documentation; BSD QML |
| `image://theme` | public | C++ `plugin/cpp/themeimageprovider.*` | Silica documentation |
| `image://keelambience` | Keel's | C++ `plugin/cpp/ambienceimageprovider.*`: the ambience wallpaper cropped and blurred as Lipstick shows it behind apps, drawn by Keel's ApplicationWindow where no compositor does | Keel's own; blur radius and tone fitted to published screenshots (`tests/screenshots/reference/SOURCES.md`) |
| `__silica_applicationwindow_instance` defaults | - | C++ `plugin/cpp/windowdefaults.h` | what BSD QML reads from the window |

## Keel stand-ins for non-BSD Silica QML

Clean-room QML (`MIT`) with the names Silica's
BSD QML uses; Silica's own files are proprietary or native.

- Private: `BackgroundRectangle`, `ClockItem`, `Expander` (as
  sailfish-components-webview's context menu uses it), `GestureHintAnimation`,
  `GridItemRemorseContainer`, `HighlightImageBase`, `OverlayGradientBase`,
  `PageStackBase`, `QuickScrollButtonBase`, `TextBaseItem`, `TextEditorLabel`,
  `TimePickerGlassItem`, `Underline`, `VariantInterpolator`,
  `WindowBackground` (`qml/private/`).
- `Sailfish.Silica.Background`: `ColorBackground`, `Corners`
  (`background/`; Silica's Background module QML is proprietary).
- Look values measured from published Sailfish OS 4/5 screenshots and the
  colour values of Jolla's stock `.ambience` files (Theme font sizes and
  families, page margin, button widths, secondary and highlight background
  colours, the GlassItem glow and dither, the blurred ambience background):
  facts only, listed with their sources in
  `tests/screenshots/reference/SOURCES.md`; no image, code or asset of
  Jolla's is copied. Keel's default ambiences ("Harbour", dark and light) and
  its glass dither tile (`ambience/`) are Keel's own artwork, generated by
  `ambience/make-ambience.py`.
- Public: `ApplicationWindow`, `Cover`, `CoverAction`, `CoverActionList`,
  `SilicaItem`, `SilicaControl`, `Theme`, `TouchBlocker`, `TextEditor` and
  the enum holders (`BusyIndicatorSize`, `CutoutMode`, `DateTime`,
  `DialogResult`, `DialogStatus`, `Dock`, `FocusBehavior`, `OpacityRamp`,
  `Orientation`, `PageNavigation`, `PageStackAction`, `PageStatus`,
  `TouchInteraction`, `TruncationMode`), from the public documentation; enum
  values are Keel's unless the public API listing gives them.
- `SilicaWebView` (`qml/SilicaWebView.qml`, `qml/private/WebKitExperimental.qml`):
  Silica dropped it from its current documentation (it was QtWebKit's
  WebView with Silica's pulley menus, quick scroll and header). Names from
  the 2014 BSD `SilicaWebView.qml` of the historical mirror (read for its
  member names only: `quickScroll`, `quickScrollEnabled`, `pullDownMenu`,
  `pushUpMenu`, `pulleyMenuActive`, `overridePageStackNavigation`,
  `header`, `_headerItem`, `_page`, `_cookiesEnabled`, `scrollToTop`,
  `scrollToBottom`, the `disableNavigation` state) and from Qt 5's public
  QtWebKit 3.0 documentation (WebView's properties, methods, signals and
  enums, and the experimental members apps used); no code of either. It
  runs on Keel's Sailfish.WebView (made at run time, so Silica does not
  depend on it).
- `Notice` and the `Notices` singleton (`qml/Notice.qml`, `qml/Notices.qml`):
  members from the public documentation (`Notices.show(text, duration,
  anchor, horizontalOffset, verticalOffset)`; Notice's `text`, `duration`
  with `Short`/`Long`, `anchor` flags, offsets), plus the two names Silica's
  BSD `private/NoticeItem.qml` and `ApplicationWindow.qml` use from the
  native singleton (`_dismissCurrent()`; Keel's `_current` stands for
  `_currentNotice`). Durations (3 s, 5 s) and anchor values are Keel's.
  Notices show one at a time as Silica's own `NoticeItem` in Keel's
  ApplicationWindow's indicator layer (Silica's window loads it in a fading
  loader above its bottom panels; Keel shows it without the fade).
- `Sailfish.Share`: `share/ShareAction.qml` and `share/keelshare.*`
  (`ShareProvider`, `ShareResource`, Keel's `KeelShareService`). Names and
  members from the public documentation (declarative-transferengine:
  ShareAction, ShareProvider and its desktop entry keys) and the Qt 5
  module's `plugins.qmltypes` (ShareAction's `selectedTransferMethodInfo`,
  `done`, `toConfiguration`, `loadConfiguration`; ShareResource's
  `ResourceType` values `StringDataType` = 1, `FilePathType` = 2). The D-Bus
  contract from the BSD-licensed `sailfishshare-components` 1.1.14 package
  of Sailfish OS 5.2 (its source repository is not public; the package's
  QML, D-Bus service file and module type information were read, and the
  plugin's exported symbols and strings were inspected only for the call it
  makes): `ShareAction.trigger()` sends its `toConfiguration()` map to
  `org.sailfishos.share.share(a{sv})` on path `/` of the session bus, where
  the out-of-process system share dialog (`/usr/libexec/sailfish-share`,
  Qt 5) listens; the dialog's app share method calls
  `org.sailfishos.share.share(a{sv})` on the receiving app's
  `/share/<method>` object (under its Sailjail name, as the Sailfish forum
  describes). No code of the package is used; Keel's implementation is its
  own.

Not used, ever: QML/JS files without an open licence header, the proprietary
Silica C++ plugin (`libsailfishsilicaplugin.so` and its sources),
`plugins.qmltypes`, `qmldir`, any binary.
