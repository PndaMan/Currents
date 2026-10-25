import React from "react";
import { Composition, staticFile } from "remotion";
import { loadFont } from "@remotion/fonts";
import { H, W } from "./kit";
import { DURATION, Preview } from "./Preview";
import { FONT } from "./TitleCard";

for (const [weight, file] of [["700", "Bold"], ["800", "ExtraBold"]]) {
  loadFont({ family: FONT, url: staticFile(`fonts/InterDisplay-${file}.ttf`), weight });
}

export const Root: React.FC = () => (
  <Composition id="Preview" component={Preview} durationInFrames={DURATION} fps={30} width={W} height={H} />
);
