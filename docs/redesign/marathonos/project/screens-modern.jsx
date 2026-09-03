/* global React, Icon, StatusBar, StatusBarLock, Dock, HomeIndicator, TopBar, TabBar, AppIcon, Card, Row, Toggle, SectionLabel, AppShell, MarathonAppMark, APP_ICONS, HomeIcon */

// ============================================================
// MARATHON OS — 2026 modernization layer
//   Active Frames home · Now Bar lock · Marathon Intelligence ·
//   Wallet · Focus Modes · Privacy dashboard · Passkey OOBE
// ============================================================

// ---------- ACTIVE FRAMES HOME (BB10's signature, modernized) ----------
// 2026 pass: tighter type, fixed-height frames so the grid aligns, simpler
// header, no AI suggestion banner competing with the live tiles.
function ActiveFramesHome() {
  return (
    <div className="phone no-scroll">
      <WallpaperSlateAurora/>
      <StatusBar time="11:42" battery={71}/>

      {/* Now Bar (Marathon's ambient activity strip) */}
      <NowBar variant="music"/>

      {/* Header — pure date + greeting, no other actions */}
      <div style={{
        position: 'absolute', top: 78, left: 20, right: 20,
      }}>
        <div style={{
          fontSize: 11, color: 'var(--text-secondary)',
          letterSpacing: 1.4, fontWeight: 600, textTransform: 'uppercase',
        }}>Friday · December 5</div>
        <div style={{
          fontSize: 26, fontWeight: 200, letterSpacing: -0.5, marginTop: 6,
          lineHeight: 1.1,
        }}>Good morning, Avery</div>
      </div>

      {/* Active Frames grid — 2x2 live tiles, fixed height for clean alignment */}
      <div style={{
        position: 'absolute', top: 168, left: 16, right: 16,
        display: 'grid', gridTemplateColumns: '1fr 1fr',
        gap: 10,
      }}>
        <ActiveFrame
          icon="calendar" iconColor="var(--teal-bright)"
          title="Calendar" badge="3 today">
          <div style={{ padding: '4px 12px 0', display: 'flex', flexDirection: 'column', gap: 6 }}>
            <FrameEvent t="12:00" name="Design review" hi/>
            <FrameEvent t="15:30" name="1:1 Devon"/>
            <FrameEvent t="19:30" name="Concert · Bowery"/>
          </div>
        </ActiveFrame>

        <ActiveFrame
          icon="music" iconColor="var(--teal-bright)"
          title="Music" badge="Playing">
          <div style={{
            padding: '8px 12px', display: 'flex', alignItems: 'center', gap: 10,
          }}>
            <div style={{
              width: 44, height: 44, borderRadius: 4,
              background: 'linear-gradient(135deg,#1a4a3e,#0d2620)',
              border: '1px solid var(--w-08)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0,
            }}>
              <Icon name="music" size={18} color="var(--teal-bright)"/>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{
                fontSize: 11, fontWeight: 600, color: 'var(--text-primary)',
                whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
              }}>Modular Tides</div>
              <div style={{
                fontSize: 10, color: 'var(--text-secondary)', marginTop: 1,
                whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
              }}>Avior</div>
              <div style={{
                marginTop: 6, height: 3, background: 'var(--w-08)',
                borderRadius: 2, position: 'relative',
              }}>
                <div style={{
                  position: 'absolute', left: 0, top: 0, bottom: 0, width: '42%',
                  background: 'var(--teal-gradient)', borderRadius: 2,
                }}/>
              </div>
            </div>
          </div>
        </ActiveFrame>

        <ActiveFrame
          icon="heart" iconColor="#a85968"
          title="Health" badge="2 of 3">
          <div style={{
            display:'flex', alignItems:'center', justifyContent:'center', height: 90,
          }}>
            <svg width="74" height="74" viewBox="0 0 74 74">
              {/* Move — muted rose */}
              <circle cx="37" cy="37" r="30" fill="none" stroke="rgba(168,89,104,0.18)" strokeWidth="5"/>
              <circle cx="37" cy="37" r="30" fill="none" stroke="#a85968" strokeWidth="5"
                strokeDasharray="188.5" strokeDashoffset="45" strokeLinecap="round"
                transform="rotate(-90 37 37)"/>
              {/* Exercise — teal */}
              <circle cx="37" cy="37" r="22" fill="none" stroke="rgba(0,191,165,0.15)" strokeWidth="5"/>
              <circle cx="37" cy="37" r="22" fill="none" stroke="#1de9b6" strokeWidth="5"
                strokeDasharray="138.2" strokeDashoffset="35" strokeLinecap="round"
                transform="rotate(-90 37 37)"/>
              {/* Stand — muted blue */}
              <circle cx="37" cy="37" r="14" fill="none" stroke="rgba(58,107,156,0.18)" strokeWidth="5"/>
              <circle cx="37" cy="37" r="14" fill="none" stroke="#3a6b9c" strokeWidth="5"
                strokeDasharray="87.9" strokeDashoffset="55" strokeLinecap="round"
                transform="rotate(-90 37 37)"/>
            </svg>
          </div>
        </ActiveFrame>

        <ActiveFrame
          icon="message" iconColor="#7da3cb"
          title="Messages" badge="3 unread">
          <div style={{ padding: '6px 12px 0', display: 'flex', flexDirection: 'column', gap: 5 }}>
            <FrameMsg name="Maya" line="Saved a spot near…"/>
            <FrameMsg name="Devon" line="Pushing 4.2.2"/>
            <FrameMsg name="Linear" line="MARS-204 assigned"/>
          </div>
        </ActiveFrame>
      </div>

      {/* Pinned dock — 4 apps in a clean row above the dock chrome */}
      <div style={{
        position: 'absolute', left: 16, right: 16, bottom: 88,
        display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
        justifyItems: 'center',
        columnGap: 4,
      }}>
        <AppTile name="phone"   label="Phone"/>
        <AppTile name="message" label="Messages"/>
        <AppTile name="mail"    label="Mail"/>
        <AppTile name="browser" label="Browser"/>
      </div>

      <Dock activePage={1} totalPages={4}/>
      <HomeIndicator/>
    </div>
  );
}

