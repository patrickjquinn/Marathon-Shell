/* global React */

// ============================================================
// Marathon wallpapers — visible behind lock + home variants.
// Pure SVG/CSS so they scale crisply at any density.
// ============================================================

// "Slate Aurora" — Marathon's default. A diagonal teal sweep + faint
// topographic lines on near-black. Mirrors the BB10 ribbon vibe.
function WallpaperSlateAurora() {
  return (
    <div style={{
      position: 'absolute', inset: 0,
      background: '#040404',
      overflow: 'hidden',
    }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
        style={{ position: 'absolute', inset: 0 }}>
        <defs>
          {/* The big aurora ribbon */}
          <linearGradient id="aurora" x1="0" y1="1" x2="1" y2="0">
            <stop offset="0" stopColor="#1de9b6" stopOpacity="0.85"/>
            <stop offset="0.4" stopColor="#00897b" stopOpacity="0.55"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </linearGradient>
          <linearGradient id="auroraGlow" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#1de9b6" stopOpacity="0.4"/>
            <stop offset="1" stopColor="#1de9b6" stopOpacity="0"/>
          </linearGradient>
          {/* Bottom right halo */}
          <radialGradient id="hbottom" cx="0" cy="1" r="0.7">
            <stop offset="0" stopColor="#00897b" stopOpacity="0.55"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
          {/* Top right faint */}
          <radialGradient id="htop" cx="1" cy="0" r="0.5">
            <stop offset="0" stopColor="#1de9b6" stopOpacity="0.18"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
        </defs>

        {/* Subtle topographic curves */}
        <g stroke="rgba(255,255,255,0.025)" strokeWidth="0.6" fill="none">
          <path d="M -50 200 Q 100 180 200 220 T 440 240"/>
          <path d="M -50 320 Q 110 290 230 340 T 440 360"/>
          <path d="M -50 460 Q 110 440 220 480 T 440 500"/>
          <path d="M -50 580 Q 130 560 240 600 T 440 620"/>
          <path d="M -50 700 Q 140 680 260 720 T 440 740"/>
        </g>

        {/* Aurora ribbon — sweeps from bottom-left up */}
        <g opacity="0.85">
          <path d="M -80 900 L 250 50 L 470 -50 L 470 200 L 100 940 Z" fill="url(#aurora)"/>
          <path d="M -80 940 L 280 200 L 470 100 L 470 350 L 70 990 Z" fill="url(#aurora)" opacity="0.5"/>
        </g>

        {/* Bottom-left teal halo */}
        <rect width="390" height="844" fill="url(#hbottom)"/>
        <rect width="390" height="844" fill="url(#htop)"/>

        {/* Crisp diagonal accent line */}
        <line x1="-30" y1="640" x2="430" y2="220" stroke="rgba(29,233,182,0.18)" strokeWidth="0.8"/>
        <line x1="-30" y1="780" x2="430" y2="360" stroke="rgba(29,233,182,0.10)" strokeWidth="0.8"/>

        {/* Light particle dots */}
        <g fill="#1de9b6">
          {[
            [60, 720, 1.4, 0.7], [120, 660, 0.8, 0.4], [320, 80, 0.6, 0.5],
            [240, 540, 1.2, 0.6], [80, 410, 0.7, 0.3], [340, 590, 1.0, 0.5],
            [180, 130, 0.5, 0.3], [300, 350, 0.6, 0.35], [200, 760, 0.9, 0.4],
          ].map(([x,y,r,o],i) => <circle key={i} cx={x} cy={y} r={r} opacity={o}/>)}
        </g>
      </svg>
    </div>
  );
}

// "Carbon" — pure near-black with a single light streak. For surfaces
// where the aurora would compete with content (e.g. settings).
function WallpaperCarbon() {
  return (
    <div style={{
      position: 'absolute', inset: 0,
      background: '#040404',
    }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
        style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <linearGradient id="streak" x1="0" y1="1" x2="1" y2="0">
            <stop offset="0" stopColor="#00897b" stopOpacity="0.18"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </linearGradient>
        </defs>
        <rect width="390" height="844" fill="url(#streak)"/>
        <line x1="0" y1="700" x2="390" y2="200" stroke="rgba(29,233,182,0.08)" strokeWidth="0.8"/>
      </svg>
    </div>
  );
}

// "Indigo Dusk" — for OOBE final. Subtle indigo+teal swirl, warmer.
function WallpaperIndigoDusk() {
  return (
    <div style={{
      position: 'absolute', inset: 0,
      background: '#040404',
      overflow: 'hidden',
    }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
        style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <radialGradient id="dusk1" cx="0.5" cy="0.4" r="0.7">
            <stop offset="0" stopColor="#1de9b6" stopOpacity="0.35"/>
            <stop offset="0.5" stopColor="#3b3bb0" stopOpacity="0.25"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
        </defs>
        <rect width="390" height="844" fill="url(#dusk1)"/>
        <g fill="#fff">
          {Array.from({length: 30}).map((_, i) => {
            const seed = i * 73;
            const x = (seed * 13) % 390;
            const y = (seed * 7) % 844;
            const r = ((seed % 3) + 1) * 0.4;
            const o = ((seed % 5) + 1) * 0.05;
            return <circle key={i} cx={x} cy={y} r={r} opacity={o}/>;
          })}
        </g>
      </svg>
    </div>
  );
}

// ============================================================
// 10 additional wallpapers. Cohesive brand language across all:
//  • Pure black base (#040404)
//  • Teal as the ONLY primary accent — secondary muted hues sparingly
//  • Every wallpaper anchors a horizon at y=540 (golden ratio of 844)
//  • Sparse, engineered, never decorative
// Mapped to canvas labels: Long Run / Track / Mesh / Contour / Stride /
// Striae / Halftone / Pulse / Dawn / Tundra. Function names stay stable
// so Marathon OS.html imports don't change.
// ============================================================

// Shared horizon — every wallpaper layers this at the end so the line
// reads consistently across the family.
const HORIZON_Y = 540;
function Horizon({ opacity = 0.5, sun = false }) {
  return (
    <g>
      <line x1="0" y1={HORIZON_Y} x2="390" y2={HORIZON_Y}
            stroke="#1de9b6" strokeWidth="0.7" opacity={opacity}/>
      <line x1="0" y1={HORIZON_Y} x2="390" y2={HORIZON_Y}
            stroke="#5dffdc" strokeWidth="0.3" opacity={opacity * 0.7}/>
      {sun && (
        <g>
          <circle cx="195" cy={HORIZON_Y} r="2.5" fill="#5dffdc" opacity="0.95"/>
          <circle cx="195" cy={HORIZON_Y} r="8" fill="#1de9b6" opacity="0.18"/>
        </g>
      )}
    </g>
  );
}

// ---------- 1. "Long Run" — Marathon's signature mark at wallpaper scale.
// Concentric horizon arcs rising from the baseline.
function WallpaperLongRun() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#040404', overflow: 'hidden' }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
           style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <radialGradient id="lr-glow" cx="0.5" cy={HORIZON_Y / 844} r="0.5">
            <stop offset="0" stopColor="#1de9b6" stopOpacity="0.20"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
        </defs>
        <rect width="390" height="844" fill="url(#lr-glow)"/>
        {/* Five concentric horizon arcs */}
        <g fill="none" strokeLinecap="round">
          {[
            { r: 360, c: '#5dffdc', w: 1.2, o: 0.85 },
            { r: 280, c: '#1de9b6', w: 1.0, o: 0.65 },
            { r: 210, c: '#00bfa5', w: 0.9, o: 0.50 },
            { r: 150, c: '#00897b', w: 0.8, o: 0.40 },
            { r:  90, c: '#006b5d', w: 0.7, o: 0.30 },
          ].map((a, i) => (
            <path key={i}
                  d={`M ${195 - a.r} ${HORIZON_Y} A ${a.r} ${a.r} 0 0 1 ${195 + a.r} ${HORIZON_Y}`}
                  stroke={a.c} strokeWidth={a.w} opacity={a.o}/>
          ))}
        </g>
        <Horizon opacity={0.6} sun/>
      </svg>
    </div>
  );
}

// ---------- 2. "Track" (was Flowfield) — parallel horizontal running lanes.
// Reads as a track from above. Subtle perspective fade in/out.
function WallpaperFlowfield() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#040404', overflow: 'hidden' }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
           style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <linearGradient id="track-fade" x1="0" y1="0" x2="1" y2="0">
            <stop offset="0" stopColor="#040404" stopOpacity="1"/>
            <stop offset="0.15" stopColor="#040404" stopOpacity="0"/>
            <stop offset="0.85" stopColor="#040404" stopOpacity="0"/>
            <stop offset="1" stopColor="#040404" stopOpacity="1"/>
          </linearGradient>
          <radialGradient id="track-glow" cx="0.5" cy={HORIZON_Y / 844} r="0.45">
            <stop offset="0" stopColor="#00897b" stopOpacity="0.18"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
        </defs>
        <rect width="390" height="844" fill="url(#track-glow)"/>
        {/* 7 lanes — center-bright, edges-dim */}
        <g>
          {[-90, -60, -30, 0, 30, 60, 90].map((dy, i) => {
            const dist = Math.abs(dy) / 90;
            const opacity = 0.55 - dist * 0.38;
            const width = i === 3 ? 1.2 : 0.7;
            return (
              <line key={i}
                    x1={20} y1={HORIZON_Y + dy} x2={370} y2={HORIZON_Y + dy}
                    stroke="#1de9b6" strokeWidth={width} opacity={opacity}/>
            );
          })}
        </g>
        <rect width="390" height="844" fill="url(#track-fade)" opacity="0.6"/>
      </svg>
    </div>
  );
}

