const test = require("node:test");
const assert = require("node:assert/strict");
const { formatDateParts, parseDateParts } = require("../Extension/lib/date.js");

const birthday = parseDateParts("1962-04-18");

test("masked day-month-year inputs receive a four-digit year", () => {
  assert.equal(formatDateParts(birthday, "Day / Month / Year", "text"), "18/04/1962");
  assert.equal(formatDateParts(birthday, "dd/mm/yyyy", "text"), "18/04/1962");
});

test("masked month-day-year inputs follow their placeholder order", () => {
  assert.equal(formatDateParts(birthday, "MM/DD/YYYY", "text"), "04/18/1962");
});

test("native date inputs receive ISO dates", () => {
  assert.equal(formatDateParts(birthday, "", "date"), "1962-04-18");
});

test("ambiguous text date inputs default to day-month-year", () => {
  assert.equal(formatDateParts(birthday, "Date of birth", "text"), "18/04/1962");
});
