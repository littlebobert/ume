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

Local matching always runs first. You can optionally connect OpenAI or Anthropic to match fields Umete does not recognize.

Only sanitized field descriptions are sent to the provider. Saved answers and values currently entered in the form never leave your device. Returned mappings are validated and applied locally.

## Using Umete

Enable Umete in Safari’s extension settings and grant website access where needed. On a form, open Umete from Safari and choose **Remember my answers** or **Fill this form**.

Requires iOS or iPadOS 15 or newer, or macOS 12 or newer.

## License

MIT
