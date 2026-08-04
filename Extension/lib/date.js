(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.UmeDate = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function parseDateParts(raw) {
    const text = String(raw ?? "").trim();
    if (!text) return null;
    let match = text.match(/^(\d{4})\D+(\d{1,2})\D+(\d{1,2})$/);
    if (match) return { year: match[1], month: String(Number(match[2])), day: String(Number(match[3])) };
    match = text.match(/^(\d{1,2})\D+(\d{1,2})\D+(\d{4})$/);
    if (match) return { year: match[3], month: String(Number(match[1])), day: String(Number(match[2])) };
    const timestamp = Date.parse(text);
    if (Number.isNaN(timestamp)) return null;
    const date = new Date(timestamp);
    return { year: String(date.getFullYear()), month: String(date.getMonth() + 1), day: String(date.getDate()) };
  }

  function formatDateParts(parts, hint, inputType = "text") {
    if (!parts) return "";
    const day = parts.day.padStart(2, "0");
    const month = parts.month.padStart(2, "0");
    const year = parts.year.padStart(4, "0");
    if (inputType === "date") return `${year}-${month}-${day}`;

    const normalized = String(hint || "").toLowerCase();
    const positions = {
      day: normalized.search(/(?:\bdd\b|\bday\b)/),
      month: normalized.search(/(?:\bmm\b|\bmonth\b)/),
      year: normalized.search(/(?:\byyyy\b|\byear\b)/)
    };
    const ordered = Object.entries(positions).filter(([, position]) => position >= 0).sort((left, right) => left[1] - right[1]).map(([part]) => part);
    const values = { day, month, year };
    if (ordered.length === 3) return ordered.map((part) => values[part]).join("/");
    return `${day}/${month}/${year}`;
  }

  return { formatDateParts, parseDateParts };
});
