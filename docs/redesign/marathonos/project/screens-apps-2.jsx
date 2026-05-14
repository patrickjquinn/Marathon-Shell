/* global React, Icon, StatusBar, Dock, HomeIndicator, TopBar, TabBar, AppIcon, Card, Row, Toggle, SectionLabel, AppShell, MarathonAppMark */

// ============================================================
// MARATHON apps (Part 2) — Music, Camera, Calendar, Calculator,
// Maps, Clock, Gallery, Notes
// ============================================================

// ---------- MUSIC — Now Playing ----------
function MusicNowPlaying() {
  return (
    <div className="phone no-scroll">
      {/* Backdrop tinted teal */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'linear-gradient(180deg, #1a4a3e 0%, #0d2620 35%, var(--bb10-black) 75%)',
      }}/>
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(ellipse 400px 300px at 50% 35%, rgba(0,191,165,0.12), transparent 60%)',
      }}/>

      <StatusBar time="11:42" battery={70}/>

      {/* Title row */}
      <div style={{
        position: 'absolute', top: 36, left: 0, right: 0, padding: '0 20px',
        display:'flex', justifyContent:'space-between', alignItems:'center',
      }}>
        <Icon name="chevron_down" size={22} color="var(--text-secondary)"/>
        <div style={{ textAlign: 'center', flex: 1 }}>
          <div style={{ fontSize: 10, color: 'var(--text-secondary)', letterSpacing: 1.5 }}>PLAYING FROM</div>
          <div style={{ fontSize: 13, color: 'var(--text-primary)', fontWeight: 500, marginTop: 2 }}>Modular Tides — EP</div>
        </div>
        <Icon name="more" size={22} color="var(--text-secondary)"/>
      </div>

      {/* Album art */}
      <div style={{
        position: 'absolute', top: 110, left: 36, right: 36,
        aspectRatio: '1', borderRadius: 4,
        background: 'linear-gradient(135deg, #1a4a3e, #0d2620 60%, #040404)',
        border: '1px solid var(--w-08)',
        boxShadow:
          '0 24px 60px -20px rgba(0,0,0,0.8), inset 0 1px 0 var(--w-08)',
        position: 'absolute',
        overflow: 'hidden',
      }}>
        <div style={{
          position: 'absolute', inset: 0,
          background: 'repeating-linear-gradient(90deg, transparent 0, transparent 6px, rgba(29,233,182,0.18) 6px, rgba(29,233,182,0.18) 7px)',
          maskImage: 'radial-gradient(ellipse at center, black 30%, transparent 65%)',
          WebkitMaskImage: 'radial-gradient(ellipse at center, black 30%, transparent 65%)',
        }}/>
        <div style={{
          position:'absolute', inset: 0, display:'flex', alignItems:'center', justifyContent:'center',
        }}>
          <div style={{
            fontSize: 90, fontWeight: 200, color: 'var(--teal-bright)',
            textShadow: '0 0 30px rgba(0,191,165,0.6)',
            letterSpacing: -2, lineHeight: 1,
          }}>~</div>
        </div>
      </div>

      {/* Info */}
      <div style={{ position: 'absolute', top: 470, left: 28, right: 28 }}>
        <div style={{ fontSize: 22, fontWeight: 500, letterSpacing: -0.3 }}>Modular Tides</div>
        <div style={{ fontSize: 14, color: 'var(--text-secondary)', marginTop: 4 }}>Avior · Slate, 2025</div>
      </div>

      {/* Scrubber */}
      <div style={{ position: 'absolute', top: 540, left: 28, right: 28 }}>
        <div style={{
          height: 4, background: 'var(--w-08)', borderRadius: 2, position: 'relative',
        }}>
          <div style={{
            position: 'absolute', left: 0, top: 0, bottom: 0, width: '42%',
            background: 'var(--teal-gradient)', borderRadius: 2,
            boxShadow: '0 0 8px var(--teal-glow)',
          }}/>
          <div style={{
            position: 'absolute', left: '42%', top: '50%',
            transform: 'translate(-50%, -50%)',
            width: 12, height: 12, borderRadius: '50%',
            background: 'var(--teal-bright)',
            border: '1px solid #fff',
          }}/>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8, fontSize: 11, color: 'var(--text-secondary)', fontVariantNumeric: 'tabular-nums' }}>
          <span>1:48</span>
          <span>4:14</span>
        </div>
      </div>

      {/* Controls */}
      <div style={{ position: 'absolute', top: 600, left: 0, right: 0, display: 'flex', justifyContent: 'center', alignItems: 'center', gap: 32 }}>
        <Icon name="refresh" size={20} color="var(--text-secondary)"/>
        <div style={{
          width: 50, height: 50, borderRadius: '50%', background: 'var(--elev-3)',
          border: '1px solid var(--w-08)', display:'flex', alignItems:'center', justifyContent:'center',
        }}><Icon name="skip_back" size={22}/></div>
        <div style={{
          width: 74, height: 74, borderRadius: '50%', background: 'var(--teal-gradient)',
          border: '1px solid var(--teal-border)',
          display:'flex', alignItems:'center', justifyContent:'center',
          color: '#000',
          boxShadow: '0 0 30px rgba(0,191,165,0.5), inset 0 1px 0 rgba(255,255,255,0.3)',
        }}><Icon name="pause" size={28}/></div>
        <div style={{
          width: 50, height: 50, borderRadius: '50%', background: 'var(--elev-3)',
          border: '1px solid var(--w-08)', display:'flex', alignItems:'center', justifyContent:'center',
        }}><Icon name="skip_forward" size={22}/></div>
        <Icon name="heart" size={20} color="var(--teal-bright)"/>
      </div>

      {/* Bottom strip */}
      <div style={{
        position: 'absolute', left: 28, right: 28, bottom: 80,
        display:'flex', justifyContent:'space-between', alignItems:'center',
        padding: '14px 16px', borderRadius: 4,
        background: 'var(--elev-2)', border: '1px solid var(--w-04)',
      }}>
        <div style={{ display:'flex', alignItems:'center', gap: 12 }}>
          <Icon name="cast" size={18} color="var(--teal-bright)"/>
          <div>
            <div style={{ fontSize: 12, fontWeight: 600 }}>Living Room</div>
            <div style={{ fontSize: 10, color: 'var(--text-secondary)' }}>Sonos · 2 speakers</div>
          </div>
        </div>
        <Icon name="chevron_right" size={16} color="var(--text-tertiary)"/>
      </div>

      <HomeIndicator/>
    </div>
  );
}

