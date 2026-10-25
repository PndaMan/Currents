// The drawn objects on the title cards, in one style: flat brand colours
// with an ink outline. Each is laid out on the 886x1920 frame.

import React from "react";
import { AbsoluteFill, Easing, interpolate, random, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { C } from "./kit";
import { FONT, Mark } from "./TitleCard";

const INK = C.ink;
const LINE = 8;
const CORAL = "#FF5A5F";
const DEEP = "#2EA3DB";
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

const useT = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const sp = (at: number, config = {}) => spring({ frame: frame - at, fps, config: { damping: 14, stiffness: 170, ...config } });
  return { frame, sp };
};

const Svg: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill>
    <svg width={886} height={1920} viewBox="0 0 886 1920" style={{ overflow: "visible" }}>{children}</svg>
  </AbsoluteFill>
);

/** Short strokes flaring out from a point, like an impact. */
const Burst: React.FC<{ x: number; y: number; at: number; r?: number; n?: number; turn?: number }> = ({ x, y, at, r = 120, n = 7, turn = 0 }) => {
  const { frame } = useT();
  const t = frame - at;
  if (t < 0 || t > 14) return null;
  const p = interpolate(t, [0, 10], [0, 1], { ...clamp, easing: Easing.out(Easing.cubic) });
  const fade = interpolate(t, [6, 14], [1, 0], clamp);
  return (
    <g opacity={fade}>
      {Array.from({ length: n }, (_, i) => {
        const a = turn + (i / n) * Math.PI * 2;
        const r0 = r * (0.55 + 0.45 * p);
        const r1 = r0 + 46 * (1 - p * 0.6);
        return <line key={i} x1={x + Math.cos(a) * r0} y1={y + Math.sin(a) * r0} x2={x + Math.cos(a) * r1} y2={y + Math.sin(a) * r1}
          stroke={INK} strokeWidth={LINE} strokeLinecap="round" />;
      })}
    </g>
  );
};

const Ripple: React.FC<{ x: number; y: number; at: number; dur?: number; max?: number }> = ({ x, y, at, dur = 30, max = 300 }) => {
  const { frame } = useT();
  const t = frame - at;
  if (t < 0 || t > dur) return null;
  const p = interpolate(t, [0, dur], [0, 1], { ...clamp, easing: Easing.out(Easing.quad) });
  const rx = 70 + (max - 70) * p;
  return <ellipse cx={x} cy={y} rx={rx} ry={rx * 0.2} fill="none" stroke={C.white} strokeWidth={7} opacity={1 - p} />;
};

// MARK: - Know when the fish bite: a float that takes a bite