function ActiveFrame({ icon, iconColor, title, badge, children }) {
  return (
    <div style={{
      background: 'rgba(22,23,24,0.78)',
      backdropFilter: 'blur(16px)',
      WebkitBackdropFilter: 'blur(16px)',
      borderRadius: 4,
      border: '1px solid var(--w-08)',
      boxShadow: 'inset 0 1px 0 var(--w-06), 0 6px 18px -8px rgba(0,0,0,0.5)',
      height: 158,
      display: 'flex', flexDirection: 'column',
      overflow: 'hidden',
    }}>
      {/* Frame chrome — single tidy header row */}
      <div style={{
        padding: '12px 12px 6px',
        display: 'flex', alignItems: 'center', gap: 8,
      }}>
        <Icon name={icon} size={14} color={iconColor}/>
        <div style={{
          fontSize: 12, fontWeight: 600, color: 'var(--text-primary)',
          letterSpacing: 0.1,
          flex: 1,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{title}</div>
        <div style={{
          fontSize: 10, color: 'var(--text-secondary)', fontWeight: 500,
          whiteSpace: 'nowrap',
        }}>{badge}</div>
      </div>
      <div style={{ flex: 1, minHeight: 0 }}>{children}</div>
    </div>
  );
}

function FrameEvent({ t, name, hi }) {
  return (
    <div style={{ display:'flex', gap: 10, alignItems:'baseline', fontSize: 11 }}>
      <div style={{
        color: hi ? 'var(--teal-bright)' : 'var(--text-secondary)',
        minWidth: 34, fontWeight: 600, fontVariantNumeric: 'tabular-nums',
      }}>{t}</div>
      <div style={{
        color: 'var(--text-primary)',
        whiteSpace:'nowrap', overflow:'hidden', textOverflow:'ellipsis',
        flex: 1, fontWeight: hi ? 500 : 400,
      }}>{name}</div>
    </div>
  );
}

function FrameMsg({ name, line }) {
  return (
    <div style={{ fontSize: 11, lineHeight: 1.35, whiteSpace: 'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>
      <span style={{ color: 'var(--text-primary)', fontWeight: 600 }}>{name}</span>
      <span style={{ color: 'var(--text-secondary)' }}>{'  '}{line}</span>
    </div>
  );
}

// ---------- NOW BAR (ambient live-activity strip) ----------
function NowBar({ variant = 'music' }) {
  const variants = {
    music: { icon: 'music', label: 'Modular Tides', sub: 'Avior · 1:48', tint: 'var(--teal-bright)' },
    call:  { icon: 'phone', label: 'Maya Chen', sub: 'Call · 02:14', tint: 'var(--teal-bright)', pulse: true },
    nav:   { icon: 'map_pin', label: 'Studio B', sub: '0.4 mi · 7 min walk', tint: 'var(--teal-bright)' },
    timer: { icon: 'clock', label: 'Pasta timer', sub: '03:12 remaining', tint: 'var(--teal-bright)' },
  };
  const v = variants[variant];
  return (
    <div style={{
      position: 'absolute', top: 28, left: 12, right: 12,
      height: 36, background: 'var(--glass-titlebar)',
      backdropFilter: 'blur(20px)',
      borderRadius: 4,
      border: '1px solid var(--border-glass-strong)',
      boxShadow:
        '0 4px 16px -4px rgba(0,0,0,0.5), inset 0 1px 0 var(--w-04)',
      display: 'flex', alignItems: 'center', gap: 10, padding: '0 12px 0 6px',
      zIndex: 20,
    }}>
      <div style={{
        width: 26, height: 26, borderRadius: '50%',
        background: 'var(--elev-3)',
        border: '1px solid var(--w-08)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: v.tint,
        position: 'relative',
      }}>
        <Icon name={v.icon} size={13}/>
        {v.pulse && <div style={{
          position: 'absolute', inset: -2, borderRadius: '50%',
          border: '1px solid var(--teal-bright)', opacity: 0.5,
        }}/>}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 11, fontWeight: 600, lineHeight: 1, color: 'var(--text-primary)' }}>{v.label}</div>
        <div style={{ fontSize: 9, color: 'var(--text-secondary)', marginTop: 2 }}>{v.sub}</div>
      </div>
      {/* Mini visualizer / progress */}
      {variant === 'music' && (
        <div style={{ display: 'flex', gap: 2, alignItems: 'center', height: 12 }}>
          {[6, 10, 4, 8, 5].map((h, i) => (
            <div key={i} style={{
              width: 2, height: h, background: 'var(--teal-bright)', borderRadius: 1,
              opacity: 0.5 + (i % 2) * 0.5,
            }}/>
          ))}
        </div>
      )}
    </div>
  );
}

// ---------- MARATHON INTELLIGENCE (AI assistant) ----------
function MarathonIntelligence() {
  return (
    <AppShell>
      {/* Custom titlebar */}
      <div style={{
        height: 88, padding: '0 18px',
        background: 'var(--glass-titlebar)',
        backdropFilter: 'blur(14px)',
        borderBottom: '1px solid var(--border-glass)',
        display:'flex', alignItems: 'flex-end', paddingBottom: 14, gap: 12,
      }}>
        <div style={{
          width: 32, height: 32, borderRadius: 4,
          background: 'var(--teal-gradient)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#000',
          boxShadow: '0 0 18px var(--teal-halo), inset 0 1px 0 rgba(255,255,255,0.3)',
          border: '1px solid var(--teal-border)',
        }}><Icon name="zap" size={16}/></div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 22, fontWeight: 200, letterSpacing: -0.3, lineHeight: 1 }}>Marathon</div>
          <div style={{ fontSize: 12, color: 'var(--teal-bright)', marginTop: 4 }}>On-device · listening</div>
        </div>
        <Icon name="more" size={22} color="var(--text-secondary)"/>
      </div>

      <div style={{
        position: 'absolute', top: 116, left: 0, right: 0, bottom: 70,
        padding: '14px 16px', overflow: 'hidden',
      }}>
        {/* Smart suggestions row */}
        <SectionLabel>Anticipated for you</SectionLabel>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8, marginBottom: 18 }}>
          <SuggestCard
            tint="var(--teal-bright)" black icon="map_pin"
            t="Leave by 11:48"
            d="Studio B · light traffic"
          />
          <SuggestCard
            tint="#3a6b9c" icon="message"
            t="Reply to Maya"
            d="“On my way, see you in 10”"
          />
          <SuggestCard
            tint="#a85968" icon="heart"
            t="Stand goal almost done"
            d="2 more hours to close it"
          />
          <SuggestCard
            tint="var(--teal)" icon="calendar"
            t="Tomorrow is light"
            d="Block 90m for focus work?"
          />
        </div>

        {/* Conversation */}
        <SectionLabel>Earlier today</SectionLabel>
        <div style={{ display:'flex', flexDirection:'column', gap: 8, marginBottom: 14 }}>
          <AiBubble side="me">
            What's the fastest way to Studio B without taking the subway?
          </AiBubble>
          <AiBubble side="ai">
            Walking via Madison takes 7 minutes — that's actually faster than the C at this hour.
            Want me to start a quiet directions session?
          </AiBubble>
          <AiBubble side="ai" actions={['Start walking', 'Show route', 'Order coffee on route']}/>
        </div>

        {/* Input */}
        <div style={{
          position: 'absolute', left: 16, right: 16, bottom: 12,
          display: 'flex', gap: 8, alignItems: 'center',
        }}>
          <div style={{
            flex: 1, height: 44, borderRadius: 22,
            background: 'var(--bb10-surface)',
            border: '1px solid var(--w-08)',
            display: 'flex', alignItems: 'center', padding: '0 16px',
            color: 'var(--text-hint)', fontSize: 14,
            boxShadow: 'inset 0 1px 0 var(--w-02)',
          }}>Ask anything, or hold to speak…</div>
          <div style={{
            width: 44, height: 44, borderRadius: '50%',
            background: 'var(--teal-gradient)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#000',
            boxShadow: '0 0 18px var(--teal-halo), inset 0 1px 0 rgba(255,255,255,0.3)',
          }}><Icon name="mic" size={20}/></div>
        </div>
      </div>
    </AppShell>
  );
}

