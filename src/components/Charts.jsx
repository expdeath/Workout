import React, { useState, useRef, useId } from 'react';

// ── SVG charts ───────────────────────────────────────────────────
// Specs: 2.5px smoothed lines w/ round caps, a fading gradient area, ≥8px end markers
// with a 2px surface ring, ≤24px columns with 4px rounded data-ends
// (square at the baseline), hairline solid gridlines, clean y ticks,
// text in ink tokens (never the series color), tap/hover tooltip.

const W = 440;
const H = 180;
const PAD = { t: 14, r: 14, b: 24, l: 38 };
const INK_MUTED = '#8391A7';
const GRID = 'rgba(255,255,255,0.07)';
const SURFACE = '#131B2E';
const FONT = 'Space Grotesk, system-ui, sans-serif';

/** Smooth path through the points (Catmull-Rom → cubic Bézier). */
function smoothPath(pts) {
  if (pts.length < 3) return pts.map(([x, y], i) => `${i ? 'L' : 'M'}${x},${y}`).join(' ');
  let d = `M${pts[0][0]},${pts[0][1]}`;
  for (let i = 0; i < pts.length - 1; i++) {
    const p0 = pts[i - 1] || pts[i];
    const p1 = pts[i];
    const p2 = pts[i + 1];
    const p3 = pts[i + 2] || p2;
    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
    d += ` C${c1[0]},${c1[1]} ${c2[0]},${c2[1]} ${p2[0]},${p2[1]}`;
  }
  return d;
}

function niceTicks(max) {
  if (max <= 0) return [0, 1];
  const raw = max / 3;
  const pow = 10 ** Math.floor(Math.log10(raw));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * pow).find((s) => s >= raw);
  const ticks = [];
  for (let v = 0; v <= max + step * 0.001; v += step) ticks.push(v);
  if (ticks[ticks.length - 1] < max) ticks.push(ticks.length * step);
  return ticks;
}

const fmtN = (n) =>
  n >= 10000 ? `${Math.round(n / 1000)}k` : n.toLocaleString();

function Tooltip({ x, y, lines }) {
  const w = 8 + Math.max(...lines.map((l) => l.length)) * 6.4;
  const h = 14 * lines.length + 8;
  const tx = Math.max(PAD.l, Math.min(x - w / 2, W - PAD.r - w));
  const ty = y - h - 10 < 2 ? y + 12 : y - h - 10;
  return (
    <g pointerEvents="none">
      <rect x={tx} y={ty} width={w} height={h} rx="5" fill="#0A0E16" stroke={GRID} />
      {lines.map((l, i) => (
        <text key={i} x={tx + w / 2} y={ty + 15 + i * 14} textAnchor="middle"
          fontSize="11" fontFamily={FONT}
          fill={i === lines.length - 1 ? '#F8FAFC' : INK_MUTED}>
          {l}
        </text>
      ))}
    </g>
  );
}

function useNearest(count, x0, dx) {
  const [active, setActive] = useState(null);
  const svgRef = useRef(null);
  const onMove = (e) => {
    const rect = svgRef.current.getBoundingClientRect();
    const x = ((e.clientX - rect.left) / rect.width) * W;
    const i = Math.round((x - x0) / dx);
    setActive(Math.max(0, Math.min(count - 1, i)));
  };
  return { active, svgRef, onMove, clear: () => setActive(null) };
}

