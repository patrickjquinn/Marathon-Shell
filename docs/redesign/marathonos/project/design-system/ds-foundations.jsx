/* global React, Icon, Card, Row, Toggle, StatusBar, AppIconFrame, IconPhone, IconMessages, IconMail, IconBrowser, IconStore, IconCalc, IconCamera, IconMusic, IconCalendar, IconClock, IconSettings, IconMaps, IconGallery, IconNotes, IconContacts, IconFiles, IconMI, IconWallet, IconHealth, IconWeather, IconVoice */

// ============================================================
// Marathon Design System — Foundations sections
// ============================================================

function Section({ id, eyebrow, title, lede, children }) {
  return (
    <section id={id} className="ds-section ds-anchor">
      {eyebrow && <div className="ds-section-eyebrow">{eyebrow}</div>}
      <h2 className="ds-section-title">{title}</h2>
      {lede && <p className="ds-section-lede">{lede}</p>}
      {children}
    </section>
  );
}

// ---------- BRAND ----------

// MarathonMark — the canonical brand mark. Lifted directly from the
// BootSplash in Marathon OS: a teal-gradient disc (#1de9b6 → #00bfa5),
// soft halo, black-filled "M" path centered, with "marathon" lowercase
// letter-spaced caps below. This is THE logo — every other surface in
// the design system references this component.
const M_FONT_STACK = '"Sora", system-ui, sans-serif';
const M_PATH = "M10 44V14h6l12 18 12-18h6v30h-6V24L28 40 16 24v20z";

function MarathonMark({ size = 220, label = true, monochrome, glow = true }) {
  // Proportions from the BootSplash reference: disc = 96, M inside = 56,
  // word below = 14 px at 6 px tracking. Scale everything off `size`.
  // Disc ≈ 44% of the wallpaper canvas in BootSplash; here we let `size`
  // describe the canvas, so disc = size * 0.43.
  const discPx = Math.round(size * 0.43);
  const mPx    = Math.round(discPx * 0.58);
  const haloPx = Math.round(discPx * 0.42);
  const wordSize = Math.max(9, Math.round(size * 0.063));
  const wordTrack = Math.max(2, Math.round(size * 0.027));

  const discBg = monochrome
    ? '#1de9b6'
    : 'linear-gradient(180deg, #1de9b6 0%, #00bfa5 100%)';

  return (
    <div style={{
      width: size,
      display: 'inline-flex', flexDirection: 'column',
      alignItems: 'center', gap: Math.round(size * 0.10),
    }}>
      <div style={{
        width: discPx, height: discPx, borderRadius: '50%',
        background: discBg,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: glow && !monochrome
          ? `0 0 ${haloPx}px rgba(0,191,165,0.45), inset 0 1px 0 rgba(255,255,255,0.3)`
          : 'inset 0 1px 0 rgba(255,255,255,0.3)',
        border: '1px solid rgba(255,255,255,0.15)',
        flexShrink: 0,
      }}>
        <svg width={mPx} height={mPx} viewBox="0 0 56 56" fill="none">
          <path d={M_PATH} fill="#000"/>
        </svg>
      </div>
      {label && (
        <div style={{
          fontFamily: M_FONT_STACK,
          letterSpacing: wordTrack,
          fontSize: wordSize,
          fontWeight: 300,
          color: monochrome ? '#040404' : '#fff',
          textTransform: 'uppercase',
        }}>marathon</div>
      )}
    </div>
  );
}

function DSBrand() {
  return (
    <Section id="brand" eyebrow="Foundation" title="Brand mark" lede="A teal disc with a heavy black 'M' inside, glowing softly. 'MARATHON' in light-tracked caps below. That is the entire brand identity. The mark scales identically from a 28-dp watermark to a 320-dp hero, and the same vector renders at every size.">

      <h3 className="ds-h3">Primary mark</h3>
      <p className="ds-p">The full lockup — disc, M, wordmark. Used on the boot splash, the About panel, the App Store header, OOBE, and external attribution. Everything else uses the mark alone (no wordmark) or the inline lockup.</p>
      <div className="ds-grid cols-3">
        <div className="ds-specimen" style={{ textAlign: 'center', padding: 24, background: '#040404' }}>
          <MarathonMark size={220}/>
          <div className="ds-specimen-caption" style={{ textAlign: 'center', marginTop: 8 }}>Primary · on black</div>
        </div>
        <div className="ds-specimen" style={{ textAlign: 'center', padding: 24, background: 'var(--elev-2)' }}>
          <MarathonMark size={220} glow={false}/>
          <div className="ds-specimen-caption" style={{ textAlign: 'center', marginTop: 8 }}>On surface · glow off</div>
        </div>
        <div className="ds-specimen" style={{ textAlign: 'center', padding: 24, background: '#f5f5f5' }}>
          <MarathonMark size={220} monochrome/>
          <div className="ds-specimen-caption" style={{ textAlign: 'center', marginTop: 8, color: '#0a0a0b' }}>On light · single-color</div>
        </div>
      </div>

      <h3 className="ds-h3">Mark alone</h3>
      <p className="ds-p">The disc + M without the wordmark. Used in tight chrome contexts — the home grid attribution, Quick Settings header, watermarks, the favicon. Same geometry; the lockup just drops the label.</p>
      <div className="ds-specimen" style={{ padding: 36, display: 'flex', alignItems: 'flex-end', justifyContent: 'space-around', gap: 24, background: '#040404' }}>
        {[28, 44, 72, 120, 200].map(sz => (
          <div key={sz} style={{ textAlign: 'center' }}>
            <MarathonMark size={sz} label={false} glow={sz >= 72}/>
            <div className="mono" style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 10 }}>{sz} dp</div>
          </div>
        ))}
      </div>

      <h3 className="ds-h3">Inline lockup</h3>
      <p className="ds-p">For headers and rows where vertical space is tight — disc + horizontal wordmark on the right, separated by 14 px. Used in About rows, OOBE step headers, the Marathon App Store top bar.</p>
      <div className="ds-specimen" style={{ padding: 36, textAlign: 'center', background: '#040404' }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', gap: 14 }}>
          <MarathonMark size={56} label={false} glow={false}/>
          <div style={{
            fontSize: 22, fontWeight: 300, letterSpacing: 5.5, color: 'var(--text-primary)',
          }}>MARATHON</div>
        </div>
      </div>

      <h3 className="ds-h3">Marathon Intelligence horizon mark</h3>
      <p className="ds-p">For AI surfaces only. Documented in full under <a href="#icons" style={{ color: 'var(--teal-bright)' }}>Iconography</a>. The horizon mark never appears alongside the primary mark at the same hierarchy.</p>

      <h3 className="ds-h3">Application rules</h3>
      <div className="ds-grid cols-2">
        <Rule kind="do" text="Use the full lockup (disc + M + MARATHON) on high-ceremony surfaces: boot, About, App Store header, external attribution."/>
        <Rule kind="dont" text="Don't use the full lockup as a 64-dp app icon — the wordmark is unreadable. Use the mark alone instead."/>
        <Rule kind="do" text="Maintain clear space equal to one-quarter of the disc's diameter on every edge. No competing strokes inside this margin."/>
        <Rule kind="dont" text="Don't recolor, rotate, distort the disc, or change the M's letterform. Don't apply effects beyond the soft halo glow defined here."/>
      </div>
    </Section>
  );
}


// ---------- OVERVIEW ----------
function DSOverview() {
  return (
    <Section id="overview" eyebrow="Marathon Design System · v1.0" title="A sharp, gesture-first operating system" lede="Marathon is a dark, glass-and-neon mobile shell with a sharp engineering aesthetic. This document defines the visual and interaction system every Marathon surface inherits — from the lock screen to a third-party app. Marathon is dark by default, single-accent, and built for one-handed gestures.">
      <div className="ds-grid cols-3" style={{ marginTop: 36 }}>
        <PrincipleCard
          n="01" title="Engineered, not styled"
          body="Every surface earns its detail. 4-pixel corners, hairline strokes, restrained shadows. Nothing is decorative — every pixel does work."
        />
        <PrincipleCard
          n="02" title="Quiet by default, alive on intent"
          body="Marathon stays out of your way. Motion, glow, and color only appear when the system is doing something for you. Silence is the default state."
        />
        <PrincipleCard
          n="03" title="Distance over distraction"
          body="One accent color. One typeface. One radius. The Marathon mark is concentric horizons — eyes forward, not on the device."
        />
      </div>

      <h3 className="ds-h3" style={{ marginTop: 56 }}>What's in this system</h3>
      <div className="ds-grid cols-2">
        <SystemContents
          group="Foundations"
          items={['Color', 'Typography', 'Iconography', 'Spacing', 'Layout', 'Shape', 'Elevation', 'Motion']}
        />
        <SystemContents
          group="Components & Patterns"
          items={['Buttons & inputs', 'Cards & rows', 'Avatars, chips, badges', 'Bars: status, top, tab, dock', 'Now Bar & Active Frames', 'Sheets, dialogs, HUD', 'Hub, Spotlight, OOBE flows', 'Voice & tone, accessibility']}
        />
      </div>
    </Section>
  );
}