function SuggestCard({ tint, black, icon, t, d }) {
  return (
    <div style={{
      padding: 12, borderRadius: 4,
      background: 'var(--elev-2)',
      border: '1px solid var(--w-04)',
      boxShadow: 'inset 0 1px 0 var(--w-04), 0 0 0 1px var(--border-dark)',
      display:'flex', flexDirection:'column', gap: 8,
    }}>
      <div style={{
        width: 26, height: 26, borderRadius: 4, background: tint,
        display:'flex', alignItems:'center', justifyContent:'center',
        color: black ? '#000' : '#fff',
      }}>
        <Icon name={icon} size={14}/>
      </div>
      <div>
        <div style={{ fontSize: 13, fontWeight: 600, lineHeight: 1.2 }}>{t}</div>
        <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 3, lineHeight: 1.3 }}>{d}</div>
      </div>
    </div>
  );
}

function AiBubble({ side, children, actions }) {
  const me = side === 'me';
  if (actions) {
    return (
      <div style={{ alignSelf: 'flex-start', display: 'flex', gap: 6, flexWrap: 'wrap' }}>
        {actions.map((a, i) => (
          <div key={i} style={{
            padding: '6px 12px', borderRadius: 4,
            background: i === 0 ? 'var(--teal-gradient)' : 'var(--elev-2)',
            color: i === 0 ? '#000' : 'var(--text-primary)',
            border: '1px solid ' + (i === 0 ? 'var(--teal-border)' : 'var(--w-08)'),
            fontSize: 12, fontWeight: 600,
            boxShadow: i === 0 ? '0 0 10px rgba(0,191,165,0.3)' : 'inset 0 1px 0 var(--w-04)',
          }}>{a}</div>
        ))}
      </div>
    );
  }
  return (
    <div style={{ alignSelf: me ? 'flex-end' : 'flex-start', maxWidth: '85%' }}>
      <div style={{
        background: me ? 'var(--elev-3)' : 'transparent',
        color: 'var(--text-primary)',
        padding: me ? '8px 12px' : '4px 0',
        borderRadius: 4,
        fontSize: 13, lineHeight: 1.45,
        border: me ? '1px solid var(--w-08)' : 'none',
      }}>{children}</div>
    </div>
  );
}

