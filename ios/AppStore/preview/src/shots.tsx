// The app shots, animated from captures. Boxes are capture pixels read off
// the stills in public/s; p/ holds each screen's empty background.

import React from "react";
import { AbsoluteFill, Easing, interpolate, Sequence, useCurrentFrame } from "remotion";
import {
  Bars, C, Confetti, Flash, Lift, Piece, Pop, Pulse, Ring, Rise, Roll, Screen, Sparkles, Still, Tap, useSpring, SW, SH,
} from "./kit";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const TAB_BAR: [number, number, number, number] = [0, 2590, 1320, 278];

// MARK: - Today: the score draws, the day's bars grow, the cards follow

export const TodayShot: React.FC = () => {
  const s = "s/today.png";
  return (
    <Screen camera={[{ f: 0, s: 1 }, { f: 46, s: 1 }, { f: 84, s: 1.16, x: 720, y: 760 }]}>
      <Still name="p/today.png" />
      <Piece name={s} box={[0, 0, 1320, 450]} />
      <Rise name={s} box={[0, 480, 930, 300]} at={3} dy={60} />
      <Ring name={s} cx={1110} cy={617} r={152} inner={110} at={5} dur={28} />
      <Pop name={s} box={[1010, 528, 200, 180]} at={20} from={0.5} />
      <Bars name={s} x0={60} x1={1262} n={24} top={836} base={1044} at={8} />
      <Rise name={s} box={[0, 1044, 1320, 110]} at={18} dy={30} />
      {[60, 468, 878].map((x, i) => <Rise key={x} name={s} box={[x, 1176, 384, 300]} at={20 + i * 3} />)}
      <Rise name={s} box={[0, 1505, 1320, 225]} at={28} />
      <Rise name={s} box={[0, 1775, 1320, 460]} at={31} />
      <Rise name={s} box={[0, 2255, 1320, 335]} at={34} />
      <Piece name={s} box={TAB_BAR} />
    </Screen>
  );
};

// MARK: - Log a catch: Add menu, camera, shutter, the scan, the answer

export const AddFlowShot: React.FC = () => {
  const frame = useCurrentFrame();
  const menu = useSpring(20, { damping: 16, stiffness: 190 });
  const sheet = useSpring(56, { damping: 20, stiffness: 120 });
  const shutter = interpolate(frame, [86, 89, 94, 98], [1, 0.86, 0.86, 1], clamp);
  const scanY = interpolate(frame, [98, 114, 115, 129], [360, 1270, 360, 1270], { ...clamp, easing: Easing.inOut(Easing.sin) });
  const scanOn = frame >= 98 && frame <= 130;
  const result = interpolate(frame, [130, 132], [0, 1], clamp);
  const m = "s/add-menu.png";
  const tiles: [number, number, number, number][] = [[104, 1794, 538, 362], [676, 1794, 544, 362], [104, 2186, 538, 362], [676, 2186, 544, 362]];
  return (
    <Screen camera={[{ f: 0, s: 1 }, { f: 132, s: 1 }, { f: 158, s: 1.22, x: 520, y: 1260 }]}>
      <Still name="s/today-65.png" />
      <Tap x={658} y={2705} at={14} />
      <AbsoluteFill style={{ background: "#000", opacity: 0.28 * Math.min(1, menu * 1.4) }} />
      <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, opacity: Math.min(1, menu * 2),
        transform: `translateY(${(1 - menu) * 160}px) scale(${0.9 + 0.1 * menu})`, transformOrigin: "660px 2700px" }}>
        <div style={{ position: "absolute", left: 60, top: 1760, width: 1200, height: 822, borderRadius: 90, background: C.white }} />
        {tiles.map((b, i) => <Pop key={i} name={m} box={b} at={23 + i * 3} from={0.7} radius={56} />)}
      </div>
      <Tap x={370} y={1975} at={48} />

      {frame >= 54 && (
        <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, transform: `translateY(${(1 - sheet) * SH}px)` }}>
          <Still name="s/log-catch-camera.png" />
          <Piece name="s/log-catch-camera.png" box={[540, 2358, 240, 240]} radius="50%" style={{ transform: `scale(${shutter})` }} />
          <Tap x={660} y={2478} at={88} />
        </div>
      )}

      <Sequence from={94} layout="none">
        <Still name="s/id-scan.png" />
        {scanOn && (
          <>
            <div style={{ position: "absolute", left: 60, width: 1080, top: scanY - 140, height: 140,
              background: "linear-gradient(to bottom, rgba(10,132,255,0), rgba(10,132,255,0.22))" }} />
            <div style={{ position: "absolute", left: 60, width: 1080, top: scanY - 4, height: 8, borderRadius: 4,
              background: C.blue, boxShadow: "0 0 26px 6px rgba(10,132,255,0.65)" }} />
          </>
        )}
        <div style={{ position: "absolute", inset: 0, opacity: result }}>
          <Still name="s/log-catch-id-trout.png" />
          <div style={{ position: "absolute", left: 645, top: 1515, width: 84, height: 63, background: "#FEFEFE" }} />
        </div>
        {frame >= 130 && (
          <Sequence from={40} layout="none">
            <Lift name="s/log-catch-id-trout.png" box={[40, 1398, 900, 290]} at={0} scale={1.08} cover={[[645, 1515, 84, 63]]} coverColor="#FEFEFE" />
          </Sequence>
        )}
      </Sequence>
      <Flash at={92} />
    </Screen>
  );
};

