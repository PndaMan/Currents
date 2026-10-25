import { Config } from "@remotion/cli/config";

// Frames as PNG and a near-lossless master; render.ts makes the store file.
Config.setVideoImageFormat("png");
Config.setCodec("h264");
Config.setCrf(10);
Config.setPixelFormat("yuv420p");
Config.setEntryPoint("src/index.ts");
