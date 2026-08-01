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
  const debugLogPanel = document.getElementById("debug-log-panel");
  const debugLogText = document.getElementById("debug-log-text");
  const DEBUG_LOG_KEY = "ume-extension-debug-log";
  const DEBUG_LOG_LIMIT = 64_000;
  let debugLoggingEnabled = false;
  let busy = false;
  let cachedAnswers = [];

  async function sendMessage(tabId, message) {
    try {
      return await api.tabs.sendMessage(tabId, message, { frameId: 0 });
    } catch (error) {
      throw new Error(`Ume could not communicate with this page. Reload it and try again. ${error.message || ""}`.trim());
    }
  }

  function sendNative(message) {
    return api.runtime.sendNativeMessage("com.justin.ume", message);
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
    debugLogText.value = stored[DEBUG_LOG_KEY] || "No extension debug entries yet.";
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
    if (!result?.ok) throw new Error(result?.error || "Ume setup status is unavailable.");
    return Boolean(result.complete);
  }

  async function refreshDebugLoggingState() {
    const result = await sendNative({ type: "UME_GET_DEBUG_LOGGING_STATE" });
    debugLoggingEnabled = Boolean(result?.ok && result.enabled);
    openDebugLogButton.hidden = !debugLoggingEnabled;
    if (!debugLoggingEnabled) {
      debugLogPanel.hidden = true;
      await api.storage.local.remove(DEBUG_LOG_KEY);
    }
  }

  async function openCompanionApp() {
    openAppButton.disabled = true;
    try {
      const result = await sendNative({ type: "UME_OPEN_APP" });
      if (!result?.ok) throw new Error(result?.error || "Open the Ume app to finish setup.");
      window.close();
    } catch (error) {
      openAppButton.disabled = false;
      getStarted.querySelector("p").textContent = error.message || "Open the Ume app to finish setup.";
    }
  }

  async function openSettings() {
    openSettingsButton.disabled = true;
    try {
      const result = await sendNative({ type: "UME_OPEN_SETTINGS" });
      if (!result?.ok) throw new Error(result?.error || "Ume Settings could not be opened.");
      window.close();
    } catch (error) {
      openSettingsButton.disabled = false;
      show(error.message || "Ume Settings could not be opened.", true);
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
      if (!saved?.ok) throw new Error(saved?.error || "Ume could not save these answers.");
      cachedAnswers = merged;
      show(`Remembered ${incoming.length} answer${incoming.length === 1 ? "" : "s"}. Passwords and payment fields were skipped.`);
    } catch (error) {
      show(error.message || "Ume could not read this page.", true);
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
          : "No confident matches found. Fill this form once, then ask Ume to remember it.");
        return;
      }

      setActivity("Asking your AI provider about unmatched fields…");
      const saved = answers.map(({ value: _value, ...descriptor }, index) => ({ key: `saved-${index}`, ...descriptor }));
      const nativeResult = await sendNative({ type: "UME_MAP_FIELDS", saved, fields });
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
        values: answers.map((answer, index) => ({ key: `saved-${index}`, ...answer }))
      });
      await appendDebug("AI APPLY RESPONSE", aiResult || { response: null });
      const aiFilled = aiResult?.filled || 0;
      const total = locallyFilled + aiFilled;
      await appendDebug("FILL COMPLETE", { locallyFilled, aiFilled, total });
      show(total
        ? `Filled ${total} field${total === 1 ? "" : "s"}${aiFilled ? `, including ${aiFilled} AI match${aiFilled === 1 ? "" : "es"}` : ""}. Please review everything before continuing.`
        : "No confident matches were found.");
    } catch (error) {
      const message = error.message || "Ume could not fill this page.";
      await appendDebug("FILL ERROR", { message, stack: error.stack || null, locallyFilled });
      show(locallyFilled
        ? `Filled ${locallyFilled} field${locallyFilled === 1 ? "" : "s"} locally. AI mapping was unavailable: ${message}`
        : message, true);
    } finally {
      setBusy(false);
      await refreshAnswers().catch(() => {});
    }
  }

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
      getStarted.querySelector("p").textContent = error.message || "Open the Ume app to finish setup.";
    });
})();
