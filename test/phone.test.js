const test = require("node:test");
const assert = require("node:assert/strict");
const { countryCodeDigits, valueForField } = require("../Extension/lib/phone.js");

test("country code text fields receive only the saved dialing code", () => {
  const phone = { value: "09012345678", countryCode: "81" };
  assert.equal(countryCodeDigits(phone), "81");
  assert.equal(valueForField(phone, true), "81");
  assert.equal(valueForField(phone, false), "9012345678");
});

test("international phone values can provide a dialing code", () => {
  const phone = { value: "+81 90-1234-5678" };
  assert.equal(valueForField(phone, true), "81");
  assert.equal(valueForField(phone, false), "9012345678");
});

test("country code fields are not filled when no code was saved", () => {
  assert.equal(valueForField({ value: "09012345678" }, true), "");
});
