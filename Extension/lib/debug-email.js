(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.UmeDebugEmail = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  const DEFAULT_MAX_LOG_LENGTH = 16_000;

  function buildDebugEmail(log, options = {}) {
    const recipient = options.recipient || "justin.garcia@gmail.com";
    const version = options.version || "unknown";
    const platform = options.platform || "unknown";
    const maxLogLength = Number.isFinite(options.maxLogLength) && options.maxLogLength > 0
      ? Math.floor(options.maxLogLength)
      : DEFAULT_MAX_LOG_LENGTH;
    const fullLog = String(log || "No extension debug entries yet.");
    const truncated = fullLog.length > maxLogLength;
    const includedLog = truncated ? fullLog.slice(-maxLogLength) : fullLog;
    const body = [
      "Hi Justin,",
      "",
      "I'm sending Ume extension debug logs for review.",
      `Ume version: ${version}`,
      `Platform: ${platform}`,
      ...(truncated ? ["", `The log exceeded the email limit. The most recent ${maxLogLength.toLocaleString("en-US")} characters are included; use Copy in Ume for the complete log.`] : []),
      "",
      "--- Ume Debug Logs ---",
      includedLog
    ].join("\r\n");
    return `mailto:${recipient}?subject=${encodeURIComponent("Ume debug logs")}&body=${encodeURIComponent(body)}`;
  }

  return { buildDebugEmail, DEFAULT_MAX_LOG_LENGTH };
});
