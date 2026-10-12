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

  function defaultStyle(element) {
    return typeof getComputedStyle === "function" ? getComputedStyle(element) : null;
  }

  // True when the element takes up space on the page and isn't hidden with
  // `visibility`. `display: none` on the element or any ancestor leaves it
  // without client rects, which also covers collapsed tabs and closed <details>.
  function isRendered(element, getStyle = defaultStyle) {
    if (!element || typeof element.getClientRects !== "function") return false;
    if (!element.getClientRects().length) return false;
    const visibility = getStyle(element)?.visibility;
    return visibility !== "hidden" && visibility !== "collapse";
  }

  // Whether a person could see and use this control. Many sites hide the real
  // radio or checkbox input and style its label instead, so those count as
  // visible when a label for them is visible.
  function isUserVisible(element, getStyle = defaultStyle) {
    if (isRendered(element, getStyle)) return true;
    const type = String(element?.type || "").toLowerCase();
    if (type !== "radio" && type !== "checkbox") return false;
    const labels = [...(element.labels || [])];
    const wrapping = element.closest?.("label");
    if (wrapping && !labels.includes(wrapping)) labels.push(wrapping);
    return labels.some((label) => isRendered(label, getStyle));
  }

  return { deepQuerySelectorAll, isRendered, isUserVisible };
});
