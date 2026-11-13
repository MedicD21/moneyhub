import { useEffect, useRef } from "react";

/**
 * The background: an LED wall behind the glass.
 *
 * - Every lamp on the grid is drawn as a dim socket, so the wall reads as a real panel of lights.
 * - Lit lamps form one wide band across the wall whose centre line sways and whose thickness
 *   breathes slowly (sums of slow sine waves). Lamps are discrete, so the band is quantised to the
 *   grid like a signal on an LED display.
 * - Colour runs warm to cold across the wall (the --lamp-1…6 tokens). The ribbon's core burns
 *   hotter (lighter) than its edges. Each lit lamp is a crisp lens: bright core, coloured body,
 *   thin halo.
 * - Cost: sockets are drawn once per resize into an offscreen canvas; lit lamps use pre-rendered
 *   sprites; frames are capped at 30fps and stop while the tab is hidden. Under Reduce Motion a
 *   single still frame is drawn.
 *
 * Purely decorative: aria-hidden, no pointer events, no data.
 */

const STOPS = [0, 0.12, 0.3, 0.44, 0.6, 0.76, 0.94];
const COLOR_STEPS = 40;
const SPRITE = 48;

type Rgb = [number, number, number];
type Lamp = {
  x: number;
  y: number;
  step: number;
  phase: number;
  speed: number;
  edge: number;
};

function parseHex(hex: string): Rgb | null {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m?.[1]) return null;
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function readRamp(): Rgb[] {
  const css = getComputedStyle(document.documentElement);
  const fallback: Rgb[] = [
    [227, 73, 72],
    [226, 101, 47],
    [233, 164, 108],
    [124, 199, 180],
    [47, 138, 107],
    [44, 111, 192],
  ];
  const colors = [1, 2, 3, 4, 5, 6].map(
    (i, k): Rgb =>
      parseHex(css.getPropertyValue(`--lamp-${i}`)) ??
      fallback[k] ?? [255, 255, 255],
  );
  const first = colors[0] ?? [255, 255, 255];
  return [first, ...colors];
}

function rampAt(ramp: Rgb[], u: number): Rgb {
  for (let i = 0; i < STOPS.length - 1; i++) {
    const a = STOPS[i] ?? 0;
    const b = STOPS[i + 1] ?? 1;
    if (u <= b || i === STOPS.length - 2) {
      const k = Math.min(1, Math.max(0, (u - a) / (b - a)));
      const c0 = ramp[i] ?? [0, 0, 0];
      const c1 = ramp[i + 1] ?? c0;
      return [
        c0[0] + (c1[0] - c0[0]) * k,
        c0[1] + (c1[1] - c0[1]) * k,
        c0[2] + (c1[2] - c0[2]) * k,
      ];
    }
  }
  return ramp[ramp.length - 1] ?? [255, 255, 255];
}

const mix = (c: Rgb, to: number, k: number): Rgb => [
  c[0] + (to - c[0]) * k,
  c[1] + (to - c[1]) * k,
  c[2] + (to - c[2]) * k,
];

/** A crisp lit lamp: thin halo, coloured lens with a defined rim, bright core and a small specular. */
function lampSprite([r, g, b]: Rgb, hot: boolean): HTMLCanvasElement {
  const c = document.createElement("canvas");
  c.width = c.height = SPRITE;
  const ctx = c.getContext("2d");
  if (!ctx) return c;
  const h = SPRITE / 2;
  const rgb = (k: Rgb, a: number) =>
    `rgba(${Math.round(k[0])},${Math.round(k[1])},${Math.round(k[2])},${a})`;
  const base: Rgb = [r, g, b];
  const core = mix(base, 255, hot ? 0.7 : 0.35);

  // halo
  const halo = ctx.createRadialGradient(h, h, h * 0.1, h, h, h);
  halo.addColorStop(0, rgb(base, hot ? 0.38 : 0.26));
  halo.addColorStop(1, rgb(base, 0));
  ctx.fillStyle = halo;
  ctx.fillRect(0, 0, SPRITE, SPRITE);

  // lens body with a defined rim
  const lens = ctx.createRadialGradient(
    h - h * 0.12,
    h - h * 0.14,
    0,
    h,
    h,
    h * 0.4,
  );
  lens.addColorStop(0, rgb(core, 1));
  lens.addColorStop(0.55, rgb(base, 0.95));
  lens.addColorStop(0.9, rgb(mix(base, 0, 0.25), 0.9));
  lens.addColorStop(1, rgb(mix(base, 0, 0.4), 0));
  ctx.fillStyle = lens;
  ctx.beginPath();
  ctx.arc(h, h, h * 0.4, 0, Math.PI * 2);
  ctx.fill();

  // specular
  ctx.fillStyle = `rgba(255,255,255,${hot ? 0.55 : 0.32})`;
  ctx.beginPath();
  ctx.arc(h - h * 0.13, h - h * 0.15, h * 0.08, 0, Math.PI * 2);
  ctx.fill();
  return c;
}

function rng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

const smooth = (e0: number, e1: number, x: number) => {
  const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0)));
  return t * t * (2.5 - 1.5 * t);
};

