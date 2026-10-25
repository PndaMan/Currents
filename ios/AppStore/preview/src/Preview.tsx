// The App Store preview: title cards that act out a line, each followed by
// the app doing it. 886x1920 at 30 fps, under Apple's 30 second limit.

import React from "react";
import { Easing } from "remotion";
import { linearTiming, TransitionSeries } from "@remotion/transitions";
import { slide } from "@remotion/transitions/slide";
import { Bobber, Calendar, Camera, EndCard, Flame, MapPins } from "./art";
import { AddFlowShot, ExploreShot, ForecastShot, StreakShot, TodayShot } from "./shots";
import { TitleCard } from "./TitleCard";

type Push = "from-right" | "from-bottom";
type Scene = { id: string; frames: number; el: React.ReactNode; then?: Push };

const PUSH = 10;

export const SCENES: Scene[] = [
  {
    id: "bite", frames: 76, then: "from-right",
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
  { id: "end", frames: 72, el: <EndCard /> },
];

/** Where each scene starts in the finished video. */
export const starts = () => {
  let at = 0;
  return SCENES.map((s) => {
    const start = at;
    at += s.frames - (s.then ? PUSH : 0);
    return { id: s.id, start };
  });
};

export const DURATION = SCENES.reduce((n, s) => n + s.frames - (s.then ? PUSH : 0), 0);

export const Preview: React.FC = () => (
  <TransitionSeries>
    {SCENES.flatMap((s) => [
      <TransitionSeries.Sequence key={s.id} durationInFrames={s.frames}>{s.el}</TransitionSeries.Sequence>,
      ...(s.then
        ? [<TransitionSeries.Transition key={`${s.id}-push`} presentation={slide({ direction: s.then })}
            timing={linearTiming({ durationInFrames: PUSH, easing: Easing.bezier(0.6, 0, 0.1, 1) })} />]
        : []),
    ])}
  </TransitionSeries>
);
