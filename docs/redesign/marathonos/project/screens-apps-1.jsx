/* global React, Icon, StatusBar, Dock, HomeIndicator, TopBar, TabBar, AppIcon, Card, Row, Toggle, SectionLabel, MarathonAppMark */

// ============================================================
// MARATHON apps (Part 1) — Settings, Phone, Messages, Mail, Browser, Store
// ============================================================

// Generic shell: status bar + content with scroll prevention
function AppShell({ children, dark = true }) {
  return (
    <div className="phone no-scroll">
      <div style={{
        position: 'absolute', inset: 0,
        background: 'var(--bb10-black)',
      }}/>
      <StatusBar time="11:42" battery={71}/>
      <div style={{ position: 'absolute', top: 28, left: 0, right: 0, bottom: 0 }}>
        {children}
      </div>
      <HomeIndicator/>
    </div>
  );
}

// ---------- SETTINGS — main ----------
function SettingsApp() {
  return (
    <AppShell>
      <TopBar title="Settings" actions={<Icon name="search" size={22} color="var(--text-secondary)"/>}/>
      <div style={{ padding: '14px 16px 76px', overflow: 'hidden', height: 'calc(100% - 88px)' }}>
        {/* Profile card */}
        <Card style={{ padding: 14, marginBottom: 18, display: 'flex', alignItems: 'center', gap: 14 }} elev={2}>
          <div style={{
            width: 52, height: 52, borderRadius: '50%',
            background: 'linear-gradient(135deg,#1a4a3e,#0a0a0b)',
            border: '1px solid var(--teal-border)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: 'var(--teal-bright)', fontSize: 18, fontWeight: 500,
          }}>AR</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 16, fontWeight: 600 }}>Avery Rhodes</div>
            <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>avery@marathon.id · Cloud, Sync</div>
          </div>
          <Icon name="chevron_right" size={18} color="var(--text-tertiary)"/>
        </Card>

        <SectionLabel>Marathon Intelligence</SectionLabel>
        <Card style={{ overflow: 'hidden', marginBottom: 16 }}>
          <Row icon="sparkles" iconBg="rgba(0,191,165,0.18)" title="Marathon Intelligence" subtitle="On-device · 3.2 GB model" value="On"/>
          <Row icon="note" title="Focus" subtitle="Sleep · active until 7 AM"/>
          <Row icon="fingerprint" iconBg="rgba(0,191,165,0.18)" title="Wallet & Passkeys" subtitle="12 sites · all hardware-backed"/>
        </Card>

        <SectionLabel>Connectivity</SectionLabel>
        <Card style={{ overflow: 'hidden', marginBottom: 16 }}>
          <Row icon="wifi" title="Wi-Fi" value="Mesh-5G"/>
          <Row icon="bluetooth" title="Bluetooth" value="On"/>
          <Row icon="airplane" title="Airplane Mode" toggle={false}/>
          <Row icon="hotspot" title="Hotspot" value="Off"/>
        </Card>

        <SectionLabel>Device</SectionLabel>
        <Card style={{ overflow: 'hidden', marginBottom: 16 }}>
          <Row icon="monitor" title="Display & Brightness" subtitle="Dark, 62%, scale 1.0×"/>
          <Row icon="volume" title="Sounds & Haptics"/>
          <Row icon="bell" title="Notifications" value="42"/>
          <Row icon="shield" title="Privacy & Security"/>
        </Card>

        <SectionLabel>System</SectionLabel>
        <Card style={{ overflow: 'hidden' }}>
          <Row icon="storage" title="Storage" subtitle="38.4 GB used of 128 GB"/>
          <Row icon="battery" title="Battery" value="71%"/>
          <Row icon="info" title="About Marathon" subtitle="OS 4.2.1 · Avior"/>
        </Card>
      </div>
    </AppShell>
  );
}

