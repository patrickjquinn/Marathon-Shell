/* global React, Icon, Card, Row, Toggle, StatusBar, HomeIndicator, Dock, TopBar, TabBar, AppTile, APP_ICON_COMPONENTS, IconPhone, IconMessages, IconMI, IconCalendar, Section, Rule */

// ============================================================
// Marathon Design System — Components & Patterns
// ============================================================

// ---------- BUTTONS ----------
function DSButtons() {
  return (
    <Section id="buttons" eyebrow="Component" title="Buttons" lede="Three variants. Primary is teal gradient with black text — used at most once per surface. Secondary is the default action button. Ghost is a link with a hit-area. Destructive uses --error and never combines with primary on the same row.">
      <div className="ds-specimen" style={{ padding: 36, background: 'var(--elev-1)' }}>
        <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
          <button className="m-btn primary">Continue</button>
          <button className="m-btn secondary">Cancel</button>
          <button className="m-btn ghost">Skip</button>
          <button className="m-btn danger">Delete</button>
        </div>
        <div style={{ marginTop: 24, display: 'flex', gap: 12, flexWrap: 'wrap' }}>
          <button className="m-btn primary" style={{ height: 38, fontSize: 13 }}>Get app</button>
          <button className="m-btn secondary" style={{ height: 38, fontSize: 13 }}>Preview</button>
          <button className="m-btn primary" style={{ height: 50, padding: '0 40px', fontSize: 15 }}>Get started</button>
        </div>
      </div>

      <h3 className="ds-h3">Spec</h3>
      <div className="ds-spec">
        <div className="ds-spec-row"><div className="k">Default height</div><div className="v">45px</div><div className="desc">--touch-min</div></div>
        <div className="ds-spec-row"><div className="k">Compact</div><div className="v">38px</div><div className="desc">in dense rows</div></div>
        <div className="ds-spec-row"><div className="k">Large CTA</div><div className="v">50px</div><div className="desc">primary OOBE actions</div></div>
        <div className="ds-spec-row"><div className="k">Radius</div><div className="v">4px</div><div className="desc">--r-md</div></div>
        <div className="ds-spec-row"><div className="k">Padding (x)</div><div className="v">18px</div><div className="desc">22px+ for large</div></div>
        <div className="ds-spec-row"><div className="k">Font</div><div className="v">14/600 Sora</div><div className="desc">tight tracking</div></div>
        <div className="ds-spec-row"><div className="k">Press</div><div className="v">scale(0.96), 160ms spring</div><div className="desc">--ease-spring</div></div>
      </div>

      <div className="ds-grid cols-2">
        <Rule kind="do" text="Use at most one primary button per surface. If you need two equally-weighted actions, both should be secondary."/>
        <Rule kind="dont" text="Don't put a primary button next to a destructive button. Pair destructive with a secondary (Cancel)."/>
      </div>
    </Section>
  );
}