// ---------- 3. "Mesh" — engineering blueprint grid with one bright crosshair.
function WallpaperMesh() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#040404', overflow: 'hidden' }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
           style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <pattern id="mesh-fine" width="6" height="6" patternUnits="userSpaceOnUse">
            <path d="M 6 0 L 0 0 0 6" fill="none" stroke="rgba(255,255,255,0.022)" strokeWidth="0.3"/>
          </pattern>
          <pattern id="mesh-main" width="30" height="30" patternUnits="userSpaceOnUse">
            <path d="M 30 0 L 0 0 0 30" fill="none" stroke="rgba(29,233,182,0.07)" strokeWidth="0.5"/>
          </pattern>
          <radialGradient id="mesh-vignette" cx="0.5" cy={HORIZON_Y / 844} r="0.85">
            <stop offset="0.35" stopColor="#040404" stopOpacity="0"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0.75"/>
          </radialGradient>
        </defs>
        <rect width="390" height="844" fill="url(#mesh-fine)"/>
        <rect width="390" height="844" fill="url(#mesh-main)"/>
        {/* One bright crosshair on the horizon — center of the mesh */}
        <line x1="0" y1={HORIZON_Y} x2="390" y2={HORIZON_Y} stroke="#1de9b6" strokeWidth="0.9" opacity="0.55"/>
        <line x1="195" y1="0" x2="195" y2="844" stroke="#1de9b6" strokeWidth="0.9" opacity="0.55"/>
        {/* Crosshair node */}
        <circle cx="195" cy={HORIZON_Y} r="3" fill="#5dffdc" opacity="0.95"/>
        <circle cx="195" cy={HORIZON_Y} r="10" fill="#1de9b6" opacity="0.18"/>
        <rect width="390" height="844" fill="url(#mesh-vignette)"/>
      </svg>
    </div>
  );
}

