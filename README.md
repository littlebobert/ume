# Ume (埋め)

Ume is a private form filler for Safari on iPhone, iPad, and Mac. Complete a form once, choose **Remember my answers**, then use **Fill this form** on similar forms later.

*Ume* (埋め) means “fill it in” in Japanese—a compact command based on *umeru* (埋める), “to fill in.”

## How it works

- Remembers completed text fields, text areas, selects, checkboxes, and radio buttons.
- Matches fields locally using `autocomplete` hints, names, labels, and placeholders.
- Rejects ambiguous matches and never submits a form.
- Skips passwords, files, hidden fields, and common payment, token, secret, and SSN fields.
- Supports JavaScript-controlled forms through native value setters and input events.

Saved answers are AES-GCM encrypted in a shared app container. The device-only encryption key and AI credentials are stored in Apple Keychain. The Ume app lets you inspect saved answers or delete everything.

## Optional AI matching

Local matching always runs first. If unmatched fields remain and an AI provider is configured, Ume sends OpenAI or Anthropic only sanitized field schemas: labels, names, types, placeholders, autocomplete hints, and select-option labels. Answer values and current form values never leave the device.

The provider returns opaque field-to-field mappings, not values. Ume validates those mappings, joins them to saved values locally, and fills the fields. OpenAI requests set `store: false`; provider retention and processing policies still apply.

Configure the provider, model, and API key in the Ume app.

## Run from Xcode

Open `Safari/Ume/Ume.xcodeproj` and choose your Apple Developer team for the app and extension targets.

### iPhone or iPad

1. Select the **Ume (iOS)** scheme and your device, then run.
2. Enable Ume under **Settings → Apps → Safari → Extensions**.
3. Grant website access where needed.

### Mac

1. Select the **Ume (macOS)** scheme and run.
2. Enable Ume under **Safari → Settings → Extensions**.

On a form, open Ume from Safari and choose **Remember my answers** or **Fill this form**.

## Development

Requires Node.js 20 or newer. The extension has no package dependencies.

```bash
npm test
npm run check
```

The Xcode targets reference `Extension/` directly, so changes there are included in the next build.

### Test form

```bash
npm run test-form
```

Open [http://localhost:8000](http://localhost:8000) in Safari. The fixture includes similar and substantially different versions of a fictional patient-intake form.

## Privacy notes

Ume collects no analytics. It reads eligible controls only when you ask it to remember or fill a form, and it does not inspect unrelated page text. Website access is required to read and populate form controls.

Saved answers may contain sensitive information. Encryption protects data at rest, but Ume does not yet require Face ID or Touch ID. Anyone with access to the unlocked device and Ume app may be able to view saved answers; do not use it on a shared device.

## Roadmap

- Review proposed matches before filling
- Named profiles and per-answer editing
- Better multi-step and cross-origin-frame support
- Optional biometric lock
- App Store artwork and distribution

## License

MIT
