// A title card: the brand field with a headline that builds word by word,
// and one drawn object acting out the line.

import React from "react";
import { AbsoluteFill, interpolate, staticFile, useCurrentFrame, useVideoConfig, spring } from "remotion";
import { C } from "./kit";

export const FONT = "Inter Display";

export type Block = { lines: string[]; at: number };

const Words: React.FC<{ block: Block; size: number; ink: string }> = ({ block, size, ink }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  let n = 0;
  return (
    <div>
      {block.lines.map((line, li) => (
        <div key={li} style={{ height: size * 0.98, whiteSpace: "nowrap" }}>
          {line.split(" ").map((word, wi) => {
            const p = spring({ frame: frame - block.at - n++ * 3, fps, config: { damping: 16, stiffness: 210, mass: 0.7 } });
            return (
              <span key={wi} style={{ display: "inline-block", marginRight: "0.24em", color: ink,
                opacity: interpolate(p, [0, 0.35], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }),
                transform: `translateY(${(1 - p) * 0.42}em)` }}>
                {word}
              </span>
            );
          })}
        </div>
      ))}
    </div>
  );
};

/** The Currents mark in one colour. */
export const Mark: React.FC<{ size: number; color: string; style?: React.CSSProperties }> = ({ size, color, style }) => {
  const url = `url(${staticFile("logo.png")})`;
  return (
    <div style={{ width: size, height: size, background: color, WebkitMaskImage: url, maskImage: url,
      WebkitMaskSize: "contain", maskSize: "contain", ...style } as React.CSSProperties} />
  );
};

export const TitleCard: React.FC<{
  blocks: Block[];
  size?: number;
  logo?: boolean;
  bg?: string;
  ink?: string;
  children?: React.ReactNode;
}> = ({ blocks, size = 124, logo = false, bg = C.field, ink = C.ink, children }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const lp = spring({ frame, fps, config: { damping: 18, stiffness: 160 } });
  return (
    <AbsoluteFill style={{ background: bg, fontFamily: FONT, fontWeight: 800, fontSize: size, letterSpacing: "-0.03em", lineHeight: 1 }}>
      {children}
      {logo && (
        <div style={{ position: "absolute", left: 60, top: 190, display: "flex", alignItems: "center", gap: 14,
          opacity: lp, transform: `translateY(${(1 - lp) * 20}px)` }}>
          <Mark size={58} color={ink} />
          <span style={{ fontSize: 54, fontWeight: 700, letterSpacing: "-0.02em", color: ink }}>Currents</span>
        </div>
      )}
      <div style={{ position: "absolute", left: 60, top: logo ? 330 : 300, display: "flex", flexDirection: "column", gap: size * 0.5 }}>
        {blocks.map((b, i) => <Words key={i} block={b} size={size} ink={ink} />)}
      </div>
    </AbsoluteFill>
  );
};
