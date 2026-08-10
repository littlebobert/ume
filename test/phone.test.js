const test = require("node:test");
const assert = require("node:assert/strict");
const { callingCodeFromOption, countryCodeDigits, resolveCountryCode, valueForField } = require("../Extension/lib/phone.js");

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

test("calling codes are read from select values or labels", () => {
  assert.equal(callingCodeFromOption("81", "Japan +81"), "81");
  assert.equal(callingCodeFromOption("81|JP", "Japan +81"), "81");
  assert.equal(callingCodeFromOption("1|US", "United States +1"), "1");
  assert.equal(callingCodeFromOption("1 684|AS", "American Samoa +1 684"), "1684");
  assert.equal(callingCodeFromOption("JP", "Japan +81"), "81");
});

test("completed phones take precedence over a code-only learned default", () => {
  const japan = {
    answerType: "phone",
    accessibleName: "Phone number",
    inputType: "text",
    kind: "text",
    value: "09012345678",
    countryCode: "81"
  };
  const learnedDefault = {
    answerType: "phone",
    accessibleName: "Country calling code",
    inputType: "select-one",
    kind: "select",
    value: "United States +1",
    countryCode: "1"
  };
  const resolution = resolveCountryCode([japan, learnedDefault], {
    accessibleName: "Phone number",
    form: "Traveler 1: Justin Garcia",
    inputType: "tel",
    kind: "text",
    name: "rtiTraveler.travelers[0].extraDetails.phone.number"
  });
  assert.equal(resolution.saved, japan);
  assert.equal(resolution.result, "preferred completed phone");
  assert.deepEqual(resolution.codes, ["81", "1"]);
});

test("genuinely ambiguous completed phones do not choose a country code", () => {
  const first = {
    answerType: "phone",
    accessibleName: "Phone number",
    inputType: "text",
    kind: "text",
    value: "09012345678",
    countryCode: "81"
  };
  const second = { ...first, value: "4155550100", countryCode: "1" };
  const resolution = resolveCountryCode([first, second], {
    accessibleName: "Phone number",
    inputType: "tel",
    kind: "text"
  });
  assert.equal(resolution.saved, null);
  assert.equal(resolution.result, "conflicting saved country codes");
});

test("related phone context disambiguates two completed phone numbers", () => {
  const personal = {
    answerType: "phone",
    accessibleName: "Personal phone",
    group: "Traveler",
    inputType: "text",
    kind: "text",
    value: "09012345678",
    countryCode: "81"
  };
  const emergency = {
    ...personal,
    accessibleName: "Emergency contact phone",
    group: "Emergency contact",
    value: "4155550100",
    countryCode: "1"
  };
  const resolution = resolveCountryCode([personal, emergency], {
    accessibleName: "Phone number",
    form: "Traveler 1: Justin Garcia",
    group: "Traveler",
    inputType: "tel",
    kind: "text",
    name: "rtiTraveler.travelers[0].extraDetails.phone.number"
  });
  assert.equal(resolution.saved, personal);
  assert.equal(resolution.result, "matched related phone field");
});