// ---------- WALLET (passkeys, payments, IDs) ----------
function WalletApp() {
  return (
    <AppShell>
      <TopBar title="Wallet" actions={<>
        <Icon name="search" size={22} color="var(--text-secondary)"/>
        <div style={{
          width: 32, height: 32, borderRadius: 4, background: 'var(--teal-gradient)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#000',
        }}><Icon name="plus" size={18}/></div>
      </>}/>
      <div style={{ position: 'absolute', top: 116, left: 0, right: 0, bottom: 70, overflow: 'hidden', padding: '14px 16px' }}>
        {/* Stacked cards */}
        <div style={{ position: 'relative', height: 250, marginBottom: 18 }}>
          {[
            { c: 'linear-gradient(135deg, #1a4a3e 0%, #040404 100%)', label:'MARATHON ID', sub:'Verified · Avery Rhodes', t: 0 },
            { c: 'linear-gradient(135deg, var(--elev-3) 0%, var(--elev-1) 100%)', label:'BANK · DEBIT', sub:'•••• 4192', t: 14 },
            { c: 'linear-gradient(135deg, #1c1c1d 0%, #040404 100%)', label:'TRANSIT · METRO', sub:'Balance $24.50', t: 28 },
          ].map((card, i) => (
            <Card key={i} style={{
              position: 'absolute', left: 0, right: 0,
              top: i * 38, padding: 0, height: 180,
              background: card.c,
              border: '1px solid var(--w-08)',
              borderRadius: 4,
              boxShadow: '0 12px 24px -8px rgba(0,0,0,0.6), inset 0 1px 0 var(--w-12)',
              overflow: 'hidden',
            }} elev={3}>
              <div style={{ padding: '14px 18px', height: '100%', display: 'flex', flexDirection: 'column', justifyContent:'space-between' }}>
                <div style={{ display:'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                  <div>
                    <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.6)', letterSpacing: 1.5, fontWeight: 600 }}>{card.label}</div>
                    <div style={{ fontSize: 14, color: '#fff', marginTop: 4, fontWeight: 600 }}>{card.sub}</div>
                  </div>
                  {i === 0 && (
                    <div style={{
                      padding: '3px 8px', background: 'var(--teal-bright)', color: '#000',
                      fontSize: 10, fontWeight: 700, borderRadius: 4, letterSpacing: 0.5,
                    }}>VERIFIED</div>
                  )}
                </div>
                {i === 0 && (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                    <div style={{
                      width: 44, height: 44, borderRadius: '50%',
                      background: 'rgba(0,0,0,0.4)',
                      border: '1px solid var(--teal-border)',
                      display: 'flex', alignItems: 'center', justifyContent: 'center',
                      color: 'var(--teal-bright)', fontWeight: 500, fontSize: 16,
                    }}>AR</div>
                    <div>
                      <div style={{ fontSize: 13, color: '#fff', fontWeight: 600 }}>Avery Rhodes</div>
                      <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.5)' }}>marathon.id/avery</div>
                    </div>
                  </div>
                )}
              </div>
            </Card>
          ))}
        </div>

        <SectionLabel>Passkeys</SectionLabel>
        <Card style={{ overflow: 'hidden' }}>
          {[
            { n: 'github.com', d: 'avery@marathon.id', last: '2 days ago' },
            { n: 'linear.app',  d: 'avery@marathon.id', last: '5 hours ago' },
            { n: 'cloudflare.com', d: 'avery.rhodes',  last: 'last week' },
          ].map((p, i) => (
            <div key={i} className="m-row" style={{ padding: '12px 14px' }}>
              <div className="row-icon" style={{ background: 'var(--elev-3)', color: 'var(--teal-bright)' }}>
                <Icon name="shield" size={16}/>
              </div>
              <div className="row-text">
                <div className="row-title" style={{ fontSize: 14 }}>{p.n}</div>
                <div className="row-subtitle">{p.d} · used {p.last}</div>
              </div>
              <Icon name="chevron_right" size={16} color="var(--text-tertiary)"/>
            </div>
          ))}
        </Card>
      </div>
      <TabBar active={0} tabs={[
        { icon:'shield', label:'Cards' },
        { icon:'star',  label:'Passes' },
        { icon:'clock', label:'Activity' },
      ]}/>
    </AppShell>
  );
}

