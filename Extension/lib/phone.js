(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.UmePhone = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
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

  return { countryCodeDigits, digitsOnly, localNumberDigits, valueForField };
});
