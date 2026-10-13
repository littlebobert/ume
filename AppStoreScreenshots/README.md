# App Store screenshots

Umete's three iPhone screenshots (English and Japanese, 6.9- and 6.3-inch), the product page header, and the search results card. `config.mjs` holds the copy and layout; `scripts/render.mjs` draws them with Playwright from Simulator captures. Captures and renders aren't kept in git.

```bash
npm install
npm run render
```

Output goes to `output/`: `<locale>-6.9/` and `<locale>-6.3/` for the iPhone screenshots, `<locale>-ipad-13/` for the 13-inch iPad ones (2064×2752, from `captures/ipad-*.png` taken the same way on the iPad Pro 13-inch Simulator), `header/<locale>/` (5244×2950 and 3840×1646; "Fill it in." in English, 埋めて in Japanese), and `search/<locale>/3840x2560.png`. The bezel is Apple's iPhone 18 Pro Max from Apple Design Resources, which can't be redistributed; the default is Karui's local copy, or set `BEZEL=<png>`.

## Taking the captures

All on the **iPhone 18 Pro Max** Simulator, whose 1320×2868 screen fills the bezel's opening. Use made-up data only: the debug seed below, never real answers.

1. Build and install the **Ume (iOS)** scheme in Debug, then set the look:
   ```bash
   xcrun simctl ui booted appearance light
   xcrun simctl status_bar booted override --time 9:41 --batteryState discharging --batteryLevel 100 --wifiBars 3 --cellularBars 4
   xcrun simctl launch booted com.justin.henry.ume.ios -umete-screenshot-demo
   ```
   `-umete-screenshot-demo` (Debug builds only; `ScreenshotDemo` in `iOS (App)/AppDelegate.swift`) replaces the saved answers with Hanako Yamada's, skips onboarding, and turns iCloud sync off.
2. In the app, open **Saved Data**, tap an empty area so no tab is highlighted, and capture `captures/saved-data.png`. Do the same on **Privacy** for `captures/privacy.png`:
   ```bash
   xcrun simctl io booted screenshot captures/saved-data.png
   ```
3. Serve the demo booking page and open it from the Home Screen, so Safari shows no "◀ Umete" back link:
   ```bash
   python3 -m http.server 8123 --bind 127.0.0.1 --directory demo-form
   xcrun simctl openurl booted http://travel.localhost:8123/
   ```
   Turn Umete on once through Safari's page menu → Manage Extensions.
4. Open Umete from the page menu and tap **Fill this form**. It should fill all 9 fields on the device, without AI matching. Capture `captures/fill-sheet.png` with the sheet open, then close the sheet and capture `captures/filled-form.png` (used by the search card).

## App Preview

`output/preview/<locale>.mp4`, 886×1920 at 30 fps with stereo AAC, for the 6.9-inch iPhone slot. It has three scenes, one per screenshot, each a Simulator recording under its headline, with a voice-over:

```bash
npm run narrate   # Japanese voice-over from ElevenLabs (ELEVENLABS_API_KEY in ../.env)
npm run preview   # assembles both languages
```

- **Japanese** is spoken by ElevenLabs with the voice in `config.mjs`. Clips are cached in `.cache/`, so only changed lines are requested again.
- **English** is recorded by hand: put `voiceover/en-US/line-1.m4a`, `line-2.m4a` and `line-3.m4a` here (mp3, wav or aiff work too), one file per scene, and run `npm run preview` again. Each scene stretches to fit its line. Until the files exist, the English preview is silent and timed like the Japanese one.
- **Recordings:** with the Simulator set up as above, record each scene to `captures/scene-<n>-*.mp4` while doing it:
  ```bash
  xcrun simctl io booted recordVideo --codec h264 --force captures/scene-1-fill.mp4
  ```
  Stop with Ctrl-C. The recorder only writes frames when the screen changes, so a still ending is held automatically.
- **Trimming:** a scene's `keep` in `config.mjs` lists the stretches of its recording to use, in seconds, so pauses while recording can be cut without recording again.
