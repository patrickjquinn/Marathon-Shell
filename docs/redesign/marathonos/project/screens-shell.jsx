/* global React, Icon, StatusBar, StatusBarLock, Dock, HomeIndicator, TopBar, TabBar, AppIcon, Card, Row, Toggle, SectionLabel, WallpaperSlateAurora, WallpaperCarbon, WallpaperIndigoDusk, AppTile, APP_ICON_COMPONENTS */

// ============================================================
// MARATHON shell screens
//   Lock, LockMedia, Home (3 pages), AppDrawer, TaskSwitcher,
//   QuickSettings, Hub, PermissionDialog, IncomingCall, Keyboard,
//   SystemHUD, BootSplash
// ============================================================

// ---------- BootSplash ----------
function BootSplash() {
  return (
    <div className="phone no-scroll" style={{ background: '#000' }}>
      <div style={{
        position: 'absolute', inset: 0, display: 'flex',
        alignItems: 'center', justifyContent: 'center', flexDirection: 'column',
        gap: 28,
      }}>
        <div style={{
          width: 96, height: 96, borderRadius: '50%',
          background: 'linear-gradient(180deg, #1de9b6 0%, #00bfa5 100%)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 0 40px rgba(0,191,165,0.45), inset 0 1px 0 rgba(255,255,255,0.3)',
          border: '1px solid rgba(255,255,255,0.15)',
        }}>
          <svg width="56" height="56" viewBox="0 0 56 56" fill="none">
            <path d="M10 44V14h6l12 18 12-18h6v30h-6V24L28 40 16 24v20z" fill="#000"/>
          </svg>
        </div>
        <div style={{
          letterSpacing: 6, fontSize: 14, fontWeight: 300, color: '#fff', textTransform: 'uppercase',
        }}>marathon</div>
        <div style={{ position: 'absolute', bottom: 110, left: 0, right: 0, textAlign: 'center' }}>
          <div style={{
            display: 'inline-block', width: 140, height: 2,
            background: 'var(--w-08)', borderRadius: 1, overflow: 'hidden', position: 'relative',
          }}>
            <div style={{
              position: 'absolute', inset: 0, width: '60%',
              background: 'var(--teal-gradient)',
              borderRadius: 1,
            }}/>
          </div>
        </div>
      </div>
    </div>
  );
}

// ---------- LOCK SCREEN (clean) ----------
function LockScreen() {
  return (
    <div className="phone no-scroll">
      <WallpaperSlateAurora/>
      <StatusBarLock battery={70}/>

      {/* Clock cluster */}
      <div style={{
        position: 'absolute', left: 0, right: 0, top: 190,
        textAlign: 'center', zIndex: 5,
      }}>
        <div style={{
          position: 'relative', display: 'inline-block',
        }}>
          <div style={{
            position: 'absolute', inset: -28,
            background: 'radial-gradient(ellipse at center, rgba(0,191,165,0.20), transparent 65%)',
            filter: 'blur(8px)',
            zIndex: -1,
          }}/>
          <div style={{
            fontSize: 84, fontWeight: 100, letterSpacing: -2,
            color: 'var(--text-primary)', lineHeight: 1,
            textShadow: '0 1px 0 rgba(0,0,0,0.5)',
          }}>7:08 PM</div>
        </div>
        <div style={{
          marginTop: 16, fontSize: 15, color: 'var(--text-secondary)',
          fontWeight: 500, letterSpacing: 0.3,
        }}>Friday, December 5</div>
      </div>

      {/* Notification stack */}
      <div style={{
        position: 'absolute', left: 18, right: 18, top: 420,
        display: 'flex', flexDirection: 'column', gap: 8,
      }}>
        <Card style={{ padding: '12px 14px' }} elev={2}>
          <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
            <div style={{
              width: 32, height: 32, borderRadius: 4,
              background: 'linear-gradient(180deg,var(--elev-3),var(--elev-4))',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0,
            }}>
              <Icon name="message" size={16}/>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <div style={{ fontSize: 13, fontWeight: 600 }}>Maya Chen</div>
                <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>now</div>
              </div>
              <div style={{ fontSize: 13, color: 'var(--text-primary)', marginTop: 2 }}>
                Heading out, see you at 8 — saved a spot near the back.
              </div>
            </div>
          </div>
        </Card>
        <Card style={{ padding: '12px 14px' }} elev={2}>
          <div style={{ display: 'flex', gap: 12, alignItems: 'flex-start' }}>
            <div style={{
              width: 32, height: 32, borderRadius: 4,
              background: 'linear-gradient(180deg,#0d0d0e,#1a1b1c)',
              border: '1px solid var(--teal-border)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0, color: 'var(--teal-bright)',
            }}>
              <Icon name="calendar" size={16}/>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <div style={{ fontSize: 13, fontWeight: 600 }}>Calendar</div>
                <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>in 22m</div>
              </div>
              <div style={{ fontSize: 13, color: 'var(--text-primary)', marginTop: 2 }}>
                Design review — Studio B
              </div>
            </div>
          </div>
        </Card>
        <Card style={{ padding: '10px 14px' }} elev={2}>
          <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
            <div style={{
              width: 28, height: 28, borderRadius: 4,
              background: 'var(--elev-3)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0,
            }}>
              <Icon name="mail" size={14}/>
            </div>
            <div style={{ flex: 1, fontSize: 12, color: 'var(--text-secondary)' }}>
              <span style={{ color: 'var(--text-primary)' }}>3 more notifications</span> · earlier today
            </div>
            <Icon name="chevron_down" size={14} color="var(--text-tertiary)"/>
          </div>
        </Card>
      </div>

      {/* Unlock hint */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 100,
        textAlign: 'center', color: 'var(--text-secondary)',
      }}>
        <Icon name="chevron_up" size={18}/>
        <div style={{ fontSize: 13, marginTop: 4, letterSpacing: 0.3 }}>Swipe up to unlock</div>
      </div>

      <Dock activePage={1} totalPages={0} showCenter={false}/>
      <HomeIndicator/>
    </div>
  );
}

