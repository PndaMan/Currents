import React from "react";
import { type CalculateMetadataFunction, Composition, staticFile } from "remotion";
import { loadFont } from "@remotion/fonts";
import { H, W } from "./kit";
import { duration, Preview, type Props } from "./Preview";
import { FONT } from "./TitleCard";

for (const [weight, file] of [["700", "Bold"], ["800", "ExtraBold"]]) {
  loadFont({ family: FONT, url: staticFile(`fonts/InterDisplay-${file}.ttf`), weight });
}

// The music's beats come in as props (render.ts passes them) and set the length.
const metadata: CalculateMetadataFunction<Props> = ({ props }) => ({ durationInFrames: duration(props.beats) });

export const Root: React.FC = () => (
  <Composition id="Preview" component={Preview} durationInFrames={duration()} fps={30} width={W} height={H}
    defaultProps={{ beats: [] } as Props} calculateMetadata={metadata} />
);