function PrincipleCard({ n, title, body }) {
  return (
    <div className="ds-specimen">
      <div className="mono" style={{ fontSize: 12, color: 'var(--teal-bright)', letterSpacing: 0.5 }}>{n}</div>
      <div style={{ fontSize: 18, fontWeight: 500, marginTop: 14, letterSpacing: -0.2, lineHeight: 1.25 }}>{title}</div>
      <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 10, lineHeight: 1.55 }}>{body}</div>
    </div>
  );
}

function SystemContents({ group, items }) {
  return (
    <div className="ds-specimen">
      <div className="ds-section-eyebrow" style={{ marginBottom: 12 }}>{group}</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        {items.map(i => (
          <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 14 }}>
            <Icon name="chevron_right" size={14} color="var(--teal-bright)"/>
            <span>{i}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ---------- COLOR ----------
function DSColor() {
  const tealRamp = [
    { token: '--teal-darkest', hex: '#006B5D', name: 'Teal · darkest' },
    { token: '--teal-dark',    hex: '#00897B', name: 'Teal · dark' },
    { token: '--teal',         hex: '#00BFA5', name: 'Teal · core' },
    { token: '--teal-bright',  hex: '#1DE9B6', name: 'Teal · bright' },
    { token: '--teal-glow',    hex: '#5DFFDC', name: 'Teal · glow' },
  ];
  const surfaces = [
    { token: '--elev-0', hex: '#040404', name: 'Elev 0 · Black' },
    { token: '--elev-1', hex: '#0A0A0B', name: 'Elev 1 · Deep' },
    { token: '--elev-2', hex: '#121213', name: 'Elev 2 · Surface' },
    { token: '--elev-3', hex: '#1C1C1D', name: 'Elev 3 · Raised' },
    { token: '--elev-4', hex: '#282829', name: 'Elev 4 · Card' },
    { token: '--elev-5', hex: '#353536', name: 'Elev 5 · Lifted' },
  ];
  const secondaries = [
    { token: '--sec-blue',   hex: '#3A6B9C', name: 'Sec · Blue',   use: 'Maps water, Sleep focus, message identity' },
    { token: '--sec-green',  hex: '#4A8A5E', name: 'Sec · Green',  use: 'Maps parks, financial signals' },
    { token: '--sec-amber',  hex: '#C89545', name: 'Sec · Amber',  use: 'Camera permission, "use caution"' },
    { token: '--sec-rose',   hex: '#A85968', name: 'Sec · Rose',   use: 'Mic permission, Move ring' },
    { token: '--sec-violet', hex: '#6B5D8F', name: 'Sec · Violet', use: 'Mentions, Linear, categorical' },
  ];
  const text = [
    { token: '--text-primary',   hex: '#F5F5F5', name: 'Primary',   use: '15px+ body, headings' },
    { token: '--text-secondary', hex: '#6A6A6A', name: 'Secondary', use: 'Subtitles, labels' },
    { token: '--text-tertiary',  hex: '#4A4A4A', name: 'Tertiary',  use: 'Chevrons, hints' },
    { token: '--text-hint',      hex: '#2A2A2A', name: 'Hint',      use: 'Empty placeholders' },
  ];

  return (
    <Section id="color" eyebrow="Foundation" title="Color" lede="Marathon is monochrome by discipline. One accent — teal — does all the work of action, focus, and brand. Neutrals do everything else. Secondary hues are heavily desaturated and reserved for places color carries meaning: real-world objects (water, parks), permission semantics, and identity.">
      <h3 className="ds-h3">Brand · Teal ramp</h3>
      <p className="ds-p">Five stops. The gradient <code>--teal-gradient</code> runs from <code>--teal-bright</code> down through <code>--teal-dark</code> on primary buttons, active tabs, focus rings, and the Marathon mark.</p>
      <div className="ds-grid cols-5">
        {tealRamp.map(s => <ColorSwatch key={s.token} {...s} dark/>)}
      </div>

      <h3 className="ds-h3">Surfaces · Elevation ramp</h3>
      <p className="ds-p">Six stops of near-black. Cards stack one step lighter than their parent. There is no light theme — Marathon is dark by design.</p>
      <div className="ds-grid cols-6">
        {surfaces.map(s => <ColorSwatch key={s.token} {...s}/>)}
      </div>

      <h3 className="ds-h3">Secondary · Muted hues</h3>
      <p className="ds-p">Used <b>only</b> where color carries semantic meaning. Never as decoration. Each is held at saturation ≈ 40 so it sits calmly beside teal without competing.</p>
      <div style={{ background: 'var(--elev-1)', border: '1px solid var(--w-04)', borderRadius: 4, padding: '4px 20px' }}>
        {secondaries.map(s => (
          <div key={s.token} className="ds-token-row">
            <div className="ds-token-chip" style={{ background: s.hex }}/>
            <div className="ds-token-name">{s.name}</div>
            <div className="ds-token-var">{s.token}</div>
            <div className="ds-token-hex">{s.hex}</div>
            <div className="ds-token-use">{s.use}</div>
          </div>
        ))}
      </div>

      <h3 className="ds-h3">Text</h3>
      <div style={{ background: 'var(--elev-1)', border: '1px solid var(--w-04)', borderRadius: 4, padding: '4px 20px' }}>
        {text.map(s => (
          <div key={s.token} className="ds-token-row">
            <div className="ds-token-chip" style={{ background: s.hex }}/>
            <div className="ds-token-name">{s.name}</div>
            <div className="ds-token-var">{s.token}</div>
            <div className="ds-token-hex">{s.hex}</div>
            <div className="ds-token-use">{s.use}</div>
          </div>
        ))}
      </div>

      <h3 className="ds-h3">Semantic</h3>
      <p className="ds-p">There is one reserved semantic color. Use it sparingly.</p>
      <div className="ds-grid cols-2">
        <ColorSwatch token="--error" hex="#EF4444" name="Error · destructive" caption="Decline call, delete confirmations. Not for warnings, not for indicators. Marathon has no warning/success/info hues — those states are surfaced with neutrals + teal accent."/>
        <ColorSwatch token="--teal-bright" hex="#1DE9B6" name="Action · accent" caption="Primary buttons, focus, active tab, brand. The only color the user maps to ‘something will happen if I press it’."/>
      </div>

      <h3 className="ds-h3">Application rules</h3>
      <div className="ds-grid cols-2">
        <Rule kind="do" text="Use teal exclusively for action — buttons that do something, the active tab, focus rings, the unread dot."/>
        <Rule kind="dont" text="Don't use teal for status (online, success). Use a neutral with text instead, e.g. ‘Synced’ in --text-secondary."/>
        <Rule kind="do" text="Use --sec-rose/blue/amber where color is semantic — permission types, health rings, real-world objects."/>
        <Rule kind="dont" text="Don't introduce new hues for decoration or to make a screen ‘feel different’. Section variety comes from layout and density, not hue."/>
      </div>
    </Section>
  );
}

function ColorSwatch({ token, hex, name, caption, dark }) {
  return (
    <div className="ds-swatch">
      <div className="ds-swatch-fill" style={{ background: hex, color: dark ? '#000' : '#fff' }}>
        {hex}
      </div>
      <div className="ds-swatch-meta">
        <div className="ds-swatch-name">{name}</div>
        <div className="ds-swatch-token">{token}</div>
        {caption && <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 6, lineHeight: 1.45 }}>{caption}</div>}
      </div>
    </div>
  );
}

function Rule({ kind, text }) {
  return (
    <div className={'ds-rule ' + kind}>
      <div className="ds-rule-label">{kind === 'do' ? 'Do' : "Don't"}</div>
      <div className="ds-rule-text">{text}</div>
    </div>
  );
}

// ---------- TYPOGRAPHY ----------
function DSType() {
  const scale = [
    { name: 'Display',    px: 96, weight: 200, tracking: -3,  sample: '9:41', mono: false },
    { name: 'Title L',    px: 48, weight: 200, tracking: -1.2, sample: 'Hub' },
    { name: 'Title 1',    px: 34, weight: 200, tracking: -0.8, sample: 'Settings' },
    { name: 'Title 2',    px: 28, weight: 300, tracking: -0.5, sample: 'Now Playing' },
    { name: 'Title 3',    px: 22, weight: 500, tracking: -0.3, sample: 'Concert · Bowery' },
    { name: 'Headline',   px: 17, weight: 600, tracking: -0.1, sample: 'Maya Chen' },
    { name: 'Body',       px: 17, weight: 400, tracking: 0,    sample: 'Heading out, see you at 8.' },
    { name: 'Callout',    px: 16, weight: 400, tracking: 0,    sample: 'Slate Notes wants Camera' },
    { name: 'Subhead',    px: 15, weight: 500, tracking: -0.1, sample: 'Marathon Intelligence' },
    { name: 'Footnote',   px: 13, weight: 400, tracking: 0.1,  sample: 'On-device · 0.4s' },
    { name: 'Caption',    px: 12, weight: 500, tracking: 0.2,  sample: 'Friday · December 5' },
    { name: 'Eyebrow',    px: 11, weight: 700, tracking: 1.4,  sample: 'ACTIVE NOW', upper: true },
    { name: 'Mono',       px: 13, weight: 500, tracking: 0.2,  sample: 'marathon-os.dev', mono: true },
  ];
  return (
    <Section id="type" eyebrow="Foundation" title="Typography" lede="Two families. One headline weight (200, airy). One body weight (400). One mono. The system reads as ‘engineered’: precision over decoration. Tabular numerics on timestamps, percentages, and currency.">
      <h3 className="ds-h3">Families</h3>
      <div className="ds-grid cols-2">
        <div className="ds-specimen">
          <div style={{ fontSize: 11, color: 'var(--teal-bright)', letterSpacing: 1.2, fontWeight: 700, textTransform: 'uppercase' }}>UI</div>
          <div style={{ fontSize: 72, fontWeight: 200, fontFamily: 'Sora', marginTop: 18, letterSpacing: -2, lineHeight: 1 }}>Sora</div>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 14 }}>Variable, 100–800. Used for every UI surface. Tracking is tight on display weights (-1px+), neutral on body.</div>
          <div style={{ marginTop: 14, padding: 12, background: 'var(--elev-2)', borderRadius: 4, fontFamily: 'Sora' }}>
            <span style={{ fontWeight: 200 }}>200</span>
            <span style={{ marginLeft: 14, fontWeight: 400 }}>400</span>
            <span style={{ marginLeft: 14, fontWeight: 500 }}>500</span>
            <span style={{ marginLeft: 14, fontWeight: 600 }}>600</span>
            <span style={{ marginLeft: 14, fontWeight: 700 }}>700</span>
          </div>
        </div>
        <div className="ds-specimen">
          <div style={{ fontSize: 11, color: 'var(--teal-bright)', letterSpacing: 1.2, fontWeight: 700, textTransform: 'uppercase' }}>Mono</div>
          <div style={{ fontSize: 56, fontWeight: 500, fontFamily: 'JetBrains Mono', marginTop: 18, letterSpacing: -1, lineHeight: 1 }}>JetBrains</div>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 14 }}>500. Used for timestamps, percentages, code, terminal-style status. Always tabular.</div>
          <div style={{ marginTop: 14, padding: 12, background: 'var(--elev-2)', borderRadius: 4, fontFamily: 'JetBrains Mono', fontSize: 13, color: 'var(--teal-bright)' }}>
            $ marathon init my-app<br/>
            <span style={{ color: 'var(--text-secondary)' }}>→ Scaffolded in 1.2s</span>
          </div>
        </div>
      </div>

      <h3 className="ds-h3">Scale</h3>
      <div style={{ background: 'var(--elev-1)', border: '1px solid var(--w-04)', borderRadius: 4, padding: '0 20px', marginTop: 14 }}>
        <div className="ds-type-row" style={{ color: 'var(--text-secondary)', fontSize: 11, letterSpacing: 1.2, textTransform: 'uppercase', fontWeight: 700 }}>
          <div>Sample</div><div>Style</div><div>Size</div><div>Weight</div><div>Used for</div>
        </div>
        {scale.map((t) => (
          <div key={t.name} className="ds-type-row">
            <div className="ds-type-sample" style={{
              fontSize: Math.min(t.px, 36),
              fontWeight: t.weight,
              letterSpacing: t.tracking + 'px',
              fontFamily: t.mono ? 'JetBrains Mono' : 'Sora',
              textTransform: t.upper ? 'uppercase' : 'none',
            }}>{t.sample}</div>
            <div className="ds-type-name">{t.name}</div>
            <div className="ds-type-cell">{t.px}px</div>
            <div className="ds-type-cell">{t.weight}</div>
            <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{usedFor(t.name)}</div>
          </div>
        ))}
      </div>

      <h3 className="ds-h3">Rules</h3>
      <div className="ds-grid cols-2">
        <Rule kind="do" text="Use weight 200 for any heading 24px+. The system reads as airy and engineered, not heavy."/>
        <Rule kind="dont" text="Don't pair 200-weight headings with 600-weight body. The contrast looks broken."/>
        <Rule kind="do" text="Set tabular numerics on times, percentages, durations, and prices. Use font-variant-numeric: tabular-nums."/>
        <Rule kind="dont" text="Don't use sentence-case for eyebrow labels (ACTIVE NOW, PRIORITY). They are UPPERCASE with 1.4 letter-spacing."/>
      </div>
    </Section>
  );
}

