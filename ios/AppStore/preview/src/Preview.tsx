// The App Store preview: title cards that act out a line, each followed by
// the app doing it. 886x1920 at 30 fps, under Apple's 30 second limit. With
// the music's beats passed in, each cut and push is nudged onto a beat.

import React from "react";
import { Easing } from "remotion";
import { linearTiming, TransitionSeries } from "@remotion/transitions";
import { slide } from "@remotion/transitions/slide";
import { Bobber, Calendar, Camera, EndCard, Flame, MapPins } from "./art";
import { Hero } from "./Hero";
import { AddFlowShot, ExploreShot, ForecastShot, StreakShot, TodayShot } from "./shots";
import { TitleCard } from "./TitleCard";

type Push = "from-right" | "from-bottom";
type Scene = { id: string; frames: number; el: React.ReactNode; then?: Push };

const PUSH = 10;
const FPS = 30;
/** Apple takes up to 30 seconds; this leaves room for the encoder's rounding. */
const MAX = 888;

export const SCENES: Scene[] = [
  { id: "hero", frames: 36, then: "from-right", el: <Hero /> },
  {
    id: "bite", frames: 70, then: "from-right",
    el: (
      <TitleCard logo blocks={[{ lines: ["Know when", "the fish bite."], at: 4 }, { lines: ["Every spot,", "every hour."], at: 26 }]}>
        <Bobber />
      </TitleCard>
    ),
  },
  { id: "today", frames: 84, then: "from-bottom", el: <TodayShot /> },
  {
    id: "snap", frames: 62, then: "from-right",
    el: (
      <TitleCard blocks={[{ lines: ["Snap a fish."], at: 2 }, { lines: ["Know the", "species."], at: 16 }]}>
        <Camera />
      </TitleCard>
    ),
  },
  { id: "add-flow", frames: 156, el: <AddFlowShot /> },
  {
    id: "plan", frames: 62, then: "from-right",
    el: (
      <TitleCard blocks={[{ lines: ["Pick the best", "day to fish."], at: 2 }]}>
        <Calendar />
      </TitleCard>
    ),
  },
  { id: "forecast", frames: 116, el: <ForecastShot /> },
  {
    id: "explore", frames: 62, then: "from-bottom",
    el: (
      <TitleCard blocks={[{ lines: ["Find water", "worth fishing."], at: 2 }]}>
        <MapPins />
      </TitleCard>
    ),
  },
  { id: "map", frames: 94, el: <ExploreShot /> },
  {
    id: "streak", frames: 62, then: "from-right",
    el: (
      <TitleCard blocks={[{ lines: ["Keep your", "streak alive."], at: 2 }]}>
        <Flame />
      </TitleCard>
    ),
  },
  { id: "streak-moment", frames: 86, el: <StreakShot /> },
  { id: "end", frames: 62, el: <EndCard /> },
];

export type Props = { beats?: number[] };

/** Each scene's length. A scene ends where the next takes over (the cut, or
 * the middle of the push); with beats, that moment moves to the nearest beat
 * when it is a few frames away, and the end card gives back any overrun. */
export const timeline = (beats: number[] = []): number[] => {
  const hits = beats.map((t) => t * FPS);
  let start = 0;
  const frames = SCENES.map((s, i) => {
    let n = s.frames;
    const handover = start + n - (s.then ? PUSH / 2 : 0);
    if (i < SCENES.length - 1 && hits.length) {
      const beat = hits.reduce((a, b) => (Math.abs(b - handover) < Math.abs(a - handover) ? b : a));
      const shift = Math.round(beat - handover);
      if (shift >= -7 && shift <= 8) n += shift;
    }
    start += n - (s.then ? PUSH : 0);
    return n;
  });
  frames[frames.length - 1] = Math.max(52, frames[frames.length - 1] - Math.max(0, start - MAX));
  return frames;
};

export const duration = (beats?: number[]) =>
  timeline(beats).reduce((n, f, i) => n + f - (SCENES[i].then ? PUSH : 0), 0);

/** Where each scene starts in the finished video. */
export const starts = (beats?: number[]) => {
  let at = 0;
  return timeline(beats).map((f, i) => {
    const start = at;
    at += f - (SCENES[i].then ? PUSH : 0);
    return { id: SCENES[i].id, start };
  });
};

export const Preview: React.FC<Props> = ({ beats }) => {
  const frames = timeline(beats);
  return (
  <TransitionSeries>
    {SCENES.flatMap((s, i) => [
      <TransitionSeries.Sequence key={s.id} durationInFrames={frames[i]}>{s.el}</TransitionSeries.Sequence>,
      ...(s.then
        ? [<TransitionSeries.Transition key={`${s.id}-push`} presentation={slide({ direction: s.then })}
            timing={linearTiming({ durationInFrames: PUSH, easing: Easing.bezier(0.6, 0, 0.1, 1) })} />]
        : []),
    ])}
  </TransitionSeries>
  );
};
