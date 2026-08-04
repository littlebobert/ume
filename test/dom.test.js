const test = require("node:test");
const assert = require("node:assert/strict");
const { deepQuerySelectorAll } = require("../Extension/lib/dom.js");

function element(name, children = [], shadowRoot = null) {
  return {
    name,
    children,
    shadowRoot,
    matches(selector) {
      return selector.split(",").map((part) => part.trim()).includes(name);
    }
  };
}

function root(...children) {
  return { children };
}

test("finds controls in the document and nested open shadow roots", () => {
  const firstName = element("input");
  const birthMonth = element("select");
  const nestedHost = element("adc-select", [], root(birthMonth));
  const firstNameHost = element("adc-text-input", [], root(firstName, nestedHost));
  const ordinaryTextarea = element("textarea");
  const documentRoot = root(firstNameHost, ordinaryTextarea);

  assert.deepEqual(
    deepQuerySelectorAll("input, select, textarea", documentRoot),
    [firstName, birthMonth, ordinaryTextarea]
  );
});

test("does not return matching shadow hosts unless they match the selector", () => {
  const host = element("adc-text-input", [], root(element("input")));
  assert.equal(deepQuerySelectorAll("input, select, textarea", root(host)).length, 1);
});
