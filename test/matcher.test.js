const test = require("node:test");
const assert = require("node:assert/strict");
const { addressFieldPart, addressValue, answerType, bestMatch, compatible, contactFieldInfo, contactParts, contactValue, looksGenerated, mergeEntries, nameFieldPart, normalize, score, selectOptionIndex } = require("../Extension/lib/matcher.js");

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

test("select options match country names independently of case and ISO-valued options", () => {
  const options = [
    { text: "Select a country", value: "" },
    { text: "UNITED STATES ", value: "US" },
    { text: "JAPAN ", value: "JP" }
  ];
  assert.equal(selectOptionIndex(options, "United States"), 1);
  assert.equal(selectOptionIndex(options, "US"), 1);
  assert.equal(selectOptionIndex(options, "Japan"), 2);
  assert.equal(selectOptionIndex(options, "Not a country"), -1);
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

test("country of residence uses the saved address country", () => {
  const address = entry({
    answerType: "address",
    kind: "aggregate",
    value: { addressLine1: "1-2-3 Jingumae", countryCode: "JP", countryName: "Japan" }
  });
  for (const label of ["Country of residence", "Country / region of residence", "Residence country"]) {
    const field = entry({ accessibleName: label, kind: "select", inputType: "select-one" });
    assert.equal(addressFieldPart(field), "country");
    assert.equal(bestMatch([address], field), address);
  }
});

test("nationality and country of birth are not treated as the address country", () => {
  assert.equal(addressFieldPart(entry({ accessibleName: "Nationality" })), "");
  assert.equal(addressFieldPart(entry({ accessibleName: "Country of citizenship" })), "");
  assert.equal(addressFieldPart(entry({ accessibleName: "Country of birth" })), "");
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

test("name field parts are recognized from labels and autocomplete", () => {
  assert.equal(nameFieldPart(entry({ accessibleName: "First name" })), "given");
  assert.equal(nameFieldPart(entry({ accessibleName: "Last name" })), "family");
  assert.equal(nameFieldPart(entry({ accessibleName: "Full name" })), "full");
  assert.equal(nameFieldPart(entry({ accessibleName: "Name" })), "full");
  assert.equal(nameFieldPart(entry({ autocomplete: "name" })), "full");
  assert.equal(nameFieldPart(entry({ accessibleName: "Username" })), "");
});

test("full name fields are composed from first and last names", () => {
  const first = entry({ accessibleName: "First name", value: "Justin" });
  const last = entry({ accessibleName: "Last name", value: "Garcia" });
  const match = bestMatch([first, last], entry({ accessibleName: "Full name" }));
  assert.equal(match.value, "Justin Garcia");
});

test("an explicit full name answer is preferred over composing parts", () => {
  const first = entry({ accessibleName: "First name", value: "Justin" });
  const last = entry({ accessibleName: "Last name", value: "Garcia" });
  const full = entry({ accessibleName: "Full name", value: "J. Garcia" });
  assert.equal(bestMatch([first, last, full], entry({ accessibleName: "Full name" })), full);
});

test("full name fields are not filled from only a first name", () => {
  const first = entry({ accessibleName: "First name", value: "Justin" });
  assert.equal(bestMatch([first], entry({ accessibleName: "Full name" })), null);
});

test("grouped first and last names compose the matching full name", () => {
  const first = entry({ accessibleName: "First name", group: "Traveler", value: "Justin" });
  const last = entry({ accessibleName: "Last name", group: "Traveler", value: "Garcia" });
  const otherFirst = entry({ accessibleName: "First name", group: "Emergency contact", value: "Jane" });
  const otherLast = entry({ accessibleName: "Last name", group: "Emergency contact", value: "Doe" });
  const match = bestMatch([first, last, otherFirst, otherLast], entry({ accessibleName: "Full name", section: "Traveler" }));
  assert.equal(match.value, "Justin Garcia");
});

const contact = (category, role, name, extra = {}) => entry({
  answerType: "contact",
  kind: "aggregate",
  inputType: "",
  userLabel: name,
  accessibleName: name,
  label: name,
  value: { version: 1, category, role, name, ...extra }
});

const doctors = () => [
  contact("doctor", "Primary care", "Dr. Sakura Ito", { phone: "03-1234-5678", organization: "Ito Family Clinic" }),
  contact("doctor", "Cardiologist", "Dr. Anita Patel", { phone: "813-555-0200", fax: "813-555-0201", address: "500 Heart Way, Tampa, FL 33602" })
];

const emergencyContacts = () => [
  contact("emergencyContact", "Daughter", "Hanako Yamada", { phone: "080-9876-5432" }),
  contact("emergencyContact", "Son", "Taro Yamada", { phone: "080-1111-2222" })
];

test("contact fields are recognized by category, part, and specialty", () => {
  const info = (overrides) => {
    const result = contactFieldInfo(entry(overrides));
    return result ? { category: result.category, part: result.part, specialty: result.specialty, ordinal: result.ordinal } : null;
  };
  assert.deepEqual(info({ accessibleName: "Primary care physician" }), { category: "doctor", part: "name", specialty: 0, ordinal: -1 });
  assert.deepEqual(info({ accessibleName: "Cardiologist phone" }), { category: "doctor", part: "phone", specialty: 1, ordinal: -1 });
  assert.deepEqual(info({ accessibleName: "Referring physician fax" }), { category: "doctor", part: "fax", specialty: -1, ordinal: -1 });
  assert.deepEqual(info({ accessibleName: "Emergency contact name" }), { category: "emergencyContact", part: "name", specialty: -1, ordinal: -1 });
  assert.deepEqual(info({ accessibleName: "Emergency contact phone number", name: "emergency_contact_phone" }), { category: "emergencyContact", part: "phone", specialty: -1, ordinal: -1 });
  assert.deepEqual(info({ accessibleName: "Emergency contact 2 phone" }), { category: "emergencyContact", part: "phone", specialty: -1, ordinal: 1 });
  assert.deepEqual(info({ accessibleName: "Relationship", group: "Emergency contact" }), { category: "emergencyContact", part: "role", specialty: -1, ordinal: -1 });
  assert.deepEqual(info({ accessibleName: "Phone", section: "In case of emergency" }), { category: "emergencyContact", part: "phone", specialty: -1, ordinal: -1 });
  assert.deepEqual(info({ accessibleName: "Practice name", section: "Primary care physician" }), { category: "doctor", part: "organization", specialty: 0, ordinal: -1 });
  assert.equal(info({ accessibleName: "Your phone", section: "Emergency contact" }), null);
  assert.equal(info({ accessibleName: "Name", section: "Emergency department intake" }), null);
  assert.equal(info({ accessibleName: "Physician license number" }), null);
  assert.equal(info({ accessibleName: "Insurance provider" }), null);
  assert.equal(info({ accessibleName: "Mobile phone", autocomplete: "tel" }), null);
  assert.equal(info({ accessibleName: "Who normally manages your care?", id: "portal-doctor" }), null);
  assert.equal(info({ accessibleName: "Date of last doctor visit" }), null);
});

test("doctor fields pick the saved doctor by specialty", () => {
  const [pcp, cardiologist] = doctors();
  const saved = [...doctors(), entry({ accessibleName: "Phone number", autocomplete: "tel", answerType: "phone", value: "090-1234-5678" })];
  const pick = (overrides) => bestMatch(saved, entry(overrides));
  assert.equal(pick({ accessibleName: "Primary care physician" }).userLabel, pcp.userLabel);
  assert.equal(pick({ accessibleName: "Primary physician", name: "primary_physician" }).userLabel, pcp.userLabel);
  assert.equal(pick({ accessibleName: "Cardiologist phone" }).userLabel, cardiologist.userLabel);
  assert.equal(pick({ accessibleName: "Cardiologist fax" }).userLabel, cardiologist.userLabel);
  assert.equal(pick({ accessibleName: "Physician name" }).userLabel, pcp.userLabel, "no specialty hint prefers the primary care doctor");
  assert.equal(pick({ accessibleName: "Specialist name" }).userLabel, cardiologist.userLabel);
  assert.equal(pick({ accessibleName: "Dermatologist phone" }), null, "unknown specialties are not guessed");
  assert.equal(pick({ accessibleName: "Primary care physician fax" }), null, "missing parts are not filled");
  assert.equal(contactValue(cardiologist, entry({ accessibleName: "Cardiologist address" })), "500 Heart Way, Tampa, FL 33602");
  assert.equal(contactValue(pcp, entry({ accessibleName: "Practice", section: "Primary care physician" })), "Ito Family Clinic");
  assert.equal(contactValue(pcp, entry({ accessibleName: "Physician last name" })), "Ito");
  assert.equal(contactValue(pcp, entry({ accessibleName: "Physician first name" })), "Sakura");
});

test("emergency contact fields use ordinals, relationships, and name parts", () => {
  const [daughter, son] = emergencyContacts();
  const saved = [...emergencyContacts(), ...doctors()];
  const pick = (overrides) => bestMatch(saved, entry(overrides));
  assert.equal(pick({ accessibleName: "Emergency contact phone number" }).userLabel, daughter.userLabel);
  assert.equal(pick({ accessibleName: "Emergency contact 2 phone" }).userLabel, son.userLabel);
  assert.equal(pick({ accessibleName: "Emergency contact 3 phone" }), null);
  assert.equal(pick({ accessibleName: "Secondary emergency contact name" }).userLabel, son.userLabel);
  const relationship = entry({ accessibleName: "Relationship", group: "Emergency contact", kind: "select" });
  assert.equal(pick(relationship).userLabel, daughter.userLabel);
  assert.equal(contactValue(daughter, relationship), "Daughter");
  assert.equal(contactValue(daughter, entry({ accessibleName: "Emergency contact first name" })), "Hanako");
  assert.equal(contactValue(daughter, entry({ accessibleName: "Emergency contact last name" })), "Yamada");
  assert.equal(pick({ accessibleName: "Emergency", kind: "checkbox", inputType: "checkbox" }), null);
});

test("your own answers never fill contact fields, and remembered contact answers stay with contact fields", () => {
  const ownPhone = entry({ accessibleName: "Phone number", autocomplete: "tel", answerType: "phone", value: "090-1234-5678" });
  const emergencyField = entry({ accessibleName: "Emergency contact phone number", name: "emergency_contact_phone", inputType: "tel" });
  assert.equal(bestMatch([ownPhone], emergencyField), null);
  assert.equal(bestMatch([ownPhone, ...emergencyContacts()], emergencyField).userLabel, "Hanako Yamada");

  const remembered = entry({ ...emergencyField, value: "080-9876-5432" });
  assert.equal(bestMatch([remembered, ownPhone], entry({ accessibleName: "Emergency contact phone", inputType: "tel" })), remembered);
  assert.equal(bestMatch([remembered], entry({ accessibleName: "Mobile phone", autocomplete: "tel", inputType: "tel" })), null);

  const given = entry({ autocomplete: "given-name", value: "Hanako" });
  const family = entry({ autocomplete: "family-name", value: "Yamada" });
  assert.equal(bestMatch([given, family], entry({ accessibleName: "Emergency contact full name" })), null);
  assert.equal(bestMatch([given, family], entry({ accessibleName: "Full name" }))?.value, "Hanako Yamada");
});

test("contacts flatten into sanitized parts for AI mapping and never merge with remembered answers", () => {
  const [, cardiologist] = doctors();
  const parts = contactParts(cardiologist);
  assert.deepEqual(parts.map((item) => item.part), ["name", "role", "phone", "fax", "address"]);
  const phone = parts.find((item) => item.part === "phone").entry;
  assert.equal(phone.accessibleName, "Doctor, Cardiologist phone");
  assert.equal(phone.inputType, "tel");
  assert.equal(phone.value, "813-555-0200");
  assert.equal(parts.find((item) => item.part === "role").entry.accessibleName, "Doctor, Cardiologist specialty");
  assert.equal(contactParts(emergencyContacts()[0]).find((item) => item.part === "role").entry.label, "Emergency contact, Daughter relationship");

  const incoming = entry({ accessibleName: "Cardiologist phone", inputType: "tel", value: "813-555-0200" });
  assert.equal(mergeEntries([cardiologist], [incoming]).length, 2);
  assert.equal(score(cardiologist, incoming), -Infinity);
  assert.equal(answerType(cardiologist), "contact");
});