// ---------- FOCUS MODES ----------
function FocusModes() {
  const modes = [
    { n: 'Work',    d: 'Mon-Fri, 9-6',         icon:'monitor', tint: 'var(--teal-bright)', black:true, on: true },
    { n: 'Sleep',   d: 'Every night, 10pm',    icon:'note',    tint:'#3a6b9c', on: true, sub: 'active until 7 AM' },
    { n: 'Driving', d: 'On CarPlay connect',   icon:'map_pin', tint:'#c89545' },
    { n: 'Reading', d: 'Manual only',          icon:'note',    tint:'#6b5d8f' },
    { n: 'Workout', d: 'On heart rate ≥ 110',   icon:'heart',   tint:'#a85968' },
  ];
  return (
    <AppShell>
      <TopBar title="Focus" back actions={<Icon name="plus" size={22} color="var(--text-secondary)"/>}/>
      <div style={{ position: 'absolute', top: 116, left: 0, right: 0, bottom: 0, padding: '14px 16px', overflow: 'hidden' }}>
        {/* Active mode hero */}
        <Card style={{
          padding: 18, marginBottom: 18,
          background: 'linear-gradient(135deg, rgba(58,107,156,0.16), rgba(58,107,156,0.04))',
          border: '1px solid rgba(58,107,156,0.35)',
        }} elev={2}>
          <div style={{ display:'flex', alignItems:'center', gap: 14 }}>
            <div style={{
              width: 56, height: 56, borderRadius: '50%',
              background: 'rgba(58,107,156,0.18)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: '#7da3cb',
              boxShadow: '0 0 20px rgba(58,107,156,0.30), inset 0 1px 0 rgba(255,255,255,0.10)',
              border: '1px solid rgba(58,107,156,0.45)',
            }}><Icon name="note" size={26}/></div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 11, color: '#7da3cb', fontWeight: 600, letterSpacing: 1 }}>ACTIVE NOW</div>
              <div style={{ fontSize: 20, fontWeight: 500, marginTop: 2 }}>Sleep</div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Until tomorrow at 7:00 AM</div>
            </div>
            <button className="m-btn ghost" style={{ height: 32, padding: '0 12px', fontSize: 12 }}>End</button>
          </div>
          <div style={{ display:'flex', gap: 6, marginTop: 14, flexWrap:'wrap' }}>
            <div className="m-chip muted">DnD on</div>
            <div className="m-chip muted">Grayscale</div>
            <div className="m-chip muted">Hub muted</div>
            <div className="m-chip muted">Alarms only</div>
          </div>
        </Card>

        <SectionLabel>All modes</SectionLabel>
        <Card style={{ overflow: 'hidden' }}>
          {modes.map((m,i) => (
            <div key={i} className="m-row" style={{ padding: '14px 14px' }}>
              <div className="row-icon" style={{ background: m.tint, color: m.black ? '#000' : '#fff' }}>
                <Icon name={m.icon} size={16}/>
              </div>
              <div className="row-text">
                <div className="row-title">{m.n}</div>
                <div className="row-subtitle">{m.sub || m.d}</div>
              </div>
              <Toggle on={m.on}/>
            </div>
          ))}
        </Card>
      </div>
    </AppShell>
  );
}

// ---------- PRIVACY DASHBOARD ----------
function PrivacyDashboard() {
  return (
    <AppShell>
      <TopBar title="Privacy" back actions={<Icon name="info" size={22} color="var(--text-secondary)"/>}/>
      <div style={{ position: 'absolute', top: 116, left: 0, right: 0, bottom: 0, padding: '14px 16px', overflow: 'hidden' }}>
        {/* Hero ring */}
        <Card style={{ padding: 18, marginBottom: 16, display: 'flex', alignItems: 'center', gap: 18 }} elev={2}>
          <svg width="72" height="72" viewBox="0 0 72 72">
            <circle cx="36" cy="36" r="30" fill="none" stroke="var(--w-08)" strokeWidth="4"/>
            <circle cx="36" cy="36" r="30" fill="none" stroke="var(--teal)"
              strokeWidth="4" strokeDasharray="188.5" strokeDashoffset="56.5"
              strokeLinecap="round" transform="rotate(-90 36 36)"/>
            <text x="36" y="40" textAnchor="middle" fill="var(--text-primary)" fontSize="18" fontWeight="600" fontFamily="Sora">70</text>
          </svg>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 16, fontWeight: 600 }}>Privacy score · Strong</div>
            <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 3 }}>
              3 apps with broad permissions you might want to review.
            </div>
          </div>
        </Card>

        <SectionLabel>Recent access · last 24h</SectionLabel>
        <Card style={{ overflow: 'hidden', marginBottom: 16 }}>
          {[
            { n:'Camera',     a:'Slate Notes',  t:'10:14 · 4s',    icon:'camera',  tint:'#c89545' },
            { n:'Location',   a:'Maps',         t:'09:30 · 12m',   icon:'map_pin', tint:'var(--teal-bright)', black: true },
            { n:'Microphone', a:'Voice Memos',  t:'08:51 · 30s',   icon:'mic',     tint:'#a85968' },
            { n:'Contacts',   a:'Messages',     t:'08:40 · once',  icon:'user',    tint:'#3a6b9c' },
          ].map((p,i) => (
            <div key={i} className="m-row" style={{ padding: '12px 14px' }}>
              <div className="row-icon" style={{ background: p.tint, color: p.black ? '#000' : '#fff' }}>
                <Icon name={p.icon} size={14}/>
              </div>
              <div className="row-text">
                <div className="row-title" style={{ fontSize: 14 }}>{p.n}</div>
                <div className="row-subtitle">{p.a} · {p.t}</div>
              </div>
              <Icon name="chevron_right" size={16} color="var(--text-tertiary)"/>
            </div>
          ))}
        </Card>

        <SectionLabel>Identity</SectionLabel>
        <Card style={{ overflow: 'hidden' }}>
          <Row icon="shield" iconBg="rgba(0,191,165,0.18)" title="Passkeys & sign-in" subtitle="12 saved · all hardware-backed"/>
          <Row icon="lock" title="Hide my email" value="42 aliases"/>
          <Row icon="info" title="Tracking report" subtitle="0 cross-site trackers blocked today"/>
        </Card>
      </div>
    </AppShell>
  );
}

