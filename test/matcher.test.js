const test = require("node:test");
const assert = require("node:assert/strict");
const { addressFieldPart, addressValue, answerType, bestMatch, compatible, looksGenerated, mergeEntries, normalize, score } = require("../Extension/lib/matcher.js");

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

test("incompatible input types never match for ordinary answers", () => {
  const saved = entry({ accessibleName: "Quantity", inputType: "date" });
  const field = entry({ accessibleName: "Quantity", inputType: "number" });
  assert.equal(bestMatch([saved], field), null);
});

test("phone answers are incompatible with travel identifier fields", () => {
  const phone = entry({ accessibleName: "Phone number", name: "traveler.phone.mobileNumber", value: "090-1234-5678" });
  for (const label of ["Frequent flyer number", "Redress Number", "Known Traveler Number or PASS ID"]) {
    const field = entry({ accessibleName: label, name: label.replaceAll(" ", ".") });
    assert.equal(compatible(phone, field), false);
    assert.equal(bestMatch([phone], field), null);
  }
});

test("untyped phone answers match phone fields via context", () => {
  const phone = entry({ accessibleName: "Phone number", name: "traveler.phone.mobileNumber", value: "090-1234-5678" });
  const field = entry({ accessibleName: "Contact phone" });
  assert.equal(compatible(phone, field), true);
});