// ---------- SETTINGS — Display detail ----------
function SettingsDisplay() {
  return (
    <AppShell>
      <TopBar title="Display" back actions={<Icon name="more" size={22} color="var(--text-secondary)"/>}/>
      <div style={{ padding: '14px 16px', height: 'calc(100% - 88px)', overflow: 'hidden' }}>
        <SectionLabel>Appearance</SectionLabel>
        <Card style={{ overflow: 'hidden', marginBottom: 16 }}>
          <Row icon="monitor" title="Dark" subtitle="Marathon does not have a light theme" value="On" chev={false}/>
        </Card>

        <SectionLabel>Brightness</SectionLabel>
        <Card style={{ padding: 16, marginBottom: 16 }}>
          <div style={{ display:'flex', alignItems:'center', gap: 12 }}>
            <Icon name="brightness" size={18}/>
            <div style={{
              flex: 1, height: 6, background: 'var(--w-08)', borderRadius: 3, position: 'relative',
            }}>
              <div style={{
                position: 'absolute', left: 0, top: 0, bottom: 0, width: '62%',
                background: 'var(--teal-gradient)', borderRadius: 3,
              }}/>
              <div style={{
                position: 'absolute', left: '62%', top: '50%', transform: 'translate(-50%,-50%)',
                width: 18, height: 18, borderRadius: '50%', background: 'var(--teal-bright)',
                border: '1px solid #fff', boxShadow: '0 0 12px var(--teal-glow)',
              }}/>
            </div>
            <div style={{ fontSize: 13, color: 'var(--text-secondary)', minWidth: 28, textAlign: 'right' }}>62</div>
          </div>
          <div style={{ borderTop: '1px solid var(--w-04)', marginTop: 14, paddingTop: 14 }}>
            <Row icon="zap" title="Adapt to ambient light" toggle={true}/>
          </div>
        </Card>

        <SectionLabel>Display scale</SectionLabel>
        <div style={{ display:'grid', gridTemplateColumns:'repeat(3,1fr)', gap: 8, marginBottom: 16 }}>
          {[
            { label: 'Small',  scale: '0.9×' },
            { label: 'Default', scale: '1.0×', active: true },
            { label: 'Large',  scale: '1.2×' },
          ].map((s,i) => (
            <div key={i} style={{
              background: 'var(--elev-2)',
              border: s.active ? '1px solid var(--teal)' : '1px solid var(--w-04)',
              borderRadius: 4,
              padding: 12,
              textAlign: 'center',
              boxShadow: s.active ? '0 0 0 1px var(--teal-border), inset 0 1px 0 var(--w-06)' : 'inset 0 1px 0 var(--w-04)',
            }}>
              {/* mini preview */}
              <div style={{
                aspectRatio: '0.65 / 1', background: 'var(--bb10-black)',
                border: '1px solid var(--w-08)', borderRadius: 3, marginBottom: 8,
                padding: 4, fontSize: i === 0 ? 5 : i === 1 ? 7 : 9, color: 'var(--text-secondary)',
                display: 'flex', flexDirection: 'column', gap: 2,
                overflow: 'hidden',
              }}>
                <div style={{ height: 4, background: 'var(--teal-bright)', borderRadius: 1, opacity: 0.5 }}/>
                <div style={{ background: 'var(--elev-2)', padding: '1px 2px' }}>Title row</div>
                <div style={{ background: 'var(--elev-2)', padding: '1px 2px' }}>Subtitle</div>
              </div>
              <div style={{ fontSize: 13, fontWeight: 600 }}>{s.label}</div>
              <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{s.scale}</div>
            </div>
          ))}
        </div>

        <SectionLabel>Accent</SectionLabel>
        <Card style={{ padding: 16 }}>
          <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', marginBottom: 4 }}>
            <div>
              <div style={{ fontSize: 15, fontWeight: 600 }}>Marathon Teal</div>
              <div style={{ fontSize: 12, color:'var(--text-secondary)' }}>The single system accent</div>
            </div>
            <div style={{ display:'flex', gap: 4 }}>
              {['#006b5d','#00897b','#00bfa5','#1de9b6','#5dffdc'].map(c => (
                <div key={c} style={{
                  width: 22, height: 22, borderRadius: '50%', background: c,
                  border: c === '#00bfa5' ? '2px solid #fff' : '1px solid var(--w-04)',
                }}/>
              ))}
            </div>
          </div>
        </Card>
      </div>
    </AppShell>
  );
}