/** Single-series line: points = [{ label, value }], unit e.g. "kg". */
export function LineChart({ points, unit = '', color = 'var(--amber)' }) {
  const gradId = useId();
  const plotW = W - PAD.l - PAD.r;
  const plotH = H - PAD.t - PAD.b;
  const max = Math.max(...points.map((p) => p.value));
  const min = Math.min(...points.map((p) => p.value));
  const lo = Math.max(0, min - (max - min || max * 0.2) * 0.25);
  // ticks span the visible (zoomed) range, not zero-up
  const span = max - lo || max || 1;
  const pow = 10 ** Math.floor(Math.log10(span / 2));
  const step = [1, 2, 2.5, 5, 10].map((m) => m * pow).find((s) => s >= span / 3) || pow;
  const ticks = [];
  for (let v = Math.ceil(lo / step) * step; v <= max + step; v += step) ticks.push(v);
  const top = ticks[ticks.length - 1];
  const yOf = (v) => PAD.t + plotH - ((v - lo) / (top - lo || 1)) * plotH;
  const dx = points.length > 1 ? plotW / (points.length - 1) : 0;
  const xOf = (i) => (points.length > 1 ? PAD.l + i * dx : PAD.l + plotW / 2);
  const { active, svgRef, onMove, clear } = useNearest(points.length, PAD.l, dx || plotW);

  const path = smoothPath(points.map((p, i) => [xOf(i), yOf(p.value)]));
  const area = `${path} L${xOf(points.length - 1)},${yOf(lo)} L${xOf(0)},${yOf(lo)} Z`;
  const last = points.length - 1;

  return (
    <svg ref={svgRef} viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', display: 'block', touchAction: 'pan-y' }}
      onPointerMove={onMove} onPointerDown={onMove} onPointerLeave={clear}>
      {ticks.filter((t) => t >= lo).map((t) => (
        <g key={t}>
          <line x1={PAD.l} x2={W - PAD.r} y1={yOf(t)} y2={yOf(t)} stroke={GRID} strokeWidth="1" />
          <text x={PAD.l - 6} y={yOf(t) + 3.5} textAnchor="end" fontSize="10"
            fontFamily={FONT} fill={INK_MUTED} style={{ fontVariantNumeric: 'tabular-nums' }}>
            {fmtN(t)}
          </text>
        </g>
      ))}
      <defs>
        <linearGradient id={gradId} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.35" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={area} fill={`url(#${gradId})`} />
      <path d={path} fill="none" stroke={color} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" />
      {active != null && (
        <line x1={xOf(active)} x2={xOf(active)} y1={PAD.t} y2={H - PAD.b} stroke={GRID} strokeWidth="1" />
      )}
      {points.map((p, i) =>
        i === last || i === active ? (
          <circle key={i} cx={xOf(i)} cy={yOf(p.value)} r="4.5" fill={color} stroke={SURFACE} strokeWidth="2" />
        ) : null
      )}
      <text x={PAD.l} y={H - 8} fontSize="10" fontFamily={FONT} fill={INK_MUTED}>
        {points[0].label}
      </text>
      <text x={W - PAD.r} y={H - 8} textAnchor="end" fontSize="10" fontFamily={FONT} fill={INK_MUTED}>
        {points[last].label}
      </text>
      {active == null && (
        <text x={Math.min(xOf(last) + 8, W - 2)} y={yOf(points[last].value) - 8}
          textAnchor="end" fontSize="12" fontWeight="700" fontFamily={FONT} fill="#F8FAFC">
          {fmtN(points[last].value)}{unit}
        </text>
      )}
      {active != null && (
        <Tooltip x={xOf(active)} y={yOf(points[active].value)}
          lines={[points[active].label, `${fmtN(points[active].value)}${unit}`]} />
      )}
    </svg>
  );
}

/**
 * GitHub-style training heatmap: one cell per day, columns are weeks
 * (Mon-top), teal intensity by session volume tertile.
 * `days` is a Map of 'YYYY-MM-DD' → { volume, count }.
 */
