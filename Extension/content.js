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

  function optionLabelFor(element) {
    if (element instanceof HTMLSelectElement) return compactText(element.selectedOptions?.[0]?.text);
    return "";
  }

  function radioGroupName(element) {
    return groupFor(element) || headingFor(element) || element.name || "";
  }

  function describe(element) {
    const descriptor = {
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
      placeholder: element instanceof HTMLSelectElement ? "" : compactText(element.placeholder),
      required: Boolean(element.required || element.getAttribute("aria-required") === "true"),
      section: headingFor(element),
      tableHeaders: tableHeadersFor(element)
    };
    if (element instanceof HTMLSelectElement) descriptor.optionLabel = optionLabelFor(element);
    if (element.type === "radio") {
      descriptor.optionLabel = compactText([labelFor(element), element.value].filter(Boolean).join(" "));
      descriptor.groupName = compactText(radioGroupName(element));
      descriptor.accessibleName = descriptor.groupName || descriptor.accessibleName;
      descriptor.label = descriptor.groupName || descriptor.label;
    }
    return descriptor;
  }

  function readValue(element) {
    if (element.type === "checkbox") return element.checked;
    if (element.type === "radio") return element.checked ? (describe(element).optionLabel || element.value) : null;
    if (element instanceof HTMLSelectElement) return optionLabelFor(element) || element.value;
    return element.value;
  }

  function collectAnswers() {
    const answers = [];
    const seenRadios = new Set();
    for (const element of document.querySelectorAll("input, select, textarea")) {
      if (!isEligible(element)) continue;
      if (element.type === "radio" && element.checked) {
        const key = element.name || `${describe(element).groupName}`;
        if (seenRadios.has(key)) continue;
        seenRadios.add(key);
      }
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

  function digitsOnly(value) {
    return String(value || "").replace(/\D/g, "");
  }

  function countryCodeDigits(saved) {
    const stored = digitsOnly(saved?.countryCode);
    if (stored) return stored;
    const value = String(saved?.value ?? "").trim();
    if (!value.startsWith("+")) return "";
    const match = value.match(/^\+(\d{1,3})/);
    return match ? match[1] : "";
  }

  function localNumberDigits(saved, code) {
    let digits = digitsOnly(saved?.value);
    if (code && digits.startsWith(code)) digits = digits.slice(code.length);
    else if (!code && digits.length > 10 && digits.startsWith("1")) digits = digits.slice(1);
    if (code && code !== "1" && digits.startsWith("0")) digits = digits.slice(1);
    return digits;
  }

  function isCountryCodeField(element) {
    const text = UmeMatcher.normalize([
      element.id, element.name, element.placeholder, labelFor(element), accessibleNameFor(element)
    ].filter(Boolean).join(" "));
    return /(?:^| )(?:country (?:phone )?code|phone country|calling code|dial code|international code|country dialing)(?: |$)/.test(text);
  }

  function countryCodeResolution(savedEntries, element) {
    if (!isCountryCodeField(element)) return { codes: [], saved: null };
    const phones = (savedEntries || []).filter((saved) => UmeMatcher.answerType(saved) === "phone" && countryCodeDigits(saved));
    const codes = [...new Set(phones.map(countryCodeDigits))];
    return { codes, saved: codes.length === 1 ? phones[0] : null };
  }

  function matchForElement(savedEntries, element) {
    if (isCountryCodeField(element)) return countryCodeResolution(savedEntries, element).saved;
    return UmeMatcher.bestMatch(savedEntries, describe(element));
  }

  function phoneParts(saved, element) {
    const code = countryCodeDigits(saved);
    if (isCountryCodeField(element)) {
      const local = localNumberDigits(saved, code);
      const candidate = code || (local && local !== digitsOnly(saved?.value) ? "1" : "");
      return candidate ? [candidate, local] : null;
    }
    return [localNumberDigits(saved, code || (String(saved?.value ?? "").trim().startsWith("+") ? countryCodeDigits(saved) : ""))];
  }

  function selectOption(element, option) {
    if (!option) return false;
    setNativeValue(element, option.value);
    if (element.value !== option.value) option.selected = true;
    element.dispatchEvent(new Event("input", { bubbles: true }));
    element.dispatchEvent(new Event("change", { bubbles: true }));
    return element.value === option.value || option.selected;
  }

  function applyCountryCodeSelect(element, code) {
    const target = digitsOnly(code);
    if (!target) return false;
    const candidates = [...element.options].filter((option) => compactText(option.text) || String(option.value || "").trim());
    const option = candidates.find((candidate) => digitsOnly(candidate.value) === target)
      || candidates.find((candidate) => new RegExp(`\\+${target}(?:\\D|$)`).test(compactText(candidate.text)))
      || candidates.find((candidate) => {
        const groups = compactText(candidate.text).match(/\+\d{1,3}/g) || [];
        return groups.some((group) => digitsOnly(group) === target);
      });
    return selectOption(element, option);
  }

  function applySelect(element, value) {
    const normalized = UmeMatcher.normalize(value);
    if (!normalized) return false;
    const candidates = [...element.options].filter((option) => UmeMatcher.normalize(option.text) !== "");
    const option = candidates.find((candidate) => UmeMatcher.normalize(candidate.text) === normalized)
      || candidates.find((candidate) => UmeMatcher.normalize(candidate.value) === normalized && UmeMatcher.normalize(candidate.value) !== "")
      || candidates.find((candidate) => {
        const text = UmeMatcher.normalize(candidate.text);
        return text.startsWith(normalized) || normalized.startsWith(text);
      })
      || candidates.find((candidate) => UmeMatcher.normalize(candidate.text).split(" ").includes(normalized));
    return selectOption(element, option);
  }

  function applyRadio(saved) {
    const normalized = UmeMatcher.normalize(saved?.value);
    if (!normalized) return false;
    const candidates = [...document.querySelectorAll("input[type='radio']")].filter(isEligible);
    const exact = candidates.find((candidate) => {
      const text = UmeMatcher.normalize([labelFor(candidate), candidate.value].filter(Boolean).join(" "));
      return text === normalized;
    });
    const match = exact || candidates.find((candidate) => {
      const text = UmeMatcher.normalize([labelFor(candidate), candidate.value].filter(Boolean).join(" "));
      return text.startsWith(normalized);
    });
    if (match && !match.checked) match.click();
    return Boolean(match);
  }

  const MONTH_NAMES = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];

  function parseDateParts(raw) {
    const text = String(raw ?? "").trim();
    if (!text) return null;
    let match = text.match(/^(\d{4})\D+(\d{1,2})\D+(\d{1,2})$/);
    if (match) return { year: match[1], month: String(Number(match[2])), day: String(Number(match[3])) };
    match = text.match(/^(\d{1,2})\D+(\d{1,2})\D+(\d{4})$/);
    if (match) return { year: match[3], month: String(Number(match[1])), day: String(Number(match[2])) };
    const timestamp = Date.parse(text);
    if (!Number.isNaN(timestamp)) {
      const date = new Date(timestamp);
      return { year: String(date.getFullYear()), month: String(date.getMonth() + 1), day: String(date.getDate()) };
    }
    return null;
  }

  function dateFieldPart(element) {
    const text = UmeMatcher.normalize([labelFor(element), element.name, element.id, element.placeholder, element.autocomplete].filter(Boolean).join(" "));
    if (/(?:^| )(?:month|mm)(?: |$)/.test(text) || element.autocomplete === "bday-month") return "month";
    if (/(?:^| )(?:year|yyyy|yy)(?: |$)/.test(text) || element.autocomplete === "bday-year") return "year";
    if (/(?:^| )(?:day|dd)(?: |$)/.test(text) || element.autocomplete === "bday-day") return "day";
    return "";
  }

  function datePartValue(parts, part) {
    if (part === "month") return { numeric: parts.month, padded: parts.month.padStart(2, "0"), name: MONTH_NAMES[Number(parts.month) - 1] || "" };
    if (part === "day") return { numeric: parts.day, padded: parts.day.padStart(2, "0") };
    if (part === "year") return { numeric: parts.year, padded: parts.year, short: parts.year.slice(-2) };
    return null;
  }

  function applyDateSelect(element, partValue) {
    const candidates = [partValue.name, partValue.numeric, partValue.padded, partValue.short].filter(Boolean);
    for (const candidate of candidates) {
      if (applySelect(element, candidate)) return true;
    }
    return false;
  }

  function applyDate(element, saved) {
    const parts = parseDateParts(saved?.value);
    if (!parts) return false;
    const part = dateFieldPart(element);
    if (!part) return false;
    const partValue = datePartValue(parts, part);
    if (!partValue) return false;
    if (element instanceof HTMLSelectElement) return applyDateSelect(element, partValue);
    const text = UmeMatcher.normalize([element.placeholder, element.name, element.id].filter(Boolean).join(" "));
    const value = (part === "month" || part === "day") && /mm|dd|yyyy|yy/.test(text) ? partValue.padded : partValue.numeric;
    setNativeValue(element, value);
    element.dispatchEvent(new Event("input", { bubbles: true }));
    element.dispatchEvent(new Event("change", { bubbles: true }));
    return true;
  }

  function dispatchValueEvents(element) {
    element.dispatchEvent(new Event("input", { bubbles: true }));
    element.dispatchEvent(new Event("change", { bubbles: true }));
  }

  function applyValue(element, value, saved) {
    if (element.type === "checkbox") {
      if (element.checked !== Boolean(value)) element.click();
      return element.checked === Boolean(value);
    }
    if (element.type === "radio") return applyRadio(saved || { value });

    const type = UmeMatcher.answerType(saved);
    if (type === "date") {
      if (applyDate(element, saved)) return true;
      if (element instanceof HTMLSelectElement) return false;
      setNativeValue(element, value);
      dispatchValueEvents(element);
      return String(element.value) === String(value);
    }

    if (type === "phone") {
      const parts = phoneParts(saved, element);
      if (!parts) return false;
      if (element instanceof HTMLSelectElement) {
        return isCountryCodeField(element)
          ? applyCountryCodeSelect(element, parts[0])
          : applySelect(element, parts[0]);
      }
      value = parts[parts.length - 1];
    } else if (element instanceof HTMLSelectElement) {
      return applySelect(element, value);
    }

    setNativeValue(element, value);
    dispatchValueEvents(element);
    return String(element.value) === String(value);
  }

  const failedApplications = new WeakSet();

  function eligibleElements() {
    return [...document.querySelectorAll("input, select, textarea")].filter(isEligible);
  }

  function fillAnswers(savedEntries, diagnosticsEnabled = false) {
    const elements = eligibleElements();
    const countryCodeDiagnostics = [];
    let filled = 0;
    let unmatched = 0;
    let matchedButNotApplied = 0;
    for (const element of elements) {
      const isCallingCode = isCountryCodeField(element);
      const resolution = isCallingCode ? countryCodeResolution(savedEntries, element) : null;
      const match = matchForElement(savedEntries, element);
      if (!match) {
        unmatched += 1;
        if (isCallingCode && diagnosticsEnabled) {
          countryCodeDiagnostics.push({
            availableSavedCodes: resolution.codes,
            result: resolution.codes.length ? "conflicting saved country codes" : "no saved phone country code",
            selectedBefore: optionLabelFor(element)
          });
        }
        continue;
      }
      const selectedBefore = isCallingCode ? optionLabelFor(element) : "";
      const applied = applyValue(element, match.value, match);
      if (isCallingCode && diagnosticsEnabled) {
        const targetCode = countryCodeDigits(match);
        countryCodeDiagnostics.push({
          availableSavedCodes: resolution.codes,
          targetCode,
          selectedBefore,
          selectedAfter: optionLabelFor(element),
          applied,
          matchingOptions: element instanceof HTMLSelectElement
            ? [...element.options].filter((option) => {
              const textCodes = compactText(option.text).match(/\+\d{1,3}/g) || [];
              return digitsOnly(option.value) === targetCode || textCodes.some((code) => digitsOnly(code) === targetCode);
            }).slice(0, 10).map((option) => ({ text: compactText(option.text), value: String(option.value || "") }))
            : []
        });
      }
      if (applied) {
        filled += 1;
        failedApplications.delete(element);
      } else {
        unmatched += 1;
        matchedButNotApplied += 1;
        failedApplications.add(element);
      }
    }
    return {
      filled,
      unmatched,
      matchedButNotApplied,
      ...(diagnosticsEnabled ? { countryCodeDiagnostics } : {}),
      eligibleFieldCount: elements.length,
      domControlCount: document.querySelectorAll("input, select, textarea").length,
      frameURL: location.href
    };
  }

  function unmatchedSchemas(savedEntries) {
    return eligibleElements().flatMap((element, index) => {
      const descriptor = describe(element);
      if (!failedApplications.has(element) && matchForElement(savedEntries, element)) return [];
      const options = element instanceof HTMLSelectElement
        ? [...element.options].map((option) => compactText(option.text)).filter(Boolean).slice(0, 50)
        : [];
      return [{ field: `field-${index}`, ...descriptor, options }];
    });
  }

  function applyMappings(mappings, values) {
    const elements = eligibleElements();
    const savedByKey = new Map((values || []).map((item) => [item.key, item]));
    let filled = 0;
    for (const mapping of mappings || []) {
      const index = Number(String(mapping.field || "").replace("field-", ""));
      const element = elements[index];
      const saved = savedByKey.get(mapping.key);
      if (!element || !saved || !UmeMatcher.compatible(saved, describe(element))) continue;
      if (applyValue(element, saved.value, saved)) filled += 1;
    }
    return { filled };
  }

  api.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === "UME_COLLECT") sendResponse({ answers: collectAnswers() });
    if (message?.type === "UME_FILL") sendResponse(fillAnswers(message.answers || [], Boolean(message.diagnostics)));
    if (message?.type === "UME_SCHEMAS") sendResponse({ fields: unmatchedSchemas(message.answers || []) });
    if (message?.type === "UME_APPLY_MAPPINGS") sendResponse(applyMappings(message.mappings, message.values));
    return false;
  });
})();
