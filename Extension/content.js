(() => {
  "use strict";

  if (globalThis.__umeContentLoaded) return;
  globalThis.__umeContentLoaded = true;

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

  const { deepQuerySelectorAll } = UmeDOM;
  const { formatDateParts, parseDateParts } = UmeDate;
  const { callingCodeFromOption, countryCodeDigits, digitsOnly, resolveCountryCode, valueForField: phoneValueForField } = UmePhone;

  function elementById(element, id) {
    const root = element.getRootNode?.();
    return root?.getElementById?.(id) || document.getElementById(id);
  }

  function referencedText(element, attribute) {
    return compactText((element.getAttribute(attribute) || "")
      .split(/\s+/)
      .map((id) => textOf(elementById(element, id)))
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
    headers.push(...explicit.map((id) => textOf(elementById(element, id))));

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
    const addressPart = UmeMatcher.addressFieldPart(descriptor);
    if (addressPart) descriptor.addressPart = addressPart;
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
    const elements = deepQuerySelectorAll("input, select, textarea").filter(isEligible);
    for (const element of elements) {
      if (isCountryCodeField(element)) continue;
      const descriptor = describe(element);
      if (element.type === "radio" && element.checked) {
        const key = element.name || `${descriptor.groupName}`;
        if (seenRadios.has(key)) continue;
        seenRadios.add(key);
      }
      const value = readValue(element);
      if (value === "" || value == null) continue;
      const answer = { ...descriptor, value };
      if (UmeMatcher.answerType(descriptor) === "phone") {
        const codeElement = relatedCountryCodeElement(element, elements);
        const code = selectedCountryCode(codeElement);
        answer.answerType = "phone";
        if (code) answer.countryCode = code;
      }
      answers.push(answer);
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

  function isCountryCodeField(element) {
    if (UmeMatcher.addressFieldPart(describe(element)) === "country") return false;
    const text = UmeMatcher.normalize([
      element.id, element.name, element.placeholder, element.autocomplete, labelFor(element), accessibleNameFor(element)
    ].filter(Boolean).join(" "));
    return /(?:^| )(?:country (?:phone )?code|phone country|calling code|dial code|international code|country dialing)(?: |$)/.test(text);
  }

  function nearestRelatedElement(element, elements, predicate) {
    const index = elements.indexOf(element);
    let candidates = elements.filter((candidate) => candidate !== element && predicate(candidate));
    const sameForm = candidates.filter((candidate) => candidate.form && candidate.form === element.form);
    if (sameForm.length) candidates = sameForm;
    candidates.sort((left, right) => Math.abs(elements.indexOf(left) - index) - Math.abs(elements.indexOf(right) - index));
    return candidates[0] || null;
  }

  function relatedPhoneElement(element, elements) {
    return nearestRelatedElement(element, elements, (candidate) => {
      return !isCountryCodeField(candidate) && UmeMatcher.answerType(describe(candidate)) === "phone";
    });
  }

  function relatedCountryCodeElement(element, elements) {
    return nearestRelatedElement(element, elements, isCountryCodeField);
  }

  function selectedCountryCode(element) {
    if (!element) return "";
    if (element instanceof HTMLSelectElement) {
      const option = element.selectedOptions?.[0];
      return callingCodeFromOption(option?.value, option?.text);
    }
    return callingCodeFromOption(element.value, element.value);
  }

  function countryCodeResolution(savedEntries, element, elements = eligibleElements()) {
    if (!isCountryCodeField(element)) return { codes: [], saved: null, result: "not a country code field" };
    const related = relatedPhoneElement(element, elements);
    return resolveCountryCode(savedEntries, related ? describe(related) : null);
  }

  function matchForElement(savedEntries, element) {
    if (isCountryCodeField(element)) return countryCodeResolution(savedEntries, element).saved;
    return UmeMatcher.bestMatch(savedEntries, describe(element));
  }

  function phoneParts(saved, element) {
    const callingCodeField = isCountryCodeField(element);
    const value = phoneValueForField(saved, callingCodeField);
    return value ? [value] : null;
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
    const option = candidates.find((candidate) => callingCodeFromOption(candidate.value, candidate.text) === target)
      || candidates.find((candidate) => new RegExp(`\\+${target}(?:\\D|$)`).test(compactText(candidate.text)))
      || candidates.find((candidate) => {
        const groups = compactText(candidate.text).match(/\+\d{1,3}/g) || [];
        return groups.some((group) => digitsOnly(group) === target);
      });
    return selectOption(element, option);
  }

  function applySelect(element, value) {
    const options = [...element.options];
    const index = UmeMatcher.selectOptionIndex(options, value);
    return selectOption(element, index >= 0 ? options[index] : null);
  }

  function applyAddress(element, saved) {
    const descriptor = describe(element);
    const part = UmeMatcher.addressFieldPart(descriptor);
    const address = saved?.value;
    if (!part || !address || typeof address !== "object" || Array.isArray(address)) return false;

    if (part === "country") {
      const code = UmeMatcher.normalize(address.countryCode);
      const name = UmeMatcher.normalize(address.countryName);
      if (element instanceof HTMLSelectElement) {
        const option = [...element.options].find((candidate) => {
          const optionValue = UmeMatcher.normalize(candidate.value);
          const optionText = UmeMatcher.normalize(candidate.text);
          const optionTextWithoutDialingCode = optionText.replace(/ \d{1,3}$/, "");
          return Boolean((code && (optionValue === code || optionText === code)) || (name && (optionValue === name || optionText === name || optionTextWithoutDialingCode === name)));
        });
        return selectOption(element, option);
      }
      const autocomplete = String(element.autocomplete || "").toLowerCase().split(/\s+/);
      const requestsCode = autocomplete.includes("country") || /(?:^| )(?:country code|iso country)(?: |$)/.test(UmeMatcher.normalize([descriptor.label, descriptor.name].join(" ")));
      const country = requestsCode ? address.countryCode : (address.countryName || address.countryCode);
      if (!country) return false;
      setNativeValue(element, country);
      dispatchValueEvents(element);
      return String(element.value) === String(country);
    }

    const value = part === "streetAddress" && !(element instanceof HTMLTextAreaElement)
      ? address.addressLine1
      : UmeMatcher.addressValue(saved, part);
    if (!value) return false;
    if (element instanceof HTMLSelectElement) return applySelect(element, value);
    setNativeValue(element, value);
    dispatchValueEvents(element);
    return String(element.value) === String(value);
  }

  function genderValue(value) {
    const normalized = UmeMatcher.normalize(value);
    const parts = new Set(normalized.split(" ").filter(Boolean));
    if (parts.has("female") || parts.has("woman") || normalized === "f") return "f";
    if (parts.has("male") || parts.has("man") || normalized === "m") return "m";
    if (parts.has("undisclosed") || normalized === "u") return "u";
    if (parts.has("unspecified") || normalized === "x" || normalized === "nonbinary" || normalized === "non binary") return "x";
    return normalized;
  }

  function applyGenderSelect(element, saved) {
    if (applySelect(element, saved?.value)) return true;
    const target = genderValue(saved?.value);
    if (!target) return false;
    const option = [...element.options].find((candidate) => {
      return genderValue([candidate.text, candidate.value].filter(Boolean).join(" ")) === target;
    });
    return selectOption(element, option);
  }

  function applyRadio(saved, sourceElement) {
    const type = UmeMatcher.answerType(saved);
    const normalized = type === "gender" ? genderValue(saved?.value) : UmeMatcher.normalize(saved?.value);
    if (!normalized) return false;
    const candidates = deepQuerySelectorAll("input[type='radio']").filter((candidate) => {
      if (!isEligible(candidate)) return false;
      const descriptor = describe(candidate);
      if (sourceElement?.name && candidate.name && sourceElement.name !== candidate.name) return false;
      return !sourceElement || UmeMatcher.compatible(saved, descriptor);
    });
    const match = candidates.find((candidate) => {
      const value = type === "gender"
        ? genderValue([labelFor(candidate), candidate.value].filter(Boolean).join(" "))
        : UmeMatcher.normalize([labelFor(candidate), candidate.value].filter(Boolean).join(" "));
      return value === normalized || value.startsWith(`${normalized} `);
    });
    if (match && !match.checked) match.click();
    return Boolean(match && match.checked);
  }

  function applySegmentedGender(saved) {
    const target = genderValue(saved?.value);
    if (!target) return false;
    const candidates = deepQuerySelectorAll("button, [role='radio']").filter((candidate) => {
      if (candidate.disabled || candidate.getAttribute("aria-disabled") === "true") return false;
      return genderValue([candidate.getAttribute("aria-label"), candidate.getAttribute("data-value"), candidate.getAttribute("value"), textOf(candidate)].filter(Boolean).join(" ")) === target;
    });
    const match = candidates.find((candidate) => {
      const container = candidate.closest("[role='radiogroup'], mat-button-toggle-group, .mat-button-toggle-group") || candidate.parentElement;
      const context = UmeMatcher.normalize(textOf(container));
      return /(?:^| )male(?: |$)/.test(context) && /(?:^| )female(?: |$)/.test(context);
    });
    if (!match) return false;
    match.click();
    return match.getAttribute("aria-checked") !== "false" && match.getAttribute("aria-pressed") !== "false";
  }

  const MONTH_NAMES = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"];

  function dateFieldPart(element) {
    const text = UmeMatcher.normalize([labelFor(element), element.name, element.id, element.placeholder, element.autocomplete].filter(Boolean).join(" "));
    if (element.autocomplete === "bday" || /(?:^| )(?:birth ?day|birth ?date|date of birth|dob)(?: |$)/.test(text)) return "";
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
    if (part) {
      const partValue = datePartValue(parts, part);
      if (!partValue) return false;
      if (element instanceof HTMLSelectElement) return applyDateSelect(element, partValue);
      const text = UmeMatcher.normalize([element.placeholder, element.name, element.id].filter(Boolean).join(" "));
      const value = (part === "month" || part === "day") && /mm|dd|yyyy|yy/.test(text) ? partValue.padded : partValue.numeric;
      setNativeValue(element, value);
      dispatchValueEvents(element);
      return String(element.value) === String(value);
    }

    if (element instanceof HTMLSelectElement) return false;
    const normalized = UmeMatcher.normalize([labelFor(element), accessibleNameFor(element), element.name, element.id, element.placeholder, element.autocomplete].filter(Boolean).join(" "));
    const isBirthDate = /(?:^| )(?:birth ?day|birth ?date|date of birth|dob)(?: |$)/.test(normalized) || element.autocomplete === "bday";
    if (!isBirthDate) return false;
    const value = formatDateParts(parts, [element.placeholder, labelFor(element), accessibleNameFor(element)].filter(Boolean).join(" "), element.type);
    setNativeValue(element, value);
    dispatchValueEvents(element);
    return String(element.value) === value;
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
    if (element.type === "radio") return applyRadio(saved || { value }, element);

    const type = UmeMatcher.answerType(saved);
    if (type === "address") return applyAddress(element, saved);
    if (type === "gender") {
      if (element instanceof HTMLSelectElement && applyGenderSelect(element, saved)) return true;
      if (applySegmentedGender(saved)) return true;
      if (element instanceof HTMLSelectElement) return false;
    }
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
    return deepQuerySelectorAll("input, select, textarea").filter(isEligible);
  }

  function fillAnswers(savedEntries, diagnosticsEnabled = false) {
    const elements = eligibleElements();
    const countryCodeDiagnostics = [];
    let filled = 0;
    let unmatched = 0;
    let matchedButNotApplied = 0;
    for (const element of elements) {
      const isCallingCode = isCountryCodeField(element);
      const resolution = isCallingCode ? countryCodeResolution(savedEntries, element, elements) : null;
      const match = isCallingCode ? resolution.saved : matchForElement(savedEntries, element);
      if (!match) {
        unmatched += 1;
        if (isCallingCode && diagnosticsEnabled) {
          countryCodeDiagnostics.push({
            availableSavedCodes: resolution.codes,
            result: resolution.result,
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
      domControlCount: deepQuerySelectorAll("input, select, textarea").length,
      frameURL: location.href
    };
  }

  function unmatchedSchemas(savedEntries) {
    const hasAddress = (savedEntries || []).some((entry) => UmeMatcher.answerType(entry) === "address");
    return eligibleElements().flatMap((element, index) => {
      const descriptor = describe(element);
      if (hasAddress && UmeMatcher.addressFieldPart(descriptor)) return [];
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
      if (!element || !saved || UmeMatcher.answerType(saved) === "address") continue;
      if (applyValue(element, saved.value, saved)) filled += 1;
    }
    return { filled };
  }

  api.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type === "UME_PING") sendResponse({ ready: true });
    if (message?.type === "UME_COLLECT") sendResponse({ answers: collectAnswers() });
    if (message?.type === "UME_FILL") sendResponse(fillAnswers(message.answers || [], Boolean(message.diagnostics)));
    if (message?.type === "UME_SCHEMAS") sendResponse({ fields: unmatchedSchemas(message.answers || []) });
    if (message?.type === "UME_APPLY_MAPPINGS") sendResponse(applyMappings(message.mappings, message.values));
    return false;
  });
})();