// ---------- INPUTS ----------
function DSInputs() {
  return (
    <Section id="inputs" eyebrow="Component" title="Inputs" lede="Text fields, toggles, sliders, segmented controls, and search. All share the same border-radius, focus treatment (1px teal border + 2px teal halo), and 45px default height.">
      <h3 className="ds-h3">Text field</h3>
      <div className="ds-specimen">
        <input className="m-input" placeholder="iMessage" defaultValue="" style={{ maxWidth: 360 }}/>
        <input className="m-input" placeholder="Search apps" style={{ maxWidth: 360, marginTop: 12 }}/>
        <input className="m-input" defaultValue="avery@marathon.id" style={{ maxWidth: 360, marginTop: 12, borderColor: 'var(--teal)', boxShadow: '0 0 0 2px var(--teal-halo), inset 0 1px 0 var(--w-02)' }}/>
        <div className="ds-specimen-caption">default · placeholder · focused</div>
      </div>

      <h3 className="ds-h3">Toggle</h3>
      <div className="ds-specimen">
        <div style={{ display: 'flex', gap: 24, alignItems: 'center' }}>
          <Toggle on={false}/>
          <Toggle on={true}/>
        </div>
        <div className="ds-specimen-caption">44 × 26 — thumb 20px, slides 18px on toggle. Glow only when on.</div>
      </div>

      <h3 className="ds-h3">Slider</h3>
      <div className="ds-specimen">
        <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 16px', borderRadius: 999, background: 'var(--elev-2)', border: '1px solid var(--w-04)' }}>
          <Icon name="brightness" size={20}/>
          <div style={{ flex: 1, position: 'relative', height: 4, background: 'var(--w-08)', borderRadius: 2 }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '62%', background: 'var(--teal-gradient)', borderRadius: 2 }}/>
            <div style={{ position: 'absolute', left: '62%', top: '50%', transform: 'translate(-50%, -50%)', width: 16, height: 16, borderRadius: '50%', background: '#fff', boxShadow: '0 2px 4px rgba(0,0,0,0.4), 0 0 8px var(--teal-halo)' }}/>
          </div>
        </div>
        <div className="ds-specimen-caption">Pill-shaped track for system sliders. Thumb is white with teal halo.</div>
      </div>

      <h3 className="ds-h3">Filter chips</h3>
      <div className="ds-specimen">
        <div style={{ display: 'flex', gap: 8 }}>
          {['All','Priority','Mentions','Mail','Work'].map((l,i) => (
            <div key={l} style={{
              padding: '7px 14px', borderRadius: 999,
              background: i === 0 ? 'var(--teal-bright)' : 'transparent',
              color: i === 0 ? '#000' : 'var(--text-secondary)',
              border: '1px solid ' + (i === 0 ? 'var(--teal-border)' : 'var(--w-08)'),
              fontSize: 13, fontWeight: 500,
            }}>{l}</div>
          ))}
        </div>
        <div className="ds-specimen-caption">Active chip is solid teal; inactive is hollow with subtle border.</div>
      </div>

      <h3 className="ds-h3">Search field</h3>
      <div className="ds-specimen">
        <div style={{
          height: 56, borderRadius: 4,
          background: 'rgba(13,13,14,0.85)',
          border: '1px solid var(--teal-border)',
          boxShadow: '0 0 18px var(--teal-halo), inset 0 1px 0 var(--w-06)',
          display: 'flex', alignItems: 'center', padding: '0 16px', gap: 12,
        }}>
          <Icon name="marathon" size={20} color="var(--teal-bright)"/>
          <span style={{ fontSize: 16 }}>concert friday</span>
          <span style={{ width: 2, height: 22, background: 'var(--teal-bright)', boxShadow: '0 0 6px var(--teal-glow)' }}/>
          <div style={{ flex: 1 }}/>
          <Icon name="mic" size={20} color="var(--text-secondary)"/>
        </div>
        <div className="ds-specimen-caption">Spotlight uses the Marathon mark prefix instead of a magnifier — AI-native search.</div>
      </div>
    </Section>
  );
}

