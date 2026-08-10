(function (root, factory) {
  const matcher = typeof module === "object" && module.exports ? require("./matcher.js") : root.UmeMatcher;
  const api = factory(matcher);
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.UmePhone = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function (UmeMatcher) {
  "use strict";

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

  function valueForField(saved, callingCodeField) {
    const code = countryCodeDigits(saved);
    if (callingCodeField) return code;
    return localNumberDigits(saved, code || (String(saved?.value ?? "").trim().startsWith("+") ? countryCodeDigits(saved) : ""));
  }

  function callingCodeFromOption(value, label) {
    const codePart = String(value || "").split("|", 1)[0].trim();
    if (/^\+?\d(?:[\s-]?\d){0,4}$/.test(codePart)) return digitsOnly(codePart);
    const match = String(label || "").match(/\+(\d(?:[\s-]?\d){0,4})(?:\D|$)/);
    return match ? digitsOnly(match[1]) : "";
  }

  function resolveCountryCode(savedEntries, relatedPhoneField) {
    const phones = (savedEntries || []).filter((saved) => UmeMatcher.answerType(saved) === "phone" && countryCodeDigits(saved));
    const codes = [...new Set(phones.map(countryCodeDigits))];
    const completed = phones.filter((saved) => localNumberDigits(saved, countryCodeDigits(saved)));
    const completedCodes = [...new Set(completed.map(countryCodeDigits))];

    if (completedCodes.length === 1) {
      return { codes, saved: completed[0], result: codes.length === 1 ? "single saved country code" : "preferred completed phone" };
    }
    if (relatedPhoneField && completed.length > 1) {
      const contextual = UmeMatcher.bestMatch(completed, relatedPhoneField);
      if (contextual) return { codes, saved: contextual, result: "matched related phone field" };
    }
    if (codes.length === 1) return { codes, saved: phones[0], result: "single saved country code" };
    return { codes, saved: null, result: codes.length ? "conflicting saved country codes" : "no saved phone country code" };
  }

  return { callingCodeFromOption, countryCodeDigits, digitsOnly, localNumberDigits, resolveCountryCode, valueForField };
});
