// Speaks the preview's Japanese narration with ElevenLabs:
// output/preview/narration/ja/line-<n>.mp3. The key is ELEVENLABS_API_KEY in the
// environment or in .env at the top of this repository (ignored by git). Clips are
// cached in .cache/ by their settings, so a rerun only asks for lines that changed.
// Kaketa's script, for one language.
//
//   npm run narrate

import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { preview } from "../config.mjs";

const here = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const root = resolve(here, "..");
const cache = join(here, ".cache");
const locale = "ja";
const voice = preview.voice[locale];
const output = join(here, "output/preview/narration", locale);

function apiKey() {
  if (process.env.ELEVENLABS_API_KEY) return process.env.ELEVENLABS_API_KEY;
  const file = join(root, ".env");
  if (existsSync(file)) {
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const [name, ...value] = line.split("=");
      if (name.trim() === "ELEVENLABS_API_KEY") return value.join("=").trim().replace(/^["']|["']$/g, "");
    }
  }
  throw new Error("Set ELEVENLABS_API_KEY in the environment or in .env to speak the preview.");
}

async function speech(text) {
  mkdirSync(cache, { recursive: true });
  const key = [voice.model, voice.id, voice.stability, voice.similarity, voice.seed, text].join("|");
  const clip = join(cache, createHash("sha256").update(key).digest("hex") + ".mp3");
  if (existsSync(clip)) return clip;
  const response = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice.id}?output_format=mp3_44100_128`, {
    method: "POST",
    headers: { "xi-api-key": apiKey(), "Content-Type": "application/json" },
    body: JSON.stringify({
      text,
      model_id: voice.model,
      language_code: locale,
      seed: voice.seed,
      voice_settings: { stability: voice.stability, similarity_boost: voice.similarity },
    }),
  });
  if (!response.ok) throw new Error(`ElevenLabs refused: ${(await response.text()).slice(0, 300)}`);
  writeFileSync(clip, Buffer.from(await response.arrayBuffer()));
  return clip;
}

// How long the voice takes, without the quiet ElevenLabs leaves at the end of a clip.
export function seconds(file) {
  const length = Number(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file]).toString());
  const log = spawnSync("ffmpeg", ["-hide_banner", "-i", file, "-af", "silencedetect=noise=-45dB:d=0.1", "-f", "null", "-"]).stderr.toString();
  const starts = [...log.matchAll(/silence_start: ([\d.]+)/g)].map((match) => Number(match[1]));
  const ends = [...log.matchAll(/silence_end: ([\d.]+)/g)].map((match) => Number(match[1]));
  const trailing = starts.length > ends.length || (ends.at(-1) ?? 0) >= length - 0.05;
  return trailing && starts.length > 0 ? starts.at(-1) : length;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  mkdirSync(output, { recursive: true });
  for (const [index, scene] of preview.scenes.entries()) {
    const clip = await speech(scene.narration[locale].replaceAll("Umete", voice.spokenName));
    const target = join(output, `line-${index + 1}.mp3`);
    copyFileSync(clip, target);
    console.log(`line ${index + 1}: ${seconds(clip).toFixed(1)} s`);
  }
}
