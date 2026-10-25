// Building blocks for the app shots. Everything inside a <Screen> is placed
// in capture pixels (1320x2868, the iPhone 16 Pro Max at 3x), so boxes can be
// read straight off a still.

import React from "react";
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  random,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

export const W = 886;
export const H = 1920;
export const SW = 1320;
export const SH = 2868;
const K = W / SW;

export const C = {
  field: "#4CC8FF",
  pale: "#DDF4FF",
  navy: "#08243F",
  sun: "#FFD84D",
  ink: "#06121F",
  white: "#FFFFFF",
  flame: "#FF9F0A",
  blue: "#0A84FF",
};

export type Box = [number, number, number, number];

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const smooth = Easing.bezier(0.45, 0, 0.2, 1);

export const ease = (f: number, a: number, b: number, from = 0, to = 1, easing = smooth) =>
  interpolate(f, [a, b], [from, to], { ...clamp, easing });

export const useSpring = (delay: number, config: Partial<{ damping: number; stiffness: number; mass: number }> = {}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: frame - delay, fps, config: { damping: 15, stiffness: 170, mass: 0.9, ...config } });
};

const src = (path: string) => staticFile(path);

// MARK: - Screen and camera

export type Shot = { f: number; s: number; x?: number; y?: number };

/** A capture-sized stage scaled to the frame. `camera` keys put point (x, y)
 * at the centre at scale s, eased between keys and kept inside the screen. */
export const Screen: React.FC<{ children: React.ReactNode; bg?: string; camera?: Shot[] }> = ({ children, bg = C.white, camera }) => {
  const frame = useCurrentFrame();
  let transform = "none";
  if (camera && camera.length) {
    const fs = camera.map((k) => k.f);
    const at = (vals: number[]) => (fs.length === 1 ? vals[0] : interpolate(frame, fs, vals, { ...clamp, easing: smooth }));
    const s = at(camera.map((k) => k.s));
    const x = at(camera.map((k) => k.x ?? SW / 2));
    const y = at(camera.map((k) => k.y ?? SH / 2));
    const tx = Math.min(0, Math.max(SW - s * SW, SW / 2 - s * x));
    const ty = Math.min(0, Math.max(SH - s * SH, SH / 2 - s * y));
    transform = `translate(${tx}px, ${ty}px) scale(${s})`;
  }
  return (
    <AbsoluteFill style={{ background: bg, overflow: "hidden" }}>
      <div style={{ position: "absolute", left: 0, top: (H - SH * K) / 2, width: SW, height: SH, transform: `scale(${K})`, transformOrigin: "0 0" }}>
        <div style={{ position: "absolute", inset: 0, transform, transformOrigin: "0 0" }}>{children}</div>
      </div>
    </AbsoluteFill>
  );
};

/** A whole capture. */
export const Still: React.FC<{ name: string; style?: React.CSSProperties }> = ({ name, style }) => (
  <Img src={src(name)} style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, ...style }} />
);

/** One box of a capture, drawn where it sits on the screen. */
export const Piece: React.FC<{
  name: string;
  box: Box;
  radius?: number | string;
  style?: React.CSSProperties;
  imgStyle?: React.CSSProperties;
  children?: React.ReactNode;
}> = ({ name, box: [x, y, w, h], radius = 0, style, imgStyle, children }) => (
  <div style={{ position: "absolute", left: x, top: y, width: w, height: h, overflow: "hidden", borderRadius: radius, ...style }}>
    <Img src={src(name)} style={{ position: "absolute", left: -x, top: -y, width: SW, height: SH, maxWidth: "none", ...imgStyle }} />
    {children}
  </div>
);

// MARK: - Motion

/** A box that rises into place (or slides in from the side with `dx`). */
export const Rise: React.FC<{ name: string; box: Box; at: number; dy?: number; dx?: number; radius?: number }> = ({
  name, box, at, dy = 90, dx = 0, radius,
}) => {
  const p = useSpring(at, { damping: 18, stiffness: 160 });
  return (
    <Piece name={name} box={box} radius={radius}
      style={{ opacity: interpolate(p, [0, 0.5], [0, 1], clamp), transform: `translate(${(1 - p) * dx}px, ${(1 - p) * dy}px)` }} />
  );
};

/** A box that pops in from smaller, with an overshoot. */
export const Pop: React.FC<{ name: string; box: Box; at: number; from?: number; radius?: number | string; origin?: string; children?: React.ReactNode }> = ({
  name, box, at, from = 0.4, radius, origin = "50% 50%", children,
}) => {
  const p = useSpring(at, { damping: 11, stiffness: 190, mass: 0.8 });
  return (
    <Piece name={name} box={box} radius={radius}
      style={{ opacity: interpolate(p, [0, 0.25], [0, 1], clamp), transform: `scale(${from + (1 - from) * p})`, transformOrigin: origin }}>
      {children}
    </Piece>
  );
};