// ---------- PHONE — dialer ----------
function PhoneDialer() {
  const keys = [
    ['1','',], ['2','ABC'], ['3','DEF'],
    ['4','GHI'], ['5','JKL'], ['6','MNO'],
    ['7','PQRS'], ['8','TUV'], ['9','WXYZ'],
    ['*',''], ['0','+'], ['#',''],
  ];
  return (
    <AppShell>
      <TopBar title="Phone" actions={<>
        <Icon name="search" size={22} color="var(--text-secondary)"/>
        <Icon name="more" size={22} color="var(--text-secondary)"/>
      </>}/>
      <div style={{ padding: '20px 24px 0', height: 'calc(100% - 88px - 70px)', display:'flex', flexDirection:'column' }}>
        <div style={{ textAlign: 'center', minHeight: 110, display:'flex', flexDirection:'column', justifyContent:'center' }}>
          <div style={{ fontSize: 36, fontWeight: 200, letterSpacing: 1, color:'var(--text-primary)' }}>(415) 555-0142</div>
          <div style={{ fontSize: 14, color: 'var(--teal-bright)', marginTop: 6, fontWeight: 500 }}>Devon Park · Mobile</div>
        </div>
        <div style={{ flex: 1, display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14, padding: '20px 0 16px' }}>
          {keys.map(([n, sub]) => (
            <div key={n} style={{
              borderRadius: '50%', height: 68, width: 68, margin: '0 auto',
              background: 'var(--elev-2)',
              border: '1px solid var(--w-04)',
              boxShadow: 'inset 0 1px 0 var(--w-06), 0 4px 12px -6px rgba(0,0,0,0.6)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', flexDirection: 'column',
              color: 'var(--text-primary)',
            }}>
              <div style={{ fontSize: 24, fontWeight: 300 }}>{n}</div>
              {sub && <div style={{ fontSize: 9, color: 'var(--text-secondary)', letterSpacing: 1.5, marginTop: -2 }}>{sub}</div>}
            </div>
          ))}
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-around', alignItems: 'center', padding: '0 0 12px' }}>
          <div style={{ width: 48, color: 'var(--text-tertiary)', textAlign: 'center' }}>
            <Icon name="user" size={22}/>
          </div>
          <div style={{
            width: 64, height: 64, borderRadius: '50%',
            background: 'var(--teal-gradient)',
            border: '1px solid var(--teal-border)',
            display:'flex', alignItems:'center', justifyContent:'center',
            color: '#000',
            boxShadow: '0 0 24px rgba(0,191,165,0.5), inset 0 1px 0 rgba(255,255,255,0.3)',
          }}>
            <Icon name="phone" size={28}/>
          </div>
          <div style={{ width: 48, color: 'var(--text-tertiary)', textAlign: 'center' }}>
            <Icon name="x" size={22}/>
          </div>
        </div>
      </div>
      <TabBar active={0} tabs={[
        { icon:'phone', label:'Dial' },
        { icon:'clock', label:'Recents' },
        { icon:'user', label:'Contacts' },
        { icon:'star', label:'Favorites' },
      ]}/>
    </AppShell>
  );
}