// ---------- LOCK SCREEN with media widget ----------
function LockMedia() {
  return (
    <div className="phone no-scroll">
      <WallpaperSlateAurora/>
      <StatusBarLock battery={68}/>

      <div style={{
        position: 'absolute', left: 0, right: 0, top: 170,
        textAlign: 'center',
      }}>
        <div style={{
          position: 'relative', display: 'inline-block',
        }}>
          <div style={{
            position: 'absolute', inset: -24,
            background: 'radial-gradient(ellipse, rgba(0,191,165,0.18), transparent 65%)',
            filter: 'blur(6px)', zIndex: -1,
          }}/>
          <div style={{ fontSize: 76, fontWeight: 100, letterSpacing: -1.5, lineHeight: 1 }}>11:42 AM</div>
        </div>
        <div style={{ marginTop: 14, fontSize: 14, color: 'var(--text-secondary)' }}>Friday, December 5</div>
      </div>

      {/* Media widget */}
      <Card style={{
        position: 'absolute', left: 18, right: 18, top: 360,
        padding: 14,
        background: 'linear-gradient(180deg, rgba(0,89,77,0.25), rgba(0,89,77,0.10))',
        border: '1px solid var(--teal-border)',
      }} elev={2}>
        <div style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
          <div style={{
            width: 64, height: 64, borderRadius: 4,
            background: 'linear-gradient(135deg, #1a4a3e 0%, #0d2620 100%)',
            border: '1px solid var(--w-08)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            position: 'relative', overflow: 'hidden',
          }}>
            <div style={{
              position: 'absolute', inset: 0,
              background: 'repeating-linear-gradient(90deg, transparent 0, transparent 3px, rgba(29,233,182,0.15) 3px, rgba(29,233,182,0.15) 4px)',
            }}/>
            <Icon name="music" size={24} color="var(--teal-bright)" style={{ zIndex: 1 }}/>
          </div>
          <div style={{ flex: 1, minWidth: 0, paddingTop: 4 }}>
            <div style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)' }}>How Fast Is The Analogue 3D</div>
            <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 4 }}>James Lambert</div>
          </div>
        </div>
        {/* Scrubber */}
        <div style={{ marginTop: 14, display: 'flex', alignItems: 'center', gap: 10 }}>
          <div style={{ fontSize: 11, color: 'var(--text-secondary)', fontVariantNumeric: 'tabular-nums' }}>4:32</div>
          <div style={{
            flex: 1, height: 3, background: 'var(--w-08)', borderRadius: 2, position: 'relative',
          }}>
            <div style={{
              position: 'absolute', left: 0, top: 0, bottom: 0, width: '38%',
              background: 'var(--teal-gradient)', borderRadius: 2,
            }}/>
            <div style={{
              position: 'absolute', left: '38%', top: '50%',
              transform: 'translate(-50%, -50%)',
              width: 10, height: 10, borderRadius: '50%',
              background: 'var(--teal-bright)',
              boxShadow: '0 0 8px var(--teal-glow)',
            }}/>
          </div>
          <div style={{ fontSize: 11, color: 'var(--text-secondary)', fontVariantNumeric: 'tabular-nums' }}>11:48</div>
        </div>
        {/* Controls */}
        <div style={{ display: 'flex', justifyContent: 'center', gap: 22, marginTop: 14, alignItems: 'center' }}>
          <CircButton glyph="skip_back" size={42}/>
          <CircButton glyph="play" size={56} primary/>
          <CircButton glyph="skip_forward" size={42}/>
        </div>
      </Card>

      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 100,
        textAlign: 'center', color: 'var(--text-secondary)',
      }}>
        <Icon name="chevron_up" size={18}/>
        <div style={{ fontSize: 13, marginTop: 4 }}>Swipe up to unlock</div>
      </div>

      <Dock activePage={1} totalPages={0} showCenter={false}/>
      <HomeIndicator/>
    </div>
  );
}

function CircButton({ glyph, size = 42, primary }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%',
      background: primary ? 'var(--teal-gradient)' : 'var(--elev-3)',
      border: primary ? '1px solid var(--teal-border)' : '1px solid var(--w-08)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      boxShadow: primary
        ? '0 0 20px rgba(0,191,165,0.45), inset 0 1px 0 rgba(255,255,255,0.3)'
        : 'inset 0 1px 0 var(--w-06), 0 4px 12px -4px rgba(0,0,0,0.6)',
      color: primary ? '#000' : 'var(--text-primary)',
    }}>
      <Icon name={glyph} size={size * 0.42}/>
    </div>
  );
}

// ---------- HOME GRID ----------
// Tiny pre-baked app icons (cohesive style: dark base + signature mark)
function MarathonAppMark({ bg, mark, accent }) {
  return (
    <div style={{
      width: '100%', height: '100%',
      background: bg,
      borderRadius: 4,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      position: 'relative',
      overflow: 'hidden',
    }}>
      {accent && <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        height: '40%', background: accent, opacity: 0.7,
        filter: 'blur(8px)',
      }}/>}
      <div style={{ zIndex: 1, color: '#fff', display: 'flex' }}>{mark}</div>
    </div>
  );
}

const APP_ICONS = {
  phone:   { bg: 'linear-gradient(180deg,#003d35,#00897b)', mark: <Icon name="phone" size={28} color="#fff"/> },
  message: { bg: 'linear-gradient(180deg,#0a0a0b,#1a1b1c)', mark: <Icon name="message" size={26} color="var(--teal-bright)"/> },
  mail:    { bg: 'linear-gradient(180deg,#0a0a0b,#161718)', mark: <Icon name="mail" size={24} color="#5dffdc"/> },
  browser: { bg: 'linear-gradient(180deg,#1a1b1c,#0d0d0e)', mark: <Icon name="globe" size={28} color="var(--teal-bright)"/> },
  store:   { bg: 'linear-gradient(180deg,#1de9b6,#00897b)', mark: <span style={{ fontFamily:'serif', fontSize:34, fontWeight: 900, color:'#000', lineHeight: 1, fontStyle:'italic' }}>M</span> },
  calc:    { bg: 'linear-gradient(180deg,#1c1c1d,#040404)', mark: <Icon name="calc" size={26} color="var(--teal-bright)"/> },
  camera:  { bg: 'linear-gradient(180deg,#1c1c1d,#040404)', mark: <Icon name="camera" size={26} color="#fff"/> },
  music:   { bg: 'linear-gradient(180deg,#1a4a3e,#0d2620)', mark: <Icon name="music" size={26} color="var(--teal-bright)"/> },
  calendar:{ bg: 'linear-gradient(180deg,#1a1b1c,#0a0a0b)', mark: <div style={{textAlign:'center'}}>
                <div style={{fontSize:9,fontWeight:700,color:'#fff',letterSpacing:1}}>FRI</div>
                <div style={{fontSize:22,fontWeight:300,color:'var(--teal-bright)',lineHeight:1,marginTop:2}}>5</div>
              </div> },
  clock:   { bg: 'linear-gradient(180deg,#0a0a0b,#040404)', mark: <Icon name="clock" size={28} color="var(--teal-bright)"/> },
  settings:{ bg: 'linear-gradient(180deg,#1a1b1c,#0a0a0b)', mark: <Icon name="cog" size={26} color="#fff"/> },
  maps:    { bg: 'linear-gradient(180deg,#0a0a0b,#040404)', mark: <Icon name="map_pin" size={26} color="var(--teal-bright)"/> },
  photos:  { bg: 'linear-gradient(135deg,#5dffdc,#00897b 50%,#040404)', mark: <Icon name="camera" size={22} color="#000"/> },
  notes:   { bg: 'linear-gradient(180deg,#1a1b1c,#0d0d0e)', mark: <Icon name="note" size={26} color="var(--teal-bright)"/> },
  contacts:{ bg: 'linear-gradient(180deg,#0a0a0b,#1c1c1d)', mark: <Icon name="user" size={26} color="var(--teal-bright)"/> },
  files:   { bg: 'linear-gradient(180deg,#1a1b1c,#040404)', mark: <Icon name="archive" size={24} color="#fff"/> },
};

