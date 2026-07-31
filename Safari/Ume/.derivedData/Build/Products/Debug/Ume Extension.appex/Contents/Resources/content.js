(() => {
  "use strict";

  const api = browser;
  const BLOCKED_TYPES = new Set(["button", "file", "hidden", "image", "password", "reset", "submit"]);
  const SENSITIVE_HINT = /\b(card(?:holder)?|credit card|cvc|cvv|password|passcode|security code|secret|social security|ssn|token)\b/i;
  const HEADING_SELECTOR = "h1, h2, h3, h4, h5, h6, [role='heading']";
  const MAX_CONTEXT_LENGTH = 160;

  function compactText(value, maximum = MAX_CONTEXT_LENGTH) {
    const text = String(value || "").replace(/\s+/g, " ").trim();
    return text.length > maximum ? `${text.slice(0, maximum - 1).trimEnd()}…` : text;
  }

  function textOf(element) {
    return compactText(element?.innerText || element?.textContent || "");
  }

  function referencedText(element, attribute) {
    return compactText((element.getAttribute(attribute) || "")
      .split(/\s+/)
      .map((id) => textOf(document.getElementById(id)))
      .filter(Boolean)
      .join(" "));
  }

  function labelFor(element) {
    if (element.labels?.length) return compactText([...element.labels].map(textOf).filter(Boolean).join(" "));
    return referencedText(element, "aria-labelledby")
      || compactText(element.getAttribute("aria-label"))
      || textOf(element.closest("label"));
  }

  function descriptionFor(element) {
    const description = referencedText(element, "aria-describedby") || compactText(element.getAttribute("title"));
    const currentValue = typeof element.value === "string" ? element.value.trim() : "";
    return currentValue && description.includes(currentValue)
      ? compactText(description.replaceAll(currentValue, ""))
      : description;
  }

  function accessibleNameFor(element) {
    return referencedText(element, "aria-labelledby")
      || compactText(element.getAttribute("aria-label"))
      || labelFor(element)
      || compactText(element.placeholder);
  }

  function namedContainer(element, selector) {
    const container = element.closest(selector);
    if (!container) return "";
    return referencedText(container, "aria-labelledby")
      || compactText(container.getAttribute("aria-label"));
  }

  function groupFor(element) {
    const fieldset = element.closest("fieldset");
    const legend = fieldset?.querySelector(":scope > legend");
    if (legend) return textOf(legend);
    return namedContainer(element, "[role='group'], [role='radiogroup']");
  }

  function headingFor(element) {
    let child = element;
    let ancestor = element.parentElement;
    for (let depth = 0; ancestor && depth < 5; depth += 1) {
      if (ancestor.matches("section, article, form, fieldset, li, [role='group'], [role='region']")) {
        const labelled = referencedText(ancestor, "aria-labelledby") || compactText(ancestor.getAttribute("aria-label"));
        if (labelled && labelled !== groupFor(element)) return labelled;
        const directHeading = [...ancestor.children].find((candidate) => candidate.matches?.(HEADING_SELECTOR));
        if (directHeading && directHeading !== child) return textOf(directHeading);
      }

      let sibling = child.previousElementSibling;
      while (sibling) {
        if (sibling.matches?.(HEADING_SELECTOR)) return textOf(sibling);
        sibling = sibling.previousElementSibling;
      }
      child = ancestor;
      ancestor = ancestor.parentElement;
    }
    return "";
  }

  function formFor(element) {
    const form = element.form || element.closest("form");
    if (!form) return "";
    const named = referencedText(form, "aria-labelledby") || compactText(form.getAttribute("aria-label"));
    if (named) return named;
    const heading = form.querySelector(HEADING_SELECTOR);
    return heading ? textOf(heading) : "";
  }

  function tableHeadersFor(element) {
    const cell = element.closest("td, th");
    const table = cell?.closest("table");
    if (!cell || !table) return [];

    const headers = [];
    const explicit = (cell.getAttribute("headers") || "").split(/\s+/).filter(Boolean);
    headers.push(...explicit.map((id) => textOf(document.getElementById(id))));

    const row = cell.closest("tr");
    if (row) {
      for (const header of row.querySelectorAll(":scope > th")) {
        if (header !== cell) headers.push(textOf(header));
      }
    }

    const columnIndex = cell.cellIndex;
    if (columnIndex >= 0) {
      for (const tableRow of table.rows) {
        const header = tableRow.cells[columnIndex];
        if (header?.tagName === "TH") headers.push(textOf(header));
      }
    }

    return [...new Set(headers.filter(Boolean))].slice(0, 4);
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
    const hints = [element.name, element.id, element.autocomplete, element.placeholder, labelFor(element), groupFor(element)]
      .filter(Boolean)
      .join(" ")
      .replace(/([a-z])([A-Z])/g, "$1 $2")
      .replace(/[_-]+/g, " ");
    return !element.disabled && !element.readOnly && !BLOCKED_TYPES.has(type) && !SENSITIVE_HINT.test(hints);
  }

  function describe(element) {
    return {
      accessibleDescription: descriptionFor(element),
      accessibleName: accessibleNameFor(element),
      autocomplete: element.autocomplete || "",
      form: formFor(element),
      group: groupFor(element),
      id: element.id || "",
      inputType: (element.type || "").toLowerCase(),
      kind: kindOf(element),
      label: labelFor(element),
      name: element.name || "",
      placeholder: compactText(element.placeholder),
      required: Boolean(element.required || element.getAttribute("aria-required") === "true"),
      section: headingFor(element),
      tableHeaders: tableHeadersFor(element)
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
      const descriptor = describe(element);
      if (UmeMatcher.bestMatch(savedEntries, descriptor)) return [];
      const options = element instanceof HTMLSelectElement
        ? [...element.options].map((option) => compactText(option.text)).filter(Boolean).slice(0, 50)
        : [];
      return [{ field: `field-${index}`, ...descriptor, options }];
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