test("semantically equivalent phone fields remain compatible", () => {
  const phone = entry({ accessibleName: "Phone number", value: "090-1234-5678" });
  assert.equal(compatible(phone, entry({ accessibleName: "Mobile telephone" })), true);
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

test("answerType falls back to semantic detection and validates explicit values", () => {
  assert.equal(answerType(entry({ accessibleName: "Date of birth" })), "date");
  assert.equal(answerType(entry({ accessibleName: "Mobile phone" })), "phone");
  assert.equal(answerType(entry({ accessibleName: "Calling code" })), "phone");
  assert.equal(answerType(entry({ accessibleName: "First name" })), "");
  assert.equal(answerType(entry({ accessibleName: "Contact", answerType: "gender" })), "gender");
  assert.equal(answerType(entry({ accessibleName: "Home", answerType: "address", kind: "aggregate" })), "address");
  assert.equal(answerType(entry({ accessibleName: "Contact", answerType: "bogus" })), "");
});

test("typed phone answers match phone and calling code fields but not identifiers", () => {
  const phone = entry({ answerType: "phone", accessibleName: "Contact", value: "15551234567", countryCode: "1" });
  assert.equal(compatible(phone, entry({ accessibleName: "Phone number" })), true);
  assert.equal(compatible(phone, entry({ accessibleName: "Country code" })), true);
  assert.equal(compatible(phone, entry({ accessibleName: "Calling code" })), true);
  assert.equal(compatible(phone, entry({ accessibleName: "Country code", kind: "select" })), true);
  assert.equal(compatible(phone, entry({ accessibleName: "Redress number" })), false);
});

test("typed answers require compatible field kinds and semantics", () => {
  const date = entry({ answerType: "date", accessibleName: "Date of birth" });
  assert.equal(compatible(date, entry({ accessibleName: "Anything", kind: "select" })), false);
  assert.equal(compatible(date, entry({ accessibleName: "Anything", kind: "text" })), false);
  assert.equal(compatible(date, entry({ accessibleName: "Date of birth", kind: "text" })), true);
});

test("gender answers match radio groups and dropdowns but not phone fields", () => {
  const gender = entry({ answerType: "gender", accessibleName: "Gender", value: "Female" });
  assert.equal(compatible(gender, entry({ accessibleName: "Gender", kind: "radio", value: "female" })), true);
  assert.equal(compatible(gender, entry({ accessibleName: "Title", kind: "radio", value: "mr" })), true);
  assert.equal(compatible(gender, entry({ accessibleName: "Department", kind: "radio", value: "engineering" })), false);
  assert.equal(compatible(gender, entry({ accessibleName: "Gender", kind: "select" })), true);
  assert.equal(compatible(gender, entry({ accessibleName: "Gender", kind: "text" })), true);
  assert.equal(compatible(gender, entry({ accessibleName: "Phone number", kind: "text" })), false);
});

test("remembered gender controls match dropdowns with a different HTML input type", () => {
  const gender = entry({
    answerType: "gender",
    accessibleName: "Gender",
    inputType: "radio",
    kind: "radio",
    value: "Female"
  });
  const unitedGender = entry({
    accessibleName: "Gender(required)",
    inputType: "select-one",
    kind: "select",
    name: "rtiTraveler.travelers[0].gender"
  });
  assert.equal(bestMatch([gender], unitedGender), gender);
});

test("legacy countrycode answers are treated as phone", () => {
  const legacy = entry({ answerType: "countrycode", accessibleName: "Country code", value: "81" });
  assert.equal(answerType(legacy), "phone");
});

test("date answers match split month, day, and year fields", () => {
  const dob = entry({ answerType: "date", accessibleName: "Date of birth", value: "1962-04-18" });
  assert.ok(bestMatch([dob], entry({ accessibleName: "Month", kind: "select", name: "dob.month" })));
  assert.ok(bestMatch([dob], entry({ accessibleName: "DD", kind: "select", name: "dob.day" })));
  assert.ok(bestMatch([dob], entry({ accessibleName: "YYYY", kind: "select", name: "dob.year" })));
  assert.ok(bestMatch([dob], entry({ accessibleName: "Birth month", autocomplete: "bday-month" })));
  assert.equal(bestMatch([dob], entry({ accessibleName: "State", kind: "select" })), null);
});

test("phone answers match country calling code dropdowns", () => {
  const phone = entry({ answerType: "phone", accessibleName: "Phone number", value: "09012345678", countryCode: "81" });
  assert.ok(bestMatch([phone], entry({ accessibleName: "Country calling code", kind: "select", name: "phone.cc" })));
});

test("typed phone answers never match unlabeled document number fields", () => {
  const phone = entry({ answerType: "phone", accessibleName: "Phone number", value: "09012345678", countryCode: "81" });
  const documentNumber = entry({ name: "docNumber", id: "adc-input-S-23BB" });
  assert.equal(compatible(phone, documentNumber), false);
  assert.equal(bestMatch([phone], documentNumber), null);
});

test("birth dates never match document expiration or issue dates", () => {
  const birthday = entry({ answerType: "date", accessibleName: "Date of birth", value: "1962-04-18" });
  for (const field of [
    entry({ accessibleName: "Document expiration date", inputType: "date" }),
    entry({ accessibleName: "Passport expiry month", kind: "select" }),
    entry({ name: "documentExpirationYear", kind: "select" }),
    entry({ accessibleName: "Document issue date", inputType: "date" })
  ]) {
    assert.equal(compatible(birthday, field), false);
    assert.equal(bestMatch([birthday], field), null);
  }
});

test("typed special answers require a positively identified destination", () => {
  const birthday = entry({ answerType: "date", accessibleName: "Date of birth", value: "1962-04-18" });
  const phone = entry({ answerType: "phone", accessibleName: "Phone number", value: "09012345678" });
  const gender = entry({ answerType: "gender", accessibleName: "Gender", value: "Female" });
  const anonymous = entry({ id: "generated-control" });
  assert.equal(compatible(birthday, anonymous), false);
  assert.equal(compatible(phone, anonymous), false);
  assert.equal(compatible(gender, anonymous), false);
});

test("full birthday controls are recognized through autocomplete", () => {
  const birthday = entry({ answerType: "date", accessibleName: "Date of birth", value: "1962-04-18" });
  assert.equal(compatible(birthday, entry({ autocomplete: "bday", inputType: "date" })), true);
});

test("structured addresses match standard address components", () => {
  const address = entry({
    answerType: "address",
    accessibleName: "Home address",
    inputType: "",
    kind: "aggregate",
    value: {
      addressLine1: "123 Main Street",
      addressLine2: "Apt 4B",
      locality: "Tampa",
      administrativeArea: "FL",
      postalCode: "33602",
      countryCode: "US",
      countryName: "United States"
    }
  });
  const fields = [
    ["address-line1", "addressLine1", "123 Main Street"],
    ["address-line2", "addressLine2", "Apt 4B"],
    ["address-level2", "locality", "Tampa"],
    ["address-level1", "administrativeArea", "FL"],
    ["postal-code", "postalCode", "33602"],
    ["country-name", "country", "United States"]
  ];
  for (const [autocomplete, part, value] of fields) {
    const field = entry({ autocomplete, inputType: autocomplete === "country-name" ? "select-one" : "text", kind: autocomplete === "country-name" ? "select" : "text" });
    assert.equal(addressFieldPart(field), part);
    assert.equal(addressValue(address, field), value);
    assert.equal(bestMatch([address], field), address);
  }
});

test("structured addresses fill street-address textareas and skip empty optional components", () => {
  const address = entry({
    answerType: "address",
    kind: "aggregate",
    value: { addressLine1: "東京都渋谷区神宮前1-2-3", addressLine2: "梅ビル405", countryCode: "JP", countryName: "Japan" }
  });
  assert.equal(addressValue(address, entry({ autocomplete: "street-address", kind: "textarea" })), "東京都渋谷区神宮前1-2-3\n梅ビル405");
  address.value.addressLine2 = "";
  assert.equal(bestMatch([address], entry({ autocomplete: "address-line2" })), null);
});

test("address country autocomplete is not treated as a phone field", () => {
  const address = entry({ answerType: "address", kind: "aggregate", value: { countryCode: "US", countryName: "United States" } });
  const country = entry({ accessibleName: "Country code", autocomplete: "country", kind: "select", inputType: "select-one" });
  assert.equal(addressFieldPart(country), "country");
  assert.equal(compatible(address, country), true);
  assert.equal(answerType(country), "");
});

test("generic address labels remain recognizable with generated control IDs", () => {
  assert.equal(addressFieldPart(entry({ accessibleName: "City", id: "f47ac10b-58cc-4372-a567-0e02b2c3d479" })), "locality");
  assert.equal(addressFieldPart(entry({ accessibleName: "State", id: "adc-input-S-23BB9102" })), "administrativeArea");
  assert.equal(addressFieldPart(entry({ accessibleName: "Country", id: "control-1749285123456" })), "country");
});

test("unrelated address labels and phone country codes are not address components", () => {
  assert.equal(addressFieldPart(entry({ accessibleName: "Email address" })), "");
  assert.equal(addressFieldPart(entry({ accessibleName: "IP address" })), "");
  assert.equal(addressFieldPart(entry({ accessibleName: "Country code" })), "");
  assert.equal(addressFieldPart(entry({ accessibleName: "Country", autocomplete: "tel-country-code", kind: "select" })), "");
  assert.equal(addressFieldPart(entry({ accessibleName: "Business unit" })), "");
  assert.equal(addressFieldPart(entry({ accessibleName: "Unit price" })), "");
  assert.equal(addressFieldPart(entry({ accessibleName: "Apartment type" })), "");
  assert.equal(addressFieldPart(entry({ accessibleName: "Building access code" })), "");
});

test("secondary address fallbacks require a dedicated line-two label or name", () => {
  assert.equal(addressFieldPart(entry({ accessibleName: "Apartment, suite, building, etc." })), "addressLine2");
  assert.equal(addressFieldPart(entry({ name: "shippingAddressLine2" })), "addressLine2");
});

test("multiple structured addresses are treated as ambiguous", () => {
  const first = entry({ answerType: "address", kind: "aggregate", value: { locality: "Tokyo" } });
  const second = entry({ answerType: "address", kind: "aggregate", value: { locality: "Tampa" } });
  assert.equal(bestMatch([first, second], entry({ autocomplete: "address-level2" })), null);
});

test("confirmation fields reuse their corresponding saved answer", () => {
  const email = entry({ accessibleName: "Email", inputType: "email", value: "hanako@example.com" });
  for (const label of ["Confirm email", "Re-enter email", "Verify email"]) {
    assert.equal(bestMatch([email], entry({ accessibleName: label, inputType: "email" })), email);
  }
});

test("confirmation matching preserves the underlying field identity", () => {
  const email = entry({ accessibleName: "Email address", inputType: "email", value: "hanako@example.com" });
  const phone = entry({ answerType: "phone", accessibleName: "Phone number", value: "09012345678" });
  assert.equal(bestMatch([email, phone], entry({ accessibleName: "Confirm email address", inputType: "email" })), email);
});
