(() => {
  "use strict";

  const api = browser;
  const learnButton = document.getElementById("learn");
  const fillButton = document.getElementById("fill");
  const status = document.getElementById("status");
  const count = document.getElementById("answer-count");
  const activity = document.getElementById("activity");
  const activityLabel = document.getElementById("activity-label");
  let busy = false;
  let cachedAnswers = [];

  function sendMessage(tabId, message) {
    return api.tabs.sendMessage(tabId, message);
  }

  function sendNative(message) {
    return api.runtime.sendNativeMessage("com.justin.ume", message);
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
    count.textContent = `${cachedAnswers.length} saved answer${cachedAnswers.length === 1 ? "" : "s"}`;
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
      if (!answers.length) throw new Error("Remember some answers first.");

      const localResult = await sendMessage(tab.id, { type: "UME_FILL", answers });
      locallyFilled = localResult?.filled || 0;
      const schemaResult = await sendMessage(tab.id, { type: "UME_SCHEMAS", answers });
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
      if (!nativeResult?.ok) throw new Error(nativeResult?.error || "AI mapping failed.");

      setActivity("Applying confident matches…");
      const aiResult = await sendMessage(tab.id, {
        type: "UME_APPLY_MAPPINGS",
        mappings: nativeResult.mappings || [],
        values: answers.map((answer, index) => ({ key: `saved-${index}`, value: answer.value }))
      });
      const aiFilled = aiResult?.filled || 0;
      const total = locallyFilled + aiFilled;
      show(total
        ? `Filled ${total} field${total === 1 ? "" : "s"}${aiFilled ? `, including ${aiFilled} AI match${aiFilled === 1 ? "" : "es"}` : ""}. Please review everything before continuing.`
        : "No confident matches were found.");
    } catch (error) {
      const message = error.message || "Ume could not fill this page.";
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
  refreshAnswers().catch((error) => show(error.message || "Ume could not access saved answers.", true));
})();
