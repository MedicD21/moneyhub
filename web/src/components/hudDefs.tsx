/** SVG helpers for the HUD chart look: gradients, glow filters and the active-point marker. */
import type { ReactNode } from 'react';
import { svgId } from './chartTheme';

export type DefKind = 'column' | 'bar' | 'area';

/** Gradient id for one series. Use as `fill={`url(#${hudFillId(uid, kind, key)})`}`. */
export function hudFillId(uid: string, kind: DefKind, key: string): string {
  return `${uid}-${kind}-${svgId(key)}`;
}
/** Glow filter id for one series. */
export function hudGlowId(uid: string, key: string): string {
  return `${uid}-glow-${svgId(key)}`;
}
export const hudFill = (uid: string, kind: DefKind, key: string) => `url(#${hudFillId(uid, kind, key)})`;
export const hudGlow = (uid: string, key: string) => `url(#${hudGlowId(uid, key)})`;

export const lit = (color: string, pct: number) => `color-mix(in oklab, ${color}, white ${pct}%)`;
export const shade = (color: string, pct: number) => `color-mix(in oklab, ${color}, black ${pct}%)`;

/**
 * SVG <defs> content for a chart: lit gradients that give bars a turned, ceramic-and-light
 * volume, fading area fills, and a soft glow that sits under lines. Place the result inside a
 * literal `<defs>` child of the Recharts chart. A plain function, not a component, so Recharts
 * sees ordinary SVG elements.
 */
export function hudDefs(uid: string, series: Array<{ key: string; color: string; kind: DefKind | 'line' }>): ReactNode {
  return series.map(({ key, color, kind }) => {
    const glow = (
      <filter key={`g-${key}`} id={hudGlowId(uid, key)} filterUnits="userSpaceOnUse" x="-10%" y="-10%" width="120%" height="120%">
        <feDropShadow dx="0" dy="2" stdDeviation="2.5" style={{ floodColor: `color-mix(in oklab, ${color} var(--glow-mix), transparent)` }} />
      </filter>
    );
    if (kind === 'line') return glow;
    if (kind === 'area') {
      return [
        glow,
        <linearGradient key={`a-${key}`} id={hudFillId(uid, 'area', key)} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" style={{ stopColor: color, stopOpacity: 0.32 }} />
          <stop offset="70%" style={{ stopColor: color, stopOpacity: 0.06 }} />
          <stop offset="100%" style={{ stopColor: color, stopOpacity: 0 }} />
        </linearGradient>,
      ];
    }
    // Columns are lit from the left, horizontal bars from the top: a highlight band, the true
    // color through the middle, a shaded edge. Reads as a rounded solid without hiding the hue.
    const horizontal = kind === 'column';
    return (
      <linearGradient
        key={`b-${key}`}
        id={hudFillId(uid, kind, key)}
        x1="0"
        y1="0"
        x2={horizontal ? '1' : '0'}
        y2={horizontal ? '0' : '1'}
      >
        <stop offset="0%" style={{ stopColor: lit(color, 22) }} />
        <stop offset="28%" style={{ stopColor: lit(color, 8) }} />
        <stop offset="60%" style={{ stopColor: color }} />
        <stop offset="100%" style={{ stopColor: shade(color, 22) }} />
      </linearGradient>
    );
  });
}

/** Active point: a solid core with a pulsing ring. */
export function hudActiveDot(color: string) {
  return (p: { cx?: number; cy?: number }) => {
    if (typeof p.cx !== 'number' || typeof p.cy !== 'number') return <g />;
    return (
      <g>
        <circle className="hud-pulse" cx={p.cx} cy={p.cy} r={5} fill="none" stroke={color} strokeWidth={1.5} />
        <circle cx={p.cx} cy={p.cy} r={4.5} fill={color} stroke="var(--surface)" strokeWidth={2} />
      </g>
    );
  };
}