function HomeIcon({ name, label }) {
  // HomeIcon kept as an alias for older callers; delegates to the new
  // distinctive AppTile component which uses real per-app marks.
  return <AppTile name={name} label={label}/>;
}

function HomeGrid({ apps, page = 1, totalPages = 4 }) {
  return (
    <div className="phone no-scroll">
      <WallpaperSlateAurora/>
      <StatusBar time="11:42" battery={71}/>

      {/* Marathon brand mark — small, top-left, anchors the home grid */}
      <div style={{
        position: 'absolute', top: 36, left: 18,
        display: 'flex', alignItems: 'center', gap: 8,
        zIndex: 5,
      }}>
        <div style={{
          width: 18, height: 18, borderRadius: 3,
          background: 'var(--teal-gradient)',
          border: '1px solid var(--teal-border)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 0 10px var(--teal-halo), inset 0 1px 0 rgba(255,255,255,0.3)',
        }}>
          <svg width="12" height="12" viewBox="0 0 24 24" fill="#000">
            <path d="M3 20V5h2.5l6.5 9 6.5-9H21v15h-2.8V10.5L13 18h-2L5.8 10.5V20z"/>
          </svg>
        </div>
        <div style={{
          fontSize: 10, fontWeight: 700, letterSpacing: 2,
          color: 'var(--text-secondary)', textTransform: 'uppercase',
        }}>Marathon</div>
      </div>

      <div style={{
        position: 'absolute', top: 80, left: 16, right: 16, bottom: 100,
        display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)',
        rowGap: 18, columnGap: 8,
        alignContent: 'start',
        justifyItems: 'center',
        padding: '8px 0',
      }}>
        {apps.map((a, i) => <AppTile key={i} name={a.name} label={a.label}/>)}
      </div>

      <Dock activePage={page} totalPages={totalPages}/>
      <HomeIndicator/>
    </div>
  );
}

function HomePage1() {
  return <HomeGrid page={1} totalPages={4} apps={[
    { name: 'phone',    label: 'Phone' },
    { name: 'message',  label: 'Messages' },
    { name: 'mail',     label: 'Mail' },
    { name: 'browser',  label: 'Browser' },
    { name: 'store',    label: 'Store' },
    { name: 'music',    label: 'Music' },
    { name: 'camera',   label: 'Camera' },
    { name: 'photos',   label: 'Gallery' },
    { name: 'maps',     label: 'Maps' },
    { name: 'calendar', label: 'Calendar' },
    { name: 'clock',    label: 'Clock' },
    { name: 'calc',     label: 'Calculator' },
    { name: 'mi',       label: 'Marathon' },
    { name: 'wallet',   label: 'Wallet' },
    { name: 'health',   label: 'Health' },
    { name: 'settings', label: 'Settings' },
  ]}/>;
}

// ---------- APP DRAWER (alphabetical with search) ----------
function AppDrawer() {
  const apps = [
    'App Store', 'Browser', 'Calculator', 'Calendar', 'Camera', 'Clock', 'Contacts',
    'Files', 'Gallery', 'Health', 'Mail', 'Maps', 'Marathon', 'Messages', 'Music',
    'Notes', 'Phone', 'Settings', 'Voice Memos', 'Wallet', 'Weather',
  ];
  const iconMap = {
    'App Store':'store','Browser':'browser','Calculator':'calc','Calendar':'calendar',
    'Camera':'camera','Clock':'clock','Contacts':'contacts','Files':'files',
    'Gallery':'photos','Health':'health','Mail':'mail','Maps':'maps',
    'Marathon':'mi','Messages':'message','Music':'music','Notes':'notes',
    'Phone':'phone','Settings':'settings','Voice Memos':'voice','Wallet':'wallet','Weather':'weather'
  };

  // group by letter
  const grouped = {};
  apps.forEach(a => {
    const k = a[0].toUpperCase();
    grouped[k] = grouped[k] || [];
    grouped[k].push(a);
  });

  return (
    <div className="phone no-scroll">
      <WallpaperCarbon/>
      <StatusBar time="11:42" battery={71}/>

      <div style={{ position: 'absolute', inset: '28px 0 0 0', display: 'flex', flexDirection: 'column' }}>
        {/* heading */}
        <div style={{ padding: '18px 20px 8px' }}>
          <div className="screen-heading">All Apps</div>
          <div style={{ marginTop: 12 }}>
            <div style={{
              height: 38, borderRadius: 'var(--r-md)', background: 'var(--bb10-elevated)',
              border: '1px solid var(--w-04)', display: 'flex', alignItems: 'center',
              padding: '0 12px', gap: 10, boxShadow: 'inset 0 1px 0 var(--w-04)',
            }}>
              <Icon name="search" size={16} color="var(--text-secondary)"/>
              <span style={{ color: 'var(--text-hint)', fontSize: 14 }}>Search apps</span>
            </div>
          </div>
        </div>

        {/* sections */}
        <div style={{ flex: 1, padding: '8px 16px 8px', overflow: 'hidden' }}>
          {Object.keys(grouped).slice(0, 4).map(letter => (
            <div key={letter} style={{ marginBottom: 14 }}>
              <div style={{
                fontSize: 11, fontWeight: 700, color: 'var(--teal-bright)',
                letterSpacing: 1, padding: '4px 4px 6px',
              }}>{letter}</div>
              <Card style={{ overflow: 'hidden' }}>
                {grouped[letter].map((a, i) => {
                  const IconCmp = APP_ICON_COMPONENTS[iconMap[a]];
                  return (
                    <div key={i} className="m-row" style={{ padding: '10px 14px' }}>
                      <div style={{ flexShrink: 0 }}>
                        {IconCmp ? <IconCmp size={36}/> : <div className="row-icon"><Icon name="note" size={18}/></div>}
                      </div>
                      <div className="row-text">
                        <div className="row-title">{a}</div>
                      </div>
                      <Icon name="chevron_right" size={16} color="var(--text-tertiary)"/>
                    </div>
                  );
                })}
              </Card>
            </div>
          ))}
        </div>
      </div>

      <HomeIndicator/>
    </div>
  );
}