export const Bobber: React.FC = () => {
  const { frame, sp } = useT();
  const water = 1520;
  const bx = 520;
  const land = sp(2, { damping: 11, stiffness: 120 });
  const bite1 = sp(40, { damping: 9, stiffness: 260 }) - sp(46, { damping: 12, stiffness: 200 });
  const bite2 = sp(54, { damping: 10, stiffness: 240 });
  const bob = frame > 12 ? Math.sin(frame * 0.22) * 9 * (1 - bite2) : 0;
  const y = water - 30 - (1 - land) * 560 + bob + bite1 * 80 + bite2 * 150;
  const tilt = Math.sin(frame * 0.17) * 5 * (1 - bite2) - bite1 * 8 - bite2 * 14;
  const wave = (x: number) => water + Math.sin(x / 90 + frame * 0.12) * 10;
  let surface = `M0,${wave(0)}`;
  for (let x = 20; x <= 886; x += 20) surface += ` L${x},${wave(x)}`;
  return (
    <Svg>
      <defs>
        <clipPath id="above"><rect x={0} y={0} width={886} height={wave(bx) + 4} /></clipPath>
      </defs>
      {/* the line, up to a rod out of frame */}
      <path d={`M${bx + Math.sin((tilt * Math.PI) / 180) * 210},${y - 205} Q${760},${1120 - bite2 * 60} ${950},${980}`} fill="none" stroke={INK} strokeWidth={4} />
      <path d={`${surface} L886,1920 L0,1920 Z`} fill={DEEP} />
      <path d={surface} fill="none" stroke={C.pale} strokeWidth={6} opacity={0.6} />
      <Ripple x={bx} y={water} at={9} />
      <Ripple x={bx} y={water} at={18} max={220} />
      <Ripple x={bx} y={water} at={41} />
      <Ripple x={bx} y={water} at={55} max={360} />
      <Ripple x={bx} y={water} at={62} max={260} />
      <g clipPath="url(#above)">
        <g transform={`translate(${bx}, ${y}) rotate(${tilt})`}>
          <rect x={-11} y={-210} width={22} height={130} rx={11} fill={C.white} stroke={INK} strokeWidth={LINE} />
          <circle cx={0} cy={-210} r={17} fill={C.sun} stroke={INK} strokeWidth={LINE} />
          <path d="M-96,0 A96,96 0 0 1 96,0 Z" fill={CORAL} stroke={INK} strokeWidth={LINE} strokeLinejoin="round" />
          <path d="M-96,0 A96,96 0 0 0 96,0 Z" fill={C.white} stroke={INK} strokeWidth={LINE} strokeLinejoin="round" />
          <path d="M-58,-52 A60,60 0 0 1 -18,-74" fill="none" stroke={C.white} strokeWidth={10} strokeLinecap="round" opacity={0.85} />
        </g>
      </g>
      <Burst x={bx} y={water - 60} at={41} r={150} n={6} turn={-Math.PI / 2 - 1.2} />
      <Burst x={bx} y={water - 60} at={55} r={170} n={7} turn={-Math.PI / 2 - 1.3} />
      {/* splash drops as it lands */}
      {Array.from({ length: 7 }, (_, i) => {
        const t = frame - 9;
        if (t < 0 || t > 20) return null;
        const a = -Math.PI / 2 + (i - 3) * 0.38;
        const v = 15 + random(`drop${i}`) * 9;
        const px = bx + Math.cos(a) * v * t;
        const py = water - 20 + Math.sin(a) * v * t + 1.3 * t * t;
        return <circle key={i} cx={px} cy={py} r={11} fill={C.white} stroke={INK} strokeWidth={5} opacity={interpolate(t, [14, 20], [1, 0], clamp)} />;
      })}
    </Svg>
  );
};

// MARK: - Snap a fish: a camera that fires

export const Camera: React.FC = () => {
  const { frame, sp } = useT();
  const enter = sp(2, { damping: 12, stiffness: 140 });
  const press = interpolate(frame, [26, 29, 33, 37], [0, 1, 1, 0], clamp);
  const recoil = interpolate(frame, [29, 32, 40], [1, 0.95, 1], clamp);
  const flash = interpolate(frame, [29, 31, 44], [0, 1, 0], clamp);
  const flashR = interpolate(frame, [29, 44], [20, 520], { ...clamp, easing: Easing.out(Easing.cubic) });
  const cx = 500, cy = 1430;
  const fx = cx + 150, fy = cy - 95;
  return (
    <Svg>
      <g transform={`translate(${cx}, ${cy + (1 - enter) * 500}) rotate(${-14 + 8 * enter}) scale(${(0.6 + 0.4 * enter) * recoil})`}>
        <path d="M-160,-150 L-140,-196 L-40,-196 L-20,-150 Z" fill={C.white} stroke={INK} strokeWidth={LINE} strokeLinejoin="round" />
        <rect x={110} y={-182 + press * 14} width={84} height={40} rx={12} fill={C.sun} stroke={INK} strokeWidth={LINE} />
        <rect x={-250} y={-152} width={500} height={330} rx={52} fill={C.white} stroke={INK} strokeWidth={LINE} />
        <rect x={-250} y={-34} width={500} height={84} fill={C.sun} stroke={INK} strokeWidth={LINE} />
        <rect x={120} y={-120} width={70} height={44} rx={10} fill={C.pale} stroke={INK} strokeWidth={LINE} />
        <circle cx={-10} cy={14} r={126} fill={C.navy} stroke={INK} strokeWidth={LINE} />
        <circle cx={-10} cy={14} r={84} fill={C.field} stroke={INK} strokeWidth={LINE} />
        <circle cx={-10} cy={14} r={44} fill={C.navy} />
        <circle cx={-40} cy={-16} r={18} fill={C.white} />
        <circle cx={14} cy={36} r={8} fill={C.white} opacity={0.8} />
      </g>
      {flash > 0 && <circle cx={fx} cy={fy} r={flashR} fill={C.white} opacity={flash * 0.85} />}
      <Burst x={fx} y={fy} at={30} r={130} n={9} />
    </Svg>
  );
};