// ---------- OOBE — Passkey setup ----------
function OOBEPasskey() {
  return (
    <div className="phone no-scroll">
      <div style={{ position:'absolute', inset:0, background:'var(--bb10-black)' }}/>
      <div style={{ position: 'absolute', inset: 0, opacity: 0.4 }}><WallpaperSlateAurora/></div>
      <StatusBar time="—" battery={100} centerTime={false}/>

      <div style={{ padding: '50px 28px 24px' }}>
        <div style={{
          width: 48, height: 48, borderRadius: 4,
          background: 'var(--teal-gradient)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#000',
          boxShadow: '0 0 24px var(--teal-halo), inset 0 1px 0 rgba(255,255,255,0.3)',
        }}>
          <Icon name="shield" size={24}/>
        </div>
        <div style={{ fontSize: 36, fontWeight: 200, letterSpacing: -0.8, marginTop: 18, lineHeight: 1.05 }}>
          No more<br/>passwords
        </div>
        <div style={{ fontSize: 14, color: 'var(--text-secondary)', marginTop: 12, lineHeight: 1.55 }}>
          Marathon uses passkeys — cryptographic credentials tied to this device — so you can sign in to sites and apps with a glance.
        </div>
      </div>

      {/* Biometric prompt mockup */}
      <Card style={{
        position: 'absolute', top: 320, left: 24, right: 24,
        padding: 22, textAlign: 'center',
      }} elev={3}>
        <div style={{
          width: 84, height: 84, borderRadius: '50%',
          background: 'var(--bb10-deep)',
          border: '2px solid var(--teal-border)',
          margin: '0 auto',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: 'var(--teal-bright)',
          boxShadow: '0 0 24px var(--teal-halo), inset 0 1px 0 var(--w-06)',
          position: 'relative',
        }}>
          <svg width="36" height="40" viewBox="0 0 36 40" fill="none">
            <path d="M5 18a13 13 0 0 1 26 0v6c0 6.5-3 11-7 14M11 32V18a7 7 0 0 1 14 0v8c0 5-2 7-5 9M16 14v12a2 2 0 0 0 4 0v-8M22 30c-1 4-3 7-5 8" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/>
          </svg>
          <div style={{
            position: 'absolute', inset: -10, borderRadius: '50%',
            border: '1px solid var(--teal-border)',
            opacity: 0.4,
          }}/>
        </div>
        <div style={{ fontSize: 18, fontWeight: 500, marginTop: 18 }}>Set up Touch ID</div>
        <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 6, lineHeight: 1.4 }}>
          Place your finger on the sensor a few times so Marathon can learn your print.
        </div>
        <div style={{ display: 'flex', gap: 4, justifyContent: 'center', marginTop: 14 }}>
          {[1,1,1,0,0,0].map((on, i) => (
            <div key={i} style={{
              width: 24, height: 4, borderRadius: 2,
              background: on ? 'var(--teal-bright)' : 'var(--w-08)',
              boxShadow: on ? '0 0 6px var(--teal-glow)' : 'none',
            }}/>
          ))}
        </div>
        <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 8 }}>3 of 6 scans complete</div>
      </Card>

      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        padding: '14px 20px 26px',
        background: 'linear-gradient(180deg, transparent, var(--bb10-black) 30%)',
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      }}>
        <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Step 4 of 6</div>
        <button className="m-btn ghost" style={{ height: 44, padding: '0 18px', fontSize: 14 }}>Skip</button>
      </div>
      <HomeIndicator/>
    </div>
  );
}

