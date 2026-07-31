(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.UmeMatcher = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const TOKEN_RE = /[^a-z0-9]+/g;
  const STOP_WORDS = new Set(["a", "an", "and", "field", "input", "of", "or", "the", "your"]);

  function normalize(value) {
    return String(value || "")
      .replace(/([a-z])([A-Z])/g, "$1 $2")
      .toLowerCase()
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(TOKEN_RE, " ")
      .trim();
  }

  function tokens(value) {
    return new Set(normalize(value).split(/\s+/).filter((token) => token && !STOP_WORDS.has(token)));
  }

  function overlap(left, right) {
    const a = tokens(left);
    const b = tokens(right);
    if (!a.size || !b.size) return 0;
    let shared = 0;
    for (const token of a) if (b.has(token)) shared += 1;
    return shared / Math.max(a.size, b.size);
  }

  function looksGenerated(value) {
    const raw = String(value || "").trim();
    if (!raw) return false;
    const normalized = normalize(raw);
    const compact = raw.replace(/[^a-z0-9]/gi, "");
    return /^\d+$/.test(compact)
      || /[a-f0-9]{8,}/i.test(compact)
      || /(?:^|[_-])(?:field|input|control|element)?[_-]?\d{3,}(?:$|[_-])/i.test(raw)
      || (/\d{4,}/.test(compact) && normalized.split(" ").length <= 2);
  }

  function contextText(entry) {
    return [entry?.group, entry?.section, entry?.form, ...(entry?.tableHeaders || [])].filter(Boolean).join(" ");
  }

  function nameText(entry) {
    return entry?.userLabel || entry?.accessibleName || entry?.label || "";
  }

  function score(saved, field) {
    if (!saved || !field || saved.kind !== field.kind) return -Infinity;
    if (saved.inputType && field.inputType && saved.inputType !== field.inputType) {
      const compatibleTextTypes = new Set(["", "email", "search", "tel", "text", "url"]);
      if (!compatibleTextTypes.has(saved.inputType) || !compatibleTextTypes.has(field.inputType)) return -Infinity;
    }

    let total = 0;
    if (saved.autocomplete && saved.autocomplete === field.autocomplete) total += 100;
    if (saved.name && !looksGenerated(saved.name) && !looksGenerated(field.name) && normalize(saved.name) === normalize(field.name)) total += 50;
    if (saved.id && !looksGenerated(saved.id) && !looksGenerated(field.id) && normalize(saved.id) === normalize(field.id)) total += 30;
    total += overlap(nameText(saved), nameText(field)) * 70;
    total += overlap(saved.label, field.label) * 45;
    total += overlap(saved.name, field.name) * (looksGenerated(saved.name) || looksGenerated(field.name) ? 3 : 22);
    total += overlap(saved.placeholder, field.placeholder) * 12;
    total += overlap(saved.accessibleDescription, field.accessibleDescription) * 12;

    const savedContext = contextText(saved);
    const fieldContext = contextText(field);
    const contextOverlap = overlap(savedContext, fieldContext);
    total += contextOverlap * 40;
    if (savedContext && fieldContext && contextOverlap === 0 && overlap(nameText(saved), nameText(field)) >= 0.8) total -= 30;
    return total;
  }

  function bestMatch(savedEntries, field, minimumScore) {
    const threshold = minimumScore == null ? 35 : minimumScore;
    let best = null;
    let bestScore = threshold;
    let tied = false;

    for (const entry of savedEntries || []) {
      const candidateScore = score(entry, field);
      if (candidateScore > bestScore) {
        best = entry;
        bestScore = candidateScore;
        tied = false;
      } else if (candidateScore === bestScore && candidateScore >= threshold) {
        tied = true;
      }
    }

    return tied ? null : best;
  }

  function mergeEntries(existing, incoming) {
    const result = [...(existing || [])];
    for (const next of incoming || []) {
      const index = result.findIndex((saved) => score(saved, next) >= 85);
      if (index >= 0) {
        const existing = result[index];
        result[index] = {
          ...existing,
          ...next,
          ...(existing.answerID ? { answerID: existing.answerID } : {}),
          ...(existing.userLabel ? { userLabel: existing.userLabel } : {})
        };
      } else {
        result.push({ answerID: next.answerID || crypto.randomUUID(), ...next });
      }
    }
    return result;
  }

  return { bestMatch, looksGenerated, mergeEntries, normalize, overlap, score };
});