// ---------- 4. "Contour" (was Topographic) — concentric ellipses, single peak.
// Cleaner than the previous version; no extraneous wavy lines.
function WallpaperTopographic() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#040404', overflow: 'hidden' }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
           style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <radialGradient id="contour-glow" cx="0.5" cy={HORIZON_Y / 844} r="0.45">
            <stop offset="0" stopColor="#1de9b6" stopOpacity="0.16"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
        </defs>
        <rect width="390" height="844" fill="url(#contour-glow)"/>
        {/* 12 concentric ellipses centered on horizon */}
        <g fill="none">
          {Array.from({ length: 12 }).map((_, i) => {
            const r = 38 + i * 28;
            const op = 0.55 - i * 0.04;
            const w = i === 0 ? 1.2 : 0.55;
            const c = i === 0 ? '#5dffdc' : '#1de9b6';
            return (
              <ellipse key={i} cx="195" cy={HORIZON_Y}
                       rx={r} ry={r * 0.62}
                       stroke={c} strokeWidth={w} opacity={op}/>
            );
          })}
        </g>
        <Horizon opacity={0.35}/>
        <circle cx="195" cy={HORIZON_Y} r="2.5" fill="#5dffdc" opacity="0.95"/>
      </svg>
    </div>
  );
}

// ---------- 5. "Stride" (was Drift) — parallel diagonal strokes, forward.
// Implies motion without animating. All same angle, varying length.
function WallpaperDrift() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#040404', overflow: 'hidden' }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
           style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <radialGradient id="stride-glow" cx="0.7" cy={HORIZON_Y / 844} r="0.55">
            <stop offset="0" stopColor="#00897b" stopOpacity="0.20"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
        </defs>
        <rect width="390" height="844" fill="url(#stride-glow)"/>
        {/* Diagonal strides on a regular lattice — angle 60° */}
        <g stroke="#1de9b6" strokeLinecap="round">
          {Array.from({ length: 22 }).map((_, row) => (
            Array.from({ length: 5 }).map((_, col) => {
              const x = col * 90 + (row % 2 ? 45 : 0) - 20;
              const y = row * 42 - 20;
              const len = 22 + (((row * 7 + col * 13) % 12));
              const dist = Math.abs(y - HORIZON_Y) / 422;
              const op = 0.50 - dist * 0.30;
              return (
                <line key={`${row}-${col}`}
                      x1={x} y1={y + len}
                      x2={x + len * 0.7} y2={y}
                      strokeWidth="0.8" opacity={op}/>
              );
            })
          )).flat()}
        </g>
        <Horizon opacity={0.4}/>
      </svg>
    </div>
  );
}