/** A box lifted off the screen towards the viewer: larger, with a shadow. */
export const Lift: React.FC<{ name: string; box: Box; at: number; scale?: number; radius?: number; cover?: Box[]; coverColor?: string }> = ({
  name, box, at, scale = 1.08, radius = 36, cover = [], coverColor = C.white,
}) => {
  const p = useSpring(at, { damping: 12, stiffness: 150 });
  const k = 1 + (scale - 1) * p;
  return (
    <Piece name={name} box={box} radius={radius}
      style={{
        transform: `scale(${k})`,
        boxShadow: `0 ${30 * p}px ${80 * p}px rgba(6, 18, 31, ${0.22 * Math.min(1, p)})`,
        background: coverColor,
      }}>
      {cover.map(([x, y, w, h], i) => (
        <div key={i} style={{ position: "absolute", left: x - box[0], top: y - box[1], width: w, height: h, background: coverColor }} />
      ))}
    </Piece>
  );
};

/** Bars of a chart growing from their baseline, left to right. */
export const Bars: React.FC<{ name: string; x0: number; x1: number; n: number; top: number; base: number; at: number; step?: number }> = ({
  name, x0, x1, n, top, base, at, step = 1,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const pitch = (x1 - x0) / n;
  return (
    <>
      {Array.from({ length: n }, (_, i) => {
        const p = spring({ frame: frame - at - i * step, fps, config: { damping: 13, stiffness: 160 } });
        const left = Math.round(x0 + i * pitch);
        const right = Math.round(x0 + (i + 1) * pitch);
        return (
          <Piece key={i} name={name} box={[left, top, right - left, base - top]}
            style={{ transform: `scaleY(${Math.max(0, p)})`, transformOrigin: "50% 100%" }} />
        );
      })}
    </>
  );
};

/** A score ring drawing itself clockwise from the top, its centre left alone. */
export const Ring: React.FC<{ name: string; cx: number; cy: number; r: number; inner: number; at: number; dur?: number; to?: number }> = ({
  name, cx, cy, r, inner, at, dur = 22, to = 1,
}) => {
  const frame = useCurrentFrame();
  const deg = ease(frame, at, at + dur, 0, 360 * to, Easing.bezier(0.3, 0, 0.1, 1));
  const pad = 8;
  const size = (r + pad) * 2;
  const mask = `conic-gradient(from 0deg, #000 0deg ${deg}deg, transparent ${deg}deg 360deg), radial-gradient(circle, transparent ${inner}px, #000 ${inner + 1}px)`;
  return (
    <Piece name={name} box={[cx - r - pad, cy - r - pad, size, size]}
      style={{
        WebkitMaskImage: mask,
        maskImage: mask,
        WebkitMaskComposite: "source-in",
        maskComposite: "intersect",
      } as React.CSSProperties} />
  );
};

/** A box whose content rolls up into place, like a counter turning over. */
export const Roll: React.FC<{ name: string; box: Box; at: number }> = ({ name, box, at }) => {
  const p = useSpring(at, { damping: 13, stiffness: 150 });
  const [x, y, w, h] = box;
  // Only the box's own content moves, so nothing from above it shows on the way in.
  return (
    <div style={{ position: "absolute", left: x, top: y, width: w, height: h, overflow: "hidden" }}>
      <Piece name={name} box={box} style={{ left: 0, top: (1 - p) * h }} />
    </div>
  );
};

/** A box that bounces once where it is, to draw the eye. */
export const Pulse: React.FC<{ name: string; box: Box; at: number; amount?: number; radius?: number | string }> = ({ name, box, at, amount = 0.3, radius = "50%" }) => {
  const up = useSpring(at, { damping: 12, stiffness: 260 });
  const down = useSpring(at + 5, { damping: 12, stiffness: 200 });
  return <Piece name={name} box={box} radius={radius} style={{ transform: `scale(${1 + amount * (up - down)})` }} />;
};

/** A finger tap: a soft disc that presses and lets go with a ring. */
export const Tap: React.FC<{ x: number; y: number; at: number }> = ({ x, y, at }) => {
  const frame = useCurrentFrame();
  const t = frame - at;
  if (t < -4 || t > 22) return null;
  const press = interpolate(t, [-4, 0, 6, 12], [0.6, 1, 0.9, 0.9], clamp);
  const fade = interpolate(t, [-4, 0, 8, 16], [0, 1, 1, 0], clamp);
  const ring = interpolate(t, [4, 22], [1, 2.2], { ...clamp, easing: Easing.out(Easing.cubic) });
  const ringFade = interpolate(t, [4, 22], [0.7, 0], clamp);
  const d = 130;
  return (
    <>
      <div style={{ position: "absolute", left: x - d / 2, top: y - d / 2, width: d, height: d, borderRadius: d,
        background: "rgba(255,255,255,0.55)", border: "5px solid rgba(6,18,31,0.25)", boxShadow: "0 6px 24px rgba(6,18,31,0.25)",
        transform: `scale(${press})`, opacity: fade }} />
      <div style={{ position: "absolute", left: x - d / 2, top: y - d / 2, width: d, height: d, borderRadius: d,
        border: "5px solid rgba(255,255,255,0.9)", transform: `scale(${ring})`, opacity: ringFade }} />
    </>
  );
};

/** A full-frame white flash, like a shutter. */
export const Flash: React.FC<{ at: number }> = ({ at }) => {
  const frame = useCurrentFrame();
  const o = interpolate(frame - at, [0, 2, 12], [0, 1, 0], clamp);
  return o > 0 ? <AbsoluteFill style={{ background: "#fff", opacity: o }} /> : null;
};

// MARK: - Particles

const star = (r: number) => {
  const k = r * 0.32;
  return `M0,${-r} C${k * 0.3},${-k} ${k},${-k * 0.3} ${r},0 C${k},${k * 0.3} ${k * 0.3},${k} 0,${r} C${-k * 0.3},${k} ${-k},${k * 0.3} ${-r},0 C${-k},${-k * 0.3} ${-k * 0.3},${-k} 0,${-r} Z`;
};

/** Four-point sparkles bursting from a point. Sizes are in the units of
 * whatever contains them (capture pixels inside a Screen). */
export const Sparkles: React.FC<{
  x: number; y: number; at: number; count?: number; spread?: number; size?: number; seed?: string;
  /** Nearest a star lands, as a share of spread; raise it to keep stars off what they surround. */
  inner?: number;
  /** Vertical spread as a share of the horizontal. */
  sy?: number;
}> = ({ x, y, at, count = 7, spread = 260, size = 34, seed = "s", inner = 0.6, sy = 1 }) => {
  const frame = useCurrentFrame();
  const t = frame - at;
  if (t < 0 || t > 34) return null;
  return (
    <svg style={{ position: "absolute", left: x - spread * 1.5, top: y - spread * 1.5, width: spread * 3, height: spread * 3, overflow: "visible" }}
      viewBox={`${-spread * 1.5} ${-spread * 1.5} ${spread * 3} ${spread * 3}`}>
      {Array.from({ length: count }, (_, i) => {
        const a = (i / count) * Math.PI * 2 + random(`${seed}a${i}`) * 0.6;
        const d = spread * (inner + random(`${seed}d${i}`) * (1.1 - inner));
        const delay = random(`${seed}t${i}`) * 5;
        const p = interpolate(t - delay, [0, 18], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
        const s = interpolate(t - delay, [0, 6, 22, 30], [0, 1, 0.8, 0], clamp);
        const r = size * (0.6 + random(`${seed}r${i}`) * 0.7);
        const fill = [C.sun, C.sun, C.field, C.white][i % 4];
        return (
          <g key={i} transform={`translate(${Math.cos(a) * d * p}, ${Math.sin(a) * d * p * sy}) scale(${s}) rotate(${p * 40})`}>
            <path d={star(r)} fill={fill} stroke={C.ink} strokeWidth={r * 0.12} strokeLinejoin="round" />
          </g>
        );
      })}
    </svg>
  );
};

/** Confetti thrown up from a point, falling under gravity. */
export const Confetti: React.FC<{ x: number; y: number; at: number; count?: number; power?: number; size?: number; seed?: string }> = ({
  x, y, at, count = 46, power = 1, size = 1, seed = "c",
}) => {
  const frame = useCurrentFrame();
  const t = frame - at;
  if (t < 0 || t > 80) return null;
  const colors = [C.sun, C.field, C.flame, C.navy, C.white, "#FF6B8A", "#34C759"];
  return (
    <svg style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, overflow: "visible" }} viewBox={`0 0 ${SW} ${SH}`}>
      {Array.from({ length: count }, (_, i) => {
        const r = (k: string) => random(`${seed}${k}${i}`);
        const a = -Math.PI / 2 + (r("a") - 0.5) * 2.3;
        const v = (34 + r("v") * 40) * power;
        const drag = 0.94;
        const travel = (1 - Math.pow(drag, t)) / (1 - drag);
        const px = x + Math.cos(a) * v * travel;
        const py = y + Math.sin(a) * v * travel + 0.9 * t * t * 0.5 * (0.7 + r("g") * 0.6);
        const spin = (r("s") - 0.5) * 30 * t;
        const flip = Math.cos(t * (0.2 + r("f") * 0.3));
        const kind = i % 3;
        const s = (18 + r("z") * 16) * size;
        const fade = interpolate(t, [60, 80], [1, 0], clamp);
        const fill = colors[i % colors.length];
        return (
          <g key={i} transform={`translate(${px}, ${py}) rotate(${spin}) scale(1, ${flip})`} opacity={fade}>
            {kind === 0 && <rect x={-s / 2} y={-s / 4} width={s} height={s / 2} rx={s * 0.08} fill={fill} stroke={C.ink} strokeWidth={3} />}
            {kind === 1 && <circle r={s * 0.36} fill={fill} stroke={C.ink} strokeWidth={3} />}
            {kind === 2 && <path d={`M${-s / 2},0 q${s / 4},${-s / 2} ${s / 2},0 t${s / 2},0`} fill="none" stroke={fill} strokeWidth={s * 0.22} strokeLinecap="round" />}
          </g>
        );
      })}
    </svg>
  );
};