// ---------- MESSAGES — list ----------
function MessagesList() {
  const threads = [
    { name:'Maya Chen',      last:'Heading out, see you at 8 — saved a spot near the back.', t:'now',   un:2, color:'#3a6b9c' },
    { name:'Marathon Devs',  last:'Devon: pushing 4.2.2 to the ring tonight',                t:'10:12', un:1, color:'var(--teal-bright)', black: true },
    { name:'Mom',            last:'Sweetheart can you check the link I sent',                t:'09:48',       color:'#a85968' },
    { name:'Linear',         last:'MARS-204 assigned to you',                                t:'09:30', un:1, color:'#6b5d8f' },
    { name:'Devon Park',     last:'You: pulled it down, looks good. lgtm 👍',                t:'Thu',         color:'#1a4a3e' },
    { name:'Studio B',       last:'Friday at 12: design review',                             t:'Wed',         color:'var(--elev-3)' },
    { name:'Alex Walters',   last:'(image)',                                                  t:'Tue',         color:'#4a8a5e' },
    { name:'Spam likely',    last:'Your delivery is ready for pickup',                       t:'Mon',         color:'#c89545' },
  ];
  return (
    <AppShell>
      <TopBar title="Messages" actions={<>
        <Icon name="search" size={22} color="var(--text-secondary)"/>
        <div style={{
          width: 32, height: 32, borderRadius: 4, background: 'var(--teal-gradient)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#000',
        }}>
          <Icon name="plus" size={18}/>
        </div>
      </>}/>
      <div style={{ padding: '6px 12px 0', height: 'calc(100% - 88px - 70px)', overflow: 'hidden' }}>
        {threads.map((th, i) => (
          <div key={i} className="m-row" style={{ padding: '14px 8px', minHeight: 70 }}>
            <div style={{
              width: 44, height: 44, borderRadius: '50%',
              background: th.color,
              border: th.tealBorder ? '1px solid var(--teal-border)' : '1px solid var(--w-08)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: th.black ? '#000' : '#fff',
              fontSize: 15, fontWeight: 600,
              flexShrink: 0,
            }}>{th.name.split(' ').map(s=>s[0]).slice(0,2).join('')}</div>
            <div className="row-text">
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <div className="row-title">{th.name}</div>
                <div style={{ fontSize: 11, color: th.un ? 'var(--teal-bright)' : 'var(--text-secondary)' }}>{th.t}</div>
              </div>
              <div style={{ display:'flex', alignItems: 'center', gap: 8, marginTop: 2 }}>
                <div className="row-subtitle" style={{ flex: 1 }}>{th.last}</div>
                {th.un && <div style={{
                  background: 'var(--teal-bright)', color: '#000',
                  fontSize: 11, fontWeight: 700, padding: '0 7px', height: 18,
                  borderRadius: 4, display: 'inline-flex', alignItems: 'center',
                }}>{th.un}</div>}
              </div>
            </div>
          </div>
        ))}
      </div>
      <TabBar active={1} tabs={[
        { icon:'star', label:'Pinned' },
        { icon:'message', label:'All' },
        { icon:'archive', label:'Archive' },
      ]}/>
    </AppShell>
  );
}

