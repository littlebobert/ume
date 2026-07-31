const provider = document.getElementById("provider");
const model = document.getElementById("model");
const apiKey = document.getElementById("api-key");
const keyState = document.getElementById("key-state");
const status = document.getElementById("status");
const answerSummary = document.getElementById("answer-summary");
const answerList = document.getElementById("answer-list");
const toggleAnswers = document.getElementById("toggle-answers");
const defaults = { openai: "gpt-5.6-terra", anthropic: "claude-haiku-4-5" };

function post(action, extra = {}) {
    webkit.messageHandlers.controller.postMessage({ action, ...extra });
}

function show(platform, enabled, useSettingsInsteadOfPreferences) {
    document.body.classList.add(`platform-${platform}`);
    if (typeof enabled === "boolean") {
        document.body.classList.toggle("state-on", enabled);
        document.body.classList.toggle("state-off", !enabled);
    }
    if (useSettingsInsteadOfPreferences) {
        document.querySelector(".open-preferences").textContent = "Open Safari Extension Settings";
    }
    post("load-settings");
}

function answerName(answer, index) {
    return answer.label || answer.placeholder || answer.name || answer.autocomplete || `Saved answer ${index + 1}`;
}

function renderAnswers(answers = []) {
    answerSummary.textContent = answers.length
        ? `${answers.length} answer${answers.length === 1 ? "" : "s"} saved on this device.`
        : "No saved answers.";
    answerList.replaceChildren();
    if (!answers.length) {
        const empty = document.createElement("p");
        empty.className = "empty-state";
        empty.textContent = "Remember answers from a completed form to see them here.";
        answerList.append(empty);
        return;
    }
    answers.forEach((answer, index) => {
        const item = document.createElement("div");
        item.className = "answer-item";
        const label = document.createElement("span");
        label.className = "answer-label";
        label.textContent = answerName(answer, index);
        const value = document.createElement("span");
        value.className = "answer-value";
        value.textContent = typeof answer.value === "boolean" ? (answer.value ? "Yes" : "No") : String(answer.value);
        item.append(label, value);
        answerList.append(item);
    });
}

function receiveSettings(settings) {
    provider.value = ["openai", "anthropic"].includes(settings.provider) ? settings.provider : "openai";
    model.value = settings.model || defaults[provider.value] || "";
    keyState.textContent = settings.hasKey ? "A key is saved in Apple Keychain." : "No key saved.";
    document.getElementById("delete-key").disabled = !settings.hasKey;
    renderAnswers(settings.answers || []);
}

function receiveResult(result) {
    status.textContent = result.message || "";
    status.className = result.ok ? "success" : "error";
    if (result.settings) receiveSettings(result.settings);
    if (result.ok) apiKey.value = "";
}

provider.addEventListener("change", () => {
    if (!model.value || Object.values(defaults).includes(model.value)) model.value = defaults[provider.value] || "";
});

document.getElementById("save").addEventListener("click", () => {
    post("save-settings", { provider: provider.value, model: model.value.trim(), apiKey: apiKey.value.trim() });
});

document.getElementById("delete-key").addEventListener("click", () => post("delete-key"));
document.getElementById("forget-everything").addEventListener("click", () => {
    if (confirm("Delete every saved answer and all AI settings? This cannot be undone.")) post("forget-everything");
});
toggleAnswers.addEventListener("click", () => {
    const willShow = answerList.hidden;
    answerList.hidden = !willShow;
    toggleAnswers.textContent = willShow ? "Hide" : "View";
    toggleAnswers.setAttribute("aria-expanded", String(willShow));
});
const preferences = document.querySelector("button.open-preferences");
if (preferences) preferences.addEventListener("click", () => post("open-preferences"));
