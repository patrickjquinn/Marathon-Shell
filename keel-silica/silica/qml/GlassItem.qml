// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// GlassItem: Silica's glowing indicator (switches, current-item marks).
// Silica exports it from Sailfish.Silica as well as from its private module,
// and apps use it directly (communi's panel and buffer marks, in the
// corpus). Keel's native implementation lives in the private module
// (plugin/cpp/private/glassitem.h); this makes the same type public.
import Sailfish.Silica.private 1.0 as Private

Private.GlassItem {}
