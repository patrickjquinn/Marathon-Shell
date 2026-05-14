/* global React */
// ============================================================
// MARATHON — shared shell pieces
//   StatusBar, Dock, HomeIndicator, TopBar, TabBar, Icon
//
// Icon uses Lucide via CDN (window.lucide.icons) as the primary
// icon pack, with inline SVG fallbacks for names lucide doesn't
// have (or for offline rendering).
// ============================================================

// Phosphor Light is the primary icon family. Map our local name → Phosphor.
// Marathon's own `marathon` glyph stays inline (bespoke horizon mark).
const PHOSPHOR_NAME_MAP = {
  battery: 'battery-full',
  bluetooth: 'bluetooth',
  wifi: 'wifi-high',
  phone_status: 'device-mobile',
  alarm: 'alarm',
  dnd: 'bell-slash',
  chevron_right: 'caret-right',
  chevron_left:  'caret-left',
  chevron_up:    'caret-up',
  chevron_down:  'caret-down',
  arrow_up:   'arrow-up',
  arrow_down: 'arrow-down',
  more: 'dots-three',
  menu: 'list',
  x: 'x',
  plus: 'plus',
  check: 'check',
  search: 'magnifying-glass',
  phone: 'phone',
  inbox: 'tray',
  layers: 'stack',
  camera: 'camera',
  message: 'chat-circle',
  mail: 'envelope',
  user: 'user',
  globe: 'globe',
  map_pin: 'map-pin',
  calendar: 'calendar-blank',
  clock: 'clock',
  music: 'music-notes',
  calc: 'calculator',
  store: 'shopping-bag',
  download: 'download-simple',
  star: 'star',
  heart: 'heart',
  reply: 'arrow-bend-up-left',
  trash: 'trash',
  archive: 'archive',
  flag: 'flag',
  mic: 'microphone',
  send: 'paper-plane-right',
  share: 'share-network',
  refresh: 'arrows-clockwise',
  copy: 'copy',
  zap: 'lightning',
  info: 'info',
  lock: 'lock',
  lock_open: 'lock-open',
  play: 'play',
  pause: 'pause',
  skip_back: 'skip-back',
  skip_forward: 'skip-forward',
  cog: 'gear',
  bell: 'bell',
  shield: 'shield-check',
  monitor: 'monitor',
  volume: 'speaker-high',
  brightness: 'sun',
  airplane: 'airplane-tilt',
  flashlight: 'flashlight',
  cast: 'broadcast',
  hotspot: 'cell-signal-high',
  rotate: 'arrow-clockwise',
  battery_saver: 'battery-low',
  note: 'note',
  storage: 'database',
  // 2026 additions
  sparkles: 'sparkle',
  brain: 'brain',
  command: 'command',
  fingerprint: 'fingerprint',
  qr: 'qr-code',
  filter: 'sliders-horizontal',
  pin: 'push-pin',
  reply_all: 'arrow-bend-up-left',
  trend: 'trend-up',
  bookmark: 'bookmark-simple',
  award: 'medal',
  link: 'link',
  external: 'arrow-square-out',
  eye: 'eye',
  eye_off: 'eye-slash',
  paperclip: 'paperclip',
  ticket: 'ticket',
  smile: 'smiley',
  gift: 'gift',
  flame: 'flame',
  cpu: 'cpu',
  history: 'clock-counter-clockwise',
  list: 'list',
  panel_right: 'sidebar',
  github: 'github-logo',
  fileText: 'file-text',
  folder: 'folder',
  // `marathon` is the bespoke Marathon Intelligence mark — drawn inline,
  // never delegated to Phosphor. Lookup falls through to INLINE_ICONS.
  marathon: null,
};

// Legacy alias — anything still importing LUCIDE_NAME_MAP gets the
// Phosphor table. Lets us swap without sweeping every caller in one go.
const LUCIDE_NAME_MAP = PHOSPHOR_NAME_MAP;