// ---------- 6. "Tundra" — pure cool gradient with horizon. No literal mountains.
function WallpaperTundra() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#040404', overflow: 'hidden' }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
           style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <linearGradient id="tundra-sky" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0"   stopColor="#3a6b9c" stopOpacity="0.55"/>
            <stop offset="0.45" stopColor="#1f3a5c" stopOpacity="0.45"/>
            <stop offset={HORIZON_Y / 844} stopColor="#040404" stopOpacity="0.95"/>
            <stop offset="1"   stopColor="#040404" stopOpacity="1"/>
          </linearGradient>
          <radialGradient id="tundra-glow" cx="0.5" cy={HORIZON_Y / 844} r="0.4">
            <stop offset="0" stopColor="#1de9b6" stopOpacity="0.22"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
        </defs>
        <rect width="390" height="844" fill="url(#tundra-sky)"/>
        <rect width="390" height="844" fill="url(#tundra-glow)"/>
        {/* A subtle concentric arc echo above the horizon */}
        <g fill="none" stroke="#1de9b6" strokeLinecap="round" opacity="0.45">
          <path d={`M ${195 - 220} ${HORIZON_Y} A 220 220 0 0 1 ${195 + 220} ${HORIZON_Y}`}
                strokeWidth="0.7"/>
          <path d={`M ${195 - 140} ${HORIZON_Y} A 140 140 0 0 1 ${195 + 140} ${HORIZON_Y}`}
                strokeWidth="0.6" opacity="0.7"/>
        </g>
        <Horizon opacity={0.55} sun/>
      </svg>
    </div>
  );
}

// ---------- 7. "Striae" — density-curve horizontals + anchored horizon.
function WallpaperStriae() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#040404', overflow: 'hidden' }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
           style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <linearGradient id="striae-glow" x1="0" y1="0.4" x2="1" y2="0.6">
            <stop offset="0" stopColor="#040404" stopOpacity="0"/>
            <stop offset="0.5" stopColor="#1de9b6" stopOpacity="0.10"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </linearGradient>
        </defs>
        <rect width="390" height="844" fill="url(#striae-glow)"/>
        <g stroke="#1de9b6" strokeLinecap="round">
          {Array.from({ length: 140 }).map((_, i) => {
            const y = (i / 140) * 844;
            // Density peaks at the horizon; falls off above and below
            const dist = Math.abs(y - HORIZON_Y) / 422;
            const opacity = Math.max(0.04, 0.30 - dist * 0.26);
            const w = 0.3 + (1 - dist) * 0.5;
            return (
              <line key={i} x1={24} y1={y} x2={366} y2={y}
                    strokeWidth={w} opacity={opacity}/>
            );
          })}
        </g>
        {/* Stronger anchor line at horizon */}
        <Horizon opacity={0.85}/>
      </svg>
    </div>
  );
}