// ---------- LOCK + Live Activity (call in progress) ----------
function LockNowBar() {
  return (
    <div className="phone no-scroll">
      <WallpaperSlateAurora/>
      <StatusBarLock battery={68}/>

      {/* Now Bar shown big on lock */}
      <div style={{
        position: 'absolute', top: 70, left: 16, right: 16,
        background: 'var(--glass-titlebar)',
        backdropFilter: 'blur(20px)',
        border: '1px solid var(--border-glass-strong)',
        borderRadius: 4,
        padding: '14px 16px',
        boxShadow: '0 12px 30px -10px rgba(0,0,0,0.5), inset 0 1px 0 var(--w-06)',
        display: 'flex', alignItems: 'center', gap: 14,
      }}>
        <div style={{
          width: 44, height: 44, borderRadius: '50%',
          background: 'linear-gradient(180deg,#1a4a3e,#0d2620)',
          border: '1px solid var(--teal-bright)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: 'var(--teal-bright)',
          position: 'relative',
        }}>
          <Icon name="phone" size={20}/>
          <div style={{
            position:'absolute', inset:-4, borderRadius:'50%',
            border: '1px solid var(--teal-bright)', opacity: 0.4,
          }}/>
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 11, color: 'var(--teal-bright)', letterSpacing: 0.8, fontWeight: 600 }}>CALL · 02:14</div>
          <div style={{ fontSize: 15, fontWeight: 600, marginTop: 2 }}>Maya Chen</div>
        </div>
        <div style={{
          width: 36, height: 36, borderRadius: '50%',
          background: 'var(--error)',
          display:'flex', alignItems:'center', justifyContent:'center',
          color: '#fff',
          transform: 'rotate(135deg)',
        }}><Icon name="phone" size={14}/></div>
      </div>

      {/* Clock */}
      <div style={{
        position: 'absolute', left: 0, right: 0, top: 220, textAlign: 'center',
      }}>
        <div style={{ fontSize: 76, fontWeight: 100, letterSpacing: -1.5, lineHeight: 1 }}>11:42 AM</div>
        <div style={{ marginTop: 12, fontSize: 14, color: 'var(--text-secondary)' }}>Friday, December 5</div>
      </div>

      {/* Health rings widget */}
      <Card style={{
        position: 'absolute', left: 16, right: 16, top: 410,
        padding: 14, display:'flex', alignItems:'center', gap: 14,
      }} elev={2}>
        <svg width="60" height="60" viewBox="0 0 60 60">
          <circle cx="30" cy="30" r="24" fill="none" stroke="rgba(168,89,104,0.18)" strokeWidth="4"/>
          <circle cx="30" cy="30" r="24" fill="none" stroke="#a85968"
            strokeWidth="4" strokeDasharray="150.8" strokeDashoffset="38"
            strokeLinecap="round" transform="rotate(-90 30 30)"/>
          <circle cx="30" cy="30" r="17" fill="none" stroke="rgba(0,191,165,0.15)" strokeWidth="4"/>
          <circle cx="30" cy="30" r="17" fill="none" stroke="#1de9b6"
            strokeWidth="4" strokeDasharray="106.8" strokeDashoffset="22"
            strokeLinecap="round" transform="rotate(-90 30 30)"/>
          <circle cx="30" cy="30" r="10" fill="none" stroke="rgba(58,107,156,0.18)" strokeWidth="4"/>
          <circle cx="30" cy="30" r="10" fill="none" stroke="#3a6b9c"
            strokeWidth="4" strokeDasharray="62.8" strokeDashoffset="14"
            strokeLinecap="round" transform="rotate(-90 30 30)"/>
        </svg>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 12, color: 'var(--text-secondary)', letterSpacing: 0.5 }}>ACTIVITY</div>
          <div style={{ fontSize: 16, fontWeight: 500, marginTop: 2 }}>Move 74% · Stand 79%</div>
          <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2 }}>1 ring left to close before bed</div>
        </div>
      </Card>

      {/* unlock hint */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 100, textAlign: 'center', color: 'var(--text-secondary)',
      }}>
        <Icon name="chevron_up" size={18}/>
        <div style={{ fontSize: 13, marginTop: 4 }}>Swipe up to unlock</div>
      </div>

      <Dock activePage={1} totalPages={0} showCenter={false}/>
      <HomeIndicator/>
    </div>
  );
}