// ---------- CAMERA viewfinder ----------
function CameraApp() {
  return (
    <div className="phone no-scroll">
      <div style={{ position:'absolute', inset:0, background:'#000' }}/>

      {/* Viewfinder fake scene: subtle gradient + horizon */}
      <div style={{
        position: 'absolute', top: 90, left: 0, right: 0, bottom: 180,
        background:
          'linear-gradient(180deg, var(--elev-2) 0%, var(--elev-3) 35%, var(--elev-4) 50%, #8b6c4f 50.5%, #4a3b2a 75%, #2a1f15 100%)',
        overflow: 'hidden',
      }}>
        {/* sun glare */}
        <div style={{
          position:'absolute', top: '20%', right: '20%',
          width: 80, height: 80, borderRadius: '50%',
          background: 'radial-gradient(circle, rgba(255,220,150,0.6), transparent 70%)',
          filter: 'blur(8px)',
        }}/>
        {/* grid */}
        <div style={{
          position: 'absolute', inset: 0,
          backgroundImage:
            'linear-gradient(rgba(255,255,255,0.12) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.12) 1px, transparent 1px)',
          backgroundSize: '33.33% 33.33%',
          backgroundPosition: '-1px -1px',
        }}/>
        {/* focus reticle */}
        <div style={{
          position: 'absolute', top: '52%', left: '38%',
          width: 60, height: 60, border: '1px solid var(--teal-bright)',
          boxShadow: '0 0 0 1px rgba(0,0,0,0.6), inset 0 0 0 1px rgba(0,0,0,0.4), 0 0 12px var(--teal-glow)',
        }}>
          <div style={{ position:'absolute', top:'50%', left:-6, width:5, height:1, background:'var(--teal-bright)'}}/>
          <div style={{ position:'absolute', top:'50%', right:-6, width:5, height:1, background:'var(--teal-bright)'}}/>
          <div style={{ position:'absolute', left:'50%', top:-6, height:5, width:1, background:'var(--teal-bright)'}}/>
          <div style={{ position:'absolute', left:'50%', bottom:-6, height:5, width:1, background:'var(--teal-bright)'}}/>
        </div>
      </div>

      <StatusBar time="11:42" battery={68}/>

      {/* Top bar */}
      <div style={{
        position: 'absolute', top: 32, left: 12, right: 12,
        display:'flex', justifyContent:'space-between', alignItems:'center',
      }}>
        <div style={{
          width: 34, height: 34, borderRadius: '50%', background: 'rgba(0,0,0,0.5)',
          border: '1px solid var(--w-12)',
          display:'flex', alignItems:'center', justifyContent:'center',
        }}>
          <Icon name="zap" size={16} color="var(--teal-bright)"/>
        </div>
        <div style={{
          padding: '4px 10px', borderRadius: 4,
          background: 'rgba(0,0,0,0.5)', border: '1px solid var(--w-12)',
          fontSize: 11, fontWeight: 600, letterSpacing: 1,
        }}>HDR · ON</div>
        <div style={{
          width: 34, height: 34, borderRadius: '50%', background: 'rgba(0,0,0,0.5)',
          border: '1px solid var(--w-12)',
          display:'flex', alignItems:'center', justifyContent:'center',
        }}>
          <Icon name="cog" size={16}/>
        </div>
      </div>

      {/* Mode picker */}
      <div style={{
        position: 'absolute', bottom: 200, left: 0, right: 0, textAlign: 'center',
        display: 'flex', justifyContent: 'center', gap: 22,
        fontSize: 11, fontWeight: 600, letterSpacing: 1,
      }}>
        {['SLO-MO','VIDEO','PHOTO','PORTRAIT','PANO'].map((m,i) => (
          <div key={m} style={{
            color: i === 2 ? 'var(--teal-bright)' : 'var(--text-secondary)',
            paddingBottom: 4,
            borderBottom: i === 2 ? '1px solid var(--teal-bright)' : '1px solid transparent',
          }}>{m}</div>
        ))}
      </div>

      {/* Shutter row */}
      <div style={{
        position: 'absolute', bottom: 80, left: 0, right: 0,
        padding: '0 30px', display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div style={{
          width: 52, height: 52, borderRadius: 4,
          background:'linear-gradient(135deg, var(--elev-3), var(--elev-2))',
          border: '1px solid var(--w-12)',
        }}/>
        <div style={{
          width: 80, height: 80, borderRadius: '50%',
          background: '#fff',
          border: '4px solid #000',
          boxShadow: '0 0 0 3px #fff, 0 0 20px rgba(0,191,165,0.3)',
        }}/>
        <div style={{
          width: 52, height: 52, borderRadius: '50%',
          background: 'rgba(0,0,0,0.5)', border: '1px solid var(--w-12)',
          display:'flex', alignItems:'center', justifyContent:'center',
        }}>
          <Icon name="rotate" size={22} color="#fff"/>
        </div>
      </div>

      <HomeIndicator light/>
    </div>
  );
}

// ---------- CALENDAR — month ----------
function CalendarApp() {
  const days = [];
  for (let i = 0; i < 35; i++) days.push(i - 1); // dec 2025 starts on monday
  return (
    <AppShell>
      <TopBar title="December" actions={<>
        <Icon name="search" size={22} color="var(--text-secondary)"/>
        <div style={{
          width: 32, height: 32, borderRadius: 4, background: 'var(--teal-gradient)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#000',
        }}>
          <Icon name="plus" size={18}/>
        </div>
      </>}/>
      <div style={{ position: 'absolute', top: 116, left: 0, right: 0, bottom: 70, overflow: 'hidden', padding: '8px 12px' }}>
        {/* year row */}
        <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', padding:'4px 4px 14px' }}>
          <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>2025</div>
          <div style={{ display: 'flex', gap: 12, color: 'var(--text-secondary)' }}>
            <Icon name="chevron_left" size={18}/>
            <span style={{ fontSize: 13, color: 'var(--text-primary)', fontWeight: 600 }}>Today</span>
            <Icon name="chevron_right" size={18}/>
          </div>
        </div>

        {/* days header */}
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 1,
          fontSize: 10, color: 'var(--text-secondary)', fontWeight: 600, letterSpacing: 1,
          textAlign: 'center', padding: '0 0 6px',
        }}>
          {['M','T','W','T','F','S','S'].map((d,i) => <div key={i}>{d}</div>)}
        </div>

        {/* grid */}
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 1,
          background: 'var(--w-04)',
          border: '1px solid var(--w-04)',
        }}>
          {days.map((d,i) => {
            const isCur = d > 0 && d <= 31;
            const isToday = d === 5;
            const events = { 8: 1, 11: 2, 16: 1, 19: 1, 22: 1, 24: 3, 31: 1 };
            const c = events[d];
            return (
              <div key={i} style={{
                aspectRatio: '1 / 1.1',
                background: isToday ? 'var(--teal-gradient)' : 'var(--bb10-black)',
                color: isToday ? '#000' : (isCur ? 'var(--text-primary)' : 'var(--text-tertiary)'),
                padding: 4,
                fontSize: 13, fontWeight: isToday ? 700 : 400,
                display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
                position: 'relative',
              }}>
                <div>{isCur ? d : (d <= 0 ? 30 + d : d - 31)}</div>
                {c && !isToday && (
                  <div style={{ display:'flex', gap: 2 }}>
                    {Array.from({length: c}).map((_, j) => (
                      <div key={j} style={{ width: 4, height: 4, borderRadius: '50%', background: 'var(--teal-bright)' }}/>
                    ))}
                  </div>
                )}
                {c && isToday && (
                  <div style={{ display:'flex', gap: 2 }}>
                    {Array.from({length: c}).map((_, j) => (
                      <div key={j} style={{ width: 4, height: 4, borderRadius: '50%', background: '#000' }}/>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        {/* events for today */}
        <div style={{ padding: '16px 4px 8px' }}>
          <SectionLabel style={{ padding: 0 }}>Friday, December 5</SectionLabel>
        </div>
        <Card style={{ overflow: 'hidden' }}>
          {[
            { t:'12:00', dur:'60m', name:'Design review · Studio B', tag:'design' },
            { t:'15:30', dur:'30m', name:'1:1 with Devon · Coffee', tag:'1:1' },
            { t:'19:30', dur:'2h',  name:'Concert · Bowery', tag:'personal' },
          ].map((e,i) => (
            <div key={i} style={{ display:'flex', gap: 14, padding:'12px 14px', borderTop: i ? '1px solid var(--w-04)' : 'none' }}>
              <div style={{ width: 50, textAlign:'right', fontVariantNumeric: 'tabular-nums', flexShrink: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 600 }}>{e.t}</div>
                <div style={{ fontSize: 10, color:'var(--text-secondary)' }}>{e.dur}</div>
              </div>
              <div style={{ width: 3, background: 'var(--teal-gradient)', borderRadius: 2 }}/>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 500 }}>{e.name}</div>
                <div style={{ fontSize: 11, color:'var(--text-secondary)', marginTop: 2 }}>{e.tag}</div>
              </div>
            </div>
          ))}
        </Card>
      </div>
      <TabBar active={1} tabs={[
        { icon:'clock', label:'Day' },
        { icon:'calendar', label:'Month' },
        { icon:'archive', label:'Year' },
        { icon:'search', label:'Search' },
      ]}/>
    </AppShell>
  );
}

// ---------- CALCULATOR ----------
function CalculatorApp() {
  const rows = [
    ['C','( )','%','÷'],
    ['7','8','9','×'],
    ['4','5','6','−'],
    ['1','2','3','+'],
    ['+/−','0','.','='],
  ];
  return (
    <AppShell>
      {/* Header */}
      <div style={{
        height: 56, padding: '0 16px',
        background: 'var(--glass-titlebar)',
        backdropFilter: 'blur(12px)',
        borderBottom: '1px solid var(--border-glass)',
        display:'flex', alignItems:'center', justifyContent:'space-between',
      }}>
        <div style={{ display: 'flex', gap: 10, alignItems: 'center', color: 'var(--text-secondary)' }}>
          <Icon name="reply" size={18}/>
          <span style={{ fontSize: 12 }}>Undo</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13 }}>
          Basic
          <Icon name="chevron_down" size={14} color="var(--text-secondary)"/>
        </div>
        <div style={{ display: 'flex', gap: 12, color: 'var(--text-secondary)' }}>
          <Icon name="menu" size={18}/>
          <Icon name="x" size={18}/>
        </div>
      </div>

      {/* Display */}
      <div style={{
        position: 'absolute', top: 28 + 56, left: 0, right: 0, height: 280,
        padding: '24px 22px',
        display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', gap: 8,
        background: 'var(--bb10-deep)',
      }}>
        <div style={{ fontSize: 18, color: 'var(--text-secondary)', textAlign: 'right' }} className="mono">
          1,248 × 7
        </div>
        <div style={{ fontSize: 14, color: 'var(--teal-bright)', textAlign: 'right' }} className="mono">
          = 8,736
        </div>
        <div style={{
          fontSize: 52, textAlign: 'right', fontWeight: 200,
          letterSpacing: -1, fontVariantNumeric: 'tabular-nums',
          color: 'var(--text-primary)',
        }}>8,736</div>
      </div>

      {/* Operators chip row */}
      <div style={{
        position: 'absolute', top: 28 + 56 + 280, left: 0, right: 0,
        padding: '8px 14px',
        display: 'flex', gap: 6, overflowX: 'hidden',
        background: 'var(--elev-1)',
        borderTop: '1px solid var(--w-04)',
        borderBottom: '1px solid var(--w-04)',
      }}>
        {['C','( )','mod','π','√','x²','sin','cos'].map((s,i) => (
          <div key={s} style={{
            background: 'var(--elev-2)', border: '1px solid var(--w-08)',
            padding: '6px 14px', borderRadius: 4,
            fontSize: 13, color: 'var(--text-primary)',
            boxShadow: 'inset 0 1px 0 var(--w-04)',
            flexShrink: 0,
          }}>{s}</div>
        ))}
      </div>

      {/* Keypad */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, top: 28 + 56 + 280 + 50,
        background: 'var(--bb10-black)',
        padding: '12px 12px 30px',
        display:'grid', gridTemplateRows: 'repeat(5, 1fr)', gap: 8,
      }}>
        {rows.map((r, ri) => (
          <div key={ri} style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
            {r.map((k, ki) => {
              const isOp = ['÷','×','−','+'].includes(k);
              const isEq = k === '=';
              const isUtil = ki === 0 && ri === 0;
              return (
                <div key={ki} style={{
                  background: isEq ? 'var(--teal-gradient)' :
                              isOp ? 'var(--elev-3)' :
                              isUtil ? 'var(--elev-3)' : 'var(--elev-2)',
                  color: isEq ? '#000' : (isOp || isUtil ? 'var(--teal-bright)' : 'var(--text-primary)'),
                  border: isEq ? '1px solid var(--teal-border)' : '1px solid var(--w-04)',
                  borderRadius: 4,
                  boxShadow: isEq
                    ? '0 0 16px rgba(0,191,165,0.4), inset 0 1px 0 rgba(255,255,255,0.3)'
                    : 'inset 0 1px 0 var(--w-04)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: 22, fontWeight: isEq ? 700 : 400,
                }}>{k}</div>
              );
            })}
          </div>
        ))}
      </div>
    </AppShell>
  );
}

// ---------- MAPS ----------
function MapsApp() {
  return (
    <AppShell>
      {/* Map */}
      <div style={{
        position: 'absolute', top: 28, left: 0, right: 0, bottom: 0,
        background: '#0a1814',
        overflow: 'hidden',
      }}>
        {/* roads */}
        <svg width="390" height="800" style={{ position: 'absolute', inset: 0 }}>
          <defs>
            <linearGradient id="mapWater" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stopColor="#1f3a5c"/>
              <stop offset="1" stopColor="#0d2238"/>
            </linearGradient>
            <linearGradient id="mapPark" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="#1a3a26"/>
              <stop offset="1" stopColor="#0f2618"/>
            </linearGradient>
          </defs>

          {/* East river — muted navy */}
          <path d="M 310 -10 Q 340 200 320 400 Q 305 600 340 810 L 400 810 L 400 -10 Z" fill="url(#mapWater)"/>
          <path d="M 310 -10 Q 340 200 320 400 Q 305 600 340 810" fill="none" stroke="rgba(120,170,220,0.18)" strokeWidth="0.6"/>

          {/* Park — muted green */}
          <path d="M -40 540 Q 60 480 180 540 Q 200 620 100 660 Q 0 680 -40 620 Z" fill="url(#mapPark)"/>
          <path d="M -40 540 Q 60 480 180 540 Q 200 620 100 660 Q 0 680 -40 620 Z" fill="none" stroke="rgba(74,138,94,0.30)" strokeWidth="0.5"/>

          {/* Major roads */}
          <path d="M -10 200 Q 100 220 200 180 T 410 250" stroke="#2a3540" strokeWidth="14" fill="none"/>
          <path d="M -10 200 Q 100 220 200 180 T 410 250" stroke="#5a6878" strokeWidth="1.2" fill="none" strokeDasharray="6 4"/>
          <path d="M 60 -10 Q 90 200 200 360 T 280 800" stroke="#2a3540" strokeWidth="14" fill="none"/>
          <path d="M 60 -10 Q 90 200 200 360 T 280 800" stroke="#5a6878" strokeWidth="1.2" fill="none" strokeDasharray="6 4"/>

          {/* Minor roads (keep clear of water polygon on the right) */}
          <path d="M 0 380 L 290 420" stroke="#1c2630" strokeWidth="6" fill="none"/>
          <path d="M 0 480 L 295 510" stroke="#1c2630" strokeWidth="6" fill="none"/>
          <path d="M 0 620 L 300 600" stroke="#1c2630" strokeWidth="6" fill="none"/>
          <path d="M 150 0 L 170 800" stroke="#1c2630" strokeWidth="6" fill="none"/>

          {/* Labels */}
          <text x="80" y="608" fill="#7eaa8a" fontSize="9.5" textAnchor="middle" fontFamily="Sora" fontWeight="500" letterSpacing="0.4">Bryant Park</text>
          <text x="362" y="450" fill="#6f96be" fontSize="9" textAnchor="middle" fontFamily="Sora" letterSpacing="0.4" transform="rotate(90 362 450)">East River</text>
          <text x="220" y="300" fill="var(--text-tertiary)" fontSize="9" fontFamily="Sora">5th Ave</text>
          <text x="40" y="160" fill="var(--text-tertiary)" fontSize="9" fontFamily="Sora">Madison</text>
        </svg>

        {/* You are here */}
        <div style={{
          position: 'absolute', left: '38%', top: '52%',
          transform: 'translate(-50%, -50%)',
        }}>
          <div style={{
            width: 16, height: 16, borderRadius: '50%', background: 'var(--teal-bright)',
            border: '3px solid #fff',
            boxShadow: '0 0 0 1px rgba(0,0,0,0.6), 0 0 30px var(--teal-glow)',
            position: 'relative', zIndex: 2,
          }}/>
          <div style={{
            position: 'absolute', inset: -22, borderRadius: '50%',
            background: 'radial-gradient(circle, rgba(0,191,165,0.25), transparent 65%)',
          }}/>
        </div>

        {/* destination pin */}
        <div style={{ position: 'absolute', left: '68%', top: '32%' }}>
          <svg width="34" height="44" viewBox="0 0 34 44">
            <path d="M17 0a14 14 0 0 1 14 14c0 11-14 28-14 28S3 25 3 14A14 14 0 0 1 17 0z" fill="#1de9b6" stroke="#040404" strokeWidth="1.5"/>
            <circle cx="17" cy="14" r="5" fill="#040404"/>
          </svg>
        </div>
      </div>

      {/* Top: search */}
      <div style={{
        position: 'absolute', top: 40, left: 14, right: 14,
        background: 'var(--glass-titlebar)',
        backdropFilter: 'blur(12px)',
        border: '1px solid var(--border-glass)',
        borderRadius: 4,
        boxShadow: '0 8px 24px -10px rgba(0,0,0,0.6), inset 0 1px 0 var(--w-04)',
        padding: '10px 14px',
        display: 'flex', alignItems: 'center', gap: 10,
      }}>
        <Icon name="search" size={18} color="var(--text-secondary)"/>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 14, fontWeight: 500 }}>Studio B</div>
          <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>475 W 26th St · 0.4 mi · 7 min walk</div>
        </div>
        <div style={{
          width: 28, height: 28, borderRadius: '50%', background: 'var(--elev-3)',
          border: '1px solid var(--w-08)',
        }}/>
      </div>

      {/* Recenter button */}
      <div style={{
        position: 'absolute', right: 14, top: 200,
        width: 42, height: 42, borderRadius: 4,
        background: 'var(--glass-titlebar)',
        backdropFilter: 'blur(12px)',
        border: '1px solid var(--border-glass)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: 'var(--teal-bright)',
        boxShadow: '0 4px 12px rgba(0,0,0,0.4)',
      }}>
        <Icon name="map_pin" size={20}/>
      </div>

      {/* Bottom card */}
      <Card style={{
        position: 'absolute', left: 14, right: 14, bottom: 24,
        padding: 0, overflow: 'hidden',
      }} elev={3}>
        <div style={{ padding: 14, display:'flex', gap: 14 }}>
          <div style={{
            width: 56, height: 56, borderRadius: 4,
            background: 'linear-gradient(135deg, #1a4a3e, #0d2620)',
            border: '1px solid var(--w-08)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon name="map_pin" size={24} color="var(--teal-bright)"/>
          </div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 16, fontWeight: 600 }}>Studio B</div>
            <div style={{ fontSize: 12, color:'var(--text-secondary)', marginTop: 2 }}>
              Design space · Open until 8 PM
            </div>
            <div style={{ display:'flex', gap: 6, marginTop: 6 }}>
              <div className="m-chip muted" style={{ fontSize: 10 }}>★ 4.7</div>
              <div className="m-chip muted" style={{ fontSize: 10 }}>$$</div>
            </div>
          </div>
        </div>
        <div style={{ display:'flex', borderTop: '1px solid var(--w-04)' }}>
          <ActionCell glyph="arrow_up" label="Directions" primary/>
          <ActionCell glyph="phone" label="Call"/>
          <ActionCell glyph="share" label="Share"/>
          <ActionCell glyph="star" label="Save"/>
        </div>
      </Card>
    </AppShell>
  );
}