// ---------- ICON ----------
// Renders a Phosphor icon using the @phosphor-icons/web stylesheet
// (loaded once in each host HTML). Phosphor ships as a font + class
// system: <i class="ph-light ph-phone"> renders the Light-weight phone
// icon at the parent's font-size.
//
// `weight` defaults to 'light' (1px stroke, pairs with Sora 200/300).
// Pass 'bold' for chrome-heavy contexts, 'duotone' to mark Marathon
// Intelligence surfaces, 'fill' for selected/active state.
function Icon({ name, size = 18, weight = 'light', strokeWidth, color, style }) {
  // Bespoke Marathon mark — never delegated.
  if (name === 'marathon') {
    return (
      <svg
        width={size} height={size} viewBox="0 0 24 24"
        style={{ color: color || 'currentColor', flexShrink: 0, display: 'block', ...style }}
      >
        {INLINE_ICONS.marathon}
      </svg>
    );
  }

  const phName = PHOSPHOR_NAME_MAP[name];
  if (phName) {
    return (
      <i
        className={`ph-${weight} ph-${phName}`}
        style={{
          fontSize: size,
          color: color || 'currentColor',
          lineHeight: 1,
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          width: size,
          height: size,
          flexShrink: 0,
          ...style,
        }}
        aria-hidden="true"
      />
    );
  }

  // Fallback to inline icon set (used for `marathon` mark and any name
  // Phosphor doesn't have an obvious mapping for).
  const inner = INLINE_ICONS[name];
  if (!inner) return null;
  return (
    <svg
      width={size} height={size} viewBox="0 0 24 24"
      style={{ color: color || 'currentColor', flexShrink: 0, display: 'block', ...style }}
    >
      {inner}
    </svg>
  );
}