function usedFor(name) {
  return ({
    'Display': 'Lock screen clock, calculator readout',
    'Title L': 'Hub, large-title hero pages',
    'Title 1': 'App top bars (Settings, Mail)',
    'Title 2': 'Music now-playing track name',
    'Title 3': 'List section heroes, modal titles',
    'Headline': 'List row primary text',
    'Body': 'Default reading text',
    'Callout': 'Modal body, prompts',
    'Subhead': 'Form labels, sub-rows',
    'Footnote': 'Inline metadata',
    'Caption': 'Date headers, eyebrows',
    'Eyebrow': 'Section banners, status pills',
    'Mono': 'Numerics, code, terminal',
  })[name] || '';
}

// ---------- ICONOGRAPHY ----------
function DSIcons() {
  const names = ['phone', 'message', 'mail', 'globe', 'search', 'star', 'heart', 'bell', 'shield', 'cog', 'plus', 'check', 'chevron_right', 'wifi', 'bluetooth', 'battery', 'lock', 'mic', 'camera', 'calendar', 'clock', 'map_pin', 'note', 'archive', 'volume', 'brightness', 'flashlight', 'rotate', 'cast', 'hotspot', 'airplane', 'eye', 'share', 'refresh', 'fingerprint', 'sparkles'];
  return (
    <Section id="icons" eyebrow="Foundation" title="Iconography" lede="A single line-icon family (Phosphor Light, 1 px stroke). Plus one inline-defined custom mark — the Marathon horizon — which represents Marathon Intelligence. Never use the AI-sparkle glyph; it is design-system slop. App tile icons are bespoke per-app, 64-pixel squircles.">
      <h3 className="ds-h3">UI glyph family</h3>
      <p className="ds-p">36 of the icons available. All are Phosphor Light — 1 px stroke, round caps and joins, viewbox 24. Sized to fit the surface they sit in, never larger than the type they sit beside. The Bold weight is reserved for chrome that needs to hold weight at very small sizes (status bar, dock).</p>
      <div className="ds-grid cols-6" style={{ gap: 0, background: 'var(--elev-1)', border: '1px solid var(--w-04)', borderRadius: 4 }}>
        {names.map(n => (
          <div key={n} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center',
            gap: 10, padding: 18,
            borderRight: '1px solid var(--w-04)',
            borderBottom: '1px solid var(--w-04)',
          }}>
            <Icon name={n} size={22} color="var(--text-primary)"/>
            <div style={{ fontSize: 10, color: 'var(--text-secondary)', fontFamily: 'var(--font-mono)' }}>{n}</div>
          </div>
        ))}
      </div>

      <h3 className="ds-h3">Marathon Intelligence — the horizon mark</h3>
      <p className="ds-p">Three concentric arcs over a baseline. Reads as a sunrise, a radar pulse, or a wavefront — all signifying foresight and distance. Replaces the generic sparkle wherever AI features appear: Spotlight, Hub priority, the Intelligence app, the Marathon Intelligence settings row.</p>
      <div className="ds-grid cols-3">
        <div className="ds-specimen" style={{ textAlign: 'center', padding: 36 }}>
          <div style={{ width: 80, height: 80, margin: '0 auto', background: 'var(--teal-gradient)', borderRadius: 4, display: 'flex', alignItems: 'center', justifyContent: 'center', boxShadow: '0 0 24px var(--teal-halo)' }}>
            <Icon name="marathon" size={50} color="#000" strokeWidth={1.6}/>
          </div>
          <div className="ds-specimen-caption" style={{ textAlign: 'center', marginTop: 18 }}>Primary · on teal</div>
        </div>
        <div className="ds-specimen" style={{ textAlign: 'center', padding: 36 }}>
          <div style={{ width: 80, height: 80, margin: '0 auto', background: 'var(--elev-2)', border: '1px solid var(--teal-border)', borderRadius: 4, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="marathon" size={50} color="var(--teal-bright)" strokeWidth={1.6}/>
          </div>
          <div className="ds-specimen-caption" style={{ textAlign: 'center', marginTop: 18 }}>Secondary · teal on slate</div>
        </div>
        <div className="ds-specimen" style={{ textAlign: 'center', padding: 36 }}>
          <div style={{ width: 80, height: 80, margin: '0 auto', background: 'var(--elev-1)', borderRadius: 4, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon name="marathon" size={50} color="var(--text-secondary)" strokeWidth={1.6}/>
          </div>
          <div className="ds-specimen-caption" style={{ textAlign: 'center', marginTop: 18 }}>Tertiary · monochrome</div>
        </div>
      </div>

      <h3 className="ds-h3">App icons — system catalog</h3>
      <p className="ds-p">Each app gets a bespoke 64×64 squircle mark. Cohesion comes from shared treatment: dark base, single teal accent, one focal subject per icon. Never a gradient with a stock glyph centered in it.</p>
      <div className="ds-grid cols-6" style={{ gap: 18 }}>
        {[
          { name: 'Phone',     Comp: IconPhone },
          { name: 'Messages',  Comp: IconMessages },
          { name: 'Mail',      Comp: IconMail },
          { name: 'Browser',   Comp: IconBrowser },
          { name: 'Store',     Comp: IconStore },
          { name: 'Calc',      Comp: IconCalc },
          { name: 'Camera',    Comp: IconCamera },
          { name: 'Music',     Comp: IconMusic },
          { name: 'Calendar',  Comp: IconCalendar },
          { name: 'Clock',     Comp: IconClock },
          { name: 'Settings',  Comp: IconSettings },
          { name: 'Maps',      Comp: IconMaps },
          { name: 'Gallery',   Comp: IconGallery },
          { name: 'Notes',     Comp: IconNotes },
          { name: 'Contacts',  Comp: IconContacts },
          { name: 'Files',     Comp: IconFiles },
          { name: 'Intel.',    Comp: IconMI },
          { name: 'Wallet',    Comp: IconWallet },
          { name: 'Health',    Comp: IconHealth },
          { name: 'Weather',   Comp: IconWeather },
          { name: 'Voice',     Comp: IconVoice },
        ].map(({ name, Comp }) => (
          <div key={name} style={{ textAlign: 'center' }}>
            <Comp size={64}/>
            <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 8 }}>{name}</div>
          </div>
        ))}
      </div>

      <h3 className="ds-h3">Rules</h3>
      <div className="ds-grid cols-2">
        <Rule kind="do" text="Use Phosphor Light icons everywhere. Round caps + joins, single 1 px stroke. Pair with Sora 200/300 type weights."/>
        <Rule kind="dont" text="Don't mix in filled icons (Material filled, FontAwesome solid) or other line packs. The stroke style is consistent across the system."/>
        <Rule kind="do" text="Use the Marathon horizon mark wherever AI assistance surfaces. It's Marathon's brand identity for intelligence."/>
        <Rule kind="dont" text="Don't use the AI sparkle. Every product uses it; it's the design-system slop tax."/>
      </div>
    </Section>
  );
}

