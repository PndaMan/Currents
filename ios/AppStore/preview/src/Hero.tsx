// The opening frame, which is also the poster App Store Connect shows before
// the preview plays: complete on frame 0, then it drifts until the first push.

import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { C } from "./kit";
import { FONT, Mark } from "./TitleCard";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const PHONE = 1446 / 2970; // width over height of the drawn iPhone

const Phone: React.FC<{ name: string; x: number; top: number; width: number; angle: number; lift: number }> = ({
  name, x, top, width, angle, lift,
}) => (
  <Img src={staticFile(`phones/${name}.png`)} style={{
    position: "absolute", left: x - width / 2, top: top - lift, width, height: width / PHONE,
    transform: `rotate(${angle}deg)`, filter: "drop-shadow(0 34px 44px rgba(6,18,31,0.28))",
  }} />
);

export const Hero: React.FC = () => {
  const frame = useCurrentFrame();
  const drift = interpolate(frame, [0, 40], [0, 1], { ...clamp, easing: Easing.inOut(Easing.sin) });
  return (
    <AbsoluteFill style={{ background: C.field, fontFamily: FONT, color: C.ink, overflow: "hidden" }}>
      <svg width={886} height={1920} style={{ position: "absolute", inset: 0 }}>
        {[0, 1, 2].map((i) => (
          <circle key={i} cx={560} cy={1330} r={330 + i * 190 + drift * 40} fill="none" stroke={C.white}
            strokeWidth={6} opacity={0.32 - i * 0.09} />
        ))}
      </svg>
      <div style={{ position: "absolute", left: 60, top: 190, display: "flex", alignItems: "center", gap: 14 }}>
        <Mark size={58} color={C.ink} />
        <span style={{ fontSize: 54, fontWeight: 700, letterSpacing: "-0.02em" }}>Currents</span>
      </div>
      <div style={{ position: "absolute", left: 60, top: 300, fontSize: 150, fontWeight: 800, letterSpacing: "-0.035em", lineHeight: 0.98 }}>
        <div>Fish more.</div>
        <div>Guess less.</div>
      </div>
      <div style={{ position: "absolute", left: 62, top: 618, fontSize: 46, fontWeight: 700, letterSpacing: "-0.015em", lineHeight: 1.2, color: C.navy }}>
        <div>Bite times, fish ID and maps,</div>
        <div>even with no signal.</div>
      </div>
      <Phone name="log-catch-id-trout" x={262} top={850} width={520} angle={-8} lift={drift * 18} />
      <Phone name="today" x={606} top={800} width={580} angle={6} lift={drift * 32} />
    </AbsoluteFill>
  );
};