// ---------- Inline icon fallback set ----------
const INLINE_ICONS = {
  // Marathon Intelligence mark — concentric "horizon" arcs. NOT a sparkle.
  // Reads as a sunrise, a radar pulse, a wavefront — Marathon-distinctive.
  marathon: (
    <g fill="none" stroke="currentColor" strokeLinecap="round">
      <path d="M3 19 Q12 4 21 19" strokeWidth="1.6"/>
      <path d="M6.5 19 Q12 9 17.5 19" strokeWidth="1.4" opacity="0.75"/>
      <path d="M10 19 Q12 14 14 19" strokeWidth="1.2" opacity="0.5"/>
      <line x1="2.5" y1="19" x2="21.5" y2="19" strokeWidth="1.2"/>
      <circle cx="12" cy="19" r="0.9" fill="currentColor" stroke="none"/>
    </g>
  ),
  // status bar
  battery: (
    <g fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="1.5" y="6" width="18" height="12" rx="1.5" />
      <rect x="20" y="9.5" width="1.5" height="5" rx="0.5" fill="currentColor" stroke="none"/>
      <rect x="3" y="7.5" width="14" height="9" rx="0.5" fill="currentColor" stroke="none"/>
    </g>
  ),
  bluetooth: (
    <path d="M7 7l10 10-5 5V2l5 5L7 17" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
  ),
  wifi: (
    <g fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 9c5.5-5 14.5-5 20 0"/>
      <path d="M5 12.5c3.8-3.5 10.2-3.5 14 0"/>
      <path d="M8 16c2.2-2 5.8-2 8 0"/>
      <circle cx="12" cy="19.5" r="1.1" fill="currentColor" stroke="none"/>
    </g>
  ),
  phone_status: (
    <rect x="6" y="2.5" width="12" height="19" rx="2" fill="none" stroke="currentColor" strokeWidth="1.5"/>
  ),
  lock: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="4" y="10" width="16" height="11" rx="2"/>
      <path d="M8 10V7a4 4 0 0 1 8 0v3"/>
    </g>
  ),
  alarm: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="13" r="8"/>
      <path d="M12 9v4l3 2M5 3L2 6M19 3l3 3"/>
    </g>
  ),
  dnd: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="9"/>
      <path d="M8 12h8"/>
    </g>
  ),
  // dock + nav
  phone: (
    <path d="M5.5 4.5l3 .8 1.4 4-2 1.5a11 11 0 0 0 5.3 5.3l1.5-2 4 1.4.8 3a2 2 0 0 1-2 2.4A16 16 0 0 1 3.1 6.5a2 2 0 0 1 2.4-2z" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
  ),
  camera: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 7h3l2-3h8l2 3h3a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1z"/>
      <circle cx="12" cy="13" r="4"/>
    </g>
  ),
  inbox: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 13l3-8h12l3 8v6a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z"/>
      <path d="M3 13h5l1 2h6l1-2h5"/>
    </g>
  ),
  layers: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 3l9 5-9 5-9-5 9-5z"/>
      <path d="M3 13l9 5 9-5"/>
    </g>
  ),
  // common
  chevron_right: <path d="M9 6l6 6-6 6" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>,
  chevron_left:  <path d="M15 6l-6 6 6 6" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>,
  chevron_down:  <path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>,
  chevron_up:    <path d="M6 15l6-6 6 6" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>,
  search: (
    <g fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="7"/>
      <path d="M21 21l-4.3-4.3"/>
    </g>
  ),
  plus: <path d="M12 5v14M5 12h14" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/>,
  x: <path d="M6 6l12 12M18 6L6 18" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/>,
  check: <path d="M5 12l5 5L20 7" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>,
  arrow_up: <path d="M12 19V5M5 12l7-7 7 7" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>,
  arrow_down: <path d="M12 5v14M5 12l7 7 7-7" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>,
  more: (
    <g fill="currentColor"><circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/></g>
  ),
  menu: <path d="M3 6h18M3 12h18M3 18h18" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/>,
  // play controls
  play: <path d="M7 5l12 7-12 7V5z" fill="currentColor"/>,
  pause: <g fill="currentColor"><rect x="6" y="5" width="4" height="14" rx="0.5"/><rect x="14" y="5" width="4" height="14" rx="0.5"/></g>,
  skip_back: <g fill="currentColor"><rect x="5" y="5" width="2" height="14"/><path d="M19 5l-11 7 11 7V5z"/></g>,
  skip_forward: <g fill="currentColor"><rect x="17" y="5" width="2" height="14"/><path d="M5 5l11 7-11 7V5z"/></g>,
  // settings glyphs
  cog: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3"/>
      <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 0 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>
    </g>
  ),
  bell: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/>
      <path d="M10 21a2 2 0 0 0 4 0"/>
    </g>
  ),
  shield: (
    <path d="M12 3l8 3v6c0 5-3.5 8.5-8 9-4.5-.5-8-4-8-9V6l8-3z" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round"/>
  ),
  monitor: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="4" width="20" height="13" rx="2"/>
      <path d="M8 21h8M12 17v4"/>
    </g>
  ),
  volume: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M11 5L6 9H3v6h3l5 4V5z" fill="currentColor"/>
      <path d="M16 9a4 4 0 0 1 0 6M19 6a8 8 0 0 1 0 12"/>
    </g>
  ),
  brightness: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="4"/>
      <path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1"/>
    </g>
  ),
  airplane: (
    <path d="M20.5 11.5l-7-4V3.5a1.5 1.5 0 0 0-3 0v4l-7 4v2l7-2v5l-2 1.5V20l3.5-1L15 20v-2l-2-1.5v-5l7 2v-2z" fill="currentColor"/>
  ),
  flashlight: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round">
      <path d="M7 2h10l-2 6H9z"/>
      <path d="M9 8h6v5l-3 9-3-9z"/>
    </g>
  ),
  cast: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M2 8V6a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-6"/>
      <path d="M2 12a8 8 0 0 1 8 8M2 16a4 4 0 0 1 4 4M2 20h.01"/>
    </g>
  ),
  hotspot: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round">
      <circle cx="12" cy="12" r="2" fill="currentColor"/>
      <path d="M9 9a4 4 0 0 0 0 6M15 9a4 4 0 0 1 0 6M6 6a8 8 0 0 0 0 12M18 6a8 8 0 0 1 0 12"/>
    </g>
  ),
  rotate: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 12a9 9 0 0 1 15-6.7L21 8"/>
      <path d="M21 3v5h-5"/>
      <path d="M21 12a9 9 0 0 1-15 6.7L3 16"/>
      <path d="M3 21v-5h5"/>
    </g>
  ),
  battery_saver: (
    <g fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="6" width="18" height="12" rx="1.5"/>
      <rect x="21" y="9.5" width="1.5" height="5" rx="0.5" fill="currentColor"/>
      <path d="M11 9l-2 3h2v3l2-3h-2z" fill="currentColor"/>
    </g>
  ),
  note: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/>
      <path d="M14 3v6h6M8 13h8M8 17h5"/>
    </g>
  ),
  message: (
    <path d="M21 12a8 8 0 0 1-12 7l-5 1 1.5-4.5A8 8 0 1 1 21 12z" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round"/>
  ),
  mail: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="5" width="18" height="14" rx="2"/>
      <path d="M3 7l9 6 9-6"/>
    </g>
  ),
  user: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="8" r="4"/>
      <path d="M4 21a8 8 0 0 1 16 0"/>
    </g>
  ),
  globe: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="9"/>
      <path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>
    </g>
  ),
  map_pin: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round">
      <path d="M12 22s7-7 7-12a7 7 0 1 0-14 0c0 5 7 12 7 12z"/>
      <circle cx="12" cy="10" r="2.5"/>
    </g>
  ),
  calendar: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="5" width="18" height="16" rx="2"/>
      <path d="M3 9h18M8 3v4M16 3v4"/>
    </g>
  ),
  clock: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="9"/>
      <path d="M12 7v5l3 2"/>
    </g>
  ),
  music: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9 18V5l12-2v13"/>
      <circle cx="6" cy="18" r="3"/>
      <circle cx="18" cy="16" r="3"/>
    </g>
  ),
  calc: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="4" y="3" width="16" height="18" rx="2"/>
      <path d="M8 7h8M8 11h2M14 11h2M8 15h2M14 15h2M8 19h2M14 19h2"/>
    </g>
  ),
  store: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 8h14l-1 12H6z"/>
      <path d="M9 8V6a3 3 0 0 1 6 0v2"/>
    </g>
  ),
  download: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 4v12M6 12l6 6 6-6M4 21h16"/>
    </g>
  ),
  star: (
    <path d="M12 3l2.9 6 6.5.9-4.7 4.6 1.1 6.5L12 18l-5.8 3 1.1-6.5L2.6 9.9 9.1 9z" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round"/>
  ),
  heart: (
    <path d="M12 21s-7-4.5-9.3-9A5.5 5.5 0 0 1 12 6.5 5.5 5.5 0 0 1 21.3 12C19 16.5 12 21 12 21z" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round"/>
  ),
  reply: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9 17l-5-5 5-5"/>
      <path d="M4 12h11a5 5 0 0 1 5 5v2"/>
    </g>
  ),
  trash: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 7h16"/>
      <path d="M19 7v13a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V7"/>
      <path d="M9 7V4h6v3"/>
    </g>
  ),
  archive: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="4" width="18" height="4" rx="1"/>
      <path d="M4 8v11a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1V8M10 12h4"/>
    </g>
  ),
  flag: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 22V4h11l-2 4 2 4H5"/>
    </g>
  ),
  mic: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="9" y="3" width="6" height="11" rx="3"/>
      <path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>
    </g>
  ),
  send: (
    <path d="M22 2L11 13M22 2l-7 20-4-9-9-4z" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"/>
  ),
  share: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="18" cy="5" r="3"/>
      <circle cx="6" cy="12" r="3"/>
      <circle cx="18" cy="19" r="3"/>
      <path d="M8.6 13.5l6.8 4M15.4 6.5l-6.8 4"/>
    </g>
  ),
  refresh: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 12a9 9 0 1 1-3-6.7L21 8"/>
      <path d="M21 3v5h-5"/>
    </g>
  ),
  copy: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="9" y="9" width="11" height="11" rx="2"/>
      <path d="M5 15V5a1 1 0 0 1 1-1h10"/>
    </g>
  ),
  zap: (
    <path d="M13 2L4 14h7l-1 8 9-12h-7l1-8z" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round"/>
  ),
  storage: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <ellipse cx="12" cy="6" rx="8" ry="3"/>
      <path d="M4 6v12c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/>
      <path d="M4 12c0 1.7 3.6 3 8 3s8-1.3 8-3"/>
    </g>
  ),
  info: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="9"/>
      <path d="M12 16v-5M12 8h.01"/>
    </g>
  ),
  lock_open: (
    <g fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
      <rect x="4" y="11" width="16" height="10" rx="2"/>
      <path d="M8 11V7a4 4 0 0 1 7.5-2"/>
    </g>
  ),
};

