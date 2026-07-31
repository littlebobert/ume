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

  function score(saved, field) {
    if (!saved || !field || saved.kind !== field.kind) return -Infinity;
    let total = 0;
    if (saved.autocomplete && saved.autocomplete === field.autocomplete) total += 100;
    if (saved.name && normalize(saved.name) === normalize(field.name)) total += 50;
    if (saved.id && normalize(saved.id) === normalize(field.id)) total += 30;
    total += overlap(saved.label, field.label) * 65;
    total += overlap(saved.name, field.name) * 25;
    total += overlap(saved.placeholder, field.placeholder) * 15;
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
      if (index >= 0) result[index] = { ...result[index], ...next };
      else result.push(next);
    }
    return result;
  }

  return { bestMatch, mergeEntries, normalize, overlap, score };
});