// ---------- APP ICON CONSTRUCTION ----------
// Self-contained guide for first-party app icon design. Grounded in
// iOS HIG (squircle, single focal subject, scale-down-from-master) and
// Material adaptive icons (foreground + background layers, safe zone)
// but Marathon-specific: dark-by-default, teal-only accent, native QML.
function DSAppIconConstruction() {
  return (
    <Section id="app-icons" eyebrow="Foundation" title="App icon construction" lede="A first-party Marathon app icon is not a logo. It's a 64-dp tile the user scans across at a glance. This page covers the anatomy, the grid, the rules of subject and color, and the QML reference implementation. Apple's HIG and Google's adaptive icons both inform the approach — Marathon adds its own dark-by-default constraints on top.">

      <h3 className="ds-h3">Anatomy</h3>
      <p className="ds-p">Every Marathon app icon is built on the same three-layer stack: <b>frame</b> (the squircle silhouette), <b>base</b> (a flat or subtly-graded background), <b>subject</b> (one focal element). Stroke and edge highlights are part of the frame — never drawn on the subject.</p>

      <div className="ds-specimen" style={{ padding: 36, display: 'flex', justifyContent: 'center' }}>
        <AppIconAnatomy/>
      </div>

      <h4 className="ds-h4">Spec</h4>
      <div className="ds-spec">
        <div className="ds-spec-row" style={{ gridTemplateColumns: '180px 1fr' }}>
          <div className="k">Master canvas</div><div className="v" style={{ textAlign: 'right' }}>192 × 192 dp · 3× the rendered size for crisp downscale</div>
        </div>
        <div className="ds-spec-row" style={{ gridTemplateColumns: '180px 1fr' }}>
          <div className="k">Rendered size</div><div className="v" style={{ textAlign: 'right' }}>64 × 64 dp · home grid, app drawer, store</div>
        </div>
        <div className="ds-spec-row" style={{ gridTemplateColumns: '180px 1fr' }}>
          <div className="k">Frame radius</div><div className="v" style={{ textAlign: 'right' }}>14 dp rendered · 42 dp on the master — superellipse</div>
        </div>
        <div className="ds-spec-row" style={{ gridTemplateColumns: '180px 1fr' }}>
          <div className="k">Safe area</div><div className="v" style={{ textAlign: 'right' }}>52 × 52 dp · 6 dp inset on every side</div>
        </div>
        <div className="ds-spec-row" style={{ gridTemplateColumns: '180px 1fr' }}>
          <div className="k">Subject area</div><div className="v" style={{ textAlign: 'right' }}>40 × 40 dp ideal · 12 dp gap from frame</div>
        </div>
        <div className="ds-spec-row" style={{ gridTemplateColumns: '180px 1fr' }}>
          <div className="k">Edge stroke</div><div className="v" style={{ textAlign: 'right' }}>1 dp inner highlight + 1 dp outer (double-edge)</div>
        </div>
        <div className="ds-spec-row" style={{ gridTemplateColumns: '180px 1fr' }}>
          <div className="k">Shadow</div><div className="v" style={{ textAlign: 'right' }}>0 8 16 -8 rgba(0,0,0,0.7) · soft drop, off the master</div>
        </div>
      </div>

      <h3 className="ds-h3">Grid construction</h3>
      <p className="ds-p">Lay every subject on the same 12-cell grid. Subjects align to the center two columns and two rows, and never bleed into the 6 dp outer margin. Apple's HIG calls this the "interior padding"; Google calls it the "safe area" — Marathon uses both terms interchangeably.</p>
      <div className="ds-grid cols-3">
        <div className="ds-specimen" style={{ padding: 24, display: 'flex', justifyContent: 'center' }}>
          <IconGridDiagram showSafe/>
          <div className="ds-specimen-caption" style={{ position: 'absolute' }}/>
        </div>
        <div className="ds-specimen" style={{ padding: 24, textAlign: 'center' }}>
          <div style={{ display: 'flex', gap: 14, justifyContent: 'center', flexWrap: 'wrap' }}>
            <IconPhone size={64}/>
            <IconMessages size={64}/>
            <IconMail size={64}/>
            <IconStore size={64}/>
          </div>
          <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 14, lineHeight: 1.5 }}>Subject sits inside the 40 × 40 dp ideal area. Edges of the subject never touch the squircle.</div>
        </div>
        <div className="ds-specimen" style={{ padding: 24, textAlign: 'center' }}>
          <div style={{ display: 'flex', gap: 14, justifyContent: 'center', flexWrap: 'wrap' }}>
            <IconClock size={64}/>
            <IconCamera size={64}/>
            <IconCalendar size={64}/>
            <IconMusic size={64}/>
          </div>
          <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 14, lineHeight: 1.5 }}>Different subjects, same grid alignment. They feel related at a glance because they share spatial framing.</div>
        </div>
      </div>

      <h3 className="ds-h3">Color and material</h3>
      <p className="ds-p">Marathon icons are dark-first. The base palette mirrors the surface ramp; the accent palette is teal alone, with rare use of one neutral muted secondary for signifier hues (red for Health, blue for Maps water). Never use more than two accent colors in one icon — and never use both teal and a secondary at the same intensity.</p>
      <div className="ds-grid cols-3">
        <RecipeCard title="Marathon primary" subtitle="Brand recognition · ‘this is us’">
          <div style={{ display: 'flex', gap: 8 }}>
            <Swatch hex="#1de9b6" label="--teal-bright"/>
            <Swatch hex="#040404" label="black"/>
          </div>
          <div className="ds-specimen-caption" style={{ marginTop: 12 }}>Used by: Store, Marathon Intelligence, any first-party brand icon.</div>
          <div style={{ marginTop: 12 }}><IconStore size={56}/></div>
        </RecipeCard>
        <RecipeCard title="Slate + teal accent" subtitle="Most icons · default recipe">
          <div style={{ display: 'flex', gap: 8 }}>
            <Swatch hex="#0a0a0b" label="--elev-1"/>
            <Swatch hex="#1de9b6" label="--teal-bright"/>
          </div>
          <div className="ds-specimen-caption" style={{ marginTop: 12 }}>Used by: Messages, Mail, Calc, Music, Calendar, Settings, Maps, Notes, Voice.</div>
          <div style={{ marginTop: 12 }}><IconMail size={56}/></div>
        </RecipeCard>
        <RecipeCard title="Slate + signifier" subtitle="One semantic secondary only">
          <div style={{ display: 'flex', gap: 8 }}>
            <Swatch hex="#0a0a0b" label="--elev-1"/>
            <Swatch hex="#a85968" label="--sec-rose"/>
          </div>
          <div className="ds-specimen-caption" style={{ marginTop: 12 }}>Used by: Health (rose heart). Reserved for cases where color carries meaning.</div>
          <div style={{ marginTop: 12 }}><IconHealth size={56}/></div>
        </RecipeCard>
      </div>

      <h3 className="ds-h3">Choosing a subject</h3>
      <p className="ds-p">The subject is the single thing the icon depicts. Marathon's rule is the same as iOS: <b>one element, one idea</b>. Avoid composite scenes. Avoid putting the company's stock glyph in a colored gradient and calling it an icon.</p>
      <div className="ds-grid cols-2">
        <Rule kind="do" text="Pick a subject that's instantly recognizable at 24dp. If you can squint at it and still know the app, it's right."/>
        <Rule kind="dont" text="Don't add a wordmark unless the icon IS the wordmark (e.g. Store uses an italic ‘M’; that's the entire subject)."/>
        <Rule kind="do" text="Use a single metaphor: vinyl groove for Music, envelope for Mail, calendar grid for Calendar. The literal object beats the abstract glyph."/>
        <Rule kind="dont" text="Don't pair a metaphor with a Phosphor glyph centered on top of it. The Music icon is a vinyl record — not a vinyl record with a Phosphor note inside."/>
        <Rule kind="do" text="Centre the subject on the canvas. Subjects sit on the cross hair of the 12-cell grid, not in the corner."/>
        <Rule kind="dont" text="Don't use literal photography or 3D renders. Marathon icons are vector, single-plane, with one focal element."/>
      </div>

      <h3 className="ds-h3">The "common mistakes" wall</h3>
      <p className="ds-p">Six bad ideas you'll be tempted to ship. Don't.</p>
      <div className="ds-grid cols-3">
        <BadIcon name="UI-glyph-on-gradient"  reason="An icon is not a square with a centered Phosphor glyph in front of a teal gradient. Design a subject."/>
        <BadIcon name="Two competing focal points" reason="Pick one focal element. If you can describe the icon as ‘X with a Y on top’ you're already wrong."/>
        <BadIcon name="Rainbow palette"         reason="More than two colors past the surface ramp + teal. Marathon icons are monochrome or teal + signifier — never both."/>
        <BadIcon name="Bevel and shine"         reason="No skeuomorphic gloss, no inner-shadow bevel, no faux 3D. Flat with one inner highlight is the rule."/>
        <BadIcon name="Stock glyph on white"    reason="No light backgrounds. Marathon is dark-first; an icon's frame is elev-1 to elev-3, never above."/>
        <BadIcon name="Off-brand color"         reason="Purple, lime, hot pink — these aren't Marathon's palette. Even when they ‘look nice’, they break the system."/>
      </div>

      <h3 className="ds-h3">Test at every size</h3>
      <p className="ds-p">Render your icon at 24, 32, 48, 56, and 64 dp and check each one. If the subject loses legibility at 24 dp, simplify until it doesn't.</p>
      <div className="ds-specimen" style={{ padding: 32 }}>
        <div style={{ display: 'flex', gap: 24, alignItems: 'flex-end', flexWrap: 'wrap' }}>
          {[24, 32, 48, 56, 64].map(sz => (
            <div key={sz} style={{ textAlign: 'center' }}>
              <IconMusic size={sz}/>
              <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 6, fontFamily: 'var(--font-mono)' }}>{sz} dp</div>
            </div>
          ))}
        </div>
      </div>

      <h3 className="ds-h3">QML reference implementation</h3>
      <p className="ds-p">First-party Marathon icons are vector — rendered at runtime in <code>QtQuick.Shapes</code> so they're crisp at any density. Bitmap PNGs are only generated for the Store listing and external attribution. The frame component (squircle + double-edge + shadow) is shared.</p>
      <CodeBlock>{`// MAppIcon.qml — the shared squircle frame.
// Drop the subject in as a child. The frame handles
// shape, border, inset highlight, and drop shadow.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import dev.marathon.UI 1.0

Rectangle {
    id: frame
    property color base: Theme.elev1
    property color subject: Theme.tealBright

    width: 64; height: 64
    color: "transparent"

    // Squircle silhouette
    Shape {
        anchors.fill: parent
        ShapePath {
            fillColor: frame.base
            strokeColor: "transparent"
            startX: 8; startY: 0
            PathLine { x: 56; y: 0 }
            PathArc { x: 64; y: 8; radiusX: 8; radiusY: 8 }
            PathLine { x: 64; y: 56 }
            PathArc { x: 56; y: 64; radiusX: 8; radiusY: 8 }
            PathLine { x: 8;  y: 64 }
            PathArc { x: 0;  y: 56; radiusX: 8; radiusY: 8 }
            PathLine { x: 0;  y: 8 }
            PathArc { x: 8;  y: 0; radiusX: 8; radiusY: 8 }
        }
    }
    // 1 dp inner highlight from above
    Rectangle {
        anchors.fill: parent
        radius: 14
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
    }
    // Subject slot
    Item {
        anchors.centerIn: parent
        width: 40; height: 40
        // — your subject goes here —
    }
    // Drop shadow rendered with MultiEffect
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowVerticalOffset: 8
        shadowBlur: 0.6
        shadowColor: Qt.rgba(0, 0, 0, 0.7)
    }
}`}</CodeBlock>

      <h3 className="ds-h3">Submission checklist</h3>
      <p className="ds-p">Before a first-party icon ships, run this list. If any answer is "no", revise.</p>
      <div className="ds-spec">
        {[
          ['One focal subject', 'a single recognizable element, not a composite scene'],
          ['Fits the 40 × 40 safe area', 'with 12 dp gap on every side'],
          ['Dark base', '--elev-0 through --elev-3 only — never light'],
          ['No more than two accent colors', 'teal + one neutral or signifier, max'],
          ['No UI glyph as the subject', 'design a custom subject; UI icons are not app icons'],
          ['Legible at 24 dp', 'test before signing off'],
          ['Vector source', 'QML / SVG — never PNG-only'],
          ['No literal wordmark', 'unless the wordmark IS the brand (e.g. Store)'],
        ].map(([t, d], i) => (
          <div key={i} className="ds-spec-row" style={{ gridTemplateColumns: '24px 1fr 1fr' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Icon name="check" size={14} color="var(--teal-bright)"/>
            </div>
            <div style={{ fontSize: 13, color: 'var(--text-primary)', fontWeight: 500 }}>{t}</div>
            <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{d}</div>
          </div>
        ))}
      </div>
    </Section>
  );
}