// ---------- 8. "Halftone" — radial dot density centered on horizon.
function WallpaperHalftone() {
  const dots = [];
  for (let row = 0; row < 38; row++) {
    for (let col = 0; col < 18; col++) {
      const x = col * 22 + (row % 2 ? 11 : 0);
      const y = row * 22;
      const dx = x - 195;
      const dy = y - HORIZON_Y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      const t = Math.min(1, dist / 460);
      const r = Math.max(0.3, 3.0 * (1 - t));
      const op = Math.max(0.04, 0.6 * (1 - t));
      dots.push({ x, y, r, op });
    }
  }
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#040404', overflow: 'hidden' }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
           style={{ position: 'absolute', inset: 0 }}>
        <g fill="#1de9b6">
          {dots.map((d, i) => <circle key={i} cx={d.x} cy={d.y} r={d.r} opacity={d.op}/>)}
        </g>
        <Horizon opacity={0.25}/>
      </svg>
    </div>
  );
}

// ---------- 9. "Pulse" — radar rings emanating from the horizon center.
function WallpaperPulse() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#040404', overflow: 'hidden' }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
           style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <radialGradient id="pulse-glow" cx="0.5" cy={HORIZON_Y / 844} r="0.5">
            <stop offset="0" stopColor="#00bfa5" stopOpacity="0.28"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
        </defs>
        <rect width="390" height="844" fill="url(#pulse-glow)"/>
        {/* Centered concentric rings — full circles, fade with distance */}
        <g fill="none" stroke="#1de9b6" strokeLinecap="round">
          {[40, 90, 150, 220, 300, 400, 520, 680].map((r, i) => (
            <circle key={i} cx="195" cy={HORIZON_Y} r={r}
                    strokeWidth={i === 0 ? 1.2 : 0.5}
                    opacity={0.55 - i * 0.06}/>
          ))}
        </g>
        <Horizon opacity={0.55} sun/>
      </svg>
    </div>
  );
}

// ---------- 10. "Dawn" (was Twilight) — sunrise gradient + horizon.
// Sparse single star at the bright moment. No constellation.
function WallpaperTwilight() {
  return (
    <div style={{ position: 'absolute', inset: 0, background: '#040404', overflow: 'hidden' }}>
      <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice"
           style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <linearGradient id="dawn-sky" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0"    stopColor="#1f2840" stopOpacity="0.55"/>
            <stop offset="0.30" stopColor="#3a4055" stopOpacity="0.45"/>
            <stop offset="0.50" stopColor="#5a4a4a" stopOpacity="0.35"/>
            <stop offset={HORIZON_Y / 844} stopColor="#040404" stopOpacity="0.95"/>
            <stop offset="1"    stopColor="#040404" stopOpacity="1"/>
          </linearGradient>
          <radialGradient id="dawn-sun" cx="0.5" cy={HORIZON_Y / 844} r="0.45">
            <stop offset="0" stopColor="#5dffdc" stopOpacity="0.35"/>
            <stop offset="0.4" stopColor="#1de9b6" stopOpacity="0.15"/>
            <stop offset="1" stopColor="#040404" stopOpacity="0"/>
          </radialGradient>
        </defs>
        <rect width="390" height="844" fill="url(#dawn-sky)"/>
        <rect width="390" height="844" fill="url(#dawn-sun)"/>
        {/* Single bright morning star — high and offset, not in a constellation */}
        <circle cx="285" cy="160" r="1.0" fill="#f5f5f5" opacity="0.85"/>
        <circle cx="285" cy="160" r="3" fill="#f5f5f5" opacity="0.15"/>
        <Horizon opacity={0.7} sun/>
      </svg>
    </div>
  );
}

Object.assign(window, {
  WallpaperSlateAurora, WallpaperCarbon, WallpaperIndigoDusk,
  WallpaperLongRun, WallpaperMesh, WallpaperTopographic, WallpaperFlowfield,
  WallpaperDrift, WallpaperTundra, WallpaperStriae, WallpaperHalftone,
  WallpaperPulse, WallpaperTwilight,
});