// ---------- TASK SWITCHER ----------
function TaskSwitcher() {
  return (
    <div className="phone no-scroll">
      <WallpaperSlateAurora/>
      <StatusBar time="11:42" battery={70}/>

      <div style={{
        position: 'absolute', top: 44, left: 14, right: 14, bottom: 88,
        display: 'grid', gridTemplateColumns: '1fr 1fr',
        gap: 12,
      }}>
        <TaskCard title="Browser" sub="Marathon News" icon="browser">
          <div style={{ background: '#0a0a0b', height: '100%', padding: 8 }}>
            <div style={{ background: 'var(--teal)', color: '#000', fontSize: 9, padding: '4px 6px', textAlign:'center', fontWeight: 700 }}>POPULAR TOPICS</div>
            <div style={{ background: '#fff', color: '#111', padding: 6, marginTop: 6, fontSize: 8 }}>
              <div style={{ color: 'var(--elev-4)', fontWeight: 700, lineHeight: 1.2 }}>Marathon OS 4.2 brings deeper Hub integration</div>
              <div style={{ color: '#666', fontSize: 7, marginTop: 4 }}>Thom Holwerda · 2 hours ago · 14 comments</div>
              <div style={{ color: '#333', marginTop: 6, lineHeight: 1.3 }}>The latest point release rewires the notification hub to pull...</div>
            </div>
          </div>
        </TaskCard>

        <TaskCard title="Messages" sub="3 unread" icon="message">
          <div style={{ background: 'var(--bb10-black)', height: '100%', padding: 8 }}>
            {['Maya Chen','Devs channel','Mom'].map((n,i) => (
              <div key={i} style={{ display:'flex', gap: 6, padding: '6px 4px', borderBottom: '1px solid var(--w-04)' }}>
                <div style={{ width: 18, height: 18, borderRadius: 4, background: 'var(--elev-3)' }}/>
                <div style={{ flex: 1, fontSize: 8 }}>
                  <div style={{ fontWeight: 600 }}>{n}</div>
                  <div style={{ color: 'var(--text-secondary)' }}>Heading out, see you...</div>
                </div>
                {i === 0 && <div style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--teal-bright)', marginTop: 6 }}/>}
              </div>
            ))}
          </div>
        </TaskCard>

        <TaskCard title="Calendar" sub="December 2025" icon="calendar">
          <div style={{ background: 'var(--bb10-black)', height: '100%', padding: 6 }}>
            <div style={{ textAlign:'center', fontSize: 9, fontWeight: 600, padding: '4px 0' }}>December 2025</div>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 1, fontSize: 7, color: 'var(--text-secondary)' }}>
              {['S','M','T','W','T','F','S'].map((d,i) => <div key={i} style={{ textAlign:'center', padding: 2 }}>{d}</div>)}
              {Array.from({length:35}).map((_,i) => {
                const day = i - 1;
                const isToday = day === 5;
                return (
                  <div key={i} style={{
                    textAlign: 'center', padding: 3,
                    background: isToday ? 'var(--teal-bright)' : 'transparent',
                    color: isToday ? '#000' : (day > 0 && day < 32 ? 'var(--text-primary)' : 'var(--text-tertiary)'),
                    fontWeight: isToday ? 700 : 400,
                  }}>{day > 0 && day < 32 ? day : (day <= 0 ? 30 + day : day - 31)}</div>
                );
              })}
            </div>
          </div>
        </TaskCard>

        <TaskCard title="Music" sub="Playing" icon="music">
          <div style={{
            height: '100%', background: 'linear-gradient(180deg,#1a4a3e,#040404)',
            display: 'flex', flexDirection: 'column', alignItems:'center', justifyContent:'center',
            padding: 8, gap: 6,
          }}>
            <div style={{
              width: 60, height: 60, borderRadius: 4,
              background: 'linear-gradient(135deg,#0a0a0b,#1a4a3e)',
              border: '1px solid var(--w-08)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icon name="music" size={22} color="var(--teal-bright)"/>
            </div>
            <div style={{ fontSize: 9, fontWeight: 600, textAlign: 'center' }}>Modular Tides</div>
            <div style={{ fontSize: 8, color: 'var(--text-secondary)' }}>Avior</div>
            <div style={{ display:'flex', gap: 8, marginTop: 2, color:'var(--teal-bright)' }}>
              <Icon name="skip_back" size={10}/>
              <Icon name="pause" size={10}/>
              <Icon name="skip_forward" size={10}/>
            </div>
          </div>
        </TaskCard>
      </div>

      {/* Bottom dock with stack icon emphasized */}
      <div className="dock">
        <div className="dock-side">
          <div style={{ color: 'var(--teal-bright)' }}><Icon name="phone" size={26}/></div>
        </div>
        <div className="dock-center">
          <div style={{ color: 'rgba(255,255,255,0.55)' }}><Icon name="inbox" size={20}/></div>
          <div className="dot active" style={{
            background:'#fff', width: 32, height: 32, borderRadius: 4,
            boxShadow: '0 0 0 1px rgba(0,0,0,0.5), 0 6px 16px rgba(0,0,0,0.5)',
          }}>
            <Icon name="layers" size={16} color="#000"/>
          </div>
          <div style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--w-24)' }}/>
          <div style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--w-24)' }}/>
        </div>
        <div className="dock-side">
          <div style={{ color: 'rgba(255,255,255,0.85)' }}><Icon name="camera" size={24}/></div>
        </div>
      </div>
      <HomeIndicator/>
    </div>
  );
}

function TaskCard({ title, sub, icon, children }) {
  return (
    <div style={{
      background: 'var(--bb10-elevated)',
      borderRadius: 4,
      overflow: 'hidden',
      boxShadow:
        '0 0 0 1px rgba(0,0,0,0.8), inset 0 1px 0 var(--w-08), 0 6px 18px -6px rgba(0,0,0,0.7)',
      display: 'flex', flexDirection: 'column',
      position: 'relative',
    }}>
      <div style={{ flex: 1, minHeight: 0, overflow: 'hidden' }}>{children}</div>
      <div style={{
        height: 52,
        background: 'var(--glass-tabbar)',
        borderTop: '1px solid var(--border-glass)',
        display: 'flex', alignItems: 'center', padding: '0 10px', gap: 10,
      }}>
        <div style={{ width: 28, height: 28, borderRadius: 4, background: 'var(--elev-3)', display:'flex', alignItems:'center', justifyContent:'center' }}>
          <Icon name={icon} size={16}/>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 13, fontWeight: 600 }}>{title}</div>
          <div style={{ fontSize: 10, color: 'var(--text-secondary)' }}>{sub}</div>
        </div>
        <div style={{ color: 'var(--text-secondary)' }}><Icon name="x" size={14}/></div>
      </div>
    </div>
  );
}

