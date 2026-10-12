// Optional form detection. Registered dynamically only after the user turns on
// "Show a badge on pages with forms" in the popup. It describes the visible,
// non-sensitive form controls on the page and hands them to the background
// script, which decides what to show on the toolbar icon. Nothing leaves the
// device, and no field values are read.
(function () {
  "use strict";
  if (window.__umeDetectInstalled) return;
  window.__umeDetectInstalled = true;

  const api = browser;
  const BLOCKED_TYPES = new Set(["button", "checkbox", "color", "file", "hidden", "image", "password", "radio", "range", "reset", "submit"]);
  const SENSITIVE_HINT = /\b(card(?:holder)?|credit card|cvc|cvv|password|passcode|security code|secret|social security|ssn|token)\b/i;
  const MAX_FIELDS = 200;
  const MAX_CONTROLS = 1500;

  function compactText(value) {
    return String(value || "").replace(/\s+/g, " ").trim().slice(0, 160);
  }

  function referencedText(element, attribute) {
    const ids = (element.getAttribute(attribute) || "").split(/\s+/).filter(Boolean);
    return compactText(ids.map((id) => textOf(document.getElementById(id))).join(" "));
  }

  // Text of a node without the text of any form controls nested inside it, so a
  // label wrapping a select does not include every option.
  function textOf(node) {
    if (!node) return "";
    let text = "";
    for (const child of node.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) text += child.textContent;
      else if (child.nodeType === Node.ELEMENT_NODE && !child.matches("input, select, textarea, script, style")) text += ` ${textOf(child)} `;
    }
    return compactText(text);
  }

  function labelFor(element) {
    if (element.labels?.length) return compactText([...element.labels].map(textOf).join(" "));
    return referencedText(element, "aria-labelledby")
      || compactText(element.getAttribute("aria-label"))
      || textOf(element.closest("label"));
  }

  function isVisible(element) {
    if (!element.getClientRects().length) return false;
    const style = getComputedStyle(element);
    return style.visibility !== "hidden" && style.opacity !== "0";
  }

  function kindOf(element) {
    if (element instanceof HTMLSelectElement) return "select";
    if (element instanceof HTMLTextAreaElement) return "textarea";
    return "text";
  }

  function describe(element) {
    const label = labelFor(element);
    const fieldset = element.closest("fieldset");
    return {
      accessibleName: label || compactText(element.placeholder),
      label,
      name: element.name || "",
      id: element.id || "",
      autocomplete: element.autocomplete || "",
      placeholder: element instanceof HTMLSelectElement ? "" : compactText(element.placeholder),
      inputType: (element.type || "").toLowerCase(),
      kind: kindOf(element),
      group: textOf(fieldset?.querySelector("legend")),
      section: "",
      tableHeaders: [],
      form: compactText(element.form?.getAttribute("aria-label") || element.form?.name || element.form?.id)
    };
  }

  function eligibleFields() {
    const controls = document.querySelectorAll("input, select, textarea");
    if (controls.length > MAX_CONTROLS) return [];
    const result = [];
    for (const element of controls) {
      const type = (element.type || "").toLowerCase();
      if (element.disabled || element.readOnly || BLOCKED_TYPES.has(type) || !isVisible(element)) continue;
      const hints = [element.name, element.id, element.autocomplete, element.placeholder, labelFor(element)].filter(Boolean).join(" ");
      if (SENSITIVE_HINT.test(hints)) continue;
      result.push(describe(element));
      if (result.length >= MAX_FIELDS) break;
    }
    return result;
  }

  let timer = null;
  let lastSignature = "";

  function report(force) {
    const fields = eligibleFields();
    const signature = JSON.stringify(fields.map((field) => [field.accessibleName, field.name, field.autocomplete, field.kind]));
    if (!force && signature === lastSignature) return;
    lastSignature = signature;
    api.runtime.sendMessage({ type: "UME_PAGE_FIELDS", fields }).catch(() => {});
  }

  function schedule(delay, force) {
    clearTimeout(timer);
    timer = setTimeout(() => report(force), delay);
  }

  schedule(300, true);
  document.addEventListener("focusin", (event) => {
    if (event.target?.matches?.("input, select, textarea")) schedule(0, true);
  }, true);
  window.addEventListener("pageshow", () => schedule(0, true));
  new MutationObserver(() => schedule(800, false)).observe(document.documentElement, { childList: true, subtree: true });

  api.runtime.onMessage.addListener((message) => {
    if (message?.type === "UME_REPORT_FIELDS") schedule(0, true);
    return false;
  });
})();
