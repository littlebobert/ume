# App Store metadata

`.github/workflows/app-store-metadata.yml` keeps Umete's iOS App Store listing (`com.justin.henry.ume.ios`) in the repository and syncs it to App Store Connect with `ci/publish_store_metadata.py`. It uses the same App Store Connect API key as the release workflow: the `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, and `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` secrets in the `release` environment. The Mac app is distributed outside the App Store, so it has no listing here.

## Files

One folder per language, named with its App Store Connect locale, with one text file per field:

```
AppStoreMetadata/
  en-US/  ja/
    name.txt                 30 characters   App information
    subtitle.txt             30 characters   App information
    privacy_policy_url.txt                   App information
    description.txt          4,000 characters
    keywords.txt             100 characters; commas, no spaces after them
    promotional_text.txt     170 characters
    whats_new.txt            4,000 characters
    support_url.txt
    marketing_url.txt
```

A field without a file is left alone, so a language can set only what differs. A language without a folder isn't touched; on the App Store it falls back to English (U.S.).

## First time: pull the current listing

Run **Actions → App Store metadata → Run workflow** with mode **pull**. It commits the listing as it is today, for the newest version, to a new branch and opens a pull request; merge it. Pull again any time the listing was edited in App Store Connect, so the files don't overwrite those edits on the next push.

Opening the pull request needs **Settings → Actions → General → Workflow permissions → Allow GitHub Actions to create and approve pull requests**.

## Updating the listing for a release

1. Create the next version in App Store Connect (the `+` next to iOS App), so there is a version being prepared.
2. Edit the files, commit, and open a pull request. The workflow checks lengths and URLs on every pull request that changes them.
3. After merging, run the workflow with mode **push** and **dry run** checked. The run's summary lists each change.
4. Run it again with **dry run** unchecked to apply them.

From a terminal:

```bash
gh workflow run app-store-metadata.yml -f mode=push -f dry_run=true
gh workflow run app-store-metadata.yml -f mode=push -f dry_run=false
```

`whats_new.txt` is the App Store's What's New text, separate from the `changelog_en` note the release workflow sends to TestFlight and umete.jp; update it for each App Store version. App Store Connect won't take What's New for an app's first version, so the script skips it then.

To add a language, create its folder; it is created in App Store Connect on the first push.

## What it can't do

- Only versions being prepared or rejected can change. A version in review or live is refused; create the next version first.
- The name and subtitle go live with the next version you submit.
- Screenshots and the app preview video aren't included; upload those in App Store Connect.
- It doesn't submit the version for review.