// ---------- QUICK SETTINGS — Marathon design system, tile grid ----------
// Compact 4-col square tile grid. Brightness + Volume sliders above.
// Marathon brand mark at top. All sharp 4px corners. Active tiles fill
// with teal gradient (signature primary action treatment), off tiles are
// elev-2 with a faint border.
function QuickSettings() {
  const tiles = [
    { i:'wifi',          l:'Wi-Fi',           on: true,  sub:'Mesh-5G' },
    { i:'bluetooth',     l:'Bluetooth',       on: true,  sub:'On' },
    { i:'phone_status',  l:'Mobile data',     on: true,  sub:'5G · 87%' },
    { i:'airplane',      l:'Flight mode',     sub:'Off' },
    { i:'dnd',           l:'Do Not Disturb',  on: true,  sub:'Sleep' },
    { i:'flashlight',    l:'Torch',           sub:'Off' },
    { i:'rotate',        l:'Rotation',        sub:'Off' },
    { i:'hotspot',       l:'Hotspot',         sub:'Off' },
    { i:'eye',           l:'Night Light',     sub:'Off' },
    { i:'battery_saver', l:'Battery saver',   sub:'Off' },
  ];
  return (
    <div className="phone no-scroll">
      <div style={{ position: 'absolute', inset: 0, opacity: 0.32 }}><WallpaperSlateAurora/></div>
      <div style={{
        position: 'absolute', inset: 0,
        background: 'linear-gradient(180deg, rgba(13,13,14,0.95), rgba(13,13,14,0.86) 65%, rgba(13,13,14,0.7))',
        pointerEvents: 'none',
      }}/>
      <StatusBar time="7:08 PM" battery={70}/>

      <div style={{
        position: 'absolute', left: 0, right: 0, top: 28, bottom: 0,
        background: 'var(--glass-titlebar)',
        backdropFilter: 'blur(24px)',
        WebkitBackdropFilter: 'blur(24px)',
        borderBottom: '1px solid var(--border-glass)',
        padding: '14px 16px 0',
        boxShadow: 'inset 0 1px 0 var(--w-04)',
        overflow: 'hidden',
        display: 'flex', flexDirection: 'column',
      }}>
        {/* Marathon lockup + date */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '0 2px 14px',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{
              width: 20, height: 20, borderRadius: 3,
              background: 'var(--teal-gradient)',
              border: '1px solid var(--teal-border)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              boxShadow: '0 0 10px var(--teal-halo), inset 0 1px 0 rgba(255,255,255,0.3)',
            }}>
              <svg width="13" height="13" viewBox="0 0 24 24" fill="#000">
                <path d="M3 20V5h2.5l6.5 9 6.5-9H21v15h-2.8V10.5L13 18h-2L5.8 10.5V20z"/>
              </svg>
            </div>
            <div style={{
              fontSize: 11, fontWeight: 700, letterSpacing: 2,
              color: 'var(--text-primary)', textTransform: 'uppercase',
            }}>Marathon</div>
          </div>
          <div style={{
            fontSize: 12, fontWeight: 500, color: 'var(--text-secondary)',
            fontVariantNumeric: 'tabular-nums',
          }}>Fri · 7:08 PM</div>
        </div>

        {/* Sliders */}
        <div style={{
          background: 'var(--elev-2)',
          border: '1px solid var(--w-04)',
          borderRadius: 4,
          boxShadow: 'inset 0 1px 0 var(--w-04)',
          padding: '12px 14px',
          marginBottom: 14,
        }}>
          <QSSlider icon="brightness" label="Brightness" value={86}/>
          <div style={{ height: 1, background: 'var(--w-04)', margin: '12px 0' }}/>
          <QSSlider icon="volume"     label="Volume"     value={40}/>
        </div>

        {/* Horizontal swipeable tile grid — page 1 of 2.
            BB10 quick settings ship in pages of 6 (3 rows × 2 cols) so the
            sheet stays glanceable. The dot indicator below confirms which
            page is showing and how many remain. Page 2 holds the secondary
            toggles (Hotspot, Night Light, Battery saver, Cast). */}
        <div style={{
          display: 'grid',
          gridTemplateColumns: '1fr 1fr',
          gap: 8,
        }}>
          {tiles.slice(0, 6).map((t, i) => <QSTile key={i} {...t}/>)}
        </div>

        {/* Page indicator — same dot pattern Marathon uses for the home dock */}
        <div style={{
          display: 'flex', justifyContent: 'center', alignItems: 'center',
          gap: 6, marginTop: 14,
        }}>
          <div style={{
            width: 18, height: 4, borderRadius: 2,
            background: 'var(--teal-bright)',
            boxShadow: '0 0 6px var(--teal-halo)',
          }}/>
          <div style={{ width: 4, height: 4, borderRadius: '50%', background: 'var(--w-24)' }}/>
        </div>

        {/* Now playing strip */}
        <div style={{
          marginTop: 14,
          padding: '10px 14px',
          background: 'linear-gradient(180deg, rgba(0,89,77,0.22), rgba(0,89,77,0.06))',
          border: '1px solid var(--teal-border)',
          borderRadius: 4,
          display: 'flex', alignItems: 'center', gap: 12,
          boxShadow: 'inset 0 1px 0 var(--w-06)',
        }}>
          <div style={{
            width: 36, height: 36, borderRadius: 4,
            background: 'linear-gradient(135deg, #1a4a3e, #0d2620)',
            border: '1px solid var(--w-08)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexShrink: 0,
          }}>
            <Icon name="music" size={16} color="var(--teal-bright)"/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 13, fontWeight: 600, lineHeight: 1.2,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              Modular Tides
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 1 }}>Avior</div>
          </div>
          <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
            <Icon name="skip_back" size={15} color="var(--text-primary)"/>
            <div style={{
              width: 28, height: 28, borderRadius: '50%',
              background: 'var(--teal-gradient)',
              border: '1px solid var(--teal-border)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: '#000',
              boxShadow: '0 0 10px rgba(0,191,165,0.4), inset 0 1px 0 rgba(255,255,255,0.3)',
            }}>
              <Icon name="play" size={12}/>
            </div>
            <Icon name="skip_forward" size={15} color="var(--text-primary)"/>
          </div>
        </div>

        {/* drag handle */}
        <div style={{ display: 'flex', justifyContent: 'center', marginTop: 'auto', paddingBottom: 14, paddingTop: 16 }}>
          <div style={{ width: 44, height: 4, borderRadius: 2, background: 'var(--w-12)' }}/>
        </div>
      </div>

      <HomeIndicator/>
    </div>
  );
}

function QSSlider({ icon, label, value }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
      <Icon name={icon} size={18} color="var(--text-primary)"/>
      <div style={{ flex: 1 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
          <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: 0.3,
            color: 'var(--text-secondary)', textTransform: 'uppercase' }}>{label}</div>
          <div style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-primary)',
            fontVariantNumeric: 'tabular-nums' }}>{value}</div>
        </div>
        <div style={{ position: 'relative', height: 4, background: 'var(--w-08)', borderRadius: 2 }}>
          <div style={{
            position: 'absolute', left: 0, top: 0, bottom: 0, width: `${value}%`,
            background: 'var(--teal-gradient)', borderRadius: 2,
            boxShadow: '0 0 8px var(--teal-halo)',
          }}/>
          <div style={{
            position: 'absolute', left: `${value}%`, top: '50%',
            transform: 'translate(-50%, -50%)',
            width: 14, height: 14, borderRadius: '50%',
            background: '#fff',
            boxShadow: '0 2px 4px rgba(0,0,0,0.4), 0 0 8px var(--teal-halo)',
          }}/>
        </div>
      </div>
    </div>
  );
}