// ---------- CARDS & ROWS ----------
function DSCardsRows() {
  return (
    <Section id="cards-rows" eyebrow="Component" title="Cards & list rows" lede="The two workhorses of Marathon. A card is one elevated container with a single thought; a row is one tappable line inside a stack. Both share the same hairline edge treatment.">
      <h3 className="ds-h3">Card anatomy</h3>
      <div className="ds-grid cols-2" style={{ alignItems: 'flex-start' }}>
        <Card style={{ padding: 18 }}>
          <div style={{ fontSize: 11, color: 'var(--teal-bright)', fontWeight: 600, letterSpacing: 0.5 }}>MARATHON INTELLIGENCE</div>
          <div style={{ fontSize: 17, lineHeight: 1.4, marginTop: 8 }}>
            Studio B in 22m — should I order your usual coffee for pickup en route?
          </div>
          <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
            <button className="m-btn primary" style={{ height: 36, padding: '0 14px', fontSize: 13 }}>Order</button>
            <button className="m-btn ghost" style={{ height: 36, padding: '0 14px', fontSize: 13 }}>Dismiss</button>
          </div>
        </Card>
        <div className="ds-spec">
          <div className="ds-spec-row"><div className="k">Background</div><div className="v">--elev-2</div><div className="desc">one step above parent</div></div>
          <div className="ds-spec-row"><div className="k">Border</div><div className="v">1px outer + 1px inner highlight</div><div className="desc">double-edge stroke</div></div>
          <div className="ds-spec-row"><div className="k">Radius</div><div className="v">4px</div><div className="desc">--r-md</div></div>
          <div className="ds-spec-row"><div className="k">Padding</div><div className="v">14–18px</div><div className="desc">content density dependent</div></div>
          <div className="ds-spec-row"><div className="k">Shadow</div><div className="v">0 6px 18px -8px rgba(0,0,0,0.6)</div><div className="desc">soft cast</div></div>
        </div>
      </div>

      <h3 className="ds-h3">List rows</h3>
      <div className="ds-grid cols-2" style={{ alignItems: 'flex-start' }}>
        <Card style={{ overflow: 'hidden' }}>
          <Row icon="wifi"       title="Wi-Fi"        value="Mesh-5G"/>
          <Row icon="bluetooth"  title="Bluetooth"    value="On"/>
          <Row icon="airplane"   title="Airplane Mode" toggle={false}/>
          <Row icon="brightness" title="Brightness"   subtitle="Adaptive · 62%"/>
        </Card>
        <div className="ds-spec">
          <div className="ds-spec-row"><div className="k">Min height</div><div className="v">60px</div><div className="desc">touch target ≥ HIG 44</div></div>
          <div className="ds-spec-row"><div className="k">Padding (vertical)</div><div className="v">14px</div><div className="desc">14×16 default</div></div>
          <div className="ds-spec-row"><div className="k">Icon container</div><div className="v">32 × 32</div><div className="desc">--elev-3 fill</div></div>
          <div className="ds-spec-row"><div className="k">Title</div><div className="v">15/500 Sora</div><div className="desc">-0.1 tracking</div></div>
          <div className="ds-spec-row"><div className="k">Subtitle</div><div className="v">13/400 Sora</div><div className="desc">--text-secondary</div></div>
          <div className="ds-spec-row"><div className="k">Value</div><div className="v">14/400 tabular</div><div className="desc">--text-secondary</div></div>
          <div className="ds-spec-row"><div className="k">Divider</div><div className="v">1px var(--w-04)</div><div className="desc">between siblings only</div></div>
        </div>
      </div>
    </Section>
  );
}

