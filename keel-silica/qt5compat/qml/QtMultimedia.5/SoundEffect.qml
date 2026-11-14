// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 SoundEffect (QtMultimedia 5.x) is Qt 6's SoundEffect plus `category`,
// which Qt 6 dropped (accepted, ignored). The enums (SoundEffect.Infinite,
// SoundEffect.Ready, ...) come from the Qt 6 type.
import QtMultimedia 6.0 as QM

QM.SoundEffect {
    property string category: ""
}
