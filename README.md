# Ume (埋め)

<img src="Extension/icons/icon-256.png" alt="Ume app icon" width="128">

**Autofill everything, securely.**

Ume is a private Safari form filler for iPhone, iPad, and Mac. Complete a form once, choose **Remember my answers**, then use **Fill this form** on similar forms later.

*Ume* (埋め) means “fill it in” in Japanese.

## What it does

- Fills text fields, text areas, selects, checkboxes, and radio buttons.
- Matches fields locally using labels, names, placeholders, and `autocomplete` hints.
- Skips ambiguous and sensitive fields, including passwords and payment details.
- Never submits a form.
- Checks for signed macOS updates automatically with Sparkle.

## Privacy

Saved answers are encrypted with AES-GCM. The device-only encryption key is stored in Apple Keychain. Ume collects no analytics and reads form controls only when you ask it to remember or fill a form.

Anyone with access to your unlocked device and the Ume app may be able to view saved answers. Avoid using Ume on a shared device.

## Optional AI matching

Local matching always runs first. You can optionally connect OpenAI or Anthropic to match fields Ume does not recognize.

Only sanitized field descriptions are sent to the provider. Saved answers and values currently entered in the form never leave your device. Returned mappings are validated and applied locally.

## Using Ume

Enable Ume in Safari’s extension settings and grant website access where needed. On a form, open Ume from Safari and choose **Remember my answers** or **Fill this form**.

Requires iOS or iPadOS 15 or newer, or macOS 12 or newer.

## License

MIT