// MARK: - Pick the best day: a calendar with one day ringed

export const Calendar: React.FC = () => {
  const { frame, sp } = useT();
  const drop = sp(1, { damping: 13, stiffness: 130 });
  const cx = 470, cy = 1430;
  const cell = 62, gap = 14;
  const gx = -(7 * cell + 6 * gap) / 2;
  const best = { col: 1, row: 1 };
  const bx = gx + best.col * (cell + gap) + cell / 2;
  const by = -60 + best.row * (cell + gap) + cell / 2;
  const draw = interpolate(frame, [24, 40], [0, 1], { ...clamp, easing: Easing.inOut(Easing.cubic) });
  const fish = sp(38, { damping: 10, stiffness: 220 });
  const loop = `M${bx + 50},${by - 30} C${bx + 66},${by + 40} ${bx - 40},${by + 66} ${bx - 58},${by + 8} C${bx - 72},${by - 44} ${bx + 10},${by - 70} ${bx + 46},${by - 44} L${bx + 58},${by - 20}`;
  return (
    <Svg>
      <g transform={`translate(${cx}, ${cy - (1 - drop) * 700}) rotate(${-12 + 7 * drop})`}>
        <rect x={-300} y={-250} width={600} height={520} rx={44} fill={C.white} stroke={INK} strokeWidth={LINE} />
        <path d="M-300,-140 L-300,-206 A44,44 0 0 1 -256,-250 L256,-250 A44,44 0 0 1 300,-206 L300,-140 Z" fill={C.navy} stroke={INK} strokeWidth={LINE} strokeLinejoin="round" />
        {[-150, 150].map((x) => (
          <rect key={x} x={x - 14} y={-286} width={28} height={74} rx={14} fill={C.white} stroke={INK} strokeWidth={LINE} />
        ))}
        {["M", "T", "W", "T", "F", "S", "S"].map((d, i) => (
          <text key={i} x={gx + i * (cell + gap) + cell / 2} y={-178} textAnchor="middle" fontFamily={FONT} fontWeight={800} fontSize={34} fill={C.white}>{d}</text>
        ))}
        {Array.from({ length: 21 }, (_, i) => {
          const col = i % 7, row = Math.floor(i / 7);
          const p = sp(6 + i * 0.8, { damping: 13, stiffness: 240 });
          const isBest = col === best.col && row === best.row;
          const x = gx + col * (cell + gap), y = -60 + row * (cell + gap);
          return (
            <rect key={i} x={x} y={y} width={cell} height={cell} rx={16} fill={isBest && fish > 0.05 ? C.sun : C.pale}
              transform={`translate(${x + cell / 2}, ${y + cell / 2}) scale(${p}) translate(${-x - cell / 2}, ${-y - cell / 2})`} />
          );
        })}
        <g transform={`translate(${bx}, ${by}) scale(${fish}) rotate(${(1 - fish) * -40})`}>
          <foreignObject x={-26} y={-26} width={52} height={52}><Mark size={52} color={INK} /></foreignObject>
        </g>
        <path d={loop} fill="none" stroke={CORAL} strokeWidth={11} strokeLinecap="round" strokeLinejoin="round"
          pathLength={1} strokeDasharray={1} strokeDashoffset={1 - draw} />
      </g>
    </Svg>
  );
};

// MARK: - Find water: a map with pins dropping on it

const pin = "M0,0 C-14,-30 -52,-62 -52,-104 A52,52 0 0 1 52,-104 C52,-62 14,-30 0,0 Z";

