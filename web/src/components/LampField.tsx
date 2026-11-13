import { useEffect, useRef } from "react";

/** Soft, defocused lights with a slowly breathing horizontal band.
 * Sprites are cached; animation pauses offscreen and respects reduced motion.
 */

const STOPS = [0, 0.22, 0.36, 0.44, 0.6, 0.76, 0.94];
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
    [166, 99, 104],
    [187, 143, 136],
    [213, 193, 141],
    [145, 196, 182],
    [82, 169, 170],
    [54, 127, 145],
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

/** A soft lens: no hard rim or white specular, like lights behind smoked glass. */
function lampSprite([r, g, b]: Rgb, hot: boolean): HTMLCanvasElement {
  const c = document.createElement("canvas");
  c.width = c.height = SPRITE;
  const ctx = c.getContext("2d");
  if (!ctx) return c;
  const h = SPRITE / 2;
  const core = mix([r, g, b], 255, hot ? 0.22 : 0.06);
  const rgb = (color: Rgb, alpha: number) =>
    `rgba(${Math.round(color[0])},${Math.round(color[1])},${Math.round(color[2])},${alpha})`;
  const lens = ctx.createRadialGradient(h, h, 0, h, h, h);
  lens.addColorStop(0, rgb(core, 0.95));
  lens.addColorStop(0.22, rgb([r, g, b], 0.85));
  lens.addColorStop(0.42, rgb([r, g, b], 0.42));
  lens.addColorStop(0.7, rgb([r, g, b], 0.08));
  lens.addColorStop(1, rgb([r, g, b], 0));
  ctx.fillStyle = lens;
  ctx.fillRect(0, 0, SPRITE, SPRITE);
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
  return t * t * (3 - 2 * t);
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
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      pitch = Math.max(17, Math.min(29, width / 48));
      const rand = rng(8919);
      const cols = Math.ceil(width / pitch) + 1;
      const rows = Math.ceil(height / pitch) + 1;
      const ox = (width - (cols - 1) * pitch) / 2;
      const oy = (height - (rows - 1) * pitch) / 2;
      lamps = [];

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
        }
      }
    };

    // Near-horizontal band, with a small travelling swell instead of a winding ribbon.
    const ribbon = (x: number, y: number, t: number, cy: number) => {
      const u = x / width;
      const centre = cy + pitch * 0.45 * Math.sin(u * 5 - t * 0.14);
      const swell = Math.exp(-Math.pow((u - (0.57 + 0.07 * Math.sin(t * 0.09))) / 0.24, 2));
      const thickness = pitch * (10.4 + 6.8 * swell + 0.72 * Math.sin(t * 0.2 + u * 4));
      const distance = Math.abs(y - centre) / thickness;
      return Math.exp(-distance * distance * 1.65);
    };

    const draw = (time: number) => {
      const t = time / 1000;
      ctx.clearRect(0, 0, width, height);
      ctx.globalAlpha = 1;

      const cy = height * 0.5 - Math.min(window.scrollY * 0.05, 48);
      const size = pitch * 1.76;
      ctx.globalCompositeOperation = "lighter";
      for (const l of lamps) {
        const main = ribbon(l.x, l.y, t, cy);
        let k = main;
        if (k < 0.04) continue;
        const flicker = 0.94 + 0.06 * Math.sin(t * l.speed * 0.3 + l.phase);
        k *= flicker;
        const hot = main > 0.9;
        const sprite = (hot ? hotSprites : sprites)[l.step];
        if (!sprite) continue;
        const s = size * (1 + l.edge * 1.2);
        ctx.globalAlpha = Math.min(1, k * (1 - l.edge * 0.55) * 0.82);
        // The left edge falls out of focus; the centre keeps a soft dot grid.
        const drift = pitch * 0.16 * Math.sin(t * 0.12);
        ctx.drawImage(sprite, l.x + drift - s / 2, l.y - s / 2, s, s);
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
      draw(4000);
      if (!reduced.matches && !document.hidden) raf = requestAnimationFrame(loop);
    };

    const onScroll = () => {
      if (reduced.matches) draw(4000);
    };

    const onVisibility = () => {
      cancelAnimationFrame(raf);
      last = 0;
      if (!document.hidden && !reduced.matches) raf = requestAnimationFrame(loop);
    };

    start();
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("resize", start);
    window.addEventListener("scroll", onScroll, { passive: true });
    reduced.addEventListener("change", start);
    return () => {
      cancelAnimationFrame(raf);
      document.removeEventListener("visibilitychange", onVisibility);
      window.removeEventListener("resize", start);
      window.removeEventListener("scroll", onScroll);
      reduced.removeEventListener("change", start);
    };
  }, []);

  return <canvas ref={ref} className='ambient-canvas' aria-hidden='true' />;
}