// ---------- STATUS BAR ----------
function StatusBar({ time = '7:08', battery = 78, dark = true, centerTime = true }) {
  return (
    <div className="status-bar">
      <div className="sb-left">
        <Icon name="battery" size={16}/>
        <span style={{ fontSize: 12, fontWeight: 500 }}>{battery}%</span>
      </div>
      {centerTime && <div className="sb-center">{time}</div>}
      <div className="sb-right">
        <Icon name="bluetooth" size={14}/>
        <Icon name="phone_status" size={14}/>
        <Icon name="wifi" size={15}/>
      </div>
    </div>
  );
}

// ---------- STATUS BAR (lock variant — centered lock glyph, no clock) ----------
function StatusBarLock({ battery = 78 }) {
  return (
    <div className="status-bar">
      <div className="sb-left">
        <Icon name="battery" size={16}/>
        <span style={{ fontSize: 12, fontWeight: 500 }}>{battery}%</span>
      </div>
      <div className="sb-center" style={{ opacity: 0.7 }}>
        <Icon name="lock" size={14}/>
      </div>
      <div className="sb-right">
        <Icon name="bluetooth" size={14}/>
        <Icon name="phone_status" size={14}/>
        <Icon name="wifi" size={15}/>
      </div>
    </div>
  );
}