// BB10 split-bay tile: a horizontal tile with two distinct sections.
// Left bay (60px) houses the icon. Right bay houses label + sub-status.
// ON state: left bay fills teal-bright, icon goes black, hairline border
// brightens. OFF state: both bays elev-2, icon and label dim slate.
function QSTile({ i, l, on, sub }) {
  return (
    <div style={{
      height: 64,
      background: 'var(--elev-2)',
      border: '1px solid ' + (on ? 'var(--teal-border)' : 'var(--w-04)'),
      borderRadius: 4,
      boxShadow: on
        ? '0 0 10px rgba(0,191,165,0.18), inset 0 1px 0 var(--w-04)'
        : 'inset 0 1px 0 var(--w-04)',
      display: 'flex', alignItems: 'stretch',
      overflow: 'hidden',
    }}>
      {/* Left bay — fills teal when on */}
      <div style={{
        width: 60,
        background: on ? 'var(--teal-bright)' : 'transparent',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: on ? '#000' : 'var(--text-tertiary)',
        borderRight: '1px solid ' + (on ? 'var(--teal-border)' : 'var(--w-04)'),
        flexShrink: 0,
      }}>
        <Icon name={i} size={22} strokeWidth={on ? 2 : 1.6}/>
      </div>
      {/* Right bay — label + sub */}
      <div style={{
        flex: 1, minWidth: 0,
        padding: '0 14px',
        display: 'flex', flexDirection: 'column', justifyContent: 'center',
      }}>
        <div style={{
          fontSize: 13, fontWeight: 600,
          color: on ? 'var(--text-primary)' : 'var(--text-secondary)',
          lineHeight: 1.2, letterSpacing: -0.1,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{l}</div>
        {sub && (
          <div style={{
            fontSize: 11, marginTop: 2,
            fontWeight: 500,
            color: on ? 'var(--teal-bright)' : 'var(--text-tertiary)',
            fontVariantNumeric: 'tabular-nums',
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>{sub}</div>
        )}
      </div>
    </div>
  );
}

// ---------- HUB — unified inbox, 2026 simplified ----------
// Lessons applied (iOS 26 + M3E):
//  • single primary action per row (the row itself)
//  • account chips reduced to 4 + "All"
//  • removed AI triage banner — it competed with the content
//  • each row is one clean unit: avatar / name+account+time / preview
//  • generous 16px gutters; 72px row height for proper touch targets
function HubScreen() {
  return (
    <div className="phone no-scroll">
      <WallpaperCarbon/>
      <StatusBar time="11:42" battery={71}/>

      {/* Header */}
      <div style={{
        position: 'absolute', left: 0, right: 0, top: 28, height: 132,
        background: 'var(--glass-actionbar)',
        backdropFilter: 'blur(20px)',
        WebkitBackdropFilter: 'blur(20px)',
        borderBottom: '1px solid var(--border-glass)',
      }}>
        <div style={{
          padding: '14px 20px 0',
          display:'flex', justifyContent:'space-between', alignItems: 'flex-end',
        }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 10 }}>
            <div style={{ fontSize: 32, fontWeight: 200, letterSpacing: -0.6, lineHeight: 1 }}>Hub</div>
            <div style={{ fontSize: 13, color: 'var(--text-secondary)', fontWeight: 400 }}>12 unread</div>
          </div>
          <div style={{ display:'flex', gap: 18, alignItems:'center', color:'var(--text-secondary)' }}>
            <Icon name="search" size={20}/>
            <Icon name="filter" size={19}/>
          </div>
        </div>

        {/* Account filter chips — pills, M3E style */}
        <div style={{
          display: 'flex', gap: 6, padding: '16px 20px 0',
          overflow: 'hidden',
        }}>
          {[
            { l:'All',      count: 12, active: true },
            { l:'Messages', count: 3 },
            { l:'Mail',     count: 5 },
            { l:'Work',     count: 2 },
            { l:'Calls',    count: 2 },
          ].map((c, i) => (
            <div key={i} style={{
              padding: '7px 14px', borderRadius: 999,
              background: c.active ? 'var(--teal-bright)' : 'transparent',
              color: c.active ? '#000' : 'var(--text-secondary)',
              border: '1px solid ' + (c.active ? 'var(--teal-border)' : 'var(--w-08)'),
              fontSize: 13, fontWeight: 500,
              display:'inline-flex', alignItems:'center', gap: 6,
              flexShrink: 0,
              transition: 'all var(--t-quick)',
            }}>
              {c.l}
              <span style={{
                fontSize: 11, opacity: c.active ? 0.65 : 1,
                fontWeight: 600, fontVariantNumeric: 'tabular-nums',
              }}>{c.count}</span>
            </div>
          ))}
        </div>
      </div>

      {/* List */}
      <div style={{
        position: 'absolute', top: 160, left: 0, right: 0, bottom: 0,
        overflow: 'hidden',
      }}>
        <HubGroup label="Today"/>
        <HubRow2
          monogram="MC" tint="#3a6b9c"
          name="Maya Chen" account="iMessage" time="11:38"
          snippet="Heading out, see you at 8 — saved a spot near the back."
          unread
        />
        <HubRow2
          monogram="L" tint="#6b5d8f"
          name="Linear" account="MARS-204 · P0" time="09:48"
          snippet="Devon assigned: investigate compositor frame timing when keyboard is shown over video."
          unread
        />
        <HubRow2
          monogram="CR" tint="#a85968"
          name="Cassandra Reyes" account="Mail" time="08:51"
          snippet="Q4 retro — agenda + pre-reads attached. Lmk what you think."
        />
        <HubRow2
          icon="phone" tint="rgba(0,137,123,0.18)" tealMark
          name="Missed call · Devon" account="2 attempts" time="07:14"
          snippet="No voicemail left"
        />

        <HubGroup label="Yesterday"/>
        <HubRow2
          monogram="GH" tint="#040404" tealBorder
          name="GitHub" account="marathon-shell" time="Thu"
          snippet="PR #1422 ready for review · Hub: account filtering"
        />
      </div>

      <HomeIndicator/>
    </div>
  );
}

function HubGroup({ label }) {
  return (
    <div style={{
      padding: '14px 20px 6px',
      fontSize: 11, fontWeight: 600, letterSpacing: 1.2, textTransform: 'uppercase',
      color: 'var(--text-secondary)',
    }}>{label}</div>
  );
}

function HubRow2({ monogram, icon, tint, tealMark, tealBorder, name, account, time, snippet, unread }) {
  return (
    <div style={{
      display: 'flex', gap: 14, padding: '14px 20px',
      borderTop: '1px solid var(--w-04)',
      alignItems: 'center',
      position: 'relative',
      minHeight: 72,
    }}>
      {/* Unread indicator dot — left-justified, simple */}
      <div style={{
        width: 8, height: 8, borderRadius: '50%',
        background: unread ? 'var(--teal-bright)' : 'transparent',
        boxShadow: unread ? '0 0 8px var(--teal-glow)' : 'none',
        flexShrink: 0, marginLeft: -4,
      }}/>
      <div style={{
        width: 40, height: 40, borderRadius: '50%',
        background: tint,
        border: tealBorder ? '1px solid var(--teal-border)' : '1px solid var(--w-08)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: tealMark ? 'var(--teal-bright)' : '#fff',
        fontSize: 14, fontWeight: 500, letterSpacing: 0.2,
        flexShrink: 0,
      }}>
        {icon ? <Icon name={icon} size={18}/> : monogram}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10 }}>
          <div style={{
            fontSize: 15, fontWeight: unread ? 600 : 500,
            color: 'var(--text-primary)',
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
            lineHeight: 1.2,
          }}>{name}</div>
          <div style={{
            fontSize: 12, color: 'var(--text-secondary)',
            fontVariantNumeric: 'tabular-nums', flexShrink: 0,
          }}>{time}</div>
        </div>
        <div style={{
          fontSize: 12, color: 'var(--text-secondary)', marginTop: 2,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          lineHeight: 1.3,
        }}>{account}</div>
        <div style={{
          fontSize: 13, color: unread ? 'var(--text-primary)' : 'var(--text-secondary)',
          marginTop: 4, lineHeight: 1.4,
          display: '-webkit-box', WebkitLineClamp: 1, WebkitBoxOrient: 'vertical',
          overflow: 'hidden',
        }}>{snippet}</div>
      </div>
    </div>
  );
}

// ---------- PERMISSION DIALOG ----------
function PermissionDialog() {
  return (
    <div className="phone no-scroll">
      {/* dimmed home behind */}
      <div style={{ position: 'absolute', inset: 0, opacity: 0.35 }}><WallpaperSlateAurora/></div>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.72)' }}/>

      <StatusBar time="11:42" battery={71}/>

      {/* Centered modal */}
      <Card style={{
        position: 'absolute', left: 24, right: 24,
        top: '50%', transform: 'translateY(-50%)',
        padding: 0, overflow: 'hidden',
        background: 'var(--elev-2)',
      }} elev={4}>
        <div style={{ padding: '24px 22px 18px', display:'flex', gap: 16, alignItems:'center' }}>
          <div style={{
            width: 64, height: 64, borderRadius: 4, overflow: 'hidden',
            boxShadow: '0 0 0 1px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.12)',
          }}>
            <MarathonAppMark
              bg="linear-gradient(180deg,#1a1b1c,#0a0a0b)"
              mark={<Icon name="note" size={28} color="var(--teal-bright)"/>}
            />
          </div>
          <div>
            <div style={{ fontSize: 20, fontWeight: 500, letterSpacing: -0.3 }}>Slate Notes</div>
            <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 2 }}>by Curlybrace Labs</div>
          </div>
        </div>

        <div style={{ borderTop: '1px solid var(--w-04)', borderBottom: '1px solid var(--w-04)' }}>
          <Row icon="storage" title="Storage" subtitle="Read and write your files" chev={false}/>
        </div>

        <div style={{ padding: '16px 22px 4px', fontSize: 14, lineHeight: 1.5, color: 'var(--text-primary)' }}>
          Slate Notes wants to save attachments and exports to your Documents folder.
        </div>
        <div style={{ padding: '4px 22px 0', fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.5 }}>
          You can change this anytime in Settings → Apps → Slate Notes.
        </div>

        <div style={{ padding: 16, display: 'flex', gap: 10 }}>
          <button className="m-btn secondary" style={{ flex: 1 }}>Deny</button>
          <button className="m-btn primary" style={{ flex: 1 }}>Allow</button>
        </div>
      </Card>

      <HomeIndicator/>
    </div>
  );
}