// ---------- MESSAGES — thread ----------
function MessagesThread() {
  return (
    <AppShell>
      {/* Custom thread header */}
      <div style={{
        height: 88, padding: '0 16px',
        background: 'var(--glass-titlebar)',
        backdropFilter: 'blur(12px)',
        borderBottom: '1px solid var(--border-glass)',
        display: 'flex', alignItems: 'flex-end', paddingBottom: 12,
        gap: 14,
      }}>
        <Icon name="chevron_left" size={24} color="var(--text-secondary)"/>
        <div style={{
          width: 36, height: 36, borderRadius: '50%',
          background: '#3a6b9c', display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 13, fontWeight: 600, color: '#fff',
        }}>MC</div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 17, fontWeight: 500 }}>Maya Chen</div>
          <div style={{ fontSize: 11, color: 'var(--teal-bright)' }}>typing…</div>
        </div>
        <Icon name="phone" size={20} color="var(--text-primary)"/>
        <Icon name="more" size={22} color="var(--text-secondary)"/>
      </div>

      <div style={{
        position: 'absolute', top: 116, left: 0, right: 0, bottom: 70,
        padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8,
        overflow: 'hidden',
      }}>
        <div style={{ textAlign:'center', fontSize: 11, color:'var(--text-secondary)', padding: '6px 0' }}>Today, 11:38 AM</div>
        <ThreadBubble side="them">Are we still on for 8?</ThreadBubble>
        <ThreadBubble side="me" status="read">Yes — heading out in a sec.</ThreadBubble>
        <ThreadBubble side="them">Cool, I saved a spot near the back</ThreadBubble>
        <ThreadBubble side="them">There's a soundcheck before, you'll like it</ThreadBubble>
        <ThreadBubble side="me" status="delivered">Even better. Want me to grab drinks on the way?</ThreadBubble>
        <ThreadBubble side="them">Yes please, the usual</ThreadBubble>
      </div>

      {/* Composer */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        height: 70,
        background: 'var(--glass-tabbar)',
        backdropFilter: 'blur(14px)',
        borderTop: '1px solid var(--border-glass)',
        display: 'flex', alignItems: 'center', gap: 10, padding: '12px 14px',
      }}>
        <div style={{
          width: 36, height: 36, borderRadius: '50%', background: 'var(--elev-2)',
          border: '1px solid var(--w-04)', display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icon name="plus" size={18}/>
        </div>
        <div style={{
          flex: 1, height: 38, borderRadius: 4, background: 'var(--bb10-surface)',
          border: '1px solid var(--w-04)', padding: '0 14px', display: 'flex', alignItems: 'center',
          color: 'var(--text-hint)', fontSize: 13,
          boxShadow: 'inset 0 1px 0 var(--w-02)',
        }}>iMessage</div>
        <div style={{
          width: 36, height: 36, borderRadius: '50%', background: 'var(--teal-gradient)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#000',
          boxShadow: '0 0 12px rgba(0,191,165,0.4), inset 0 1px 0 rgba(255,255,255,0.3)',
        }}>
          <Icon name="send" size={16}/>
        </div>
      </div>
    </AppShell>
  );
}

function ThreadBubble({ side, children, status }) {
  const me = side === 'me';
  return (
    <div style={{ alignSelf: me ? 'flex-end' : 'flex-start', maxWidth: '78%' }}>
      <div style={{
        background: me ? 'var(--teal-gradient)' : 'var(--elev-2)',
        color: me ? '#000' : 'var(--text-primary)',
        padding: '8px 12px',
        borderRadius: 4,
        fontSize: 14, lineHeight: 1.35,
        border: '1px solid ' + (me ? 'var(--teal-border)' : 'var(--w-04)'),
        boxShadow: me ? '0 0 12px rgba(0,191,165,0.2)' : 'inset 0 1px 0 var(--w-04)',
      }}>{children}</div>
      {status && me && (
        <div style={{ fontSize: 10, color: 'var(--text-secondary)', textAlign: 'right', marginTop: 2, letterSpacing: 0.5 }}>
          {status === 'read' ? '✓✓ READ' : '✓ DELIVERED'}
        </div>
      )}
    </div>
  );
}