export function TrainingHeatmap({ days, weeks = 16, cellHeight }) {
  const MS = 86400000;
  const now = new Date();
  const shift = (now.getDay() + 6) % 7; // Mon=0
  const monday = new Date(now.getTime() - shift * MS);
  const vols = [...days.values()].map((d) => d.volume).filter((v) => v > 0).sort((a, b) => a - b);
  const t1 = vols[Math.floor(vols.length / 3)] ?? 1;
  const t2 = vols[Math.floor((2 * vols.length) / 3)] ?? 1;
  const cells = [];
  for (let w = weeks - 1; w >= 0; w--) {
    for (let d = 0; d < 7; d++) {
      const dt = new Date(monday.getTime() - w * 7 * MS + d * MS);
      const iso = new Date(dt.getTime() + 12 * 3600000).toISOString().slice(0, 10);
      const future = dt.getTime() > now.getTime() + 12 * 3600000;
      const day = days.get(iso);
      const level = !day ? 0 : !day.volume ? 'cardio' : day.volume > t2 ? 3 : day.volume > t1 ? 2 : 1;
      cells.push({ iso, level, future, title: day ? `${iso} — ${day.count} session${day.count > 1 ? 's' : ''}${day.volume ? `, ${day.volume.toLocaleString()}kg` : ''}` : iso });
    }
  }
  // amber by session size; a logged day with no lifting (cardio) is green
  const fill = ['var(--bg-high)', 'rgba(245,158,11,0.4)', 'rgba(245,158,11,0.7)', 'var(--amber)'];
  return (
    <div
      style={{
        display: 'grid',
        gridAutoFlow: 'column',
        gridTemplateRows: 'repeat(7, 1fr)',
        gridTemplateColumns: `repeat(${weeks}, 1fr)`,
        gap: weeks > 26 ? 2 : 4,
      }}
    >
      {cells.map((c) => (
        <div
          key={c.iso}
          title={c.title}
          style={{
            ...(cellHeight ? { height: cellHeight } : { aspectRatio: '1' }),
            borderRadius: weeks > 26 ? 2 : 3,
            background: c.future ? 'var(--bg-input)' : c.level === 'cardio' ? 'var(--chart-green)' : fill[c.level],
          }}
        />
      ))}
    </div>
  );
}

/** Single-series columns: bars = [{ label, value }], unit e.g. "kg". */
export function BarChart({ bars, unit = '', color = 'var(--chart-amber)' }) {
  const plotW = W - PAD.l - PAD.r;
  const plotH = H - PAD.t - PAD.b;
  const ticks = niceTicks(Math.max(...bars.map((b) => b.value), 1));
  const top = ticks[ticks.length - 1];
  const yOf = (v) => PAD.t + plotH - (v / top) * plotH;
  const band = plotW / bars.length;
  const bw = Math.min(24, band - 8);
  const xOf = (i) => PAD.l + i * band + (band - bw) / 2;
  const { active, svgRef, onMove, clear } = useNearest(bars.length, PAD.l + band / 2, band);
  const last = bars.length - 1;

  // Rounded top (4px), square baseline
  const barPath = (i, v) => {
    const x = xOf(i);
    const y = yOf(v);
    const h = H - PAD.b - y;
    const r = Math.min(4, h);
    if (h <= 0) return '';
    return `M${x},${H - PAD.b} V${y + r} Q${x},${y} ${x + r},${y} H${x + bw - r} Q${x + bw},${y} ${x + bw},${y + r} V${H - PAD.b} Z`;
  };

  return (
    <svg ref={svgRef} viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', display: 'block', touchAction: 'pan-y' }}
      onPointerMove={onMove} onPointerDown={onMove} onPointerLeave={clear}>
      {ticks.map((t) => (
        <g key={t}>
          <line x1={PAD.l} x2={W - PAD.r} y1={yOf(t)} y2={yOf(t)} stroke={GRID} strokeWidth="1" />
          <text x={PAD.l - 6} y={yOf(t) + 3.5} textAnchor="end" fontSize="10"
            fontFamily={FONT} fill={INK_MUTED} style={{ fontVariantNumeric: 'tabular-nums' }}>
            {fmtN(t)}
          </text>
        </g>
      ))}
      {bars.map((b, i) => (
        <path key={i} d={barPath(i, b.value)} fill={color} opacity={active == null || active === i ? 1 : 0.45} />
      ))}
      {bars.map((b, i) => (
        <text key={i} x={xOf(i) + bw / 2} y={H - 8} textAnchor="middle" fontSize="9.5"
          fontFamily={FONT} fill={INK_MUTED}>
          {b.label}
        </text>
      ))}
      {active == null && bars[last].value > 0 && (
        <text x={xOf(last) + bw / 2} y={yOf(bars[last].value) - 6} textAnchor="middle"
          fontSize="11" fontFamily={FONT} fill="#C7CEDC">
          {fmtN(bars[last].value)}{unit}
        </text>
      )}
      {active != null && (
        <Tooltip x={xOf(active) + bw / 2} y={yOf(bars[active].value)}
          lines={[bars[active].label, `${fmtN(bars[active].value)}${unit}`]} />
      )}
    </svg>
  );
}
