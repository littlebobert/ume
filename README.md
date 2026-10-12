# Umete (埋めて)

<img src="Extension/icons/icon-256.png" alt="Umete app icon" width="128">

**Autofill everything, securely.**

Umete is a private Safari form filler for iPhone, iPad, and Mac. Complete a form once, choose **Remember my answers**, then use **Fill this form** on similar forms later.

*Umete* (埋めて) is Japanese for “fill it in,” the thing you say to a form.

## What it does

- Fills text fields, text areas, selects, checkboxes, and radio buttons.
- Stores structured addresses and contacts, such as doctors and emergency contacts, and fills each part into the matching fields.
- Matches fields locally using labels, names, placeholders, and `autocomplete` hints.
- Skips ambiguous and sensitive fields, including passwords and payment details.
- Never submits a form.
- Checks for signed macOS updates automatically with Sparkle.

## Privacy

Saved answers are encrypted with AES-GCM. The encryption key is stored in your iCloud Keychain so that your own devices can share it, and Apple never sees it. Umete collects no analytics and reads form controls only when you ask it to remember or fill a form.

Saved answers sync between your Mac, iPhone, and iPad through your iCloud account. Each answer is stored in your private CloudKit database already encrypted, so Apple cannot read it. You can turn sync off in Settings → General, after which answers stay on each device.

Optionally, you can turn on a toolbar badge from the extension popup. Umete then checks each page you open for forms it can fill and shows the count on its icon. This check runs entirely on your device, reads field labels but never field values, and requires granting Umete access to all websites in Safari. It is off by default.

Anyone with access to your unlocked device and the Umete app may be able to view saved answers. Avoid using Umete on a shared device.

## Optional AI matching

Local matching always runs first. For fields it does not recognize, Umete can ask an AI which saved answer fits.

By default this uses **Umete (free)**, which needs no API key and has a daily limit. Requests go to Umete's small server at `api.umete.jp`, which forwards them to OpenAI's Decisions API. The server never logs or stores request content; it keeps only a daily request count keyed by a salted hash of a random per-install ID and of your IP address, and deletes those counts after three days. You can instead connect your own OpenAI or Anthropic key for unlimited use.

The "OpenAI Decisions (your key)" option calls the same API directly with your own OpenAI key. It asks one multiple-choice question per unmatched field, applies a match only when the model is confident, and costs a fraction of a cent per form because only input tokens are billed.

Only sanitized field descriptions are sent, whichever option you choose. Saved answers and values currently entered in the form never leave your device. Returned mappings are validated and applied locally.

## Using Umete

Enable Umete in Safari’s extension settings and grant website access where needed. On a form, open Umete from Safari and choose **Remember my answers** or **Fill this form**.

Requires iOS or iPadOS 15 or newer, or macOS 12 or newer.

## License

MIT