// ---------- MAIL — inbox ----------
function MailInbox() {
  const mails = [
    { from:'Linear',          subj:'MARS-204 assigned to you',            preview:'Devon Park assigned you a high-priority issue',     t:'09:30', un:true, tint:'#6b5d8f' },
    { from:'Cassandra Reyes', subj:'Re: Q4 retro — agenda + pre-reads',   preview:'I split the timing slightly differently. Take a look', t:'08:51', un:true, tint:'#3a6b9c' },
    { from:'GitHub',          subj:'[marathon-os] PR #1422 ready',         preview:'devon-p wants to merge 3 commits into main',         t:'Thu',         tint:'#040404' },
    { from:'Stripe',          subj:'Your December invoice',                preview:'Your invoice for $84.00 is now available.',          t:'Thu',         tint:'#4a8a5e' },
    { from:'Curlybrace Labs', subj:'Slate Notes 2.4 — what\'s new',        preview:'A faster outliner, sync redesign, and 16 fixes.',    t:'Wed',         tint:'#1a4a3e' },
    { from:'Maya Chen',       subj:'concert lineup pdf',                   preview:'attached — let me know what you want to see',        t:'Wed',         tint:'#3a6b9c' },
  ];
  return (
    <AppShell>
      <TopBar title="Inbox" actions={<>
        <Icon name="search" size={22} color="var(--text-secondary)"/>
        <Icon name="more" size={22} color="var(--text-secondary)"/>
      </>}/>
      <div style={{ position: 'absolute', top: 116, left: 0, right: 0, bottom: 70, overflow: 'hidden' }}>
        <div style={{ padding: '8px 18px 4px', display: 'flex', justifyContent: 'space-between' }}>
          <SectionLabel style={{ padding: 0 }}>2 unread · 84 total</SectionLabel>
          <SectionLabel style={{ padding: 0, color: 'var(--teal-bright)' }}>Sort: Newest</SectionLabel>
        </div>
        {mails.map((m,i) => (
          <div key={i} style={{
            display: 'flex', padding: '12px 18px', gap: 14, alignItems: 'flex-start',
            borderTop: i === 0 ? '1px solid var(--w-04)' : '1px solid var(--w-04)',
            background: m.un ? 'rgba(0,191,165,0.025)' : 'transparent',
            position: 'relative',
          }}>
            {m.un && <div style={{
              position: 'absolute', left: 0, top: 0, bottom: 0, width: 3,
              background: 'var(--teal-bright)',
            }}/>}
            <div style={{
              width: 36, height: 36, borderRadius: 4, background: m.tint,
              border: '1px solid var(--w-08)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontSize: 13, fontWeight: 600, color: '#fff', flexShrink: 0,
            }}>{m.from[0]}</div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ display: 'flex', justifyContent:'space-between', alignItems:'baseline', gap: 8 }}>
                <div style={{ fontSize: 14, fontWeight: m.un ? 700 : 500, color: 'var(--text-primary)' }}>{m.from}</div>
                <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{m.t}</div>
              </div>
              <div style={{ fontSize: 13, color: 'var(--text-primary)', marginTop: 2, fontWeight: m.un ? 600 : 400, whiteSpace: 'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{m.subj}</div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 3, whiteSpace: 'nowrap', overflow:'hidden', textOverflow:'ellipsis' }}>{m.preview}</div>
            </div>
          </div>
        ))}
      </div>
      <TabBar active={0} tabs={[
        { icon:'inbox', label:'Inbox' },
        { icon:'star', label:'Starred' },
        { icon:'send', label:'Sent' },
        { icon:'archive', label:'All' },
      ]}/>
    </AppShell>
  );
}

