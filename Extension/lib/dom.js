(function (root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.UmeDOM = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  "use strict";

  function deepQuerySelectorAll(selector, root = document) {
    const matches = [];

    function visit(element) {
      if (element.matches?.(selector)) matches.push(element);
      if (element.shadowRoot) visitRoot(element.shadowRoot);
      for (const child of element.children || []) visit(child);
    }

    function visitRoot(currentRoot) {
      for (const child of currentRoot.children || []) visit(child);
    }

    visitRoot(root);
    return matches;
  }

  return { deepQuerySelectorAll };
});