export const MapPins: React.FC = () => {
  const { frame, sp } = useT();
  const open = sp(1, { damping: 15, stiffness: 150 });
  const cx = 450, cy = 1460;
  const pw = 210, ph = 470;
  const panels = [0, 1, 2].map((i) => {
    const x0 = -1.5 * pw + i * pw, x1 = x0 + pw;
    const up = i % 2 === 0 ? 0 : 26;
    return `M${x0},${-ph / 2 + (i % 2 ? up : 0)} L${x1},${-ph / 2 + (i % 2 ? 0 : up)} L${x1},${ph / 2 + (i % 2 ? 0 : up)} L${x0},${ph / 2 + (i % 2 ? up : 0)} Z`;
  });
  const lake = "M-250,-60 C-220,-160 -60,-170 -10,-100 C40,-30 150,-90 210,-20 C270,50 180,150 60,120 C-40,95 -110,160 -200,110 C-280,70 -270,0 -250,-60 Z";
  const pins = [
    { x: -150, y: -40, at: 14, fill: C.sun },
    { x: 150, y: -70, at: 19, fill: CORAL },
    { x: 20, y: 150, at: 24, fill: C.white },
  ];
  const route = interpolate(frame, [28, 50], [0, 1], { ...clamp, easing: Easing.inOut(Easing.quad) });
  const trail = `M${pins[0].x},${pins[0].y - 20} C-40,-200 100,-160 ${pins[1].x},${pins[1].y - 20} S120,120 ${pins[2].x},${pins[2].y - 20}`;
  return (
    <Svg>
      <g transform={`translate(${cx}, ${cy}) rotate(-5) scale(${0.3 + 0.7 * open}, 1)`} opacity={Math.min(1, open * 2)}>
        <clipPath id="sheet">{panels.map((d, i) => <path key={i} d={d} />)}</clipPath>
        {panels.map((d, i) => <path key={i} d={d} fill={i === 1 ? "#C9ECFF" : C.pale} />)}
        <g clipPath="url(#sheet)">
          <path d={lake} fill={C.field} stroke={INK} strokeWidth={6} />
          <mask id="drawn">
            <path d={trail} fill="none" stroke="#fff" strokeWidth={24} pathLength={1} strokeDasharray={1} strokeDashoffset={1 - route} />
          </mask>
          <path d={trail} fill="none" stroke={INK} strokeWidth={7} strokeLinecap="round" strokeDasharray="4 22" mask="url(#drawn)" />
        </g>
        {panels.map((d, i) => <path key={i} d={d} fill="none" stroke={INK} strokeWidth={LINE} strokeLinejoin="round" />)}
      </g>
      {pins.map((p, i) => {
        const s = sp(p.at, { damping: 9, stiffness: 200 });
        const t = frame - p.at;
        if (t < 0) return null;
        const fall = interpolate(t, [0, 9], [-520, 0], { ...clamp, easing: Easing.in(Easing.quad) });
        const squash = t >= 9 ? 1 - Math.sin(Math.min(1, (t - 9) / 8) * Math.PI) * 0.18 : 1;
        return (
          <g key={i} transform={`translate(${cx + p.x}, ${cy + p.y})`}>
            <ellipse cx={0} cy={4} rx={40 * Math.min(1, s)} ry={11 * Math.min(1, s)} fill={INK} opacity={0.25} />
            <g transform={`translate(0, ${fall}) scale(${2 - squash}, ${squash})`}>
              <path d={pin} fill={p.fill} stroke={INK} strokeWidth={LINE} strokeLinejoin="round" />
              <circle cx={0} cy={-104} r={20} fill={i === 2 ? C.field : C.white} stroke={INK} strokeWidth={6} />
            </g>
          </g>
        );
      })}
    </Svg>
  );
};

// MARK: - Keep your streak: a flame and a week of ticks

const flamePath = "M0,0 C-120,0 -170,-90 -150,-180 C-135,-250 -80,-280 -70,-360 C-30,-310 -10,-260 -20,-210 C10,-260 40,-330 20,-420 C110,-360 170,-250 160,-150 C155,-60 100,0 0,0 Z";
const innerPath = "M0,-8 C-60,-8 -86,-56 -76,-104 C-66,-150 -30,-160 -26,-200 C10,-170 30,-140 22,-104 C40,-126 52,-150 50,-170 C90,-130 96,-80 82,-50 C68,-20 40,-8 0,-8 Z";