// ---------- BROWSER ----------
function BrowserApp() {
  return (
    <AppShell>
      {/* status bar already */}
      {/* URL bar */}
      <div style={{
        height: 56, background: 'var(--glass-titlebar)',
        backdropFilter: 'blur(12px)',
        borderBottom: '1px solid var(--border-glass)',
        display: 'flex', alignItems: 'center', gap: 8, padding: '0 12px',
      }}>
        <Icon name="chevron_left" size={22} color="var(--text-secondary)"/>
        <Icon name="chevron_right" size={22} color="var(--text-tertiary)"/>
        <div style={{
          flex: 1, height: 36, borderRadius: 4, background: 'var(--bb10-surface)',
          border: '1px solid var(--w-04)', display: 'flex', alignItems: 'center',
          padding: '0 10px', gap: 8, boxShadow: 'inset 0 1px 0 var(--w-02)',
        }}>
          <Icon name="lock" size={12} color="var(--teal-bright)"/>
          <span style={{ fontSize: 13, color: 'var(--text-primary)' }}>marathon-os.dev</span>
          <span style={{ fontSize: 13, color: 'var(--text-secondary)' }}>/docs</span>
        </div>
        <Icon name="refresh" size={20} color="var(--text-secondary)"/>
        <Icon name="more" size={20} color="var(--text-secondary)"/>
      </div>

      {/* Page content (faked Marathon docs) */}
      <div style={{
        position: 'absolute', top: 28 + 56, left: 0, right: 0, bottom: 86,
        padding: '20px 22px', overflow: 'hidden',
        background: 'var(--bb10-black)',
      }}>
        <div style={{
          display:'inline-flex', alignItems:'center', gap: 8,
          background: 'var(--elev-2)', border: '1px solid var(--w-04)',
          padding: '5px 10px', borderRadius: 4, fontSize: 11, color: 'var(--text-secondary)',
        }}>
          <Icon name="info" size={12} color="var(--teal-bright)"/>
          MARATHON DOCS · v4.2
        </div>
        <div style={{ fontSize: 26, fontWeight: 200, marginTop: 14, letterSpacing: -0.4, lineHeight: 1.15 }}>
          Building for Marathon
        </div>
        <div style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 12, lineHeight: 1.55 }}>
          Marathon is a glass-and-neon mobile shell with a sharp engineering aesthetic. Apps are written
          in QML and follow a strict five-point spacing grid scaled to device density.
        </div>
        <div style={{ marginTop: 18, display:'flex', flexDirection:'column', gap: 6 }}>
          {[
            { n: '01', t: 'Install the Marathon SDK', d: 'macOS, Linux, Windows' },
            { n: '02', t: 'Scaffold your first app',   d: 'marathon init / app run' },
            { n: '03', t: 'Embrace the design system', d: 'Spacing, color, motion tokens' },
          ].map(x => (
            <div key={x.n} style={{
              padding: 12, borderRadius: 4,
              background: 'var(--elev-2)', border: '1px solid var(--w-04)',
              display: 'flex', gap: 12, alignItems: 'center',
            }}>
              <div className="mono" style={{ fontSize: 11, color: 'var(--teal-bright)', minWidth: 24 }}>{x.n}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 600 }}>{x.t}</div>
                <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2 }}>{x.d}</div>
              </div>
              <Icon name="chevron_right" size={16} color="var(--text-tertiary)"/>
            </div>
          ))}
        </div>
        <div style={{
          marginTop: 18, padding: 12, borderRadius: 4,
          border: '1px solid var(--teal-border)',
          background: 'rgba(0,191,165,0.07)',
        }}>
          <div className="mono" style={{ fontSize: 11, color: 'var(--teal-bright)' }}>$ marathon init my-app</div>
          <div className="mono" style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 4 }}>→ Scaffolded my-app in 1.2s</div>
        </div>
      </div>

      {/* Bottom toolbar */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        height: 70, background: 'var(--glass-tabbar)',
        backdropFilter: 'blur(14px)',
        borderTop: '1px solid var(--border-glass)',
        display:'flex', alignItems:'center', justifyContent:'space-around',
      }}>
        <Icon name="share" size={22} color="var(--text-primary)"/>
        <Icon name="star" size={22} color="var(--text-primary)"/>
        <Icon name="plus" size={22} color="var(--text-primary)"/>
        <div style={{ position: 'relative' }}>
          <Icon name="layers" size={22} color="var(--text-primary)"/>
          <div style={{ position: 'absolute', top: -4, right: -8,
            background: 'var(--teal-bright)', color: '#000',
            fontSize: 10, fontWeight: 700, borderRadius: 2,
            padding: '0 4px', minWidth: 14, height: 14,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          }}>3</div>
        </div>
        <Icon name="user" size={22} color="var(--text-primary)"/>
      </div>
    </AppShell>
  );
}

