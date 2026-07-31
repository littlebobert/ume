(() => {
  "use strict";

  const tabs = [...document.querySelectorAll(".tab")];
  const panels = {
    learn: document.getElementById("learn-panel"),
    replay: document.getElementById("replay-panel"),
    different: document.getElementById("different-panel")
  };

  for (const tab of tabs) {
    tab.addEventListener("click", () => {
      for (const candidate of tabs) candidate.classList.toggle("active", candidate === tab);
      for (const [name, panel] of Object.entries(panels)) panel.hidden = name !== tab.dataset.form;
      history.replaceState(null, "", `#${tab.dataset.form}`);
    });
  }

  const expected = {
    patientGiven: "Hanako",
    patientFamily: "Yamada",
    dobValue: "1962-04-18",
    contactEmail: "hanako@example.com",
    mobileNumber: "090-1234-5678",
    emergencyPerson: "Taro Yamada",
    emergencyPhone: "080-9876-5432",
    patientBloodGroup: "B",
    primaryCarePhysician: "Dr. Sakura Ito",
    medicationList: "Atorvastatin 10 mg once daily",
    allergyList: "Penicillin",
    insuranceCoverage: true
  };

  function check(form, expectedValues, output) {
    const missed = [];
    for (const [name, value] of Object.entries(expectedValues)) {
      const field = form.elements.namedItem(name);
      const actual = field.type === "checkbox" ? field.checked : field.value;
      if (actual !== value) missed.push(field.labels?.[0]?.textContent.trim() || field.getAttribute("aria-label") || name);
    }

    output.className = missed.length ? "partial" : "success";
    output.textContent = missed.length
      ? `${Object.keys(expectedValues).length - missed.length} of ${Object.keys(expectedValues).length} matched. Review: ${missed.join(", ")}.`
      : `All ${Object.keys(expectedValues).length} test fields matched correctly.`;
  }

  document.getElementById("check-results").addEventListener("click", () => {
    check(document.getElementById("returning-patient"), expected, document.getElementById("result"));
  });

  document.getElementById("check-different").addEventListener("click", () => {
    check(document.getElementById("different-format"), {
      q_1042: "hanako@example.com",
      q_2001: "Yamada",
      q_2002: "Hanako",
      q_3100: "1962-04-18",
      q_4200: "090-1234-5678",
      q_5517: "Atorvastatin 10 mg once daily",
      q_6612: "Penicillin",
      q_7720: "Dr. Sakura Ito"
    }, document.getElementById("different-result"));
  });

  const requestedTab = tabs.find((tab) => `#${tab.dataset.form}` === location.hash);
  if (requestedTab) requestedTab.click();
})();