function AppIconAnatomy() {
  return (
    <svg width="320" height="340" viewBox="0 0 320 340">
      {/* TOP label — above the frame */}
      <text x="160" y="22" textAnchor="middle" fill="var(--text-secondary)" fontSize="11" letterSpacing="1.4" fontFamily="JetBrains Mono">FRAME · 64 dp · radius 14</text>

      {/* Frame (the squircle) */}
      <rect x="60" y="50" width="200" height="200" rx="44"
            fill="var(--elev-2)" stroke="var(--w-12)" strokeWidth="1"/>

      {/* Safe area */}
      <rect x="82" y="72" width="156" height="156" rx="30"
            fill="none" stroke="var(--teal-bright)" strokeWidth="0.8"
            strokeDasharray="4 4" opacity="0.7"/>

      {/* Subject area */}
      <rect x="110" y="100" width="100" height="100" rx="18"
            fill="rgba(0,191,165,0.15)" stroke="var(--teal-bright)" strokeWidth="0.8"/>

      {/* Subject sample */}
      <g transform="translate(160,150)">
        <circle cx="0" cy="0" r="32" fill="var(--teal-bright)"/>
        <text textAnchor="middle" dominantBaseline="central" fontSize="36" fontWeight="700" fill="#000" fontFamily="JetBrains Mono">M</text>
      </g>

      {/* Right-side tick labels — pointing into the rings */}
      {/* Safe-area label */}
      <line x1="238" y1="72" x2="270" y2="72" stroke="var(--teal-bright)" strokeWidth="0.6" opacity="0.7"/>
      <text x="274" y="69" fill="var(--teal-bright)" fontSize="10" fontFamily="JetBrains Mono">SAFE</text>
      <text x="274" y="82" fill="var(--text-secondary)" fontSize="9" fontFamily="JetBrains Mono">52 × 52</text>

      {/* Subject-area label */}
      <line x1="210" y1="100" x2="270" y2="135" stroke="var(--teal-bright)" strokeWidth="0.6" opacity="0.7"/>
      <text x="274" y="138" fill="var(--teal-bright)" fontSize="10" fontFamily="JetBrains Mono">SUBJECT</text>
      <text x="274" y="151" fill="var(--text-secondary)" fontSize="9" fontFamily="JetBrains Mono">40 × 40</text>

      {/* Bottom dimension line — measuring frame width */}
      <line x1="60" y1="276" x2="260" y2="276" stroke="var(--w-24)" strokeWidth="0.5"/>
      <line x1="60" y1="270" x2="60" y2="282" stroke="var(--w-24)" strokeWidth="0.5"/>
      <line x1="260" y1="270" x2="260" y2="282" stroke="var(--w-24)" strokeWidth="0.5"/>
      <text x="160" y="298" textAnchor="middle" fill="var(--text-secondary)" fontSize="10" fontFamily="JetBrains Mono">64 dp</text>

      {/* Inset arrow — showing the 6dp inset */}
      <line x1="60" y1="320" x2="82" y2="320" stroke="var(--teal-bright)" strokeWidth="0.6"/>
      <line x1="60" y1="316" x2="60" y2="324" stroke="var(--teal-bright)" strokeWidth="0.6"/>
      <line x1="82" y1="316" x2="82" y2="324" stroke="var(--teal-bright)" strokeWidth="0.6"/>
      <text x="96" y="324" fill="var(--teal-bright)" fontSize="10" fontFamily="JetBrains Mono">6 dp inset</text>
    </svg>
  );
}