// ---------- APP STORE — discover ----------
function StoreDiscover() {
  return (
    <AppShell>
      <TopBar title="Store" actions={<>
        <Icon name="search" size={22} color="var(--text-secondary)"/>
        <div style={{ width: 28, height: 28, borderRadius: '50%', background: 'var(--elev-3)' }}/>
      </>}/>
      <div style={{
        position: 'absolute', top: 116, left: 0, right: 0, bottom: 70,
        overflow: 'hidden', padding: '14px 0',
      }}>
        {/* Featured hero */}
        <div style={{ padding: '0 16px' }}>
          <Card style={{
            padding: 18, overflow: 'hidden', position: 'relative',
            background: 'linear-gradient(135deg, #1a4a3e 0%, #040404 70%)',
          }} elev={3}>
            <div style={{ position: 'absolute', right: -40, top: -30, width: 200, height: 200,
              background: 'radial-gradient(circle, rgba(0,191,165,0.35), transparent 60%)' }}/>
            <div style={{ position:'relative' }}>
              <div className="m-chip" style={{ marginBottom: 12 }}>EDITORS' PICK</div>
              <div style={{ fontSize: 22, fontWeight: 500, letterSpacing: -0.3, lineHeight: 1.15 }}>Slate Editor — for writing that doesn't fight back.</div>
              <div style={{ fontSize: 13, color:'var(--text-secondary)', marginTop: 8 }}>Curlybrace Labs · Free with in-app pro tier</div>
              <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
                <button className="m-btn primary" style={{ height: 38, padding: '0 22px' }}>Get</button>
                <button className="m-btn ghost" style={{ height: 38, padding: '0 14px' }}>Preview</button>
              </div>
            </div>
          </Card>
        </div>

        <div style={{ padding: '20px 16px 8px' }}>
          <div style={{ fontSize: 18, fontWeight: 600 }}>Trending now</div>
          <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Top picks from across the system</div>
        </div>

        {/* Trending rail */}
        <div style={{
          display: 'flex', gap: 10, padding: '0 16px', overflowX: 'hidden',
        }}>
          {[
            { n:'Lattice', d:'Tasks', icon:'check', bg:'#1de9b6', black:true, rating:'4.8' },
            { n:'Sigil', d:'Password', icon:'shield', bg:'#1c1c1d', rating:'4.9' },
            { n:'Tide', d:'Sleep', icon:'music', bg:'#1a4a3e', rating:'4.7' },
          ].map((a,i) => (
            <div key={i} style={{ width: 140, flexShrink: 0 }}>
              <div style={{
                aspectRatio: '1', borderRadius: 4, background: a.bg,
                display:'flex', alignItems:'center', justifyContent:'center',
                color: a.black ? '#000' : '#fff',
                boxShadow: '0 0 0 1px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.15)',
              }}>
                <Icon name={a.icon} size={38}/>
              </div>
              <div style={{ marginTop: 8, fontSize: 13, fontWeight: 600 }}>{a.n}</div>
              <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{a.d} · ★ {a.rating}</div>
            </div>
          ))}
        </div>

        <div style={{ padding: '18px 16px 8px' }}>
          <div style={{ fontSize: 18, fontWeight: 600 }}>Updates available · 3</div>
        </div>
        <Card style={{ margin: '0 16px', overflow: 'hidden' }}>
          {[
            { n:'Browser', sz:'24.6 MB', what:'Faster tab switcher, fixes 12 reader bugs', icon:'globe' },
            { n:'Slate Notes', sz:'8.2 MB', what:'New outliner, sync redesign', icon:'note' },
            { n:'Voice Memos', sz:'4.1 MB', what:'Reliability improvements', icon:'mic' },
          ].map((u,i) => (
            <div key={i} className="m-row" style={{ padding: '12px 14px' }}>
              <div className="row-icon" style={{ background:'var(--elev-3)' }}><Icon name={u.icon} size={18}/></div>
              <div className="row-text">
                <div className="row-title">{u.n}</div>
                <div className="row-subtitle">{u.what} · {u.sz}</div>
              </div>
              <button className="m-btn primary" style={{ height: 32, padding: '0 14px', fontSize: 12 }}>Update</button>
            </div>
          ))}
        </Card>
      </div>
      <TabBar active={0} tabs={[
        { icon:'zap', label:'Discover' },
        { icon:'store', label:'Apps' },
        { icon:'download', label:'Installed' },
        { icon:'user', label:'Account' },
      ]}/>
    </AppShell>
  );
}

Object.assign(window, {
  AppShell, SettingsApp, SettingsDisplay,
  PhoneDialer, MessagesList, MessagesThread, MailInbox,
  BrowserApp, StoreDiscover,
});
