import React, { useState, useRef } from 'react';

// ── SVG charts ───────────────────────────────────────────────────
// Specs: 2px lines w/ round caps, ~10% area wash, ≥8px end markers
// with a 2px surface ring, ≤24px columns with 4px rounded data-ends
// (square at the baseline), hairline solid gridlines, clean y ticks,
// text in ink tokens (never the series color), tap/hover tooltip.

const W = 440;
const H = 180;
const PAD = { t: 14, r: 14, b: 24, l: 38 };
const INK_MUTED = '#8A93A6';
const GRID = '#232B3A';
const SURFACE = '#161C28';

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
      <rect x={tx} y={ty} width={w} height={h} rx="5" fill="#0D1119" stroke={GRID} />
      {lines.map((l, i) => (
        <text key={i} x={tx + w / 2} y={ty + 15 + i * 14} textAnchor="middle"
          fontSize="11" fontFamily="IBM Plex Mono, monospace"
          fill={i === lines.length - 1 ? '#E8ECF4' : INK_MUTED}>
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
export function LineChart({ points, unit = '', color = 'var(--chart-amber)' }) {
  const plotW = W - PAD.l - PAD.r;
  const plotH = H - PAD.t - PAD.b;
  const max = Math.max(...points.map((p) => p.value));
  const min = Math.min(...points.map((p) => p.value));
  const lo = Math.max(0, min - (max - min || max * 0.2) * 0.25);
  const ticks = niceTicks(max);
  const top = ticks[ticks.length - 1];
  const yOf = (v) => PAD.t + plotH - ((v - lo) / (top - lo || 1)) * plotH;
  const dx = points.length > 1 ? plotW / (points.length - 1) : 0;
  const xOf = (i) => (points.length > 1 ? PAD.l + i * dx : PAD.l + plotW / 2);
  const { active, svgRef, onMove, clear } = useNearest(points.length, PAD.l, dx || plotW);

  const path = points.map((p, i) => `${i ? 'L' : 'M'}${xOf(i)},${yOf(p.value)}`).join(' ');
  const area = `${path} L${xOf(points.length - 1)},${yOf(lo)} L${xOf(0)},${yOf(lo)} Z`;
  const last = points.length - 1;

  return (
    <svg ref={svgRef} viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', display: 'block', touchAction: 'pan-y' }}
      onPointerMove={onMove} onPointerDown={onMove} onPointerLeave={clear}>
      {ticks.filter((t) => t >= lo).map((t) => (
        <g key={t}>
          <line x1={PAD.l} x2={W - PAD.r} y1={yOf(t)} y2={yOf(t)} stroke={GRID} strokeWidth="1" />
          <text x={PAD.l - 6} y={yOf(t) + 3.5} textAnchor="end" fontSize="10"
            fontFamily="IBM Plex Mono, monospace" fill={INK_MUTED} style={{ fontVariantNumeric: 'tabular-nums' }}>
            {fmtN(t)}
          </text>
        </g>
      ))}
      <path d={area} fill={color} opacity="0.1" />
      <path d={path} fill="none" stroke={color} strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />
      {active != null && (
        <line x1={xOf(active)} x2={xOf(active)} y1={PAD.t} y2={H - PAD.b} stroke={GRID} strokeWidth="1" />
      )}
      {points.map((p, i) =>
        i === last || i === active ? (
          <circle key={i} cx={xOf(i)} cy={yOf(p.value)} r="4.5" fill={color} stroke={SURFACE} strokeWidth="2" />
        ) : null
      )}
      <text x={PAD.l} y={H - 8} fontSize="10" fontFamily="IBM Plex Mono, monospace" fill={INK_MUTED}>
        {points[0].label}
      </text>
      <text x={W - PAD.r} y={H - 8} textAnchor="end" fontSize="10" fontFamily="IBM Plex Mono, monospace" fill={INK_MUTED}>
        {points[last].label}
      </text>
      {active == null && (
        <text x={Math.min(xOf(last) + 8, W - 2)} y={yOf(points[last].value) - 8}
          textAnchor="end" fontSize="11" fontFamily="IBM Plex Mono, monospace" fill="#C7CEDC">
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

/** Single-series columns: bars = [{ label, value }], unit e.g. "kg". */
export function BarChart({ bars, unit = '', color = 'var(--chart-teal)' }) {
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
            fontFamily="IBM Plex Mono, monospace" fill={INK_MUTED} style={{ fontVariantNumeric: 'tabular-nums' }}>
            {fmtN(t)}
          </text>
        </g>
      ))}
      {bars.map((b, i) => (
        <path key={i} d={barPath(i, b.value)} fill={color} opacity={active == null || active === i ? 1 : 0.45} />
      ))}
      {bars.map((b, i) => (
        <text key={i} x={xOf(i) + bw / 2} y={H - 8} textAnchor="middle" fontSize="9.5"
          fontFamily="IBM Plex Mono, monospace" fill={INK_MUTED}>
          {b.label}
        </text>
      ))}
      {active == null && bars[last].value > 0 && (
        <text x={xOf(last) + bw / 2} y={yOf(bars[last].value) - 6} textAnchor="middle"
          fontSize="11" fontFamily="IBM Plex Mono, monospace" fill="#C7CEDC">
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
