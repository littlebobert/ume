// Umete's App Store screenshots, product page header, and search results card, in
// English and Japanese, from the Simulator captures in captures/ (see README.md). The
// app's own screens are English only; the headlines are per language.

export const screenshot = Object.freeze({
  // The layout's own size, the 6.9-inch iPhone's; the 6.3-inch set is the same page
  // scaled to its pixels.
  width: 1320,
  height: 2868,
  // App Store Connect's iPhone slots: the medium display (6.1 and 6.3 inch, required)
  // and the large one (6.5 to 6.9 inch).
  sizes: Object.freeze([
    { suffix: "6.3", width: 1206, height: 2622 },
    { suffix: "6.9", width: 1320, height: 2868 },
  ]),
  // The landing page's paper and dark green.
  background: "#f5f1e9",
  ink: "#28251f",
  accent: "#3f4d28",
  // The phone, drawn 1029 wide, centered, its bottom this far above the page's.
  device: Object.freeze({ width: 1029, bottom: 120 }),
});

// Apple's iPhone 18 Pro Max bezel (Apple Design Resources, Product Bezels), which can't
// be redistributed, so it isn't in git: Karui's copy by default, or BEZEL=<png>. The
// numbers are the PNG's size and its screen opening, which a 1320 × 2868 capture fills.
export const bezel = Object.freeze({
  file: process.env.BEZEL || "../../karui/AppStoreScreenshots/assets/bezels/iphone-18-pro-max-silver.png",
  width: 1470,
  height: 3000,
  screen: Object.freeze({ x: 75, y: 66, width: 1320, height: 2868, radius: 190 }),
});

export const locales = Object.freeze(["en-US", "ja"]);

// In App Store order. A <br> places a line break where the headline would wrap badly.
export const slides = Object.freeze([
  {
    id: "fill",
    capture: "captures/fill-sheet.png",
    hero: { "en-US": "Fill a whole form<br>with one tap.", ja: "フォームをまるごと、<br>ワンタップで。" },
  },
  {
    id: "remembers",
    capture: "captures/saved-data.png",
    hero: { "en-US": "Remembers addresses,<br>doctors, and more.", ja: "住所も、かかりつけ医も、<br>覚えておく。" },
  },
  {
    id: "private",
    capture: "captures/privacy.png",
    hero: { "en-US": "Your answers<br>never go to AI.", ja: "回答は、<br>AIに送りません。" },
  },
]);

// The product page header, App Store Connect's wide image above the listing, in both
// sizes it takes: the name's meaning in the green, centered over faint empty form
// fields, and nothing else, like Kaketa's 書けた, since the store crops the edges and
// draws the name and icon beneath it. 埋めて in Japanese; its translation in English.
export const header = Object.freeze({
  text: { "en-US": "Fill it in.", ja: "埋めて" },
  sizes: Object.freeze([
    { file: "5244x2950.png", width: 5244, height: 2950 },
    { file: "3840x1646.png", width: 3840, height: 1646 },
  ]),
});

// The search results card, the 3:2 image the Search tab shows under the app's row in
// place of the screenshots. It states the purpose: the headline on the left, the
// filled form on a phone to the right, running off the bottom edge.
export const search = Object.freeze({
  file: "3840x2560.png",
  width: 3840,
  height: 2560,
  capture: "captures/filled-form.png",
  // Short lines, big, since the card is shown about 280 points wide in the list.
  hero: { "en-US": "Fill any form<br>in Safari<br>with one tap.", ja: "Safariの<br>フォームを、<br>ワンタップで<br>埋める。" },
  device: Object.freeze({ width: 1520, top: 280 }),
});

// The App Preview: three Simulator recordings (captures/scene-<n>-*.mp4, see
// README.md), each under its screenshot's headline, with a voice-over per scene.
// 886 × 1920 at 30 fps, as App Store Connect takes for 6.9-inch iPhones.
export const preview = Object.freeze({
  width: 886,
  height: 1920,
  fps: 30,
  // Each scene lasts its recording or its line plus this tail, whichever is longer.
  tail: 0.8,
  crossfade: 0.4,
  scenes: Object.freeze([
    {
      clip: "captures/scene-1-fill.mp4",
      // The stretches of the recording to use, in seconds: up to the sheet settling,
      // then from just before the tap on Fill, cutting the wait between.
      keep: [[0, 6.0], [14.2, 17.7]],
      // Long enough to show the whole fill, even if the line is shorter.
      minimum: 9.5,
      caption: { "en-US": "Fill a whole form with one tap.", ja: "フォームをまるごと、<br>ワンタップで。" },
      narration: {
        "en-US": "Umete fills in web forms for you. Open it in Safari, tap Fill this form, and your answers go right where they belong.",
        ja: "Umeteは、Webフォームを代わりに埋めてくれます。Safariで開いて「このフォームに入力」をタップするだけ。答えが、それぞれの欄に入ります。",
      },
    },
    {
      clip: "captures/scene-2-saved.mp4",
      minimum: 6.5,
      caption: { "en-US": "Remembers addresses, doctors, and more.", ja: "住所も、かかりつけ医も、<br>覚えておく。" },
      narration: {
        "en-US": "It remembers your address, your doctors, even your passport number.",
        ja: "住所も、かかりつけ医も、パスポート番号も覚えておきます。",
      },
    },
    {
      clip: "captures/scene-3-privacy.mp4",
      caption: { "en-US": "Your answers never go to AI.", ja: "回答は、AIに送りません。" },
      narration: {
        "en-US": "Your answers stay encrypted, and they never go to AI. Umete: fill it in.",
        ja: "回答は暗号化されたまま。AIに送ることはありません。Umete、埋めて。",
      },
    },
  ]),
  // Japanese is spoken by ElevenLabs (scripts/narrate.mjs). English is recorded by
  // hand: voiceover/en-US/line-<n>.(m4a|mp3|wav), one file per scene.
  voice: Object.freeze({
    ja: Object.freeze({
      id: "gHBfNp2PWSyFgpPlzCOd",
      model: "eleven_multilingual_v2",
      stability: 0.75,
      similarity: 0.75,
      seed: 7,
      // How to spell the name for the voice, so it isn't read as English.
      spokenName: "ウメテ",
    }),
  }),
});
