const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

const project = fs.readFileSync("Safari/Ume/Ume.xcodeproj/project.pbxproj", "utf8");
const appDelegate = fs.readFileSync("Safari/Ume/macOS (App)/AppDelegate.swift", "utf8");
const info = fs.readFileSync("Safari/Ume/macOS (App)/Info.plist", "utf8");
const entitlements = fs.readFileSync("Safari/Ume/macOS (App)/Ume.entitlements", "utf8");
const releaseWorkflow = fs.readFileSync(".github/workflows/release.yml", "utf8");

test("pins Sparkle 2.9.5 on the macOS app target", () => {
  assert.match(project, /repositoryURL = "https:\/\/github\.com\/sparkle-project\/Sparkle";/);
  assert.match(project, /kind = exactVersion;\s+version = 2\.9\.5;/);
  assert.match(project, /A20000010000000000000001 \/\* Sparkle in Frameworks \*\//);
  assert.match(project, /A20000030000000000000001 \/\* Sparkle \*\//);
});

test("configures a signed automatic update feed", () => {
  assert.match(info, /<key>SUFeedURL<\/key>\s*<string>https:\/\/littlebobert\.github\.io\/ume-appcast\.xml<\/string>/);
  assert.match(info, /<key>SUPublicEDKey<\/key>\s*<string>Gjz4eaBW734cY7idF99PyqOWtycJBF4i8wSAUXg2p\+0=<\/string>/);
  for (const key of ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUEnableAutomaticChecks", "SUAllowsAutomaticUpdates", "SUAutomaticallyUpdate", "SUEnableInstallerLauncherService"]) {
    assert.match(info, new RegExp(`<key>${key}<\\/key>\\s*<true\\/>`));
  }
  assert.doesNotMatch(info, /SUEnableDownloaderService/);
});

test("starts Sparkle and exposes Check for Updates", () => {
  assert.match(appDelegate, /import Sparkle/);
  assert.match(appDelegate, /SPUStandardUpdaterController\(\s*startingUpdater: true/);
  assert.match(appDelegate, /Check for Updates…/);
  assert.match(appDelegate, /updaterController\.checkForUpdates\(sender\)/);
});

test("links Sparkle version history to the website changelog", () => {
  assert.match(releaseWorkflow, /--full-release-notes-url https:\/\/littlebobert\.github\.io\/ume\.html#changelog/);
});

test("grants only Sparkle's required sandbox Mach lookup exceptions", () => {
  assert.match(entitlements, /com\.apple\.security\.temporary-exception\.mach-lookup\.global-name/);
  assert.match(entitlements, /\$\(PRODUCT_BUNDLE_IDENTIFIER\)-spks/);
  assert.match(entitlements, /\$\(PRODUCT_BUNDLE_IDENTIFIER\)-spki/);
});