// MARK: - Forecast: the week lands, then the day and its best hour

export const ForecastShot: React.FC = () => {
  const frame = useCurrentFrame();
  const push = interpolate(frame, [44, 58], [0, 1], { ...clamp, easing: Easing.bezier(0.3, 0, 0.1, 1) });
  const hour = interpolate(frame, [88, 89], [0, 1], clamp);
  const w = "s/forecast-week.png";
  const d = "s/forecast-day.png";
  return (
    <Screen camera={[{ f: 0, s: 1 }, { f: 70, s: 1 }, { f: 118, s: 1.14, x: 660, y: 1990 }]}>
      <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, transform: `translateX(${-push * 420}px)` }}>
        <Still name="p/forecast-week.png" />
        <Piece name={w} box={[0, 0, 1320, 660]} />
        <Pop name={w} box={[60, 695, 1200, 300]} at={3} from={0.85} radius={56} />
        <div style={{ position: "absolute", left: 60, top: 1062, width: 1200, height: 1806, borderRadius: 56, background: "#F2F2F7",
          opacity: interpolate(frame, [5, 10], [0, 1], clamp) }} />
        {Array.from({ length: 6 }, (_, i) => <Rise key={i} name={w} box={[60, 1062 + i * 254, 1200, 254]} at={7 + i * 3} dx={200} dy={0} />)}
        <Piece name={w} box={TAB_BAR} />
        <Tap x={660} y={1190} at={38} />
        <AbsoluteFill style={{ background: "#000", opacity: push * 0.12 }} />
      </div>

      {frame >= 44 && (
        <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, transform: `translateX(${(1 - push) * SW}px)`,
          boxShadow: "-20px 0 60px rgba(0,0,0,0.12)" }}>
          <Still name="p/forecast-day.png" />
          <Piece name={d} box={[0, 0, 1320, 1500]} />
          <div style={{ position: "absolute", left: 960, top: 886, width: 310, height: 310, borderRadius: "50%", background: "#F6FAFF" }} />
          <Ring name={d} cx={1114} cy={1040} r={146} inner={112} at={50} dur={26} />
          <Pop name={d} box={[1024, 960, 180, 170]} at={62} from={0.5} />
          <Piece name={d} box={[0, 1500, 1320, 180]} />
          <Bars name={d} x0={60} x1={1262} n={24} top={1680} base={1966} at={52} />
          <Rise name={d} box={[0, 1966, 1320, 902]} at={60} />
          <div style={{ position: "absolute", inset: 0, opacity: hour }}>
            <Still name="s/forecast-day-hour.png" />
          </div>
          {frame >= 88 && <Pop name="s/forecast-day-hour.png" box={[60, 2132, 1200, 298]} at={88} from={0.9} radius={56} />}
          <Tap x={986} y={1830} at={86} />
        </div>
      )}
    </Screen>
  );
};