function IconGridDiagram({ showSafe }) {
  return (
    <svg width="220" height="220" viewBox="0 0 220 220">
      <rect x="14" y="14" width="192" height="192" rx="44"
            fill="var(--elev-2)" stroke="var(--w-12)" strokeWidth="1"/>
      {/* 12-cell grid */}
      <g stroke="var(--teal-border)" strokeWidth="0.5" opacity="0.5">
        {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(n => (
          <g key={n}>
            <line x1={14 + n * 16} y1="14" x2={14 + n * 16} y2="206"/>
            <line x1="14" y1={14 + n * 16} x2="206" y2={14 + n * 16}/>
          </g>
        ))}
      </g>
      {/* Safe area highlight */}
      {showSafe && (
        <rect x="34" y="34" width="152" height="152" rx="28"
              fill="none" stroke="var(--teal-bright)" strokeWidth="1.2"
              strokeDasharray="4 4"/>
      )}
      {/* Center crosshair */}
      <line x1="110" y1="14" x2="110" y2="206" stroke="var(--teal-bright)" strokeWidth="0.6" opacity="0.7"/>
      <line x1="14" y1="110" x2="206" y2="110" stroke="var(--teal-bright)" strokeWidth="0.6" opacity="0.7"/>
      <circle cx="110" cy="110" r="3" fill="var(--teal-bright)"/>
    </svg>
  );
}

function Swatch({ hex, label }) {
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11 }}>
      <div style={{ width: 16, height: 16, borderRadius: 3, background: hex, border: '1px solid var(--w-12)' }}/>
      <span className="mono" style={{ color: 'var(--text-secondary)' }}>{label}</span>
    </div>
  );
}

function RecipeCard({ title, subtitle, children }) {
  return (
    <div className="ds-specimen" style={{ padding: 18 }}>
      <div style={{ fontSize: 14, fontWeight: 600, letterSpacing: -0.1 }}>{title}</div>
      <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 2 }}>{subtitle}</div>
      <div style={{ marginTop: 12 }}>{children}</div>
    </div>
  );
}

function BadIcon({ name, reason }) {
  return (
    <div style={{
      padding: 16, background: 'var(--elev-1)',
      border: '1px solid var(--w-04)', borderRadius: 4,
      borderLeft: '3px solid var(--error)',
    }}>
      <div style={{ fontSize: 11, fontWeight: 700, color: 'var(--error)', letterSpacing: 0.8, textTransform: 'uppercase' }}>Anti-pattern</div>
      <div style={{ fontSize: 13, fontWeight: 600, marginTop: 8 }}>{name}</div>
      <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 6, lineHeight: 1.5 }}>{reason}</div>
    </div>
  );
}

function CodeBlock({ children }) {
  return (
    <pre style={{
      background: 'var(--bb10-deep)',
      border: '1px solid var(--w-04)',
      borderRadius: 4,
      padding: '16px 18px',
      fontFamily: 'var(--font-mono)',
      fontSize: 12,
      lineHeight: 1.6,
      color: 'var(--text-primary)',
      overflow: 'auto',
      maxWidth: '100%',
      whiteSpace: 'pre',
      margin: '14px 0',
    }}>{children}</pre>
  );
}

