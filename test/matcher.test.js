const test = require("node:test");
const assert = require("node:assert/strict");
const { bestMatch, mergeEntries, normalize, score } = require("../Extension/lib/matcher.js");

const entry = (overrides = {}) => ({
  autocomplete: "",
  id: "",
  kind: "text",
  label: "",
  name: "",
  placeholder: "",
  value: "saved",
  ...overrides
});

test("normalizes punctuation and diacritics", () => {
  assert.equal(normalize("  E-mail Áddress  "), "e mail address");
});

test("autocomplete creates a strong match", () => {
  assert.ok(score(entry({ autocomplete: "email" }), entry({ autocomplete: "email" })) >= 100);
});

test("similar labels match across differently named forms", () => {
  const saved = entry({ label: "Emergency contact phone number", name: "contact_phone" });
  const field = entry({ label: "Emergency contact phone", name: "emergencyPhone" });
  assert.equal(bestMatch([saved], field), saved);
});

test("different field kinds never match", () => {
  const saved = entry({ label: "State", kind: "select" });
  const field = entry({ label: "State", kind: "text" });
  assert.equal(bestMatch([saved], field), null);
});

test("ambiguous equal matches are rejected", () => {
  const first = entry({ label: "Phone number", value: "one" });
  const second = entry({ label: "Phone number", value: "two" });
  assert.equal(bestMatch([first, second], entry({ label: "Phone number" })), null);
});

test("merge updates a strongly matching saved answer", () => {
  const previous = entry({ autocomplete: "email", label: "Email", value: "old@example.com" });
  const next = entry({ autocomplete: "email", label: "Email address", value: "new@example.com" });
  const merged = mergeEntries([previous], [next]);
  assert.equal(merged.length, 1);
  assert.equal(merged[0].value, "new@example.com");
});
