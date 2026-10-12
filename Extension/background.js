// Background script. Its only job is the optional toolbar badge: when the user
// has turned on form detection, it receives field descriptions from detect.js,
// matches them against saved answers locally, and badges the icon for that tab.
(function () {
  "use strict";
  const api = browser;
  const SETTING_KEY = "ume-form-badge";
  const SCRIPT_ID = "ume-detect";
  const ANSWER_CACHE_MS = 60_000;
  const BADGE_COLOR = "#c2410c";
  let answerCache = { at: 0, answers: [] };

  const nativeAppIdentifier = api.runtime.getPlatformInfo().then(({ os }) =>
    os === "ios" ? "com.justin.henry.ume.ios" : "com.justin.henry.ume"
  );

  async function isEnabled() {
    const stored = await api.storage.local.get(SETTING_KEY);
    return Boolean(stored[SETTING_KEY]);
  }

  async function savedAnswers() {
    if (Date.now() - answerCache.at < ANSWER_CACHE_MS) return answerCache.answers;
    let answers = [];
    try {
      const result = await api.runtime.sendNativeMessage(await nativeAppIdentifier, { type: "UME_GET_ANSWERS" });
      answers = result?.answers || [];
    } catch (_error) {
      // The app may be unavailable; treat it as having no saved answers for now.
    }
    answerCache = { at: Date.now(), answers };
    return answers;
  }

  function matchCount(answers, fields) {
    let count = 0;
    for (const field of fields) {
      if (UmeMatcher.bestMatch(answers, field)) count += 1;
    }
    return count;
  }

  async function setBadge(tabId, text, title) {
    await api.action.setBadgeText({ tabId, text });
    if (text) await api.action.setBadgeBackgroundColor({ tabId, color: BADGE_COLOR }).catch(() => {});
    await api.action.setTitle({ tabId, title }).catch(() => {});
  }

  async function clearBadge(tabId) {
    await setBadge(tabId, "", "Umete");
  }

  async function handleFields(tabId, fields) {
    if (!(await isEnabled())) return;
    const answers = await savedAnswers();
    const count = answers.length ? matchCount(answers, fields) : 0;
    if (count) {
      await setBadge(tabId, String(count), `Umete can fill ${count} field${count === 1 ? "" : "s"} on this page`);
    } else if (fields.length >= 3) {
      await setBadge(tabId, "•", "This page has a form. Fill it once, then ask Umete to remember it.");
    } else {
      await clearBadge(tabId);
    }
  }

  async function clearAllBadges() {
    const tabs = await api.tabs.query({});
    await Promise.all(tabs.map((tab) => clearBadge(tab.id).catch(() => {})));
  }

  async function syncRegistration() {
    if (!api.scripting?.registerContentScripts) return;
    const enabled = await isEnabled();
    const registered = await api.scripting.getRegisteredContentScripts({ ids: [SCRIPT_ID] }).catch(() => []);
    if (enabled && !registered.length) {
      await api.scripting.registerContentScripts([{
        id: SCRIPT_ID,
        js: ["detect.js"],
        matches: ["<all_urls>"],
        runAt: "document_idle",
        persistAcrossSessions: true
      }]).catch(() => {});
    } else if (!enabled && registered.length) {
      await api.scripting.unregisterContentScripts({ ids: [SCRIPT_ID] }).catch(() => {});
    }
  }

  api.runtime.onMessage.addListener((message, sender) => {
    if (message?.type === "UME_PAGE_FIELDS" && sender?.tab?.id != null) {
      handleFields(sender.tab.id, Array.isArray(message.fields) ? message.fields : []).catch(() => {});
    } else if (message?.type === "UME_ANSWERS_CHANGED") {
      answerCache.at = 0;
    }
    return false;
  });

  api.tabs.onUpdated.addListener((tabId, info) => {
    if (info.status === "loading") clearBadge(tabId).catch(() => {});
  });

  api.storage.onChanged.addListener((changes, area) => {
    if (area !== "local" || !(SETTING_KEY in changes)) return;
    answerCache.at = 0;
    if (!changes[SETTING_KEY].newValue) clearAllBadges().catch(() => {});
    syncRegistration().catch(() => {});
  });

  syncRegistration().catch(() => {});
})();