// ---------- SPACING ----------
function DSSpacing() {
  const steps = [
    { token: '--xs',  px: 5,  use: 'Icon-to-text gap, dense chips' },
    { token: '--sm',  px: 10, use: 'Stacked metadata, card inner-stack' },
    { token: '--md',  px: 16, use: 'Default gutter, list item gap' },
    { token: '--lg',  px: 20, use: 'Section gutters, modal padding' },
    { token: '--xl',  px: 32, use: 'Page outer padding, modal margin' },
    { token: '--xxl', px: 40, use: 'Top-bar inner stack, large blocks' },
  ];
  return (
    <Section id="spacing" eyebrow="Foundation" title="Spacing" lede="A 5-point grid scaled to phone density. Every gap, padding, and offset in the system is a multiple of 5. This is BB10 lineage: nothing is by feel, everything is by ruler.">
      <h3 className="ds-h3">Scale</h3>
      <div style={{ background: 'var(--elev-1)', border: '1px solid var(--w-04)', borderRadius: 4, padding: '12px 24px' }}>
        <div className="ds-space-row" style={{ color: 'var(--text-secondary)', fontSize: 11, letterSpacing: 1.2, textTransform: 'uppercase', fontWeight: 700, borderBottom: '1px solid var(--w-04)' }}>
          <div>Token</div><div>Value</div><div>Bar</div><div>Common use</div>
        </div>
        {steps.map(s => (
          <div key={s.token} className="ds-space-row">
            <div className="ds-token-var">{s.token}</div>
            <div className="ds-token-hex">{s.px}px</div>
            <div className="ds-space-bar" style={{ width: s.px, opacity: 0.85 }}/>
            <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>{s.use}</div>
          </div>
        ))}
      </div>

      <h3 className="ds-h3">Touch targets</h3>
      <p className="ds-p">Marathon respects iOS HIG's 44px minimum and exceeds it for primary actions. Rule of thumb: anything tappable is 45px tall at minimum.</p>
      <div className="ds-grid cols-4">
        <SpecCallout n="--touch-min" v="45px" desc="Smallest tappable surface"/>
        <SpecCallout n="--touch-small" v="60px" desc="Compact buttons, chips"/>
        <SpecCallout n="--touch-med" v="70px" desc="Tab bar height, list rows"/>
        <SpecCallout n="--touch-large" v="90px" desc="Primary CTAs, dialer keys"/>
      </div>
    </Section>
  );
}

function SpecCallout({ n, v, desc }) {
  return (
    <div className="ds-specimen" style={{ padding: 18 }}>
      <div className="mono" style={{ fontSize: 11, color: 'var(--teal-bright)' }}>{n}</div>
      <div style={{ fontSize: 32, fontWeight: 200, letterSpacing: -0.8, marginTop: 6 }}>{v}</div>
      <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 6 }}>{desc}</div>
    </div>
  );
}

// ---------- LAYOUT ----------
function DSLayout() {
  return (
    <Section id="layout" eyebrow="Foundation" title="Layout" lede="A 390 × 844 phone canvas (iPhone 14 Pro scaled). Every surface lives between fixed system bars: status bar at top, dock or tab bar at bottom. Content respects safe areas; chrome glasses over them.">
      <div className="ds-grid cols-2" style={{ alignItems: 'flex-start' }}>
        <div className="ds-specimen ds-specimen-large" style={{ display: 'flex', justifyContent: 'center' }}>
          <LayoutDiagram/>
        </div>
        <div>
          <h4 className="ds-h4" style={{ marginTop: 0 }}>System bar heights</h4>
          <SpecRow k="Status bar" v="28 px"/>
          <SpecRow k="Top bar (with title)" v="96 px"/>
          <SpecRow k="Tab bar (bottom nav)" v="70 px"/>
          <SpecRow k="Dock (home gesture)" v="64 px"/>
          <SpecRow k="Now Bar (live activity)" v="36 px"/>
          <SpecRow k="Home indicator" v="8 px clear"/>

          <h4 className="ds-h4">Content padding</h4>
          <SpecRow k="Outer (left/right)" v="16–20 px"/>
          <SpecRow k="Section vertical" v="20–32 px"/>
          <SpecRow k="Stack gap (default)" v="14–16 px"/>

          <h4 className="ds-h4">Safe areas</h4>
          <p className="ds-p" style={{ marginTop: 4 }}>Top safe area is the 28px status bar. Bottom safe area depends on context — when a tab bar is present, content sits above it; when only the home indicator is shown, content sits above an 8px gutter.</p>
        </div>
      </div>
    </Section>
  );
}

function SpecRow({ k, v }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 0', borderBottom: '1px solid var(--w-04)' }}>
      <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>{k}</div>
      <div className="mono" style={{ fontSize: 12, color: 'var(--text-primary)' }}>{v}</div>
    </div>
  );
}

function LayoutDiagram() {
  return (
    <svg viewBox="0 0 390 844" width="270" height="585" style={{ background: '#040404', border: '1px solid #1a1a1a', borderRadius: 14 }}>
      <defs>
        <pattern id="dotgrid" width="10" height="10" patternUnits="userSpaceOnUse">
          <circle cx="0" cy="0" r="0.6" fill="rgba(255,255,255,0.08)"/>
        </pattern>
      </defs>
      <rect width="390" height="844" fill="url(#dotgrid)"/>
      {/* Status bar */}
      <rect x="0" y="0" width="390" height="28" fill="rgba(0,191,165,0.10)" stroke="var(--teal-border)" strokeWidth="0.5"/>
      <text x="195" y="18" textAnchor="middle" fill="var(--teal-bright)" fontSize="11" fontFamily="JetBrains Mono">28 · status</text>
      {/* Top bar */}
      <rect x="0" y="28" width="390" height="96" fill="rgba(0,191,165,0.06)" stroke="var(--teal-border)" strokeWidth="0.5"/>
      <text x="195" y="78" textAnchor="middle" fill="var(--teal-bright)" fontSize="13" fontFamily="JetBrains Mono">96 · top bar</text>
      {/* Content */}
      <text x="195" y="430" textAnchor="middle" fill="var(--text-secondary)" fontSize="11" fontFamily="JetBrains Mono">content area</text>
      <text x="195" y="450" textAnchor="middle" fill="var(--text-tertiary)" fontSize="11" fontFamily="JetBrains Mono">padding 16–20</text>
      {/* Tab bar */}
      <rect x="0" y="774" width="390" height="70" fill="rgba(0,191,165,0.06)" stroke="var(--teal-border)" strokeWidth="0.5"/>
      <text x="195" y="814" textAnchor="middle" fill="var(--teal-bright)" fontSize="13" fontFamily="JetBrains Mono">70 · tab bar</text>
      {/* Home indicator */}
      <rect x="128" y="830" width="134" height="4" rx="2" fill="rgba(255,255,255,0.4)"/>
    </svg>
  );
}

// ---------- SHAPE ----------
function DSShape() {
  return (
    <Section id="shape" eyebrow="Foundation" title="Shape" lede="Marathon is sharp. The default radius is 4 pixels. Pills are reserved for sliders and filter chips. Squircles (radius 14) are reserved for app icons. Avatars are perfect circles. Everything else is 4.">
      <h3 className="ds-h3">Radius scale</h3>
      <div className="ds-grid cols-5">
        <ShapeSpecimen size={72} radius={0}  name="None"     token="--r-none" use="Hairline rulers"/>
        <ShapeSpecimen size={72} radius={2}  name="Subtle"   token="--r-sm"   use="Inline tags"/>
        <ShapeSpecimen size={72} radius={4}  name="Default"  token="--r-md"   use="Cards, buttons, rows" emphasis/>
        <ShapeSpecimen size={72} radius={6}  name="Soft"     token="--r-lg"   use="Sheets, dialogs"/>
        <ShapeSpecimen size={72} radius={8}  name="Lifted"   token="--r-xl"   use="Map, gallery thumbs"/>
      </div>

      <h3 className="ds-h3">Special shapes</h3>
      <div className="ds-grid cols-3">
        <div className="ds-specimen" style={{ textAlign: 'center', padding: 32 }}>
          <div style={{ width: 80, height: 80, margin: '0 auto', borderRadius: 14, background: 'var(--teal-gradient)', boxShadow: '0 0 16px var(--teal-halo)' }}/>
          <div className="ds-specimen-caption" style={{ textAlign: 'center', marginTop: 14 }}>Squircle · app icons only</div>
          <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 6 }}>radius 14 — reserved for the 64px home-grid tiles</div>
        </div>
        <div className="ds-specimen" style={{ textAlign: 'center', padding: 32 }}>
          <div style={{ width: 80, height: 80, margin: '0 auto', borderRadius: '50%', background: 'var(--elev-3)', border: '1px solid var(--w-08)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontWeight: 500 }}>MC</div>
          <div className="ds-specimen-caption" style={{ textAlign: 'center', marginTop: 14 }}>Circle · avatars only</div>
          <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 6 }}>border-radius 50% — never used for chrome</div>
        </div>
        <div className="ds-specimen" style={{ textAlign: 'center', padding: 32 }}>
          <div style={{ display: 'inline-block', padding: '8px 18px', background: 'var(--teal-bright)', color: '#000', borderRadius: 999, fontSize: 13, fontWeight: 600 }}>Priority</div>
          <div className="ds-specimen-caption" style={{ textAlign: 'center', marginTop: 26 }}>Pill · filter chips, sliders</div>
          <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 6 }}>radius 999 — segmenting state</div>
        </div>
      </div>

      <div className="ds-grid cols-2">
        <Rule kind="do" text="Use the 4px default for everything that isn't an app icon, avatar, slider, or filter pill."/>
        <Rule kind="dont" text="Don't use 12, 14, 16, or 18px corners. They drift toward iOS softness — Marathon stays engineered."/>
      </div>
    </Section>
  );
}