export function LampField() {
  const ref = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = ref.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx) return;

    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    const ramp = readRamp();
    const colors = Array.from({ length: COLOR_STEPS }, (_, i) =>
      rampAt(ramp, i / (COLOR_STEPS - 1)),
    );
    const sprites = colors.map((c) => lampSprite(c, false));
    const hotSprites = colors.map((c) => lampSprite(c, true));
    const sockets = document.createElement("canvas");
    const sctx = sockets.getContext("2d");

    let lamps: Lamp[] = [];
    let width = 0;
    let height = 0;
    let pitch = 24;
    let dpr = 1;
    let raf = 0;
    let last = 0;

    const layout = () => {
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      width = window.innerWidth;
      height = window.innerHeight;
      canvas.width = sockets.width = Math.round(width * dpr);
      canvas.height = sockets.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      pitch = width < 640 ? 18 : 24;
      const rand = rng(8919);
      const cols = Math.ceil(width / pitch) + 1;
      const rows = Math.ceil(height / pitch) + 1;
      const ox = (width - (cols - 1) * pitch) / 2;
      const oy = (height - (rows - 1) * pitch) / 2;
      lamps = [];

      if (sctx) {
        sctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        sctx.clearRect(0, 0, width, height);
      }
      for (let c = 0; c < cols; c++) {
        for (let r = 0; r < rows; r++) {
          const x = ox + c * pitch;
          const y = oy + r * pitch;
          const u = Math.min(1, Math.max(0, x / width));
          lamps.push({
            x,
            y,
            step: Math.round(u * (COLOR_STEPS - 1)),
            phase: rand() * Math.PI * 2,
            speed: 0.4 + rand() * 0.9,
            // the far left edge sits slightly out of the focal plane
            edge: 1 - smooth(0, 0.14, u),
          });
          if (sctx) {
            // unlit socket: a dark recess with a faint lower rim
            const rad = pitch * 0.02;
            sctx.fillStyle = "rgba(0, 0, 0, 0.45)";
            sctx.beginPath();
            sctx.arc(x, y, rad, 0, Math.PI * 2);
            sctx.fill();
            sctx.strokeStyle = "rgba(160, 210, 220, 0.07)";
            sctx.lineWidth = 1;
            sctx.beginPath();
            sctx.arc(x, y, rad, 0.15 * Math.PI, 0.85 * Math.PI);
            sctx.stroke();
          }
        }
      }
    };

    /** Ribbon intensity at (x, y) for time t: 1 at the centre line, falling to 0 at its edge. */
    const ribbon = (
      x: number,
      y: number,
      t: number,
      cy: number,
      amp: number,
      phase: number,
    ) => {
      // gentle sway of the centre line
      const centre =
        cy +
        amp * 3 * Math.sin(x * 0.0032 + t * 0.212 + phase) +
        amp * 0.1 * Math.sin(x * 0.0071 - t * 0.17 + phase * 2);
      // a wide body that breathes slightly; never pinches thin
      const thick =
        pitch *
        (12 +
          0.2 * Math.sin(x * 0.0045 - t * 0.25 + phase) +
          0.6 * Math.sin(x * 0.011 + t * 0.22));
      const d = Math.abs(y - centre) / thick;
      return 1 - smooth(0.001, 1, d);
    };

    const draw = (time: number) => {
      const t = time / 700;
      ctx.clearRect(0, 0, width, height);
      ctx.globalAlpha = 1;
      ctx.drawImage(sockets, 0, 0, width, height);

      const cy = height * 0.5 - Math.min(window.scrollY * 0.05, 48);
      const amp = height * 0.02;
      const size = pitch * 1.25;
      ctx.globalCompositeOperation = "lighter";
      for (const l of lamps) {
        const main = ribbon(l.x, l.y, t, cy, amp, 0);
        let k = main;
        if (k < 0.04) continue;
        const flicker = 0.85 + 0.15 * Math.sin(t * l.speed + l.phase);
        k *= flicker;
        const hot = main > 0.9;
        const sprite = (hot ? hotSprites : sprites)[l.step];
        if (!sprite) continue;
        const s = size * (1 + l.edge * 0.6);
        ctx.globalAlpha = Math.min(1, k * (1 - l.edge * 0.45));
        ctx.drawImage(sprite, l.x - s / 2, l.y - s / 2, s, s);
      }
      ctx.globalAlpha = 1;
      ctx.globalCompositeOperation = "source-over";
    };

    const loop = (time: number) => {
      raf = requestAnimationFrame(loop);
      if (time - last < 33) return; // ~30fps is plenty for slow light
      last = time;
      draw(time);
    };

    const start = () => {
      cancelAnimationFrame(raf);
      layout();
      if (reduced.matches) draw(4000);
      else raf = requestAnimationFrame(loop);
    };

    const onScroll = () => {
      if (reduced.matches) draw(4000);
    };

    start();
    window.addEventListener("resize", start);
    window.addEventListener("scroll", onScroll, { passive: true });
    reduced.addEventListener("change", start);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", start);
      window.removeEventListener("scroll", onScroll);
      reduced.removeEventListener("change", start);
    };
  }, []);

  return <canvas ref={ref} className='ambient-canvas' aria-hidden='true' />;
}
