/* global React, Icon */

// ============================================================
// Marathon app icons
// Distinctive marks per app — proper iconography, not just gradients.
// Every icon is sized to fill the 64×64 home tile, rendered inside the
// rounded squircle frame the home grid provides.
// ============================================================

// AppIconFrame — the consistent squircle + edge stroke + inner highlight
function AppIconFrame({ children, bg, size = 64, radius = 14 }) {
  return (
    <div style={{
      width: size, height: size,
      background: bg,
      borderRadius: radius,
      position: 'relative',
      overflow: 'hidden',
      boxShadow:
        '0 0 0 1px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.15), 0 8px 16px -8px rgba(0,0,0,0.7)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      {children}
    </div>
  );
}

// Phone — green gradient + chunky handset
function IconPhone({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #00897b 0%, #006b5d 100%)">
      <svg width={size * 0.55} height={size * 0.55} viewBox="0 0 24 24" fill="#fff">
        <path d="M5.5 4l3.2.8 1.6 4-2.1 1.7a12 12 0 0 0 5.4 5.4l1.7-2.1 4 1.6.8 3.2a2 2 0 0 1-2 2.4A17 17 0 0 1 3.1 6.5a2 2 0 0 1 2.4-2z"/>
      </svg>
    </AppIconFrame>
  );
}

// Messages — teal-on-black, BB-style speech mark
function IconMessages({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #0a0a0b, #040404)">
      <svg width={size * 0.6} height={size * 0.6} viewBox="0 0 24 24" fill="none">
        <path d="M3 5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-4l-4 4-1-4H5a2 2 0 0 1-2-2z" fill="#1de9b6"/>
        <circle cx="9" cy="10" r="1.2" fill="#000"/>
        <circle cx="12" cy="10" r="1.2" fill="#000"/>
        <circle cx="15" cy="10" r="1.2" fill="#000"/>
      </svg>
    </AppIconFrame>
  );
}

// Mail — teal envelope on slate, with subtle "open" flap
function IconMail({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #161718, #0a0a0b)">
      <svg width={size * 0.6} height={size * 0.6} viewBox="0 0 24 24" fill="none">
        <rect x="3" y="6" width="18" height="13" rx="2" fill="#1de9b6"/>
        <path d="M3.5 7l8.5 6 8.5-6" stroke="#040404" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </AppIconFrame>
  );
}

// Browser — slate base + teal globe meridians + accent latitude. No off-brand red.
function IconBrowser({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="radial-gradient(circle at 30% 30%, #1c1c1d 0%, #040404 100%)">
      <svg width={size * 0.78} height={size * 0.78} viewBox="0 0 24 24" fill="none">
        <circle cx="12" cy="12" r="9" stroke="#1de9b6" strokeWidth="1.4"/>
        <path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18" stroke="#1de9b6" strokeWidth="1.1" strokeLinecap="round" opacity="0.7"/>
        <path d="M5 8.5h14M5 15.5h14" stroke="#1de9b6" strokeWidth="1.1" strokeLinecap="round" opacity="0.3"/>
      </svg>
    </AppIconFrame>
  );
}

// Store — Marathon's brand "M" on bright teal (matches the boot mark)
function IconStore({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #1de9b6 0%, #00897b 100%)">
      <svg width={size * 0.62} height={size * 0.62} viewBox="0 0 24 24">
        <path d="M3 20V5h2.5l6.5 9 6.5-9H21v15h-2.8V10.5L13 18h-2L5.8 10.5V20z" fill="#000"/>
      </svg>
    </AppIconFrame>
  );
}

// Calculator — dark with orange = and teal numerals
function IconCalc({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #1c1c1d 0%, #040404 100%)">
      <svg width={size * 0.62} height={size * 0.62} viewBox="0 0 24 24" fill="none">
        <rect x="3" y="3" width="6" height="6" rx="1" fill="#1de9b6"/>
        <rect x="10" y="3" width="6" height="6" rx="1" fill="rgba(255,255,255,0.15)"/>
        <rect x="17" y="3" width="4" height="6" rx="1" fill="rgba(255,255,255,0.15)"/>
        <rect x="3" y="10" width="6" height="6" rx="1" fill="rgba(255,255,255,0.15)"/>
        <rect x="10" y="10" width="6" height="6" rx="1" fill="rgba(255,255,255,0.15)"/>
        <rect x="17" y="10" width="4" height="11" rx="1" fill="var(--teal)"/>
        <rect x="3" y="17" width="13" height="4" rx="1" fill="rgba(255,255,255,0.15)"/>
      </svg>
    </AppIconFrame>
  );
}

// Camera — dark gray with realistic lens
function IconCamera({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #353536 0%, #1c1c1d 100%)">
      <svg width={size * 0.65} height={size * 0.65} viewBox="0 0 24 24" fill="none">
        <rect x="2" y="6" width="20" height="14" rx="2" fill="#0a0a0b" stroke="#5b5b5e" strokeWidth="0.6"/>
        <circle cx="12" cy="13" r="5" fill="#040404" stroke="#5b5b5e" strokeWidth="0.5"/>
        <circle cx="12" cy="13" r="3.5" fill="url(#lens)"/>
        <circle cx="10.5" cy="11.5" r="1" fill="rgba(255,255,255,0.4)"/>
        <rect x="15" y="3" width="3.5" height="3" rx="0.5" fill="#0a0a0b"/>
        <circle cx="18" cy="9" r="0.6" fill="#1de9b6"/>
        <defs>
          <radialGradient id="lens" cx="0.4" cy="0.4">
            <stop offset="0" stopColor="#1de9b6" stopOpacity="0.6"/>
            <stop offset="0.5" stopColor="#0a0a0b"/>
            <stop offset="1" stopColor="#000"/>
          </radialGradient>
        </defs>
      </svg>
    </AppIconFrame>
  );
}

// Music — teal-on-black with vinyl groove
function IconMusic({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(135deg, #0d2620 0%, #1a4a3e 100%)">
      <svg width={size * 0.7} height={size * 0.7} viewBox="0 0 24 24" fill="none">
        <circle cx="12" cy="12" r="9" fill="#040404" stroke="rgba(29,233,182,0.35)" strokeWidth="0.5"/>
        <circle cx="12" cy="12" r="7" fill="none" stroke="rgba(29,233,182,0.2)" strokeWidth="0.5"/>
        <circle cx="12" cy="12" r="5.5" fill="none" stroke="rgba(29,233,182,0.2)" strokeWidth="0.5"/>
        <circle cx="12" cy="12" r="3" fill="#1de9b6"/>
        <circle cx="12" cy="12" r="1" fill="#000"/>
      </svg>
    </AppIconFrame>
  );
}

// Calendar — slate card with teal weekday + bold day
function IconCalendar({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #1a1b1c 0%, #0a0a0b 100%)">
      <div style={{ textAlign: 'center', lineHeight: 1 }}>
        <div style={{ fontSize: size * 0.16, fontWeight: 700, color: '#1de9b6', letterSpacing: 1, marginBottom: 2 }}>FRI</div>
        <div style={{ fontSize: size * 0.5, fontWeight: 200, color: '#f5f5f5', letterSpacing: -2, lineHeight: 1 }}>5</div>
      </div>
    </AppIconFrame>
  );
}

// Clock — black dial w/ teal markers, classic
function IconClock({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #0a0a0b, #040404)">
      <svg width={size * 0.72} height={size * 0.72} viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="10" fill="#040404" stroke="rgba(29,233,182,0.5)" strokeWidth="0.6"/>
        {[0,1,2,3,4,5,6,7,8,9,10,11].map(i => {
          const a = (i*30 - 90) * Math.PI / 180;
          const big = i % 3 === 0;
          return <line key={i}
            x1={12+Math.cos(a)*9} y1={12+Math.sin(a)*9}
            x2={12+Math.cos(a)*(big?8:8.4)} y2={12+Math.sin(a)*(big?8:8.4)}
            stroke={big ? '#1de9b6' : 'rgba(245,245,245,0.5)'} strokeWidth={big?1:0.5}
          />;
        })}
        <line x1="12" y1="12" x2="12" y2="7" stroke="#f5f5f5" strokeWidth="1" strokeLinecap="round"/>
        <line x1="12" y1="12" x2="16" y2="13.5" stroke="#f5f5f5" strokeWidth="0.8" strokeLinecap="round"/>
        <line x1="12" y1="12" x2="9" y2="15" stroke="#1de9b6" strokeWidth="0.5" strokeLinecap="round"/>
        <circle cx="12" cy="12" r="0.8" fill="#1de9b6"/>
      </svg>
    </AppIconFrame>
  );
}

// Settings — slate disc with a clean stroked-line gear glyph. Uses
// Lucide's "Settings" icon vocabulary (single-stroke teal cog) on a dark
// disc — sharp, well-formed at every size, no malformed geometry.
function IconSettings({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #1c1c1d 0%, #0a0a0b 100%)">
      <svg width={size * 0.62} height={size * 0.62} viewBox="0 0 24 24" fill="none">
        {/* Lucide-style gear — single stroke, round caps, 8 teeth */}
        <path
          d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"
          stroke="#1de9b6" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"
        />
        <circle cx="12" cy="12" r="3" stroke="#1de9b6" strokeWidth="1.6"/>
      </svg>
    </AppIconFrame>
  );
}

// Maps — slate w/ teal terrain + teal pin (brand-consistent)
function IconMaps({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(135deg, #0f1e16 0%, #040404 100%)">
      <svg width={size * 0.9} height={size * 0.9} viewBox="0 0 24 24" fill="none">
        <rect x="0" y="0" width="24" height="24" fill="#0a1814"/>
        <path d="M-2 14 Q5 12 12 14 T26 13" stroke="rgba(0,191,165,0.55)" strokeWidth="1.4" fill="none"/>
        <path d="M-2 18 Q7 17 14 19 T26 18" stroke="rgba(0,137,123,0.4)" strokeWidth="1" fill="none"/>
        <ellipse cx="6" cy="20" rx="6" ry="3" fill="rgba(0,137,123,0.35)"/>
        <path d="M14 6a4 4 0 0 1 4 4c0 3-4 8-4 8s-4-5-4-8a4 4 0 0 1 4-4z" fill="#1de9b6" stroke="#040404" strokeWidth="0.8"/>
        <circle cx="14" cy="10" r="1.5" fill="#040404"/>
      </svg>
    </AppIconFrame>
  );
}

// Gallery — slate base with three overlapping teal rounded squares — a
// stack-of-photos metaphor, clean geometry, no rainbow petals.
function IconGallery({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #0a0a0b, #040404)">
      <svg width={size * 0.78} height={size * 0.78} viewBox="0 0 24 24" fill="none">
        {/* Back photo */}
        <rect x="4" y="4" width="13" height="13" rx="1.2"
          fill="#006b5d" stroke="rgba(0,0,0,0.6)" strokeWidth="0.4"/>
        {/* Middle photo */}
        <rect x="6" y="6" width="13" height="13" rx="1.2"
          fill="#00bfa5" stroke="rgba(0,0,0,0.6)" strokeWidth="0.4"/>
        {/* Front photo — brightest, with a tiny "scene" inside it */}
        <rect x="8" y="8" width="13" height="13" rx="1.2"
          fill="#1de9b6" stroke="rgba(0,0,0,0.6)" strokeWidth="0.4"/>
        {/* Mini landscape inside the front photo */}
        <circle cx="13.5" cy="12" r="1.3" fill="#040404" opacity="0.7"/>
        <path d="M9 18l3.5-3 2 1.5L17.5 14 20 18 z" fill="#040404" opacity="0.5"/>
      </svg>
    </AppIconFrame>
  );
}

// Notes — slate w/ teal-trim "legal pad" (no off-brand yellow)
function IconNotes({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #1a1b1c, #0a0a0b)">
      <svg width={size * 0.7} height={size * 0.7} viewBox="0 0 24 24" fill="none">
        <rect x="4" y="2" width="16" height="20" rx="1.5" fill="#161718" stroke="rgba(245,245,245,0.10)" strokeWidth="0.5"/>
        <rect x="4" y="2" width="16" height="3" rx="1.5" fill="#1de9b6"/>
        <line x1="6" y1="9" x2="18" y2="9" stroke="rgba(245,245,245,0.5)" strokeWidth="0.7"/>
        <line x1="6" y1="13" x2="18" y2="13" stroke="rgba(245,245,245,0.4)" strokeWidth="0.7"/>
        <line x1="6" y1="17" x2="14" y2="17" stroke="rgba(245,245,245,0.4)" strokeWidth="0.7"/>
      </svg>
    </AppIconFrame>
  );
}

// Contacts — slate w/ silhouette
function IconContacts({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #161718, #0a0a0b)">
      <svg width={size * 0.7} height={size * 0.7} viewBox="0 0 24 24" fill="none">
        <rect x="4" y="3" width="16" height="18" rx="1.5" fill="rgba(245,245,245,0.05)" stroke="rgba(245,245,245,0.2)" strokeWidth="0.5"/>
        <line x1="2" y1="8" x2="4" y2="8" stroke="#1de9b6" strokeWidth="1"/>
        <line x1="2" y1="12" x2="4" y2="12" stroke="#1de9b6" strokeWidth="1"/>
        <line x1="2" y1="16" x2="4" y2="16" stroke="#1de9b6" strokeWidth="1"/>
        <circle cx="12" cy="10" r="2.5" fill="#1de9b6"/>
        <path d="M7 17a5 5 0 0 1 10 0" fill="#1de9b6"/>
      </svg>
    </AppIconFrame>
  );
}

// Files — slate folder w/ teal tab
function IconFiles({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #1c1c1d, #040404)">
      <svg width={size * 0.78} height={size * 0.78} viewBox="0 0 24 24" fill="none">
        <path d="M3 7a1 1 0 0 1 1-1h6l2 2h8a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z" fill="#1de9b6"/>
        <path d="M3 9.5h18V18a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1z" fill="#00897b"/>
      </svg>
    </AppIconFrame>
  );
}

// Marathon Intelligence app icon — distinctive, visible, brand-coherent.
// Dark slate base with a bold teal horizon mark (sunrise) — the same mark
// used inline for AI surfaces, but drawn at icon weight so it READS from
// across the home grid. No sparkles, no near-invisible faint arcs.
function IconMI({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #0a0a0b 0%, #040404 100%)">
      <svg width={size * 0.85} height={size * 0.85} viewBox="0 0 24 24" fill="none">
        <defs>
          <radialGradient id={`mi-glow-${size}`} cx="0.5" cy="0.75" r="0.4">
            <stop offset="0" stopColor="#1de9b6" stopOpacity="0.45"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
        </defs>
        {/* Halo behind the mark */}
        <rect x="0" y="0" width="24" height="24" fill={`url(#mi-glow-${size})`}/>
        {/* Three concentric horizon arcs — heavy stroke so it reads at 64px */}
        <path d="M2 17.5 Q12 4 22 17.5" stroke="#5dffdc" strokeWidth="1.8" strokeLinecap="round" fill="none"/>
        <path d="M5 17.5 Q12 8 19 17.5" stroke="#1de9b6" strokeWidth="1.5" strokeLinecap="round" fill="none" opacity="0.75"/>
        <path d="M8.5 17.5 Q12 12.5 15.5 17.5" stroke="#00bfa5" strokeWidth="1.2" strokeLinecap="round" fill="none" opacity="0.55"/>
        {/* Horizon baseline */}
        <line x1="2" y1="17.5" x2="22" y2="17.5" stroke="#5dffdc" strokeWidth="1.3" strokeLinecap="round"/>
        {/* Sun anchor — bright dot on the baseline */}
        <circle cx="12" cy="17.5" r="1.4" fill="#5dffdc"/>
        <circle cx="12" cy="17.5" r="3" fill="#1de9b6" opacity="0.35"/>
      </svg>
    </AppIconFrame>
  );
}

// Wallet — slate with stacked teal-tinted cards (no off-brand purple)
function IconWallet({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #1c1c1d, #040404)">
      <svg width={size * 0.78} height={size * 0.78} viewBox="0 0 24 24" fill="none">
        <rect x="3" y="6" width="18" height="11" rx="1.5" fill="#1de9b6"/>
        <rect x="3" y="8" width="18" height="11" rx="1.5" fill="#00897b"/>
        <rect x="3" y="10" width="18" height="11" rx="1.5" fill="#161718" stroke="rgba(255,255,255,0.15)" strokeWidth="0.6"/>
        <circle cx="17" cy="15.5" r="1.8" fill="#1de9b6"/>
        <line x1="6" y1="13.5" x2="14" y2="13.5" stroke="rgba(255,255,255,0.4)" strokeWidth="0.8"/>
        <line x1="6" y1="16.5" x2="11" y2="16.5" stroke="rgba(255,255,255,0.3)" strokeWidth="0.8"/>
      </svg>
    </AppIconFrame>
  );
}

// Health — slate with teal heart + EKG line (no off-brand red)
function IconHealth({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #0a0a0b, #040404)">
      <svg width={size * 0.72} height={size * 0.72} viewBox="0 0 24 24" fill="none">
        <path d="M12 21s-7-4.5-9.3-9A5.5 5.5 0 0 1 12 6.5 5.5 5.5 0 0 1 21.3 12C19 16.5 12 21 12 21z"
          fill="#1de9b6"/>
        <path d="M4 14h3l1.5-3 2 6 2-9 1.5 6h4" stroke="#040404" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" fill="none"/>
      </svg>
    </AppIconFrame>
  );
}

// Weather — slate sky w/ teal sun (brand-consistent)
function IconWeather({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #0a1a18 0%, #040404 100%)">
      <svg width={size * 0.78} height={size * 0.78} viewBox="0 0 24 24" fill="none">
        <circle cx="15" cy="9" r="4" fill="#1de9b6"/>
        <path d="M3 16a4 4 0 0 1 4-4 5 5 0 0 1 9.5-1A3.5 3.5 0 0 1 20 14.5 3.5 3.5 0 0 1 16.5 18H7a4 4 0 0 1-4-2z" fill="#5b5b5e"/>
      </svg>
    </AppIconFrame>
  );
}

// Voice memos — slate with teal record dot
function IconVoice({ size = 64 }) {
  return (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #040404, #1c1c1d)">
      <svg width={size * 0.6} height={size * 0.6} viewBox="0 0 24 24" fill="none">
        <rect x="9" y="3" width="6" height="11" rx="3" fill="#1de9b6"/>
        <path d="M5 11a7 7 0 0 0 14 0M12 18v3" stroke="#f5f5f5" strokeWidth="1.4" strokeLinecap="round"/>
        <line x1="3" y1="20" x2="21" y2="20" stroke="#1de9b6" strokeWidth="0.6" opacity="0.5"/>
      </svg>
    </AppIconFrame>
  );
}

// Generic app icon (used for store listings)
function GenericAppIcon({ size = 64, glyph, bg, glyphColor = '#fff', black }) {
  return (
    <AppIconFrame size={size} bg={bg}>
      <Icon name={glyph} size={size * 0.5} color={black ? '#000' : glyphColor}/>
    </AppIconFrame>
  );
}

// Master registry keyed by app name (used by HomeIcon, AppDrawer, etc.)
const APP_ICON_COMPONENTS = {
  phone: IconPhone,
  message: IconMessages,
  mail: IconMail,
  browser: IconBrowser,
  store: IconStore,
  calc: IconCalc,
  camera: IconCamera,
  music: IconMusic,
  calendar: IconCalendar,
  clock: IconClock,
  settings: IconSettings,
  maps: IconMaps,
  photos: IconGallery,
  notes: IconNotes,
  contacts: IconContacts,
  files: IconFiles,
  mi: IconMI,
  wallet: IconWallet,
  health: IconHealth,
  weather: IconWeather,
  voice: IconVoice,
};

// Wrapper that pads in the home-grid layout (tile + label below)
function AppTile({ name, label, size = 64 }) {
  const Cmp = APP_ICON_COMPONENTS[name] || (() => (
    <AppIconFrame size={size} bg="linear-gradient(180deg, #1c1c1d, #040404)">
      <Icon name="store" size={size * 0.5} color="#1de9b6"/>
    </AppIconFrame>
  ));
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6, width: size + 14 }}>
      <Cmp size={size}/>
      <div style={{
        fontSize: 12,
        fontWeight: 500,
        color: 'var(--text-primary)',
        textAlign: 'center',
        letterSpacing: 0.1,
        textShadow: '0 1px 1px rgba(0,0,0,0.5)',
      }}>{label}</div>
    </div>
  );
}

Object.assign(window, {
  AppIconFrame,
  IconPhone, IconMessages, IconMail, IconBrowser, IconStore, IconCalc,
  IconCamera, IconMusic, IconCalendar, IconClock, IconSettings, IconMaps,
  IconGallery, IconNotes, IconContacts, IconFiles, IconMI, IconWallet,
  IconHealth, IconWeather, IconVoice,
  APP_ICON_COMPONENTS, AppTile,
  GenericAppIcon,
});