// ---------- BADGES, CHIPS, AVATARS ----------
function DSBadges() {
  return (
    <Section id="badges" eyebrow="Component" title="Badges, chips & avatars" lede="Atomic identifiers. Badges count things, chips label them, avatars represent people. Each has one job and one shape.">
      <h3 className="ds-h3">Counts</h3>
      <div className="ds-specimen">
        <div style={{ display: 'flex', gap: 18, alignItems: 'center' }}>
          <span className="m-badge">3</span>
          <span className="m-badge">12</span>
          <span className="m-badge">99+</span>
          <span style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--teal-bright)', boxShadow: '0 0 8px var(--teal-glow)' }}/>
          <span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>= unread indicator (no count)</span>
        </div>
        <div className="ds-specimen-caption">Teal-on-black for counts. A bare teal dot signals "new" without a number — quieter, used on rows.</div>
      </div>

      <h3 className="ds-h3">Status pills</h3>
      <div className="ds-specimen">
        <div style={{ display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>
          <span className="m-chip">EDITORS' PICK</span>
          <span className="m-chip muted">Free</span>
          <span className="m-chip muted">★ 4.7</span>
          <span style={{ padding: '3px 8px', background: 'var(--error)', color: '#fff', fontSize: 10, fontWeight: 700, borderRadius: 2, letterSpacing: 0.4 }}>P0</span>
          <span className="ds-badge teal">On-device</span>
        </div>
      </div>

      <h3 className="ds-h3">Avatars</h3>
      <div className="ds-specimen">
        <div style={{ display: 'flex', gap: 18, alignItems: 'center' }}>
          {[
            { l:'MC', bg:'#3a6b9c' },
            { l:'CR', bg:'#a85968' },
            { l:'L',  bg:'#6b5d8f' },
            { l:'GH', bg:'#040404', border:'1px solid var(--teal-border)' },
            { l:'AR', bg:'linear-gradient(135deg,#1a4a3e,#0a0a0b)', text:'var(--teal-bright)', border:'1px solid var(--teal-border)' },
          ].map((a, i) => (
            <div key={i} style={{
              width: 44, height: 44, borderRadius: '50%',
              background: a.bg,
              border: a.border || '1px solid var(--w-08)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: a.text || '#fff',
              fontSize: 14, fontWeight: 500,
            }}>{a.l}</div>
          ))}
        </div>
        <div className="ds-specimen-caption">Always circular. Monogram primary; bring in a muted secondary color only to disambiguate identity.</div>
      </div>
    </Section>
  );
}

// ---------- BARS ----------
function DSBars() {
  return (
    <Section id="bars" eyebrow="Component" title="System bars" lede="The four pieces of fixed chrome that anchor every screen. Status bar and home indicator are always present; top bar and tab bar (or dock) depend on the surface.">
      <BarSpec
        name="Status bar" h={28}
        spec={[
          ['Battery + %', 'left'],
          ['Clock or lock glyph', 'center'],
          ['Connectivity icons', 'right'],
        ]}
        sample={<div style={{ height: 28, background: 'var(--glass-titlebar)', backdropFilter: 'blur(8px)', borderBottom: '1px solid var(--border-glass)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 14px', fontSize: 12, fontVariantNumeric: 'tabular-nums', letterSpacing: 0.2 }}>
          <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}><Icon name="battery" size={16}/><span>71%</span></div>
          <div>11:42</div>
          <div style={{ display: 'flex', gap: 8 }}><Icon name="bluetooth" size={14}/><Icon name="phone_status" size={14}/><Icon name="wifi" size={15}/></div>
        </div>}
      />

      <BarSpec
        name="Top bar" h={96}
        spec={[
          ['Large-title text', '34/200 Sora'],
          ['Back chevron', 'left (optional)'],
          ['Actions', 'right (icons)'],
        ]}
        sample={<div style={{ position: 'relative', height: 96, background: 'var(--glass-titlebar)', backdropFilter: 'blur(18px)', borderBottom: '1px solid var(--border-glass)', display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', padding: '0 20px 16px' }}>
          <div style={{ fontSize: 34, fontWeight: 200, letterSpacing: -0.8 }}>Settings</div>
          <Icon name="search" size={22} color="var(--text-secondary)"/>
        </div>}
      />

      <BarSpec
        name="Tab bar" h={70}
        spec={[
          ['Up to 4 tabs', 'equal-width'],
          ['Active', 'teal gradient underline + glow'],
          ['Glyph + label', '20 + 12'],
        ]}
        sample={<TabBar active={1} tabs={[
          { icon:'inbox', label:'Inbox' },
          { icon:'star', label:'Starred' },
          { icon:'send', label:'Sent' },
          { icon:'archive', label:'All' },
        ]}/>}
        relative
      />

      <BarSpec
        name="Now Bar" h={36}
        spec={[
          ['Live activity strip', 'floats above status bar'],
          ['Glyph + label + sub', '26px circle, 11/9pt text'],
          ['Live indicator', 'visualizer or pulse'],
        ]}
        sample={<div style={{ position: 'relative', height: 60, padding: 12 }}>
          <div style={{ position: 'relative', height: 36, background: 'var(--glass-titlebar)', backdropFilter: 'blur(20px)', borderRadius: 4, border: '1px solid var(--border-glass-strong)', boxShadow: '0 4px 16px -4px rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', gap: 10, padding: '0 12px 0 6px' }}>
            <div style={{ width: 26, height: 26, borderRadius: '50%', background: 'var(--elev-3)', border: '1px solid var(--w-08)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--teal-bright)' }}><Icon name="music" size={13}/></div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 11, fontWeight: 600 }}>Modular Tides</div>
              <div style={{ fontSize: 9, color: 'var(--text-secondary)' }}>Avior · 1:48</div>
            </div>
            <div style={{ display: 'flex', gap: 2 }}>
              {[6,10,4,8,5].map((h,i) => <div key={i} style={{ width: 2, height: h, background: 'var(--teal-bright)', borderRadius: 1, opacity: 0.6 + (i%2)*0.4 }}/>)}
            </div>
          </div>
        </div>}
      />
    </Section>
  );
}