function ShapeSpecimen({ size, radius, name, token, use, emphasis }) {
  return (
    <div className="ds-specimen" style={{ textAlign: 'center', padding: 24 }}>
      <div style={{
        width: size, height: size, margin: '0 auto',
        background: emphasis ? 'var(--teal-gradient)' : 'var(--elev-3)',
        border: '1px solid ' + (emphasis ? 'var(--teal-border)' : 'var(--w-08)'),
        borderRadius: radius,
        boxShadow: emphasis ? '0 0 16px var(--teal-halo)' : 'inset 0 1px 0 var(--w-06)',
      }}/>
      <div style={{ fontSize: 13, fontWeight: 600, marginTop: 14 }}>{name}</div>
      <div className="mono" style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{token} · {radius}px</div>
      <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 6 }}>{use}</div>
    </div>
  );
}

// ---------- ELEVATION ----------
function DSElevation() {
  const levels = [
    { name: 'Base', shadow: 'none',                                                                          z: 0 },
    { name: 'Resting card',  shadow: '0 6px 18px -8px rgba(0,0,0,0.6)',                                       z: 1 },
    { name: 'Active card',   shadow: '0 12px 30px -10px rgba(0,0,0,0.7), inset 0 1px 0 var(--w-06)',          z: 2 },
    { name: 'Sheet / dialog', shadow: '0 24px 60px -20px rgba(0,0,0,0.8), inset 0 1px 0 var(--w-08)',         z: 3 },
    { name: 'HUD overlay',   shadow: '0 12px 30px -10px rgba(0,0,0,0.7), 0 0 22px var(--teal-halo), inset 0 1px 0 var(--w-06)', z: 4 },
  ];
  return (
    <Section id="elevation" eyebrow="Foundation" title="Elevation" lede="Marathon doesn't use big drop shadows. Elevation is communicated through (a) one step lighter on the surface ramp, (b) a 1px inset highlight from above, and (c) a soft cast shadow that fades through negative Y-offset blur.">
      <div className="ds-grid cols-5">
        {levels.map(l => (
          <div key={l.name} style={{ padding: 32 }}>
            <div style={{
              width: '100%', aspectRatio: '1',
              background: 'var(--elev-' + Math.min(l.z + 1, 4) + ')',
              border: '1px solid var(--w-08)',
              borderRadius: 4,
              boxShadow: l.shadow,
            }}/>
            <div style={{ fontSize: 12, fontWeight: 600, marginTop: 12 }}>{l.name}</div>
            <div className="mono" style={{ fontSize: 10, color: 'var(--text-secondary)' }}>z = {l.z}</div>
          </div>
        ))}
      </div>
      <div className="ds-grid cols-2">
        <Rule kind="do" text="Pair a soft cast shadow with a subtle inset highlight on lifted surfaces. That single highlight does most of the work."/>
        <Rule kind="dont" text="Don't use opaque Material-style shadows. Marathon's shadows are dark on dark — colored shadows don't exist in this system."/>
      </div>
    </Section>
  );
}

// ---------- MOTION ----------
function DSMotion() {
  return (
    <Section id="motion" eyebrow="Foundation" title="Motion" lede="Motion in Marathon is functional, not decorative. Three durations, three easings. Anything bigger than ‘quick’ is reserved for spatial transitions (sheet, modal, screen).">
      <h3 className="ds-h3">Duration</h3>
      <div className="ds-grid cols-3">
        <SpecCallout n="--t-micro" v="80ms"  desc="Tap response, toggle thumb"/>
        <SpecCallout n="--t-quick" v="160ms" desc="Hover, color change, chip"/>
        <SpecCallout n="--t-mod"   v="240ms" desc="Sheet, modal, page transition"/>
      </div>

      <h3 className="ds-h3">Easing</h3>
      <div className="ds-grid cols-4">
        <EasingCard token="--ease-std"    fn="cubic-bezier(.2, 0, .2, 1)"     use="General UI"/>
        <EasingCard token="--ease-dec"    fn="cubic-bezier(0, 0, .2, 1)"      use="Entering"/>
        <EasingCard token="--ease-acc"    fn="cubic-bezier(.4, 0, 1, 1)"      use="Exiting"/>
        <EasingCard token="--ease-spring" fn="cubic-bezier(.34, 1.56, .64, 1)" use="Buttons, primary"/>
      </div>

      <h3 className="ds-h3">Gesture-first</h3>
      <p className="ds-p">Marathon is gesture-first by lineage (BlackBerry 10). Every primary navigation is reachable with a single thumb swipe:</p>
      <div className="ds-grid cols-2">
        <GestureCard
          name="Peek" arrow="↑"
          desc="Swipe up from the home indicator a short distance to peek at the Hub. Release to return; swipe up further to commit."
        />
        <GestureCard
          name="Flow" arrow="↑→"
          desc="Swipe up and right in one motion to enter Hub fully. Marathon's defining gesture — opens the unified inbox without a button press."
        />
        <GestureCard
          name="Active Frames" arrow="←"
          desc="Swipe left on the home grid to see running apps as live frames. Tap a frame to resume; press-and-hold to close."
        />
        <GestureCard
          name="Quick Settings" arrow="↓"
          desc="Pull down from the top edge to reveal sliders + tile grid. Pull further to access everything; release short for a peek."
        />
      </div>

      <div className="ds-grid cols-2">
        <Rule kind="do" text="Tie motion to causality. A press triggers a quick, a swipe-up triggers a moderate. The user always sees what their gesture caused."/>
        <Rule kind="dont" text="Don't animate decoratively. Idle screens stay still — animation is a signal, not a flourish."/>
      </div>
    </Section>
  );
}

function EasingCard({ token, fn, use }) {
  return (
    <div className="ds-specimen" style={{ padding: 18 }}>
      <div className="mono" style={{ fontSize: 11, color: 'var(--teal-bright)' }}>{token}</div>
      <div className="mono" style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 4, lineHeight: 1.5 }}>{fn}</div>
      <div style={{ fontSize: 12, color: 'var(--text-primary)', marginTop: 8 }}>{use}</div>
    </div>
  );
}

function GestureCard({ name, arrow, desc }) {
  return (
    <div className="ds-specimen">
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{
          width: 40, height: 40, borderRadius: 4,
          background: 'var(--elev-2)', border: '1px solid var(--teal-border)',
          color: 'var(--teal-bright)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 20, fontWeight: 300,
        }}>{arrow}</div>
        <div style={{ fontSize: 16, fontWeight: 500 }}>{name}</div>
      </div>
      <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 12, lineHeight: 1.55 }}>{desc}</div>
    </div>
  );
}

Object.assign(window, {
  Section, PrincipleCard, Rule, ColorSwatch,
  DSBrand, DSAppIconConstruction,
  MarathonMark,
  DSOverview, DSColor, DSType, DSIcons, DSSpacing,
  DSLayout, DSShape, DSElevation, DSMotion,
});
/* global React, Icon, Card, Row, Toggle, StatusBar, AppIconFrame, IconPhone, IconMessages, IconMail, IconBrowser, IconStore, IconCalc, IconCamera, IconMusic, IconCalendar, IconClock, IconSettings, IconMaps, IconGallery, IconNotes, IconContacts, IconFiles, IconMI, IconWallet, IconHealth, IconWeather, IconVoice */

// ============================================================
// Marathon Design System — Foundations sections
// ============================================================