// ---------- INCOMING CALL ----------
function IncomingCall() {
  return (
    <div className="phone no-scroll">
      <WallpaperSlateAurora/>
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(ellipse at center, rgba(0,89,77,0.22), transparent 70%)',
      }}/>
      <StatusBar time="11:42" battery={68}/>

      <div style={{
        position: 'absolute', top: 100, left: 0, right: 0, textAlign: 'center',
      }}>
        <div style={{ fontSize: 13, color: 'var(--text-secondary)', letterSpacing: 1 }}>INCOMING CALL · MOBILE</div>
      </div>

      <div style={{ position: 'absolute', top: 160, left: 0, right: 0, textAlign: 'center' }}>
        <div style={{
          width: 130, height: 130, borderRadius: '50%',
          background: 'linear-gradient(180deg,#1a4a3e,#0d2620)',
          margin: '0 auto', display:'flex', alignItems:'center', justifyContent:'center',
          border: '2px solid var(--teal-border)',
          boxShadow: '0 0 40px rgba(0,191,165,0.35), inset 0 1px 0 var(--w-12)',
          position: 'relative',
        }}>
          <span style={{ fontSize: 50, fontWeight: 200, color: 'var(--teal-bright)' }}>DP</span>
          {/* pulse */}
          <div style={{
            position: 'absolute', inset: -16,
            borderRadius: '50%',
            border: '1px solid var(--teal-border)',
            opacity: 0.6,
          }}/>
          <div style={{
            position: 'absolute', inset: -28,
            borderRadius: '50%',
            border: '1px solid var(--teal-border)',
            opacity: 0.3,
          }}/>
        </div>
        <div style={{ marginTop: 24, fontSize: 30, fontWeight: 200, letterSpacing: -0.5 }}>Devon Park</div>
        <div style={{ marginTop: 6, fontSize: 14, color: 'var(--text-secondary)' }}>+1 (415) 555-0142 · San Francisco</div>
      </div>

      {/* Quick replies */}
      <div style={{
        position: 'absolute', left: 24, right: 24, bottom: 220,
        display: 'flex', gap: 8, flexWrap: 'wrap', justifyContent: 'center',
      }}>
        {['I\'ll call you back','In a meeting','On my way'].map(s => (
          <div key={s} style={{
            padding: '8px 14px', borderRadius: 4,
            background: 'var(--elev-2)', border: '1px solid var(--w-08)',
            fontSize: 13, color: 'var(--text-primary)',
            boxShadow: 'inset 0 1px 0 var(--w-04)',
          }}>{s}</div>
        ))}
      </div>

      {/* Answer / decline */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 80,
        display: 'flex', justifyContent: 'space-around', alignItems: 'center',
      }}>
        <CallButton color="var(--error)" glyph="phone" label="Decline" flip/>
        <CallButton primary glyph="phone" label="Accept"/>
      </div>

      <HomeIndicator/>
    </div>
  );
}

function CallButton({ color, primary, glyph, label, flip }) {
  return (
    <div style={{ textAlign: 'center' }}>
      <div style={{
        width: 72, height: 72, borderRadius: '50%',
        background: primary ? 'var(--teal-gradient)' : color,
        display:'flex', alignItems:'center', justifyContent:'center',
        boxShadow: primary
          ? '0 0 24px rgba(0,191,165,0.5), inset 0 1px 0 rgba(255,255,255,0.3)'
          : '0 0 24px rgba(239,68,68,0.4), inset 0 1px 0 rgba(255,255,255,0.2)',
        border: '1px solid rgba(255,255,255,0.15)',
        color: primary ? '#000' : '#fff',
        transform: flip ? 'rotate(135deg)' : 'none',
      }}>
        <Icon name={glyph} size={32}/>
      </div>
      <div style={{ marginTop: 10, fontSize: 13, color: 'var(--text-secondary)', textTransform: 'uppercase', letterSpacing: 1.5 }}>{label}</div>
    </div>
  );
}

