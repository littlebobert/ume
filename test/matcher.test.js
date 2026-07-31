const test = require("node:test");
const assert = require("node:assert/strict");
const { bestMatch, looksGenerated, mergeEntries, normalize, score } = require("../Extension/lib/matcher.js");

const entry = (overrides = {}) => ({
  accessibleDescription: "",
  accessibleName: "",
  autocomplete: "",
  form: "",
  group: "",
  id: "",
  inputType: "text",
  kind: "text",
  label: "",
  name: "",
  placeholder: "",
  section: "",
  tableHeaders: [],
  value: "saved",
  ...overrides
});

test("normalizes punctuation, camel case, and diacritics", () => {
  assert.equal(normalize("EmergencyContact E-mail Áddress"), "emergency contact e mail address");
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

test("incompatible input types never match", () => {
  const saved = entry({ accessibleName: "Birthday", inputType: "date" });
  const field = entry({ accessibleName: "Birthday", inputType: "number" });
  assert.equal(bestMatch([saved], field), null);
});

test("ambiguous equal matches are rejected", () => {
  const first = entry({ label: "Phone number", value: "one" });
  const second = entry({ label: "Phone number", value: "two" });
  assert.equal(bestMatch([first, second], entry({ label: "Phone number" })), null);
});

test("group context distinguishes repeated labels", () => {
  const patient = entry({ accessibleName: "First name", group: "Patient", value: "Justin" });
  const emergency = entry({ accessibleName: "First name", group: "Emergency contact", value: "Jane" });
  const field = entry({ accessibleName: "First name", section: "Emergency contact" });
  assert.equal(bestMatch([patient, emergency], field), emergency);
});

test("conflicting context penalizes otherwise identical fields", () => {
  const saved = entry({ accessibleName: "Phone", group: "Patient" });
  const sameContext = entry({ accessibleName: "Phone", section: "Patient information" });
  const conflictingContext = entry({ accessibleName: "Phone", section: "Emergency contact" });
  assert.ok(score(saved, sameContext) > score(saved, conflictingContext));
});

test("generated identifiers are detected and weakly weighted", () => {
  assert.equal(looksGenerated("input_839102"), true);
  assert.equal(looksGenerated("emergencyContactPhone"), false);
  const generatedOnly = score(entry({ id: "input_839102" }), entry({ id: "input_839102" }));
  const semantic = score(entry({ id: "emergencyContactPhone" }), entry({ id: "emergencyContactPhone" }));
  assert.ok(semantic > generatedOnly);
});

test("user labels participate in semantic matching", () => {
  const saved = entry({ userLabel: "Mother's mobile phone", label: "Contact" });
  const field = entry({ accessibleName: "Mother mobile phone" });
  assert.equal(bestMatch([saved], field), saved);
});

test("merge updates a strongly matching saved answer and preserves its identity", () => {
  const previous = entry({ answerID: "answer-1", userLabel: "My email", autocomplete: "email", label: "Email", value: "old@example.com" });
  const next = entry({ autocomplete: "email", label: "Email address", value: "new@example.com" });
  const merged = mergeEntries([previous], [next]);
  assert.equal(merged.length, 1);
  assert.equal(merged[0].value, "new@example.com");
  assert.equal(merged[0].answerID, "answer-1");
  assert.equal(merged[0].userLabel, "My email");
});

test("merge assigns stable identities to new answers", () => {
  const merged = mergeEntries([], [entry({ label: "Email" })]);
  assert.equal(typeof merged[0].answerID, "string");
  assert.ok(merged[0].answerID.length > 10);
});
