(() => {
  "use strict";

  const api = browser;
  const BLOCKED_TYPES = new Set(["button", "file", "hidden", "image", "password", "reset", "submit"]);
  const SENSITIVE_HINT = /\b(card(?:holder)?|credit card|cvc|cvv|password|passcode|security code|secret|social security|ssn|token)\b/i;

  function textOf(element) {
    return (element?.innerText || element?.textContent || "").replace(/\s+/g, " ").trim();
  }

  function labelFor(element) {
    if (element.labels?.length) return [...element.labels].map(textOf).filter(Boolean).join(" ");
    const labelledBy = element.getAttribute("aria-labelledby");
    if (labelledBy) {
      const value = labelledBy.split(/\s+/).map((id) => textOf(document.getElementById(id))).filter(Boolean).join(" ");
      if (value) return value;
    }
    return element.getAttribute("aria-label") || textOf(element.closest("label"));
  }

  function kindOf(element) {
    if (element.tagName === "SELECT") return "select";
    if (element.tagName === "TEXTAREA") return "textarea";
    const type = (element.type || "text").toLowerCase();
    return type === "checkbox" || type === "radio" ? type : "text";
  }

  function isEligible(element) {
    if (!(element instanceof HTMLInputElement || element instanceof HTMLSelectElement || element instanceof HTMLTextAreaElement)) return false;
    const type = (element.type || "").toLowerCase();
    const hints = [element.name, element.id, element.autocomplete, element.placeholder, labelFor(element)]
      .filter(Boolean)
      .join(" ")
      .replace(/([a-z])([A-Z])/g, "$1 $2")
      .replace(/[_-]+/g, " ");
    return !element.disabled && !element.readOnly && !BLOCKED_TYPES.has(type) && !SENSITIVE_HINT.test(hints);
  }

  function describe(element) {
    return {
      autocomplete: element.autocomplete || "",
      id: element.id || "",
      kind: kindOf(element),
      label: labelFor(element),
      name: element.name || "",
      placeholder: element.placeholder || ""
    };
  }

  function readValue(element) {
    if (element.type === "checkbox") return element.checked;
    if (element.type === "radio") return element.checked ? element.value : null;
    return element.value;
  }

  function collectAnswers() {
    const answers = [];
    for (const element of document.querySelectorAll("input, select, textarea")) {
      if (!isEligible(element)) continue;
      const value = readValue(element);
      if (value === "" || value == null) continue;
      answers.push({ ...describe(element), value });
    }
    return answers;
  }

  function setNativeValue(element, value) {
    const prototype = element instanceof HTMLTextAreaElement
      ? HTMLTextAreaElement.prototype
      : element instanceof HTMLSelectElement
        ? HTMLSelectElement.prototype
        : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
    if (setter) setter.call(element, String(value));
    else element.value = String(value);
  }

  function applyValue(element, value) {
    if (element.type === "checkbox") {
      if (element.checked !== Boolean(value)) element.click();
      return;
    }
    if (element.type === "radio") {
      if (String(element.value) === String(value) && !element.checked) element.click();
      return;
    }
    setNativeValue(element, value);
    element.dispatchEvent(new Event("input", { bubbles: true }));
    element.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function eligibleElements() {
    return [...document.querySelectorAll("input, select, textarea")].filter(isEligible);
  }

  function fillAnswers(savedEntries) {
    let filled = 0;
    let unmatched = 0;
    for (const element of eligibleElements()) {
      const match = UmeMatcher.bestMatch(savedEntries, describe(element));
      if (!match) {
        unmatched += 1;
        continue;
      }
      applyValue(element, match.value);
      filled += 1;
    }
    return { filled, unmatched };
  }

  function unmatchedSchemas(savedEntries) {
    return eligibleElements().flatMap((element, index) => {
      if (UmeMatcher.bestMatch(savedEntries, describe(element))) return [];
      const options = element instanceof HTMLSelectElement
        ? [...element.options].map((option) => option.text.trim()).filter(Boolean).slice(0, 50)
        : [];
      return [{ field: `field-${index}`, ...describe(element), options }];
    });
  }

  function applyMappings(mappings, values) {
    const elements = eligibleElements();
    const valueByKey = new Map((values || []).map((item) => [item.key, item.value]));
    let filled = 0;
    for (const mapping of mappings || []) {
      const index = Number(String(mapping.field || "").replace("field-", ""));
      const element = elements[index];
      if (!element || !valueByKey.has(mapping.key)) continue;
      applyValue(element, valueByKey.get(mapping.key));
      filled += 1;
    }
    return { filled };
  }

  api.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === "UME_COLLECT") sendResponse({ answers: collectAnswers() });
    if (message?.type === "UME_FILL") sendResponse(fillAnswers(message.answers || []));
    if (message?.type === "UME_SCHEMAS") sendResponse({ fields: unmatchedSchemas(message.answers || []) });
    if (message?.type === "UME_APPLY_MAPPINGS") sendResponse(applyMappings(message.mappings, message.values));
    return false;
  });
})();