export const Flame: React.FC = () => {
  const { frame, sp } = useT();
  const grow = sp(2, { damping: 10, stiffness: 150 });
  const sy = 1 + Math.sin(frame * 0.8) * 0.035 + Math.sin(frame * 1.7) * 0.02;
  const skew = Math.sin(frame * 0.55) * 4;
  const cx = 450, cy = 1540;
  return (
    <Svg>
      {Array.from({ length: 6 }, (_, i) => {
        const t = (frame + i * 9) % 40;
        const x = cx + Math.sin(i * 2.1 + t * 0.15) * 40 + (i - 2.5) * 30;
        const y = cy - 300 - t * 9;
        return frame > 8 ? <circle key={i} cx={x} cy={y} r={9 - t * 0.18} fill={C.sun} stroke={INK} strokeWidth={4} opacity={interpolate(t, [0, 6, 30, 40], [0, 1, 1, 0])} /> : null;
      })}
      <g transform={`translate(${cx}, ${cy - 100}) scale(${grow}) skewX(${skew}) scale(1, ${sy})`}>
        <path d={flamePath} fill={C.flame} stroke={INK} strokeWidth={LINE} strokeLinejoin="round" />
        <path d={innerPath} fill={C.sun} stroke={INK} strokeWidth={6} strokeLinejoin="round" />
      </g>
      {Array.from({ length: 7 }, (_, i) => {
        const x = 443 - 3 * 100 + i * 100, y = 1640;
        const p = sp(14 + i * 4, { damping: 9, stiffness: 260 });
        const done = p > 0.02;
        return (
          <g key={i} transform={`translate(${x}, ${y})`}>
            <circle r={38} fill={C.white} stroke={INK} strokeWidth={6} />
            {done && (
              <g transform={`scale(${p})`}>
                <circle r={38} fill={C.flame} stroke={INK} strokeWidth={6} />
                <path d="M-15,1 L-4,13 L17,-11" fill="none" stroke={C.white} strokeWidth={8} strokeLinecap="round" strokeLinejoin="round" />
              </g>
            )}
          </g>
        );
      })}
    </Svg>
  );
};

// MARK: - End card

export const EndCard: React.FC = () => {
  const { frame, sp } = useT();
  const mark = sp(0, { damping: 10, stiffness: 160 });
  const name = sp(10, { damping: 16, stiffness: 180 });
  const words = ["Works", "with", "no", "signal."];
  return (
    <AbsoluteFill style={{ background: C.field, fontFamily: FONT, fontWeight: 800, letterSpacing: "-0.03em", color: INK }}>
      <Svg>
        {[0, 9, 18].map((d) => {
          const t = frame - 6 - d;
          if (t < 0) return null;
          const p = interpolate(t, [0, 40], [0, 1], { ...clamp, easing: Easing.out(Easing.quad) });
          return <circle key={d} cx={443} cy={760} r={150 + p * 420} fill="none" stroke={C.white} strokeWidth={8} opacity={(1 - p) * 0.8} />;
        })}
      </Svg>
      <div style={{ position: "absolute", left: 443 - 150, top: 610, width: 300, height: 300,
        transform: `scale(${mark}) rotate(${(1 - mark) * -30}deg)` }}>
        <Mark size={300} color={C.white} style={{ filter: "drop-shadow(0 14px 0 rgba(6,18,31,0.18))" }} />
      </div>
      <div style={{ position: "absolute", top: 960, width: "100%", textAlign: "center", fontSize: 128,
        opacity: name, transform: `translateY(${(1 - name) * 40}px)` }}>Currents</div>
      <div style={{ position: "absolute", top: 1160, width: "100%", textAlign: "center", fontSize: 84, lineHeight: 1.05 }}>
        {[words.slice(0, 2), words.slice(2)].map((line, li) => (
          <div key={li}>
            {line.map((w, wi) => {
              const p = sp(20 + (li * 2 + wi) * 3, { damping: 16, stiffness: 210, mass: 0.7 });
              return <span key={wi} style={{ display: "inline-block", margin: "0 0.12em", opacity: Math.min(1, p * 3), transform: `translateY(${(1 - p) * 0.42}em)` }}>{w}</span>;
            })}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};
