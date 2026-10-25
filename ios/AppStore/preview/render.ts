// Renders the App Store preview: gathers the captures into public/, renders
// the composition, then encodes it the way App Store Connect takes it:
// 886x1920 at 30 fps, H.264 High, stereo AAC (a silent track unless --music).
//
//     bun render.ts [--stills DIR] [--footage DIR] [--out FILE] [--music FILE]

import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { parseArgs } from "node:util";

const here = import.meta.dir;
const root = resolve(here, "../../..");
const { values: args } = parseArgs({
  options: {
    stills: { type: "string", default: `${root}/ios/build/store-stills` },
    footage: { type: "string", default: `${root}/ios/build/preview-footage` },
    out: { type: "string", default: `${root}/ios/build/appstore-media/preview.mp4` },
    music: { type: "string" },
  },
});

const run = (cmd: string[]): string => {
  const p = Bun.spawnSync(cmd, { cwd: here, stdout: "pipe", stderr: "inherit" });
  if (p.exitCode !== 0) throw new Error(`${cmd.slice(0, 3).join(" ")} exited with ${p.exitCode}`);
  return p.stdout.toString();
};

process.stdout.write(run(["uv", "run", "prepare.py", "--stills", resolve(args.stills!), "--footage", resolve(args.footage!)]));
run(["bunx", "remotion", "render", "Preview", "out/master.mp4", "--log=error"]);

const seconds = Number(run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", "out/master.mp4"]));
if (!(seconds >= 15 && seconds <= 30)) throw new Error(`App Store previews run 15 to 30 seconds, this is ${seconds}`);

const out = resolve(args.out!);
mkdirSync(dirname(out), { recursive: true });
const audio = args.music
  ? ["-i", resolve(args.music), "-af", `afade=t=out:st=${(seconds - 1.2).toFixed(2)}:d=1.2`]
  : ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"];
run([
  "ffmpeg", "-v", "error", "-y", "-i", "out/master.mp4", ...audio,
  "-map", "0:v", "-map", "1:a", "-t", seconds.toFixed(3),
  "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p",
  "-preset", "slow", "-b:v", "11M", "-maxrate", "12M", "-bufsize", "16M", "-r", "30",
  "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
  "-movflags", "+faststart", out,
]);
console.log(`${out}: ${seconds.toFixed(2)}s`);