function BarSpec({ name, h, spec, sample, relative }) {
  return (
    <div style={{ marginTop: 32 }}>
      <h4 className="ds-h4" style={{ marginBottom: 12 }}>{name} · {h}px</h4>
      <div className="ds-grid cols-2" style={{ alignItems: 'flex-start' }}>
        <div className="ds-specimen" style={{ padding: 0, overflow: 'hidden', background: '#040404', position: relative ? 'relative' : 'static', height: relative ? h + 40 : 'auto' }}>
          {sample}
        </div>
        <div className="ds-spec">
          {spec.map(([k, v]) => (
            <div key={k} className="ds-spec-row" style={{ gridTemplateColumns: '1fr 1fr' }}>
              <div className="k">{k}</div>
              <div className="v" style={{ textAlign: 'right' }}>{v}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// ---------- ACTIVE FRAMES / TILE ----------
function DSActiveFrames() {
  return (
    <Section id="frames" eyebrow="Pattern" title="Active Frames" lede="Marathon's signature metaphor, carried forward from BlackBerry 10. The home isn't a wall of icons — it's a board of live, peeking frames of your running apps. Each frame shows current state and accepts a tap to resume.">
      <div className="ds-grid cols-2" style={{ alignItems: 'flex-start' }}>
        <div className="ds-specimen" style={{ padding: 24 }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            {[
              { title: 'Calendar', icon: 'calendar', badge: '3 today', tint: 'var(--teal-bright)' },
              { title: 'Music', icon: 'music', badge: 'Playing', tint: 'var(--teal-bright)' },
              { title: 'Health', icon: 'heart', badge: '2 of 3', tint: '#a85968' },
              { title: 'Messages', icon: 'message', badge: '3 unread', tint: '#7da3cb' },
            ].map(f => (
              <div key={f.title} style={{
                background: 'rgba(22,23,24,0.78)',
                borderRadius: 4,
                border: '1px solid var(--w-08)',
                padding: '10px 12px 14px',
                height: 130,
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <Icon name={f.icon} size={14} color={f.tint}/>
                  <div style={{ fontSize: 12, fontWeight: 600, flex: 1 }}>{f.title}</div>
                  <div style={{ fontSize: 10, color: 'var(--text-secondary)' }}>{f.badge}</div>
                </div>
                <div style={{ marginTop: 14, height: 60, background: 'var(--elev-2)', borderRadius: 4, opacity: 0.4 }}/>
              </div>
            ))}
          </div>
        </div>
        <div className="ds-spec">
          <div className="ds-spec-row"><div className="k">Tile size</div><div className="v">~163 × 158px</div><div className="desc">2-up grid, 16px outer</div></div>
          <div className="ds-spec-row"><div className="k">Background</div><div className="v">rgba(22,23,24,0.78) + blur 16</div><div className="desc">glass over wallpaper</div></div>
          <div className="ds-spec-row"><div className="k">Header height</div><div className="v">38px</div><div className="desc">icon + title + badge</div></div>
          <div className="ds-spec-row"><div className="k">Live region</div><div className="v">flex 1</div><div className="desc">app-specific content</div></div>
          <div className="ds-spec-row"><div className="k">Update rate</div><div className="v">≤ 1 Hz</div><div className="desc">no busy animation</div></div>
        </div>
      </div>

      <div className="ds-grid cols-2">
        <Rule kind="do" text="Each frame shows current state — three events, current song, ring progress, unread count. The frame is a window into the app's now."/>
        <Rule kind="dont" text="Don't pack frames with branding or marketing. The user already chose this app; show them what's happening."/>
      </div>
    </Section>
  );
}

// ---------- DIALOGS / SHEETS / HUD ----------
function DSDialogs() {
  return (
    <Section id="dialogs" eyebrow="Component" title="Dialogs, sheets & HUD" lede="Three layered surfaces above the app. Dialogs interrupt and ask. Sheets reveal context-dependent UI. The HUD shows transient feedback — volume, brightness, focus change. All three glass over their parent at the same blur depth (20px) so they read as one elevation tier.">
      <h3 className="ds-h3">Dialog</h3>
      <div className="ds-specimen" style={{ padding: 36, background: '#040404' }}>
        <Card style={{ padding: 0, overflow: 'hidden', maxWidth: 340, margin: '0 auto', background: 'var(--elev-2)', boxShadow: '0 24px 60px -20px rgba(0,0,0,0.8)' }} elev={4}>
          <div style={{ padding: '24px 22px 18px', display:'flex', gap: 16, alignItems:'center' }}>
            <div style={{ width: 56, height: 56, borderRadius: 14, background: 'linear-gradient(180deg,#fef4a8,#e8c843)' }}/>
            <div>
              <div style={{ fontSize: 18, fontWeight: 500, letterSpacing: -0.3 }}>Slate Notes</div>
              <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 2 }}>by Curlybrace Labs</div>
            </div>
          </div>
          <div style={{ borderTop: '1px solid var(--w-04)', borderBottom: '1px solid var(--w-04)' }}>
            <Row icon="storage" title="Storage" subtitle="Read and write your files" chev={false}/>
          </div>
          <div style={{ padding: '16px 22px 4px', fontSize: 14, lineHeight: 1.5 }}>
            Slate Notes wants to save attachments to your Documents folder.
          </div>
          <div style={{ padding: 16, display: 'flex', gap: 10 }}>
            <button className="m-btn secondary" style={{ flex: 1 }}>Deny</button>
            <button className="m-btn primary" style={{ flex: 1 }}>Allow</button>
          </div>
        </Card>
      </div>

      <h3 className="ds-h3">System HUD</h3>
      <div className="ds-specimen" style={{ padding: 36, background: '#040404' }}>
        <Card style={{ padding: '14px 18px', maxWidth: 340, margin: '0 auto', background: 'var(--glass-titlebar)', backdropFilter: 'blur(20px)', border: '1px solid var(--border-glass-strong)' }} elev={3}>
          <div style={{ display:'flex', alignItems:'center', gap: 12 }}>
            <Icon name="volume" size={22} color="var(--teal-bright)"/>
            <div style={{ fontSize: 13, color: 'var(--text-secondary)', letterSpacing: 0.4 }}>MEDIA VOLUME</div>
            <div style={{ marginLeft: 'auto', fontSize: 18, fontWeight: 300, fontVariantNumeric: 'tabular-nums' }}>62</div>
          </div>
          <div style={{ marginTop: 10, height: 6, background: 'var(--w-08)', borderRadius: 3, position: 'relative', overflow: 'hidden' }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '62%', background: 'var(--teal-gradient)', boxShadow: '0 0 12px var(--teal-glow)' }}/>
          </div>
        </Card>
      </div>

      <div className="ds-grid cols-2">
        <Rule kind="do" text="Always show the app's own icon at the top of a permission dialog. Identity first, scope second, action third."/>
        <Rule kind="dont" text="Don't put more than two actions in a dialog. If the question needs three, it's the wrong question."/>
      </div>
    </Section>
  );
}

// ---------- HUB & SPOTLIGHT ----------
function DSAISurfaces() {
  return (
    <Section id="ai-surfaces" eyebrow="Pattern" title="AI surfaces" lede="Marathon Intelligence shows up in three places: the Hub (priority filter + on-device triage), Spotlight (search → answer with citations), and as anticipatory cards in the assistant app. All three use the same building blocks: the Marathon mark, an inline-citation pattern, and source pills.">
      <h3 className="ds-h3">Inline citations</h3>
      <p className="ds-p">When Marathon synthesizes an answer from multiple sources, each fact gets a numbered superscript pill. The same numbers appear in a source list inside the same card. No external links surface unless the user taps a source.</p>
      <div className="ds-specimen" style={{ padding: 24 }}>
        <div style={{
          padding: 18,
          background: 'linear-gradient(135deg, rgba(0,191,165,0.12), rgba(0,191,165,0.03))',
          border: '1px solid var(--teal-border)',
          borderRadius: 4,
        }}>
          <div style={{ display:'flex', alignItems:'center', gap: 8, marginBottom: 12 }}>
            <div style={{ width: 22, height: 22, borderRadius: 4, background: 'var(--teal-gradient)', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#000' }}><Icon name="marathon" size={12}/></div>
            <div style={{ fontSize: 11, color: 'var(--teal-bright)', fontWeight: 600, letterSpacing: 0.5 }}>Marathon Intelligence</div>
            <div style={{ flex: 1 }}/>
            <div style={{ fontSize: 10, color: 'var(--text-tertiary)' }}>on-device</div>
          </div>
          <div style={{ fontSize: 15, lineHeight: 1.55 }}>
            Your concert at <b>The Bowery Ballroom</b> starts at <b>7:30 PM</b>
            <sup style={{ display:'inline-flex', alignItems:'center', justifyContent:'center', width: 16, height: 16, borderRadius: 4, background: 'var(--teal-bright)', color: '#000', fontSize: 10, fontWeight: 700, margin: '0 2px', verticalAlign: 'top' }}>1</sup>.
            Maya saved a spot near the back
            <sup style={{ display:'inline-flex', alignItems:'center', justifyContent:'center', width: 16, height: 16, borderRadius: 4, background: 'var(--teal-bright)', color: '#000', fontSize: 10, fontWeight: 700, margin: '0 2px', verticalAlign: 'top' }}>2</sup>.
          </div>
        </div>
      </div>

      <h3 className="ds-h3">Rules of intelligence</h3>
      <div className="ds-grid cols-2">
        <Rule kind="do" text="Always show 'on-device' if the answer was synthesized locally. It's Marathon's privacy promise — make it visible."/>
        <Rule kind="dont" text="Don't auto-act on suggestions. Marathon proposes; the user confirms. Anticipatory cards always have a dismiss action."/>
        <Rule kind="do" text="Use the Marathon mark in place of the AI sparkle, everywhere AI surfaces. It brands intelligence as a Marathon feature, not an industry tax."/>
        <Rule kind="dont" text="Don't bury sources. Every synthesized claim has a number, and every number resolves to a tappable source."/>
      </div>
    </Section>
  );
}

// ---------- VOICE & TONE ----------
function DSVoice() {
  return (
    <Section id="voice" eyebrow="Foundation" title="Voice & tone" lede="Marathon speaks like a quiet, technical friend. Sentences are short. Commands are direct. We never say 'oops' or use exclamation marks except in errors that genuinely deserve them.">
      <h3 className="ds-h3">Capitalization</h3>
      <div className="ds-grid cols-2">
        <Rule kind="do" text="Sentence case for buttons and titles: ‘Set up Touch ID’, ‘Get started’, ‘Continue’."/>
        <Rule kind="dont" text="Don't Title Case Random Things. It reads as marketing copy."/>
        <Rule kind="do" text="UPPER CASE with letter-spacing 1.2–1.6 for eyebrow labels: ACTIVE NOW, PRIORITY, EDITORS' PICK."/>
        <Rule kind="dont" text="Don't capitalize app names mid-sentence unless they're proper nouns (Marathon, Lucide)."/>
      </div>

      <h3 className="ds-h3">Voice samples</h3>
      <div className="ds-grid cols-2">
        <VoiceSample bad="Oops! Looks like we couldn't connect to Wi-Fi. Try again or check your network settings to continue with setup."
                    good="Couldn't connect. Pick a network, or skip and connect later."/>
        <VoiceSample bad="Great choice! Marathon Intelligence will use your data to provide personalized recommendations!"
                    good="Marathon Intelligence runs on-device. Nothing leaves this phone unless you share it."/>
        <VoiceSample bad="Are you sure you want to permanently delete this conversation? This action cannot be undone."
                    good="Delete this conversation? Can't be undone."/>
        <VoiceSample bad="Welcome to Marathon OS! We're so excited to have you on board. Let's get started by choosing a language!"
                    good="Choose your language. You can change either later."/>
      </div>
    </Section>
  );
}

function VoiceSample({ bad, good }) {
  return (
    <div className="ds-specimen" style={{ padding: 18 }}>
      <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--error)', letterSpacing: 1.2, textTransform: 'uppercase' }}>Don't</div>
      <div style={{ fontSize: 13, marginTop: 6, color: 'var(--text-secondary)', lineHeight: 1.5, textDecoration: 'line-through', textDecorationColor: 'rgba(239,68,68,0.4)' }}>{bad}</div>
      <div style={{ fontSize: 10, fontWeight: 700, color: 'var(--teal-bright)', letterSpacing: 1.2, textTransform: 'uppercase', marginTop: 14 }}>Do</div>
      <div style={{ fontSize: 13, marginTop: 6, color: 'var(--text-primary)', lineHeight: 1.5 }}>{good}</div>
    </div>
  );
}

// ---------- ACCESSIBILITY ----------
function DSAccess() {
  return (
    <Section id="a11y" eyebrow="Foundation" title="Accessibility" lede="Marathon's dark-by-default is accessible by default for high-contrast environments and OLED battery, but accessibility is more than contrast. Every Marathon surface is designed for one-handed operation, motion-reduced fallbacks, and screen reader semantics.">
      <h3 className="ds-h3">Contrast targets</h3>
      <div className="ds-grid cols-3">
        <ContrastCard fg="#F5F5F5" bg="#040404" ratio="19.8 : 1" name="Body text" rule="AAA"/>
        <ContrastCard fg="#6A6A6A" bg="#040404" ratio="5.3 : 1"  name="Secondary text" rule="AA"/>
        <ContrastCard fg="#1DE9B6" bg="#040404" ratio="13.2 : 1" name="Teal accent on dark" rule="AAA"/>
        <ContrastCard fg="#000000" bg="#1DE9B6" ratio="13.2 : 1" name="Black on teal button" rule="AAA"/>
        <ContrastCard fg="#A85968" bg="#040404" ratio="4.9 : 1"  name="Sec-rose on dark" rule="AA"/>
        <ContrastCard fg="#3A6B9C" bg="#040404" ratio="4.6 : 1"  name="Sec-blue on dark" rule="AA"/>
      </div>

      <h3 className="ds-h3">Other targets</h3>
      <div className="ds-spec">
        <div className="ds-spec-row"><div className="k">Touch target</div><div className="v">45 × 45 px min</div><div className="desc">exceeds iOS 44, Android 48</div></div>
        <div className="ds-spec-row"><div className="k">Focus ring</div><div className="v">1px teal + 2px teal halo</div><div className="desc">visible without color reliance</div></div>
        <div className="ds-spec-row"><div className="k">Motion reduce</div><div className="v">All motion ≤ 80ms</div><div className="desc">no parallax, no spring</div></div>
        <div className="ds-spec-row"><div className="k">Hit-area expansion</div><div className="v">+8px around tap target</div><div className="desc">invisible padding</div></div>
        <div className="ds-spec-row"><div className="k">Tabular numerics</div><div className="v">tnum on times, %, $</div><div className="desc">prevents reading-order shift</div></div>
        <div className="ds-spec-row"><div className="k">Color coding</div><div className="v">never sole signal</div><div className="desc">always paired with label or icon</div></div>
      </div>

      <div className="ds-grid cols-2">
        <Rule kind="do" text="Pair color with text or icon. The unread dot has a count beside it; the permission icon has a category label."/>
        <Rule kind="dont" text="Don't ship a state that's only color. ‘Online (green dot)’ is not a state — ‘Online · synced 2s ago’ is."/>
      </div>
    </Section>
  );
}

function ContrastCard({ fg, bg, ratio, name, rule }) {
  return (
    <div style={{ background: bg, border: '1px solid var(--w-04)', borderRadius: 4, padding: 20 }}>
      <div style={{ color: fg, fontSize: 18, fontWeight: 500 }}>Marathon</div>
      <div style={{ marginTop: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
        <div className="mono" style={{ color: 'var(--text-secondary)', fontSize: 11 }}>{ratio}</div>
        <div style={{ fontSize: 10, color: 'var(--teal-bright)', fontWeight: 700, letterSpacing: 1 }}>{rule}</div>
      </div>
      <div style={{ marginTop: 2, fontSize: 11, color: 'var(--text-secondary)' }}>{name}</div>
    </div>
  );
}

Object.assign(window, {
  DSButtons, DSInputs, DSCardsRows, DSBadges, DSBars,
  DSActiveFrames, DSDialogs, DSAISurfaces, DSVoice, DSAccess,
});