// ---------- DOCK (bottom corners + page indicator) ----------
function Dock({ activePage = 1, totalPages = 4, showCenter = true }) {
  return (
    <div className="dock">
      <div className="dock-side">
        <div className="dock-icon" style={{ color: 'var(--teal-bright)' }}>
          <Icon name="phone" size={26}/>
        </div>
      </div>
      {showCenter && (
        <div className="dock-center">
          <div style={{ color: 'rgba(255,255,255,0.55)' }}><Icon name="inbox" size={20}/></div>
          <div style={{ color: 'rgba(255,255,255,0.55)' }}><Icon name="layers" size={20}/></div>
          {Array.from({ length: totalPages }).map((_, i) => (
            i === activePage - 1
              ? <div key={i} className="dot active">{activePage}</div>
              : <div key={i} className="dot" />
          ))}
        </div>
      )}
      <div className="dock-side">
        <div className="dock-icon" style={{ color: 'rgba(255,255,255,0.85)' }}>
          <Icon name="camera" size={24}/>
        </div>
      </div>
    </div>
  );
}

// ---------- HOME INDICATOR ----------
function HomeIndicator({ light = false }) {
  return <div className="home-indicator" style={ light ? { background: 'rgba(0,0,0,0.35)' } : undefined } />;
}

// ---------- TOP BAR ----------
function TopBar({ title, back, actions }) {
  return (
    <div className="top-bar">
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        {back && (
          <div style={{ color: 'var(--text-secondary)', display: 'flex', alignItems: 'center' }}>
            <Icon name="chevron_left" size={26}/>
          </div>
        )}
        <div className="title">{title}</div>
      </div>
      <div className="actions">{actions}</div>
    </div>
  );
}

// ---------- TAB BAR (bottom navigation) ----------
function TabBar({ tabs, active }) {
  return (
    <div className="tab-bar">
      {tabs.map((t, i) => (
        <div key={i} className={'tab' + (i === active ? ' active' : '')}>
          <Icon name={t.icon} size={20}/>
          <div>{t.label}</div>
        </div>
      ))}
    </div>
  );
}

// ---------- APP ICON ----------
// Mini app icons; not photorealistic, but cohesive with the system.
function AppIcon({ label, color = 'var(--elev-3)', glyph, glyphColor = '#fff', accent }) {
  return (
    <div className="app-tile">
      <div className="app-icon" style={{ background: color }}>
        {accent && <div style={{
          position: 'absolute', inset: 0, background: accent, borderRadius: 14,
          opacity: 0.9, mixBlendMode: 'overlay'
        }}/>}
        <div style={{ color: glyphColor, zIndex: 1, display: 'flex' }}>{glyph}</div>
      </div>
      <div className="app-label">{label}</div>
    </div>
  );
}

// ---------- Surface helpers ----------
function Card({ children, style, elev, className }) {
  return (
    <div
      className={'m-card' + (elev ? ' elev-' + elev : '') + (className ? ' ' + className : '')}
      style={style}
    >
      {children}
    </div>
  );
}

function Toggle({ on }) { return <div className={'m-toggle' + (on ? ' on' : '')} />; }

function Row({ icon, iconBg, title, subtitle, value, toggle, chev = true, danger }) {
  return (
    <div className="m-row">
      {icon && (
        <div className="row-icon" style={{ background: iconBg || 'var(--elev-3)', color: danger ? 'var(--error)' : 'var(--text-primary)' }}>
          <Icon name={icon} size={18}/>
        </div>
      )}
      <div className="row-text">
        <div className="row-title" style={ danger ? { color: 'var(--error)' } : null}>{title}</div>
        {subtitle && <div className="row-subtitle">{subtitle}</div>}
      </div>
      {value && <div className="row-value">{value}</div>}
      {typeof toggle === 'boolean' && <Toggle on={toggle}/>}
      {chev && !value && typeof toggle !== 'boolean' && <div className="row-chev"><Icon name="chevron_right" size={18}/></div>}
    </div>
  );
}

// ---------- Section header (small caps style) ----------
function SectionLabel({ children, style }) {
  return (
    <div style={{
      fontSize: 11, fontWeight: 700, letterSpacing: 1.2, textTransform: 'uppercase',
      color: 'var(--text-secondary)', padding: '0 4px 8px',
      ...style,
    }}>{children}</div>
  );
}

// expose to other babel scripts
Object.assign(window, {
  Icon, INLINE_ICONS, LUCIDE_NAME_MAP, PHOSPHOR_NAME_MAP,
  StatusBar, StatusBarLock,
  Dock, HomeIndicator,
  TopBar, TabBar,
  AppIcon, Card, Row, Toggle, SectionLabel,
});
