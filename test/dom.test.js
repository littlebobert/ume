const test = require("node:test");
const assert = require("node:assert/strict");
const { deepQuerySelectorAll, isRendered, isUserVisible } = require("../Extension/lib/dom.js");

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

function control({ type = "text", rects = 1, visibility = "visible", labels = [], wrappingLabel = null } = {}) {
  return {
    type,
    labels,
    style: { visibility },
    getClientRects: () => Array.from({ length: rects }, () => ({})),
    closest: (selector) => (selector === "label" ? wrappingLabel : null)
  };
}

const styleOf = (node) => node.style;

test("hidden fields are not rendered: display none, visibility hidden, or detached", () => {
  assert.equal(isRendered(control(), styleOf), true);
  assert.equal(isRendered(control({ rects: 0 }), styleOf), false, "display: none on the field or an ancestor");
  assert.equal(isRendered(control({ visibility: "hidden" }), styleOf), false);
  assert.equal(isRendered(control({ visibility: "collapse" }), styleOf), false);
  assert.equal(isRendered(null, styleOf), false);
});

test("alternate phone inputs hidden behind tabs are skipped, the visible one is kept", () => {
  const mobile = control({ type: "tel" });
  const office = control({ type: "tel", rects: 0 });
  const home = control({ type: "tel", rects: 0 });
  assert.deepEqual([mobile, office, home].filter((field) => isUserVisible(field, styleOf)), [mobile]);
});

test("visually hidden radios and checkboxes count as visible through their label", () => {
  const visibleLabel = control({ type: "" });
  const hiddenLabel = control({ type: "", rects: 0 });
  assert.equal(isUserVisible(control({ type: "radio", rects: 0, labels: [visibleLabel] }), styleOf), true);
  assert.equal(isUserVisible(control({ type: "checkbox", rects: 0, wrappingLabel: visibleLabel }), styleOf), true);
  assert.equal(isUserVisible(control({ type: "radio", rects: 0, labels: [hiddenLabel] }), styleOf), false, "a whole hidden section stays hidden");
  assert.equal(isUserVisible(control({ type: "text", rects: 0, labels: [visibleLabel] }), styleOf), false, "only radios and checkboxes use the label");
});