function ActionCell({ glyph, label, primary }) {
  return (
    <div style={{
      flex: 1, padding: '12px 0',
      display:'flex', flexDirection:'column', alignItems:'center', gap: 4,
      color: primary ? 'var(--teal-bright)' : 'var(--text-primary)',
      borderRight: '1px solid var(--w-04)',
    }}>
      <Icon name={glyph} size={18}/>
      <div style={{ fontSize: 11, fontWeight: 500 }}>{label}</div>
    </div>
  );
}

// ---------- CLOCK — world clocks + analog ----------
function ClockApp() {
  const cities = [
    { n:'New York', off:'Local', t:'11:42 AM', d:'Fri' },
    { n:'London',   off:'+5h', t:'4:42 PM', d:'Fri' },
    { n:'Tokyo',    off:'+14h', t:'1:42 AM', d:'Sat' },
    { n:'Sydney',   off:'+16h', t:'3:42 AM', d:'Sat' },
  ];
  return (
    <AppShell>
      <TopBar title="Clock" actions={<>
        <Icon name="plus" size={22} color="var(--text-secondary)"/>
        <Icon name="more" size={22} color="var(--text-secondary)"/>
      </>}/>
      <div style={{ position: 'absolute', top: 116, left: 0, right: 0, bottom: 70, padding: '12px 16px', overflow: 'hidden' }}>
        {/* Big analog clock */}
        <div style={{
          aspectRatio: '1', maxWidth: 240, margin: '8px auto 18px',
          position: 'relative',
        }}>
          <svg viewBox="0 0 200 200" width="100%" height="100%">
            <defs>
              <radialGradient id="cdial" cx="50%" cy="50%" r="50%">
                <stop offset="0" stopColor="#1a1b1c"/>
                <stop offset="1" stopColor="#040404"/>
              </radialGradient>
            </defs>
            <circle cx="100" cy="100" r="96" fill="url(#cdial)" stroke="rgba(0,191,165,0.35)" strokeWidth="1"/>
            {/* tick marks every 6° */}
            {Array.from({length: 60}).map((_,i) => {
              const big = i % 5 === 0;
              const a = (i * 6 - 90) * Math.PI / 180;
              const r1 = big ? 78 : 86;
              const r2 = 92;
              return <line key={i}
                x1={100 + Math.cos(a)*r1} y1={100 + Math.sin(a)*r1}
                x2={100 + Math.cos(a)*r2} y2={100 + Math.sin(a)*r2}
                stroke={big ? 'var(--teal-bright)' : 'var(--text-tertiary)'}
                strokeWidth={big ? 2 : 1}/>;
            })}
            {/* numbers at 12 3 6 9 */}
            {[[12,100,30],[3,170,108],[6,100,178],[9,30,108]].map(([n,x,y]) => (
              <text key={n} x={x} y={y} fill="var(--teal-bright)" fontSize="14" textAnchor="middle" fontFamily="Sora" fontWeight="300">{n}</text>
            ))}
            {/* hour hand */}
            <line x1="100" y1="100" x2="148" y2="76" stroke="#f5f5f5" strokeWidth="3" strokeLinecap="round"/>
            {/* minute hand */}
            <line x1="100" y1="100" x2="120" y2="34" stroke="#f5f5f5" strokeWidth="2" strokeLinecap="round"/>
            {/* second hand */}
            <line x1="100" y1="100" x2="58" y2="148" stroke="var(--teal-bright)" strokeWidth="1" strokeLinecap="round"/>
            <circle cx="100" cy="100" r="4" fill="var(--teal-bright)"/>
            <circle cx="100" cy="100" r="2" fill="#000"/>
            {/* PM / FRI markers */}
            <text x="100" y="138" fill="var(--text-secondary)" fontSize="10" textAnchor="middle" fontFamily="Sora">PM</text>
            <text x="62" y="108" fill="var(--text-tertiary)" fontSize="9" fontFamily="Sora">FRI</text>
          </svg>
        </div>

        <SectionLabel>World Clocks</SectionLabel>
        <Card style={{ overflow: 'hidden' }}>
          {cities.map((c, i) => (
            <div key={i} className="m-row" style={{ padding: '14px 14px' }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{c.off}</div>
                <div style={{ fontSize: 16, fontWeight: 500, marginTop: 2 }}>{c.n}</div>
              </div>
              <div style={{ textAlign:'right' }}>
                <div style={{ fontSize: 22, fontWeight: 200, fontVariantNumeric: 'tabular-nums' }}>{c.t}</div>
                <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>{c.d}</div>
              </div>
            </div>
          ))}
        </Card>
      </div>
      <TabBar active={1} tabs={[
        { icon:'globe', label:'World' },
        { icon:'clock', label:'Clock' },
        { icon:'alarm', label:'Alarm' },
        { icon:'play', label:'Timer' },
      ]}/>
    </AppShell>
  );
}

// ---------- GALLERY ----------
function GalleryApp() {
  // Generate a "moments" grid with subtle abstract images via CSS
  const tiles = [
    'linear-gradient(135deg, #1a4a3e, #0d2620)',
    'linear-gradient(135deg, var(--elev-3), var(--elev-2))',
    'linear-gradient(180deg, var(--elev-4), var(--elev-2))',
    'linear-gradient(180deg, #1a1b1c, #040404), radial-gradient(circle at 60% 30%, #5dffdc, transparent 60%)',
    'linear-gradient(45deg, #1de9b6 0%, #006b5d 100%)',
    'linear-gradient(180deg, var(--elev-3), var(--elev-4))',
    'linear-gradient(135deg, var(--elev-3), var(--elev-2))',
    'linear-gradient(180deg, #040404, #1c1c1d)',
    'linear-gradient(135deg, #f5f5f5, #6a6a6a)',
  ];
  return (
    <AppShell>
      <TopBar title="Gallery" actions={<>
        <Icon name="search" size={22} color="var(--text-secondary)"/>
        <Icon name="more" size={22} color="var(--text-secondary)"/>
      </>}/>
      <div style={{ position: 'absolute', top: 116, left: 0, right: 0, bottom: 70, padding: '8px 14px', overflow: 'hidden' }}>
        <SectionLabel>Today · Studio B</SectionLabel>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 4, marginBottom: 14 }}>
          {[0,1,2].map(i => (
            <div key={i} style={{
              aspectRatio: '1', background: tiles[i],
              border: '1px solid var(--w-04)',
              position: 'relative',
            }}>
              {i === 0 && <div style={{
                position:'absolute', top: 4, right: 4,
                background: 'rgba(0,0,0,0.6)', borderRadius: 2,
                padding: '1px 4px', fontSize: 9, color: '#fff',
              }}>0:14</div>}
            </div>
          ))}
        </div>
        <SectionLabel>Yesterday · Brooklyn</SectionLabel>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 4, marginBottom: 14 }}>
          {[3,4,5,6,7,8].map(i => (
            <div key={i} style={{
              aspectRatio: '1', background: tiles[i],
              border: '1px solid var(--w-04)',
            }}/>
          ))}
        </div>
        <SectionLabel>Memories</SectionLabel>
        <div style={{ display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 4 }}>
          <div style={{
            aspectRatio: '2', borderRadius: 4, overflow: 'hidden',
            background: 'linear-gradient(135deg, #1a4a3e, #040404)',
            position: 'relative',
            border: '1px solid var(--w-04)',
          }}>
            <div style={{ position:'absolute', bottom: 8, left: 10 }}>
              <div style={{ fontSize: 14, fontWeight: 600 }}>One year ago</div>
              <div style={{ fontSize: 11, color: 'var(--text-secondary)' }}>14 photos · 2 videos</div>
            </div>
          </div>
          <div style={{
            aspectRatio: '1', background: tiles[4],
            border: '1px solid var(--w-04)',
          }}/>
        </div>
      </div>
      <TabBar active={1} tabs={[
        { icon:'star', label:'Albums' },
        { icon:'camera', label:'Photos' },
        { icon:'play', label:'Memories' },
        { icon:'search', label:'Search' },
      ]}/>
    </AppShell>
  );
}