// ---------- KEYBOARD active (with messages above) ----------
function KeyboardActive() {
  return (
    <div className="phone no-scroll">
      <StatusBar time="11:42" battery={68}/>

      {/* Mock messages page above */}
      <div style={{
        position: 'absolute', top: 28, left: 0, right: 0,
        bottom: 290, background: 'var(--bb10-black)',
        padding: '12px 16px',
        display: 'flex', flexDirection: 'column', gap: 8,
        overflow: 'hidden',
      }}>
        <div style={{ textAlign: 'center', fontSize: 11, color: 'var(--text-secondary)', padding: '6px 0' }}>Today, 11:38 AM</div>
        <Bubble side="them" name="Maya">Are we still on for 8?</Bubble>
        <Bubble side="me">Yes — heading out in a sec.</Bubble>
        <Bubble side="them">Cool, I saved a spot near the back</Bubble>
        <Bubble side="me" composing>Awesome, see you in</Bubble>
      </div>

      {/* Keyboard */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        height: 290,
        background: 'var(--glass-tabbar)',
        backdropFilter: 'blur(14px)',
        borderTop: '1px solid var(--border-glass)',
        padding: '8px 6px 28px',
      }}>
        {/* prediction strip */}
        <div style={{
          display: 'flex', gap: 8, padding: '4px 8px', justifyContent: 'space-between',
          borderBottom: '1px solid var(--w-04)', paddingBottom: 8,
        }}>
          {['Awesome','30 min','about'].map((w,i) => (
            <div key={i} style={{
              flex: 1, textAlign: 'center', fontSize: 13, color: 'var(--text-primary)',
              padding: '6px 0', borderRadius: 4,
              background: i === 0 ? 'var(--elev-2)' : 'transparent',
              border: i === 0 ? '1px solid var(--teal-border)' : '1px solid transparent',
              fontWeight: i === 0 ? 600 : 400,
            }}>{w}</div>
          ))}
        </div>
        {/* rows */}
        <KbRow letters="qwertyuiop"/>
        <KbRow letters="asdfghjkl" inset/>
        <KbRow letters="zxcvbnm" shift/>
        <KbBottomRow/>
      </div>

      <HomeIndicator/>
    </div>
  );
}

function Bubble({ side, name, children, composing }) {
  const me = side === 'me';
  return (
    <div style={{
      alignSelf: me ? 'flex-end' : 'flex-start',
      maxWidth: '78%',
    }}>
      {!me && name && <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginBottom: 3, marginLeft: 4 }}>{name}</div>}
      <div style={{
        background: me
          ? (composing ? 'var(--elev-2)' : 'var(--teal-gradient)')
          : 'var(--elev-2)',
        color: me && !composing ? '#000' : 'var(--text-primary)',
        padding: '8px 12px',
        borderRadius: 4,
        fontSize: 14, lineHeight: 1.35,
        border: me && composing ? '1px solid var(--teal-border)' : '1px solid var(--w-04)',
        position: 'relative',
        boxShadow: me && !composing ? '0 0 12px rgba(0,191,165,0.2)' : 'none',
      }}>{children}{composing && <span style={{ borderLeft: '2px solid var(--teal-bright)', marginLeft: 4 }}/>}</div>
    </div>
  );
}

function KbRow({ letters, inset, shift }) {
  return (
    <div style={{ display: 'flex', gap: 4, padding: '4px 0', justifyContent: 'center' }}>
      {shift && (
        <Key wide highlight>
          <Icon name="arrow_up" size={16}/>
        </Key>
      )}
      {letters.split('').map(l => <Key key={l}>{l.toUpperCase()}</Key>)}
      {shift && (
        <Key wide highlight>
          <Icon name="x" size={16}/>
        </Key>
      )}
    </div>
  );
}

function Key({ children, wide, highlight }) {
  return (
    <div style={{
      flex: wide ? '0 0 42px' : 1,
      height: 42,
      borderRadius: 4,
      background: highlight ? 'var(--elev-3)' : 'var(--bb10-surface)',
      border: '1px solid var(--border-glass)',
      boxShadow: 'inset 0 1px 0 var(--w-04), 0 1px 0 rgba(0,0,0,0.4)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: 16, color: 'var(--text-primary)', fontWeight: 400,
    }}>{children}</div>
  );
}

function KbBottomRow() {
  return (
    <div style={{ display: 'flex', gap: 4, padding: '4px 0' }}>
      <Key wide highlight>123</Key>
      <Key wide><Icon name="globe" size={16}/></Key>
      <div style={{ flex: 4, height: 42, borderRadius: 4, background: 'var(--bb10-surface)',
        border: '1px solid var(--border-glass)', boxShadow: 'inset 0 1px 0 var(--w-04)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12,
        color: 'var(--text-secondary)',
      }}>space</div>
      <Key>.</Key>
      <div style={{
        flex: '0 0 58px', height: 42, borderRadius: 4, background: 'var(--teal-gradient)',
        boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.3), 0 0 12px rgba(0,191,165,0.4)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#000',
      }}><Icon name="send" size={16}/></div>
    </div>
  );
}

// ---------- SYSTEM HUD (volume scrubbing) ----------
function SystemHUD() {
  return (
    <div className="phone no-scroll">
      {/* simulate music app behind */}
      <WallpaperSlateAurora/>
      <div style={{
        position: 'absolute', inset: 0,
        background: 'linear-gradient(180deg, #1a4a3e 0%, #040404 60%)',
        opacity: 0.6,
      }}/>
      <StatusBar time="11:42" battery={71}/>

      {/* faint behind: album art */}
      <div style={{
        position: 'absolute', top: 80, left: 60, right: 60, height: 260,
        background: 'linear-gradient(135deg, #1a4a3e, #0d2620)',
        border: '1px solid var(--w-08)',
        borderRadius: 4,
        opacity: 0.6,
      }}/>

      {/* HUD strip */}
      <Card style={{
        position: 'absolute', left: 20, right: 20, top: 60,
        padding: '14px 18px',
        background: 'var(--glass-titlebar)',
        backdropFilter: 'blur(16px)',
        border: '1px solid var(--border-glass-strong)',
        display: 'flex', flexDirection: 'column', gap: 10,
        boxShadow: '0 12px 30px -10px rgba(0,0,0,0.7), inset 0 1px 0 var(--w-06)',
      }} elev={3}>
        <div style={{ display:'flex', alignItems:'center', gap: 12 }}>
          <Icon name="volume" size={22} color="var(--teal-bright)"/>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)', letterSpacing: 0.4 }}>MEDIA VOLUME</div>
          <div style={{ marginLeft: 'auto', fontSize: 18, fontWeight: 300, fontVariantNumeric: 'tabular-nums' }}>62</div>
        </div>
        <div style={{
          height: 6, background: 'var(--w-08)', borderRadius: 3, position: 'relative',
          overflow: 'hidden',
        }}>
          <div style={{
            position: 'absolute', left: 0, top: 0, bottom: 0, width: '62%',
            background: 'var(--teal-gradient)',
            boxShadow: '0 0 12px var(--teal-glow)',
          }}/>
        </div>
      </Card>

      <HomeIndicator/>
    </div>
  );
}

Object.assign(window, {
  BootSplash, LockScreen, LockMedia, HomePage1, AppDrawer, TaskSwitcher,
  QuickSettings, HubScreen, PermissionDialog, IncomingCall, KeyboardActive, SystemHUD,
  MarathonAppMark, APP_ICONS, HomeIcon,
});