// MARK: - Explore: the map, the pins, a spot opened

export const ExploreShot: React.FC = () => {
  const frame = useCurrentFrame();
  const sheet = useSpring(40, { damping: 19, stiffness: 120 });
  const e = "s/explore.png";
  const n = "s/explore-near.png";
  const pins: { box: [number, number, number, number]; at: number; radius?: number | string }[] = [
    { box: [660, 728, 150, 150], at: 4, radius: 40 },
    { box: [486, 1040, 182, 182], at: 8, radius: 40 },
    { box: [808, 1375, 100, 100], at: 11 },
    { box: [372, 1534, 100, 100], at: 14 },
    { box: [576, 1714, 120, 120], at: 17 },
  ];
  return (
    <Screen camera={[{ f: 0, s: 1 }, { f: 38, s: 1.14, x: 570, y: 1150 }, { f: 56, s: 1 }]}>
      <Still name={e} />
      {pins.map((p, i) => <Pulse key={i} name={e} box={p.box} at={p.at} radius={p.radius} />)}
      <Tap x={566} y={1135} at={34} />
      {frame >= 38 && (
        <div style={{ position: "absolute", left: 0, top: 0, width: SW, height: SH, transform: `translateY(${(1 - sheet) * 1600}px)` }}>
          <Piece name={n} box={[20, 1340, 1280, 1528]} radius="92px 92px 0 0" style={{ boxShadow: "0 -10px 50px rgba(0,0,0,0.18)" }} />
          <div style={{ position: "absolute", left: 1109 - 140, top: 1716 - 140, width: 280, height: 280, borderRadius: "50%", background: C.white }} />
          <Ring name={n} cx={1109} cy={1716} r={130} inner={98} at={54} dur={24} />
          <Pop name={n} box={[1040, 1660, 140, 120]} at={62} from={0.5} />
          <Sparkles x={1109} y={1716} at={72} count={6} spread={200} size={30} seed="x" />
        </div>
      )}
    </Screen>
  );
};

// MARK: - Streak: the flame, the count, the week ticking over

export const StreakShot: React.FC = () => {
  const s = "s/streak-moment.png";
  const dots = [186, 345, 502, 660, 818, 975, 1133];
  return (
    <Screen camera={[{ f: 0, s: 1.06, x: 660, y: 1300 }, { f: 84, s: 1, x: 660, y: 1300 }]}>
      <Still name="p/streak-moment.png" />
      <Piece name={s} box={[0, 0, 1320, 180]} />
      <Pop name={s} box={[330, 570, 654, 654]} at={2} from={0.2} radius="50%" />
      <Roll name={s} box={[440, 1290, 440, 296]} at={12} />
      <Rise name={s} box={[400, 1586, 520, 110]} at={16} dy={40} />
      <Rise name="s/streak-empty.png" box={[58, 1774, 1204, 274]} at={16} radius={60} />
      {dots.map((x, i) => <Pop key={x} name={s} box={[x - 58, 1818, 116, 116]} at={22 + i * 3} from={0} radius="50%" />)}
      <Rise name={s} box={[150, 2085, 1020, 110]} at={44} dy={40} />
      <Rise name={s} box={[58, 2552, 1204, 170]} at={48} radius={84} />
      <Confetti x={657} y={880} at={26} count={54} power={1.15} size={1.6} />
      <Sparkles x={657} y={897} at={30} count={8} spread={380} size={40} seed="n" inner={0.95} sy={0.9} />
    </Screen>
  );
};