// ---------- NOTES ----------
function NotesApp() {
  return (
    <AppShell>
      <TopBar title="Notes" actions={<>
        <Icon name="search" size={22} color="var(--text-secondary)"/>
        <div style={{
          width: 32, height: 32, borderRadius: 4, background: 'var(--teal-gradient)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#000',
        }}><Icon name="plus" size={18}/></div>
      </>}/>
      <div style={{ position: 'absolute', top: 116, left: 0, right: 0, bottom: 70, padding: '0 16px', overflow: 'hidden' }}>
        <SectionLabel style={{ padding: '12px 4px 8px' }}>Pinned</SectionLabel>
        <Card style={{ padding: 14, marginBottom: 10 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
            <Icon name="star" size={12} color="var(--teal-bright)"/>
            <div style={{ fontSize: 11, color: 'var(--teal-bright)', fontWeight: 600, letterSpacing: 0.5 }}>MARATHON OS — DESIGN AUDIT</div>
          </div>
          <div style={{ fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.5, marginTop: 6 }}>
            Marathon reads as a dark, glass-and-neon mobile shell with a sharp engineering aesthetic — equal parts BlackBerry 10 and modern Material-era restraint…
          </div>
          <div style={{ fontSize: 11, color: 'var(--text-secondary)', marginTop: 10 }}>edited 11:14 AM · 1,294 words</div>
        </Card>

        <SectionLabel style={{ padding: '8px 4px 8px' }}>Today</SectionLabel>
        <Card style={{ overflow: 'hidden' }}>
          {[
            { t:'Concert prep', d:'tickets, route, what to bring…', tag:'#personal' },
            { t:'1:1 Devon · agenda', d:'Roadmap risks, hiring debrief', tag:'#work' },
            { t:'Slate Editor — release notes', d:'v2.4 — new outliner; collab cursors landed', tag:'#work' },
            { t:'Reading list', d:'two papers + Halt and Catch Fire rewatch', tag:'#read' },
            { t:'Grocery', d:'oat milk · coffee · lemons · spinach', tag:'#home' },
          ].map((n,i) => (
            <div key={i} className="m-row" style={{ alignItems: 'flex-start', padding: '14px 14px' }}>
              <div className="row-icon" style={{ background: 'var(--elev-3)' }}>
                <Icon name="note" size={16}/>
              </div>
              <div className="row-text">
                <div className="row-title" style={{ fontSize: 14 }}>{n.t}</div>
                <div className="row-subtitle">{n.d}</div>
              </div>
              <div style={{ fontSize: 10, color: 'var(--teal-bright)', fontWeight: 600 }}>{n.tag}</div>
            </div>
          ))}
        </Card>
      </div>
      <TabBar active={0} tabs={[
        { icon:'note', label:'Notes' },
        { icon:'archive', label:'Folders' },
        { icon:'check', label:'Tasks' },
      ]}/>
    </AppShell>
  );
}

// ============================================================
// OOBE flow
// ============================================================
function OOBELanguage() {
  const langs = [
    { l:'English', s:'United States', sel: true },
    { l:'English', s:'United Kingdom' },
    { l:'Español', s:'México' },
    { l:'Français', s:'France' },
    { l:'Deutsch',  s:'Deutschland' },
    { l:'日本語',    s:'日本' },
    { l:'한국어',    s:'대한민국' },
    { l:'Português', s:'Brasil' },
  ];
  return (
    <div className="phone no-scroll">
      <div style={{ position:'absolute', inset:0, background: 'var(--bb10-black)' }}/>
      <div style={{ position: "absolute", inset: 0, opacity: 0.4 }}><WallpaperSlateAurora/></div>

      <StatusBar time="—" battery={100} centerTime={false}/>

      <div style={{ padding: '50px 28px 24px' }}>
        <Icon name="globe" size={48} color="var(--teal-bright)"/>
        <div style={{ fontSize: 36, fontWeight: 200, letterSpacing: -0.8, marginTop: 18, lineHeight: 1.05 }}>
          Choose your<br/>language
        </div>
        <div style={{ fontSize: 14, color: 'var(--text-secondary)', marginTop: 10 }}>
          This sets the system language and default keyboard. You can change either later.
        </div>
      </div>

      <div style={{ position: 'absolute', top: 290, left: 16, right: 16, bottom: 110, overflow: 'hidden' }}>
        <Card style={{ overflow: 'hidden' }}>
          {langs.map((g,i) => (
            <div key={i} className="m-row" style={{ padding: '14px 16px' }}>
              <div className="row-text">
                <div className="row-title">{g.l}</div>
                <div className="row-subtitle">{g.s}</div>
              </div>
              {g.sel && <div style={{ color: 'var(--teal-bright)' }}><Icon name="check" size={20}/></div>}
            </div>
          ))}
        </Card>
      </div>

      {/* Footer */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        padding: '14px 20px 26px',
        background: 'linear-gradient(180deg, transparent, var(--bb10-black) 30%)',
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      }}>
        <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Step 1 of 5</div>
        <button className="m-btn primary" style={{ height: 44, padding: '0 26px' }}>
          Continue <Icon name="chevron_right" size={16}/>
        </button>
      </div>
      <HomeIndicator/>
    </div>
  );
}

function OOBEWifi() {
  const nets = [
    { n:'Marathon-Mesh', s:5, locked:true, sel: true },
    { n:'Marathon-Guest', s:4, locked:false },
    { n:'CafeBleu_5G', s:3, locked:true },
    { n:'eduroam', s:3, locked:true },
    { n:'xfinitywifi', s:2, locked:false },
    { n:'Pixel_2A1B', s:2, locked:true },
  ];
  return (
    <div className="phone no-scroll">
      <div style={{ position:'absolute', inset:0, background:'var(--bb10-black)' }}/>
      <div style={{ position: "absolute", inset: 0, opacity: 0.4 }}><WallpaperSlateAurora/></div>
      <StatusBar time="—" battery={100} centerTime={false}/>

      <div style={{ padding: '50px 28px 24px' }}>
        <Icon name="wifi" size={48} color="var(--teal-bright)"/>
        <div style={{ fontSize: 36, fontWeight: 200, letterSpacing: -0.8, marginTop: 18, lineHeight: 1.05 }}>
          Get<br/>connected
        </div>
        <div style={{ fontSize: 14, color: 'var(--text-secondary)', marginTop: 10 }}>
          Marathon will download the latest updates and verify your device. This takes about a minute.
        </div>
      </div>

      <div style={{ position: 'absolute', top: 290, left: 16, right: 16, bottom: 110, overflow: 'hidden' }}>
        <Card style={{ overflow: 'hidden' }}>
          {nets.map((n,i) => (
            <div key={i} className="m-row" style={{ padding: '14px 16px' }}>
              <div className="row-icon" style={{
                background: n.sel ? 'rgba(0,191,165,0.15)' : 'var(--elev-3)',
                color: n.sel ? 'var(--teal-bright)' : 'var(--text-primary)',
                border: n.sel ? '1px solid var(--teal-border)' : 'none',
              }}>
                <Icon name="wifi" size={16}/>
              </div>
              <div className="row-text">
                <div className="row-title">{n.n}</div>
                <div className="row-subtitle">Signal {n.s}/5 · {n.locked ? 'WPA2' : 'Open'}</div>
              </div>
              {n.sel ? (
                <div style={{ color: 'var(--teal-bright)' }}><Icon name="check" size={20}/></div>
              ) : (
                n.locked && <Icon name="lock" size={14} color="var(--text-tertiary)"/>
              )}
            </div>
          ))}
        </Card>
        <div style={{ padding: '12px 4px', fontSize: 12, color: 'var(--text-secondary)' }}>
          Connected to Marathon-Mesh · 2.4 Mbps download
        </div>
      </div>

      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        padding: '14px 20px 26px',
        background: 'linear-gradient(180deg, transparent, var(--bb10-black) 30%)',
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      }}>
        <div style={{ fontSize: 12, color: 'var(--text-secondary)' }}>Step 2 of 5</div>
        <button className="m-btn primary" style={{ height: 44, padding: '0 26px' }}>
          Continue <Icon name="chevron_right" size={16}/>
        </button>
      </div>
      <HomeIndicator/>
    </div>
  );
}

