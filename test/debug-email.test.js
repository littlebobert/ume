const test = require("node:test");
const assert = require("node:assert/strict");
const { buildDebugEmail } = require("../Extension/lib/debug-email.js");

function parsedEmail(log, options = {}) {
  const url = new URL(buildDebugEmail(log, options));
  return {
    recipient: url.pathname,
    subject: url.searchParams.get("subject"),
    body: url.searchParams.get("body")
  };
}

test("drafts a reviewable support email with log and app context", () => {
  const email = parsedEmail("[2026-08-12] FILL ERROR\nSomething failed", { version: "0.1.6", platform: "mac" });
  assert.equal(email.recipient, "justin.garcia@gmail.com");
  assert.equal(email.subject, "Ume debug logs");
  assert.match(email.body, /Hi Justin,/);
  assert.match(email.body, /Ume version: 0\.1\.6/);
  assert.match(email.body, /Platform: mac/);
  assert.match(email.body, /FILL ERROR/);
});

test("preserves unicode log text", () => {
  const email = parsedEmail("国の選択を改善しました。", { version: "1", platform: "ios" });
  assert.match(email.body, /国の選択を改善しました。/);
});

test("limits mailto size and keeps the newest log content", () => {
  const email = parsedEmail(`old-${"x".repeat(20)}-new`, { maxLogLength: 10 });
  assert.doesNotMatch(email.body, /old-/);
  assert.match(email.body, /-new/);
  assert.match(email.body, /most recent 10 characters/);
  assert.match(email.body, /use Copy in Ume for the complete log/);
});