// ---------- SPOTLIGHT — AI-native universal search, 2026 simplified ----------
// 2026 pass: one big AI answer w/ inline citations, one Top Hit card,
// one compact "More results" list. No multi-row chip noise, no clutter.
function Spotlight() {
  return (
    <div className="phone no-scroll">
      <WallpaperSlateAurora/>
      <div style={{
        position: 'absolute', inset: 0,
        background: 'linear-gradient(180deg, rgba(4,4,4,0.65), rgba(4,4,4,0.92))',
      }}/>
      <StatusBar time="11:42" battery={71}/>

      {/* Search field */}
      <div style={{
        position: 'absolute', top: 60, left: 16, right: 16,
        height: 56, borderRadius: 4,
        background: 'rgba(13,13,14,0.85)',
        backdropFilter: 'blur(20px)',
        WebkitBackdropFilter: 'blur(20px)',
        border: '1px solid var(--teal-border)',
        boxShadow: '0 8px 30px -8px rgba(0,0,0,0.7), 0 0 22px var(--teal-halo), inset 0 1px 0 var(--w-06)',
        display:'flex', alignItems: 'center', padding: '0 16px', gap: 12,
      }}>
        <Icon name="marathon" size={20} color="var(--teal-bright)"/>
        <span style={{ fontSize: 17, color: 'var(--text-primary)', fontWeight: 400 }}>concert friday</span>
        <span style={{
          width: 2, height: 22, background: 'var(--teal-bright)',
          boxShadow: '0 0 6px var(--teal-glow)',
        }}/>
        <div style={{ flex: 1 }}/>
        <Icon name="mic" size={20} color="var(--text-secondary)"/>
      </div>

      {/* Body — generous vertical rhythm */}
      <div style={{
        position: 'absolute', top: 144, left: 16, right: 16, bottom: 20,
        overflow: 'hidden',
        display: 'flex', flexDirection: 'column', gap: 16,
      }}>
        {/* AI Answer — the headline */}
        <div style={{
          padding: 18,
          background: 'linear-gradient(135deg, rgba(0,191,165,0.12), rgba(0,191,165,0.03) 75%)',
          border: '1px solid var(--teal-border)',
          borderRadius: 4,
          boxShadow: 'inset 0 1px 0 var(--w-04)',
        }}>
          <div style={{ display:'flex', alignItems:'center', gap: 8, marginBottom: 12 }}>
            <div style={{
              width: 22, height: 22, borderRadius: 4,
              background: 'var(--teal-gradient)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: '#000',
              boxShadow: '0 0 8px var(--teal-halo)',
            }}><Icon name="marathon" size={12}/></div>
            <div style={{
              fontSize: 11, color: 'var(--teal-bright)',
              fontWeight: 600, letterSpacing: 0.5,
            }}>Marathon Intelligence</div>
            <div style={{ flex: 1 }}/>
            <div style={{ fontSize: 10, color: 'var(--text-tertiary)' }}>on-device</div>
          </div>
          <div style={{ fontSize: 15, lineHeight: 1.55, color: 'var(--text-primary)' }}>
            Your concert at <b>The Bowery Ballroom</b> starts at <b>7:30 PM</b><Citation n={1}/>. Maya saved a spot near the back<Citation n={2}/>. The walk from the studio takes <b>14 minutes</b> — leave by <b>7:15</b><Citation n={3}/>.
          </div>
          {/* Sources */}
          <div style={{
            display:'flex', gap: 14, marginTop: 14, paddingTop: 14,
            borderTop: '1px solid var(--w-04)',
            fontSize: 12, color: 'var(--text-secondary)',
            flexWrap: 'wrap',
          }}>
            <SrcRef n={1} app="calendar" name="Calendar"/>
            <SrcRef n={2} app="message"  name="Maya Chen"/>
            <SrcRef n={3} app="map_pin"  name="Maps"/>
          </div>
        </div>

        {/* Top hit */}
        <div>
          <SpotLabel>Top hit</SpotLabel>
          <div style={{
            padding: 16, borderRadius: 4,
            background: 'rgba(22,23,24,0.75)',
            backdropFilter: 'blur(12px)',
            border: '1px solid var(--w-08)',
            display: 'flex', gap: 14, alignItems: 'center',
            marginTop: 8,
          }}>
            <div style={{
              width: 44, height: 44, borderRadius: 4,
              background: 'rgba(0,191,165,0.18)',
              border: '1px solid var(--teal-border)',
              display:'flex', alignItems:'center', justifyContent:'center',
              flexShrink: 0,
            }}>
              <Icon name="calendar" size={20} color="var(--teal-bright)"/>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 15, fontWeight: 500, color: 'var(--text-primary)', letterSpacing: -0.1 }}>Concert · Bowery</div>
              <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 2 }}>
                Tonight, 7:30 PM · 4 attendees
              </div>
            </div>
            <Icon name="chevron_right" size={18} color="var(--text-tertiary)"/>
          </div>
        </div>

        {/* More results */}
        <div>
          <SpotLabel>More results</SpotLabel>
          <div style={{ display:'flex', flexDirection: 'column', marginTop: 8 }}>
            <SpotRow icon="message" tint="#3a6b9c" title="Maya Chen" sub="iMessage · 11:38"/>
            <SpotRow icon="archive" tint="#a85968" title="concert-lineup.pdf" sub="Maya Chen · Wed"/>
            <SpotRow icon="globe"   tint="#4a8a5e" title="boweryballroom.com" sub="Dec 5 · doors 7:00"/>
          </div>
        </div>

        <div style={{ flex: 1 }}/>
        <div style={{
          fontSize: 11, color: 'var(--text-tertiary)',
          textAlign: 'center', letterSpacing: 0.3,
          paddingTop: 8, paddingBottom: 4,
        }}>Searches stay on this device</div>
      </div>
    </div>
  );
}

function Citation({ n }) {
  return (
    <sup style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      width: 16, height: 16, borderRadius: 4,
      background: 'var(--teal-bright)', color: '#000',
      fontSize: 10, fontWeight: 700,
      margin: '0 2px', verticalAlign: 'top',
    }}>{n}</sup>
  );
}

function SrcRef({ n, app, name }) {
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
      <span style={{
        width: 16, height: 16, borderRadius: 4,
        background: 'var(--teal-bright)', color: '#000',
        fontSize: 10, fontWeight: 700,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>{n}</span>
      <Icon name={app} size={12} color="var(--text-secondary)"/>
      <span style={{ color: 'var(--text-primary)', fontWeight: 500 }}>{name}</span>
    </div>
  );
}

function SpotLabel({ children }) {
  return (
    <div style={{
      fontSize: 11, fontWeight: 600, letterSpacing: 1.2,
      color: 'var(--text-secondary)', textTransform: 'uppercase',
    }}>{children}</div>
  );
}

function SpotRow({ icon, tint, title, sub }) {
  return (
    <div style={{
      display: 'flex', gap: 14, padding: '12px 4px',
      borderTop: '1px solid var(--w-04)',
      alignItems: 'center',
    }}>
      <div style={{
        width: 36, height: 36, borderRadius: 4, background: tint,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#fff', flexShrink: 0,
      }}>
        <Icon name={icon} size={16}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 14, fontWeight: 500, color: 'var(--text-primary)',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{title}</div>
        <div style={{
          fontSize: 12, color: 'var(--text-secondary)', marginTop: 2,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{sub}</div>
      </div>
      <Icon name="chevron_right" size={16} color="var(--text-tertiary)"/>
    </div>
  );
}

Object.assign(window, {
  ActiveFramesHome, NowBar,
  MarathonIntelligence, WalletApp, FocusModes, PrivacyDashboard,
  OOBEPasskey, LockNowBar, Spotlight,
});