function OOBEFinish() {
  return (
    <div className="phone no-scroll">
      <div style={{ position:'absolute', inset:0, background:'var(--bb10-black)' }}/>
      <div style={{ position: "absolute", inset: 0, opacity: 0.7 }}><WallpaperIndigoDusk/></div>
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(ellipse 380px 380px at 50% 35%, rgba(0,191,165,0.25), transparent 60%)',
      }}/>
      <StatusBar time="11:42" battery={100}/>

      <div style={{
        position: 'absolute', inset: 0,
        display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
        textAlign: 'center', padding: '0 36px',
      }}>
        <div style={{
          width: 110, height: 110, borderRadius: '50%',
          background: 'var(--teal-gradient)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#000',
          boxShadow: '0 0 60px rgba(0,191,165,0.5), inset 0 1px 0 rgba(255,255,255,0.3)',
          marginBottom: 30,
        }}>
          <Icon name="check" size={56}/>
        </div>
        <div style={{ fontSize: 40, fontWeight: 200, letterSpacing: -1, lineHeight: 1 }}>You're all set</div>
        <div style={{ fontSize: 14, color: 'var(--text-secondary)', marginTop: 14, lineHeight: 1.5 }}>
          Marathon is ready. Your apps will appear on the home grid in a moment, and Cloud sync is running in the background.
        </div>
        <button className="m-btn primary" style={{ height: 50, padding: '0 40px', marginTop: 40, fontSize: 15 }}>
          Get started
        </button>
        <div style={{ fontSize: 12, color: 'var(--text-tertiary)', marginTop: 18 }}>
          Marathon OS · 4.2.1 (Avior)
        </div>
      </div>

      <HomeIndicator/>
    </div>
  );
}

Object.assign(window, {
  MusicNowPlaying, CameraApp, CalendarApp, CalculatorApp,
  MapsApp, ClockApp, GalleryApp, NotesApp,
  OOBELanguage, OOBEWifi, OOBEFinish,
});
