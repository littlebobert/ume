(() => {
  "use strict";

  const api = browser;
  const learnButton = document.getElementById("learn");
  const fillButton = document.getElementById("fill");
  const status = document.getElementById("status");
  const activity = document.getElementById("activity");
  const activityLabel = document.getElementById("activity-label");
  const getStarted = document.getElementById("get-started");
  const readyContent = document.getElementById("ready-content");
  const openAppButton = document.getElementById("open-app");
  const openSettingsButton = document.getElementById("open-settings");
  const openDebugLogButton = document.getElementById("open-debug-log");
  const closeDebugLogButton = document.getElementById("close-debug-log");
  const deleteDebugLogButton = document.getElementById("delete-debug-log");
  const copyDebugLogButton = document.getElementById("copy-debug-log");
  const emailDebugLogButton = document.getElementById("email-debug-log");
  const debugLogPanel = document.getElementById("debug-log-panel");
  const debugLogText = document.getElementById("debug-log-text");
  const DEBUG_LOG_KEY = "ume-extension-debug-log";
  const DEBUG_LOG_LIMIT = 64_000;
  const CONTENT_SCRIPT_FILES = ["lib/matcher.js", "lib/dom.js", "lib/date.js", "lib/phone.js", "content.js"];
  const AI_SCHEMA_KEYS = [
    "accessibleDescription", "accessibleName", "answerType", "autocomplete", "form", "group",
    "groupName", "id", "inputType", "kind", "label", "name", "options", "placeholder",
    "required", "section", "tableHeaders", "userLabel"
  ];
  let debugLoggingEnabled = false;
  let busy = false;
  let cachedAnswers = [];

  async function injectContentScript(tabId) {
    if (api.scripting?.executeScript) {
      await api.scripting.executeScript({
        target: { tabId, frameIds: [0] },
        files: CONTENT_SCRIPT_FILES
      });
      return;
    }
    if (api.tabs.executeScript) {
      for (const file of CONTENT_SCRIPT_FILES) {
        await api.tabs.executeScript(tabId, { file, frameId: 0 });
      }
      return;
    }
    throw new Error("This version of Safari does not support on-demand extension access.");
  }

  async function ensureContentScript(tabId) {
    try {
      const response = await api.tabs.sendMessage(tabId, { type: "UME_PING" }, { frameId: 0 });
      if (response?.ready) return;
    } catch (_error) {
      // The script is intentionally absent until the user invokes Umete on this tab.
    }
    await injectContentScript(tabId);
    const response = await api.tabs.sendMessage(tabId, { type: "UME_PING" }, { frameId: 0 });
    if (!response?.ready) throw new Error("Umete could not start on this page.");
  }

  async function sendMessage(tabId, message) {
    try {
      await ensureContentScript(tabId);
      return await api.tabs.sendMessage(tabId, message, { frameId: 0 });
    } catch (error) {
      throw new Error(`Umete could not communicate with this page. Reload it and try again. ${error.message || ""}`.trim());
    }
  }

  const nativeAppIdentifier = api.runtime.getPlatformInfo().then(({ os }) =>
    os === "ios" ? "com.justin.henry.ume.ios" : "com.justin.henry.ume"
  );

  async function sendNative(message) {
    return api.runtime.sendNativeMessage(await nativeAppIdentifier, message);
  }

  async function appendDebug(event, details = {}) {
    if (!debugLoggingEnabled) return;
    try {
      const stored = await api.storage.local.get(DEBUG_LOG_KEY);
      const previous = stored[DEBUG_LOG_KEY] || "";
      const entry = `[${new Date().toISOString()}] ${event}\n${JSON.stringify(details, null, 2)}\n\n`;
      await api.storage.local.set({ [DEBUG_LOG_KEY]: (previous + entry).slice(-DEBUG_LOG_LIMIT) });
    } catch (_error) {
      // Diagnostics must never interrupt filling.
    }
  }

  async function refreshDebugLog() {
    const stored = await api.storage.local.get(DEBUG_LOG_KEY);
    const existing = stored[DEBUG_LOG_KEY] || "";
    if (!debugLoggingEnabled) {
      debugLogText.value = existing
        ? `${existing}\n\nLogging is currently off. Enable it in Umete Settings → AI Provider to capture new entries.`
        : "Logging is off. Enable it in Umete Settings → AI Provider → Enable logging for bug reports, then reproduce the problem.";
      return;
    }
    debugLogText.value = existing || "No extension debug entries yet.";
  }

  // Addresses are matched locally only. Contacts are split into one sanitized
  // entry per part ("Doctor 2, Cardiologist phone") so the AI can place them
  // without seeing their labels, which are often the person's name.
  function aiSavedEntries(answers) {
    const contacts = answers.filter((answer) => UmeMatcher.answerType(answer) === "contact");
    const totals = {};
    for (const contact of contacts) {
      const category = UmeMatcher.contactCategory(contact);
      totals[category] = (totals[category] || 0) + 1;
    }
    const seen = {};
    return answers.flatMap((answer, index) => {
      const type = UmeMatcher.answerType(answer);
      if (type === "address") return [];
      if (type === "contact") {
        const category = UmeMatcher.contactCategory(answer);
        seen[category] = (seen[category] || 0) + 1;
        const number = totals[category] > 1 ? seen[category] : undefined;
        return UmeMatcher.contactParts(answer, number).map(({ part, entry }) => ({ key: `saved-${index}-${part}`, ...entry }));
      }
      return [{ key: `saved-${index}`, ...answer }];
    });
  }

  function schemaForAI(source, identityKey, identityValue) {
    const result = { [identityKey]: identityValue };
    for (const key of AI_SCHEMA_KEYS) {
      if (source?.[key] !== undefined) result[key] = source[key];
    }
    return result;
  }

  async function activeTab() {
    const [tab] = await api.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !/^https?:/.test(tab.url || "")) throw new Error("Open a regular web page first.");
    return tab;
  }

  function setBusy(nextBusy, message = "Working…") {
    busy = nextBusy;
    learnButton.disabled = nextBusy;
    fillButton.disabled = nextBusy || cachedAnswers.length === 0;
    activity.hidden = !nextBusy;
    activityLabel.textContent = message;
  }

  function setActivity(message) {
    activityLabel.textContent = message;
  }

  function show(message, isError = false) {
    status.textContent = message;
    status.classList.toggle("error", isError);
  }

  async function loadOnboardingState() {
    const result = await sendNative({ type: "UME_GET_ONBOARDING_STATE" });
    if (!result?.ok) throw new Error(result?.error || "Umete setup status is unavailable.");
    return Boolean(result.complete);
  }

  async function refreshDebugLoggingState() {
    try {
      const result = await sendNative({ type: "UME_GET_DEBUG_LOGGING_STATE" });
      debugLoggingEnabled = Boolean(result?.ok && result.enabled);
    } catch (_error) {
      debugLoggingEnabled = false;
    }
    openDebugLogButton.hidden = false;
  }

  async function openCompanionApp() {
    openAppButton.disabled = true;
    try {
      const result = await sendNative({ type: "UME_OPEN_APP" });
      if (!result?.ok) throw new Error(result?.error || "Open the Umete app to finish setup.");
      window.close();
    } catch (error) {
      openAppButton.disabled = false;
      getStarted.querySelector("p").textContent = error.message || "Open the Umete app to finish setup.";
    }
  }

  async function openSettings() {
    openSettingsButton.disabled = true;
    try {
      const result = await sendNative({ type: "UME_OPEN_SETTINGS" });
      if (!result?.ok) throw new Error(result?.error || "Umete Settings could not be opened.");
      window.close();
    } catch (error) {
      openSettingsButton.disabled = false;
      show(error.message || "Umete Settings could not be opened.", true);
    }
  }

  async function loadNativeAnswers() {
    const result = await sendNative({ type: "UME_GET_ANSWERS" });
    if (!result?.ok) throw new Error(result?.error || "Saved answers are unavailable.");
    return result.answers || [];
  }

  async function migrateLegacyAnswers(answers) {
    const { answers: legacy = [] } = await api.storage.local.get("answers");
    if (!legacy.length) return answers;
    const merged = UmeMatcher.mergeEntries(answers, legacy);
    const result = await sendNative({ type: "UME_SAVE_ANSWERS", answers: merged });
    if (!result?.ok) throw new Error(result?.error || "Saved answers could not be migrated.");
    await api.storage.local.remove("answers");
    return merged;
  }

  async function refreshAnswers() {
    cachedAnswers = await migrateLegacyAnswers(await loadNativeAnswers());
    if (!busy) fillButton.disabled = cachedAnswers.length === 0;
    return cachedAnswers;
  }

  async function learn() {
    setBusy(true, "Reading completed fields…");
    try {
      const tab = await activeTab();
      const result = await sendMessage(tab.id, { type: "UME_COLLECT" });
      const incoming = result?.answers || [];
      if (!incoming.length) throw new Error("No completed, supported fields found on this page.");
      const merged = UmeMatcher.mergeEntries(cachedAnswers, incoming);
      const saved = await sendNative({ type: "UME_SAVE_ANSWERS", answers: merged });
      if (!saved?.ok) throw new Error(saved?.error || "Umete could not save these answers.");
      cachedAnswers = merged;
      api.runtime.sendMessage({ type: "UME_ANSWERS_CHANGED" }).catch(() => {});
      api.tabs.sendMessage(tab.id, { type: "UME_REPORT_FIELDS" }, { frameId: 0 }).catch(() => {});
      show(`Remembered ${incoming.length} answer${incoming.length === 1 ? "" : "s"}. Passwords and payment fields were skipped.`);
    } catch (error) {
      show(error.message || "Umete could not read this page.", true);
    } finally {
      setBusy(false);
      await refreshAnswers().catch(() => {});
    }
  }

  async function fill() {
    setBusy(true, "Matching saved answers…");
    let locallyFilled = 0;
    try {
      const tab = await activeTab();
      const answers = await refreshAnswers();
      await refreshDebugLoggingState();
      await appendDebug("FILL START", { url: tab.url, tabId: tab.id, savedAnswerCount: answers.length });
      if (!answers.length) throw new Error("Remember some answers first.");

      const localResult = await sendMessage(tab.id, { type: "UME_FILL", answers, diagnostics: debugLoggingEnabled });
      await appendDebug("LOCAL FILL RESPONSE", localResult || { response: null });
      locallyFilled = localResult?.filled || 0;
      const schemaResult = await sendMessage(tab.id, { type: "UME_SCHEMAS", answers });
      await appendDebug("SCHEMA RESPONSE", {
        fieldCount: schemaResult?.fields?.length || 0,
        fields: (schemaResult?.fields || []).map(({ options, ...field }) => ({ ...field, optionCount: options?.length || 0 }))
      });
      const fields = schemaResult?.fields || [];

      if (!fields.length) {
        show(locallyFilled
          ? `Filled ${locallyFilled} field${locallyFilled === 1 ? "" : "s"}. Please review everything before continuing.`
          : "No confident matches found. Fill this form once, then ask Umete to remember it.");
        return;
      }

      setActivity("Asking your AI provider about unmatched fields…");
      const aiValues = aiSavedEntries(answers);
      const saved = aiValues.map((answer) => schemaForAI(answer, "key", answer.key));
      const sanitizedFields = fields.map((field) => schemaForAI(field, "field", field.field));
      const nativeResult = await sendNative({ type: "UME_MAP_FIELDS", saved, fields: sanitizedFields });
      await appendDebug("NATIVE AI RESPONSE", {
        ok: nativeResult?.ok,
        error: nativeResult?.error || null,
        mappings: nativeResult?.mappings || []
      });
      if (!nativeResult?.ok) throw new Error(nativeResult?.error || "AI mapping failed.");

      setActivity("Applying confident matches…");
      const aiResult = await sendMessage(tab.id, {
        type: "UME_APPLY_MAPPINGS",
        mappings: nativeResult.mappings || [],
        values: aiValues
      });
      await appendDebug("AI APPLY RESPONSE", aiResult || { response: null });
      const aiFilled = aiResult?.filled || 0;
      const total = locallyFilled + aiFilled;
      await appendDebug("FILL COMPLETE", { locallyFilled, aiFilled, total });
      show(total
        ? `Filled ${total} field${total === 1 ? "" : "s"}${aiFilled ? `, including ${aiFilled} AI match${aiFilled === 1 ? "" : "es"}` : ""}. Please review everything before continuing.`
        : "No confident matches were found.");
    } catch (error) {
      const message = error.message || "Umete could not fill this page.";
      await appendDebug("FILL ERROR", { message, stack: error.stack || null, locallyFilled });
      show(locallyFilled
        ? `Filled ${locallyFilled} field${locallyFilled === 1 ? "" : "s"} locally. AI mapping was unavailable: ${message}`
        : message, true);
    } finally {
      setBusy(false);
      await refreshAnswers().catch(() => {});
    }
  }

  // Optional toolbar badge. Turning it on asks Safari for access to all websites,
  // then registers detect.js so pages are checked for forms. Off by default.
  const FORM_BADGE_KEY = "ume-form-badge";
  const DETECT_SCRIPT_ID = "ume-detect";
  const formBadgeOption = document.getElementById("form-badge-option");
  const formBadgeToggle = document.getElementById("form-badge");
  const supportsFormBadge = Boolean(api.scripting?.registerContentScripts && api.permissions?.request && api.action?.setBadgeText);

  async function loadFormBadgeState() {
    if (!supportsFormBadge) return;
    const stored = await api.storage.local.get(FORM_BADGE_KEY);
    formBadgeToggle.checked = Boolean(stored[FORM_BADGE_KEY]);
    formBadgeOption.hidden = false;
  }

  async function enableFormBadge(permissionRequest) {
    const granted = await permissionRequest.catch(() => false);
    if (!granted) {
      formBadgeToggle.checked = false;
      show("Umete needs access to all websites to check pages for forms. Allow it in Safari’s extension settings, then try again.", true);
      return;
    }
    try {
      await api.scripting.registerContentScripts([{
        id: DETECT_SCRIPT_ID,
        js: ["detect.js"],
        matches: ["<all_urls>"],
        runAt: "document_idle",
        persistAcrossSessions: true
      }]);
    } catch (error) {
      if (!/already|exist|duplicate/i.test(error.message || "")) throw error;
    }
    await api.storage.local.set({ [FORM_BADGE_KEY]: true });
    const tab = await activeTab().catch(() => null);
    if (tab) await api.tabs.sendMessage(tab.id, { type: "UME_REPORT_FIELDS" }, { frameId: 0 }).catch(() => {});
    show("Umete will badge its toolbar icon on pages with forms it can fill. Reload open pages to badge them now.");
  }

  async function disableFormBadge() {
    await api.scripting.unregisterContentScripts({ ids: [DETECT_SCRIPT_ID] }).catch(() => {});
    await api.storage.local.set({ [FORM_BADGE_KEY]: false });
    show("Form badges are off.");
  }

  formBadgeToggle.addEventListener("change", () => {
    // permissions.request must start synchronously inside the user gesture.
    const request = formBadgeToggle.checked ? api.permissions.request({ origins: ["<all_urls>"] }) : null;
    const change = request ? enableFormBadge(request) : disableFormBadge();
    change.catch((error) => {
      formBadgeToggle.checked = !formBadgeToggle.checked;
      show(error.message || "Umete could not change the badge setting.", true);
    });
  });

  learnButton.addEventListener("click", learn);
  fillButton.addEventListener("click", fill);
  openAppButton.addEventListener("click", openCompanionApp);
  openSettingsButton.addEventListener("click", openSettings);
  openDebugLogButton.addEventListener("click", async () => {
    await refreshDebugLog();
    debugLogPanel.hidden = false;
    debugLogText.focus();
  });
  closeDebugLogButton.addEventListener("click", () => { debugLogPanel.hidden = true; });
  deleteDebugLogButton.addEventListener("click", async () => {
    await api.storage.local.remove(DEBUG_LOG_KEY);
    await refreshDebugLog();
  });
  copyDebugLogButton.addEventListener("click", async () => {
    await navigator.clipboard.writeText(debugLogText.value);
    copyDebugLogButton.textContent = "Copied";
    setTimeout(() => { copyDebugLogButton.textContent = "Copy"; }, 1200);
  });
  emailDebugLogButton.addEventListener("click", async () => {
    emailDebugLogButton.disabled = true;
    try {
      const { os = "unknown" } = await api.runtime.getPlatformInfo();
      const version = api.runtime.getManifest()?.version || "unknown";
      window.location.href = UmeDebugEmail.buildDebugEmail(debugLogText.value, { version, platform: os });
    } catch (error) {
      show(error.message || "Umete could not open an email draft.", true);
      emailDebugLogButton.disabled = false;
    }
  });

  loadFormBadgeState().catch(() => {});
  Promise.all([loadOnboardingState(), refreshDebugLoggingState()])
    .then(([complete]) => {
      getStarted.hidden = complete;
      readyContent.hidden = !complete;
      if (complete) return refreshAnswers();
      return undefined;
    })
    .catch((error) => {
      getStarted.hidden = false;
      readyContent.hidden = true;
      getStarted.querySelector("p").textContent = error.message || "Open the Umete app to finish setup.";
    });
})();
