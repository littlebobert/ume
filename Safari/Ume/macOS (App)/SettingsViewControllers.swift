import AppKit
import SafariServices

private func symbol(_ name: String, fallback: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: fallback) ?? NSImage(named: NSImage.preferencesGeneralName)
}

private func titleLabel(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 20, weight: .semibold)
    return label
}

private func descriptionLabel(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.textColor = .secondaryLabelColor
    label.font = .systemFont(ofSize: 12)
    return label
}

private let settingsPaneSize = NSSize(width: 720, height: 500)

private enum SafariSettingsError: LocalizedError {
    case appNotInApplications

    var errorDescription: String? {
        "Move Umete to Applications, reopen it, then try again."
    }
}

private var isInstalledInApplicationsDirectory: Bool {
#if DEBUG
    true
#else
    let appPath = Bundle.main.bundleURL.standardizedFileURL.path
    let domains: [FileManager.SearchPathDomainMask] = [.localDomainMask, .userDomainMask]
    return domains
        .flatMap { FileManager.default.urls(for: .applicationDirectory, in: $0) }
        .map { $0.standardizedFileURL.path + "/" }
        .contains { appPath.hasPrefix($0) }
#endif
}

private func openSafariExtensionSettings(completion: @escaping (Error?) -> Void) {
    guard isInstalledInApplicationsDirectory else {
        completion(SafariSettingsError.appNotInApplications)
        return
    }
    let safariURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
        ?? URL(fileURLWithPath: "/Applications/Safari.app")
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true

    NSWorkspace.shared.openApplication(at: safariURL, configuration: configuration) { app, launchError in
        guard launchError == nil else {
            DispatchQueue.main.async { completion(launchError) }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { settingsError in
                DispatchQueue.main.async {
                    app?.activate(options: [.activateAllWindows])
                    completion(settingsError)
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

class ConfirmPopoverViewController: NSViewController, NSWindowDelegate {
    var onApply: (() -> Void)?
    private var applied = false

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.delegate = self
    }

    func applyAndClose() {
        guard !applied else { return }
        applied = true
        onApply?()
        view.window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !applied else { return }
        applied = true
        onApply?()
    }

    func windowDidResignKey(_ notification: Notification) {
        applyAndClose()
    }
}

final class PhonePopoverViewController: ConfirmPopoverViewController {
    private let countryField: NSTextField
    private let numberField: NSTextField

    init(countryField: NSTextField, numberField: NSTextField) {
        self.countryField = countryField
        self.numberField = numberField
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 118))
        let countryLabel = NSTextField(labelWithString: "Country code")
        let numberLabel = NSTextField(labelWithString: "Phone number")
        countryField.translatesAutoresizingMaskIntoConstraints = false
        numberField.translatesAutoresizingMaskIntoConstraints = false
        let grid = NSGridView(views: [
            [countryLabel, countryField],
            [numberLabel, numberField]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 8
        grid.rowSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false
        let done = NSButton(title: "Done", target: self, action: #selector(donePressed))
        done.keyEquivalent = "\r"
        done.bezelStyle = .rounded
        done.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        view.addSubview(done)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countryField.widthAnchor.constraint(equalToConstant: 80),
            numberField.widthAnchor.constraint(equalToConstant: 180),
            done.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 10),
            done.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            done.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(numberField)
    }

    @objc private func donePressed() {
        applyAndClose()
    }
}

/// A text view for values with several lines, like a medication list, which the
/// table's one-line fields can't edit. Return adds a line; Command-Return or
/// clicking away keeps the text.
final class MultilineValuePopoverViewController: ConfirmPopoverViewController {
    private let scroll = NSTextView.scrollableTextView()
    private var textView: NSTextView { scroll.documentView as! NSTextView }
    private let initialText: String

    var text: String { textView.string }

    init(text: String) {
        initialText = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 270))
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.string = initialText
        textView.isRichText = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        // Lists of names and doses are not prose.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        let hint = NSTextField(labelWithString: "One item per line. Press Return to add a line.")
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        let done = NSButton(title: "Done", target: self, action: #selector(donePressed))
        done.keyEquivalent = "\r"
        done.keyEquivalentModifierMask = [.command]
        done.bezelStyle = .rounded
        done.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        view.addSubview(hint)
        view.addSubview(done)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            scroll.heightAnchor.constraint(equalToConstant: 190),
            hint.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            hint.centerYAnchor.constraint(equalTo: done.centerYAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: done.leadingAnchor, constant: -8),
            done.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            done.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            done.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    @objc private func donePressed() {
        applyAndClose()
    }
}

final class AddressEditorViewController: NSViewController {
    var onSave: ((String, [String: Any]) -> Void)?

    private let initialLabel: String
    private let initialAddress: [String: Any]
    private let labelField = NSTextField()
    private let countryPopup = NSPopUpButton()
    private let line1Field = NSTextField()
    private let line2Field = NSTextField()
    private let localityField = NSTextField()
    private let areaField = NSTextField()
    private let postalField = NSTextField()
    private let areaLabel = NSTextField(labelWithString: "State / province / region")
    private let postalLabel = NSTextField(labelWithString: "Postal code")

    init(label: String, address: [String: Any]) {
        initialLabel = label
        initialAddress = address
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 310))
        labelField.stringValue = initialLabel
        labelField.placeholderString = "Home address"
        line1Field.stringValue = initialAddress["addressLine1"] as? String ?? ""
        line1Field.placeholderString = "Street address"
        line2Field.stringValue = initialAddress["addressLine2"] as? String ?? ""
        line2Field.placeholderString = "Apartment, suite, building, etc."
        localityField.stringValue = initialAddress["locality"] as? String ?? ""
        localityField.placeholderString = "City or locality"
        areaField.stringValue = initialAddress["administrativeArea"] as? String ?? ""
        postalField.stringValue = initialAddress["postalCode"] as? String ?? ""

        let locale = Locale.current
        let countries = Locale.isoRegionCodes.compactMap { code -> (String, String)? in
            guard let name = locale.localizedString(forRegionCode: code) else { return nil }
            return (code, name)
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        for (code, name) in countries {
            countryPopup.addItem(withTitle: name)
            countryPopup.lastItem?.representedObject = code
        }
        let initialCode = (initialAddress["countryCode"] as? String ?? locale.regionCode ?? "US").uppercased()
        if let index = countryPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == initialCode }) {
            countryPopup.selectItem(at: index)
        }
        countryPopup.target = self
        countryPopup.action = #selector(countryChanged)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Label"), labelField],
            [NSTextField(labelWithString: "Country / region"), countryPopup],
            [NSTextField(labelWithString: "Street address"), line1Field],
            [NSTextField(labelWithString: "Address line 2"), line2Field],
            [NSTextField(labelWithString: "City / locality"), localityField],
            [areaLabel, areaField],
            [postalLabel, postalField]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 10
        grid.rowSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.bezelStyle = .rounded
        let save = NSButton(title: "Save Address", target: self, action: #selector(savePressed))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        for field in [labelField, line1Field, line2Field, localityField, areaField, postalField] {
            field.translatesAutoresizingMaskIntoConstraints = false
        }
        countryPopup.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        view.addSubview(buttons)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            labelField.widthAnchor.constraint(equalToConstant: 300),
            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ])
        updateRegionalLabels()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(labelField.stringValue.isEmpty ? labelField : line1Field)
    }

    private var selectedCountryCode: String {
        countryPopup.selectedItem?.representedObject as? String ?? "US"
    }

    @objc private func countryChanged() {
        updateRegionalLabels()
    }

    private func updateRegionalLabels() {
        switch selectedCountryCode {
        case "US":
            areaLabel.stringValue = "State"
            postalLabel.stringValue = "ZIP code"
        case "CA":
            areaLabel.stringValue = "Province"
            postalLabel.stringValue = "Postal code"
        case "JP":
            areaLabel.stringValue = "Prefecture"
            postalLabel.stringValue = "Postal code"
        default:
            areaLabel.stringValue = "State / province / region"
            postalLabel.stringValue = "Postal code"
        }
    }

    @objc private func cancelPressed() {
        view.window?.close()
    }

    @objc private func savePressed() {
        let label = labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let line1 = line1Field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            NSSound.beep()
            view.window?.makeFirstResponder(labelField)
            return
        }
        guard !line1.isEmpty else {
            NSSound.beep()
            view.window?.makeFirstResponder(line1Field)
            return
        }
        var address: [String: Any] = [
            "version": 1,
            "countryCode": selectedCountryCode,
            "countryName": countryPopup.titleOfSelectedItem ?? selectedCountryCode,
            "addressLine1": line1
        ]
        let optional = [
            "addressLine2": line2Field.stringValue,
            "locality": localityField.stringValue,
            "administrativeArea": areaField.stringValue,
            "postalCode": postalField.stringValue
        ]
        for (key, raw) in optional {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { address[key] = value }
        }
        onSave?(label, address)
        view.window?.close()
    }
}

final class ContactEditorViewController: NSViewController {
    var onSave: ((String, [String: Any]) -> Void)?

    private static let categories = AnswerStore.contactCategories
    private static let categoryTitles = ["Doctor", "Emergency contact"]
    private static let doctorRoles = [
        "Primary care", "Cardiologist", "Dentist", "Dermatologist", "Endocrinologist", "Gastroenterologist",
        "Neurologist", "Oncologist", "Ophthalmologist", "Orthopedist", "Psychiatrist", "Pulmonologist",
        "Rheumatologist", "Surgeon", "Urologist"
    ]
    private static let emergencyRoles = [
        "Spouse", "Partner", "Parent", "Mother", "Father", "Child", "Son", "Daughter", "Sibling", "Brother",
        "Sister", "Friend", "Neighbor", "Caregiver", "Guardian"
    ]

    private let initialLabel: String
    private let initialContact: [String: Any]
    private let labelField = NSTextField()
    private let categoryPopup = NSPopUpButton()
    private let nameField = NSTextField()
    private let roleField = NSComboBox()
    private let phoneField = NSTextField()
    private let faxField = NSTextField()
    private let emailField = NSTextField()
    private let organizationField = NSTextField()
    private let addressField = NSTextField()
    private let roleLabel = NSTextField(labelWithString: "Specialty")
    private let organizationLabel = NSTextField(labelWithString: "Practice or clinic")
    private let saveButton = NSButton()

    init(label: String, contact: [String: Any]) {
        initialLabel = label
        initialContact = contact
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 400))
        labelField.stringValue = initialLabel
        categoryPopup.addItems(withTitles: Self.categoryTitles)
        let initialCategory = initialContact["category"] as? String ?? "doctor"
        categoryPopup.selectItem(at: Self.categories.firstIndex(of: initialCategory) ?? 0)
        categoryPopup.target = self
        categoryPopup.action = #selector(categoryChanged)
        nameField.stringValue = initialContact["name"] as? String ?? ""
        roleField.stringValue = initialContact["role"] as? String ?? ""
        roleField.completes = true
        phoneField.stringValue = initialContact["phone"] as? String ?? ""
        phoneField.placeholderString = "Phone number"
        faxField.stringValue = initialContact["fax"] as? String ?? ""
        faxField.placeholderString = "Fax number"
        emailField.stringValue = initialContact["email"] as? String ?? ""
        emailField.placeholderString = "Email address"
        organizationField.stringValue = initialContact["organization"] as? String ?? ""
        addressField.stringValue = initialContact["address"] as? String ?? ""
        addressField.placeholderString = "Street, city, state, postal code"

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Label"), labelField],
            [NSTextField(labelWithString: "Kind"), categoryPopup],
            [NSTextField(labelWithString: "Name"), nameField],
            [roleLabel, roleField],
            [NSTextField(labelWithString: "Phone"), phoneField],
            [NSTextField(labelWithString: "Fax"), faxField],
            [NSTextField(labelWithString: "Email"), emailField],
            [organizationLabel, organizationField],
            [NSTextField(labelWithString: "Address"), addressField]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 10
        grid.rowSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.bezelStyle = .rounded
        saveButton.target = self
        saveButton.action = #selector(savePressed)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [cancel, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        for field in [labelField, nameField, roleField, phoneField, faxField, emailField, organizationField, addressField] as [NSView] {
            field.translatesAutoresizingMaskIntoConstraints = false
        }
        categoryPopup.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)
        view.addSubview(buttons)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            labelField.widthAnchor.constraint(equalToConstant: 340),
            buttons.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ])
        updateCategoryUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(nameField.stringValue.isEmpty ? nameField : labelField)
    }

    private var selectedCategory: String {
        Self.categories[max(categoryPopup.indexOfSelectedItem, 0)]
    }

    @objc private func categoryChanged() {
        updateCategoryUI()
    }

    private func updateCategoryUI() {
        let isDoctor = selectedCategory == "doctor"
        roleLabel.stringValue = isDoctor ? "Specialty" : "Relationship"
        roleField.removeAllItems()
        roleField.addItems(withObjectValues: isDoctor ? Self.doctorRoles : Self.emergencyRoles)
        roleField.placeholderString = isDoctor ? "e.g. Cardiologist or Primary care" : "e.g. Daughter"
        organizationLabel.stringValue = isDoctor ? "Practice or clinic" : "Employer"
        nameField.placeholderString = isDoctor ? "Dr. Anita Patel" : "Full name"
        labelField.placeholderString = isDoctor ? "Defaults to the doctor's name" : "Defaults to the contact's name"
        saveButton.title = isDoctor ? "Save Doctor" : "Save Contact"
    }

    @objc private func cancelPressed() {
        view.window?.close()
    }

    @objc private func savePressed() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            NSSound.beep()
            view.window?.makeFirstResponder(nameField)
            return
        }
        var contact: [String: Any] = ["version": 1, "category": selectedCategory, "name": name]
        let optional: [String: String] = [
            "role": roleField.stringValue,
            "phone": phoneField.stringValue,
            "fax": faxField.stringValue,
            "email": emailField.stringValue,
            "organization": organizationField.stringValue,
            "address": addressField.stringValue
        ]
        for (key, raw) in optional {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { contact[key] = value }
        }
        onSave?(labelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), contact)
        view.window?.close()
    }
}

final class DebugLogWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AI Debug Log"
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.contentViewController = DebugLogViewController()
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

final class DebugLogViewController: NSViewController {
    private let textView = NSTextView()
    private let noteLabel = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 440))
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.stringValue = AIDebugLogStore.hidesSensitiveInfo
            ? "Sensitive field details are hidden. Saved answer values and API keys are never logged."
            : "This log may contain field labels and other potentially sensitive form details, but never saved answer values or API keys."

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let deleteButton = NSButton(title: "Delete Log", target: self, action: #selector(deleteLog))
        deleteButton.bezelStyle = .rounded
        let doneButton = NSButton(title: "Done", target: self, action: #selector(closeWindow))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        let buttons = NSStackView(views: [deleteButton, NSView(), doneButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(noteLabel)
        view.addSubview(scroll)
        view.addSubview(buttons)
        NSLayoutConstraint.activate([
            noteLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            noteLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            noteLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),

            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: noteLabel.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),

            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
        reloadLog()
    }

    private func reloadLog() {
        let log = AIDebugLogStore.read()
        if !log.isEmpty {
            textView.string = log
        } else if let error = AIDebugLogStore.lastError {
            textView.string = "Umete attempted to write the AI debug log, but it failed:\n\n\(error)"
        } else if let attempt = AIDebugLogStore.lastAttempt {
            textView.string = "Umete attempted to write the AI debug log at \(attempt.formatted()), but no entries could be read."
        } else if !AIDebugLogStore.isEnabled {
            textView.string = "AI debug logging is disabled. Enable it in AI Provider settings, then fill a form again."
        } else {
            textView.string = "No AI debug request has reached the native extension yet."
        }
    }

    @objc private func deleteLog() {
        try? AIDebugLogStore.clear()
        view.window?.close()
    }

    @objc private func closeWindow() {
        view.window?.close()
    }
}

final class DatePopoverViewController: ConfirmPopoverViewController {
    private let picker: NSDatePicker

    init(picker: NSDatePicker) {
        self.picker = picker
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 56))
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            picker.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        let done = NSButton(title: "Done", target: self, action: #selector(donePressed))
        done.keyEquivalent = "\r"
        done.isBordered = false
        done.isTransparent = true
        view.addSubview(done)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(picker)
    }

    @objc private func donePressed() {
        applyAndClose()
    }
}

// AI provider choices shared by onboarding and the AI settings pane.
private let aiProviderIDs = SafariWebExtensionHandlerProviders.supported
private let aiProviderTitles = ["Umete (free, no API key)", "OpenAI", "Anthropic", "OpenAI Decisions (your key)"]
private let aiDefaultModels = ["umete": "", "openai": "gpt-5.6-sol", "anthropic": "claude-opus-5", "openai-decisions": "gpt-6-luna"]

private func aiProviderIndex(_ provider: String?) -> Int {
    aiProviderIDs.firstIndex(of: provider ?? SafariWebExtensionHandlerProviders.default) ?? 0
}

/// The free service needs no model or key, so those fields are disabled while it is selected.
private func updateKeyFields(provider: String, model: NSTextField, apiKey: NSTextField) {
    let needsKey = SafariWebExtensionHandlerProviders.requiresKey(provider)
    model.isEnabled = needsKey
    apiKey.isEnabled = needsKey
    if !needsKey {
        model.stringValue = ""
        model.placeholderString = "Not needed"
        apiKey.placeholderString = "Not needed"
    } else if model.placeholderString == "Not needed" {
        model.placeholderString = "Provider model name"
    }
}

private func settingsPaneView() -> NSView {
    NSView(frame: NSRect(origin: .zero, size: settingsPaneSize))
}

private func paneStack(title: String, description: String) -> NSStackView {
    let stack = NSStackView(views: [titleLabel(title), descriptionLabel(description)])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 5
    stack.edgeInsets = NSEdgeInsets(top: 28, left: 30, bottom: 28, right: 30)
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

final class OnboardingWindowController: NSWindowController {
    init(completion: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Get Started with Umete"
        window.isReleasedWhenClosed = false
        window.contentViewController = OnboardingViewController(completion: completion)
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }
}

final class OnboardingViewController: NSViewController {
    private let content = NSView()
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let nextButton = NSButton(title: "Continue", target: nil, action: nil)
    private let safariSettingsButton = NSButton(title: "Open Safari Extension Settings…", target: nil, action: nil)
    private let provider = NSPopUpButton()
    private let model = NSTextField()
    private let apiKey = NSSecureTextField()
    private let status = descriptionLabel("")
    private let completion: () -> Void
    private var step = 0
    private var attemptedSafariSettings = false

    init(completion: @escaping () -> Void) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 440))
        content.translatesAutoresizingMaskIntoConstraints = false

        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.bezelStyle = .rounded
        nextButton.target = self
        nextButton.action = #selector(goForward)
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"

        let spacer = NSView()
        let controls = NSStackView(views: [backButton, spacer, nextButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(content)
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 42),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -42),
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 30),
            content.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -20),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            controls.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
        showStep(0)
    }

    private func showStep(_ newStep: Int) {
        step = newStep
        content.subviews.forEach { $0.removeFromSuperview() }
        let page: NSView
        switch step {
        case 0:
            page = welcomePage()
            backButton.isHidden = true
            nextButton.title = "Continue"
            nextButton.isEnabled = true
            nextButton.keyEquivalent = "\r"
        case 1:
            page = providerPage()
            backButton.isHidden = false
            nextButton.title = "Save and Continue"
            nextButton.isEnabled = true
            nextButton.keyEquivalent = "\r"
        case 2:
            page = safariPage()
            backButton.isHidden = false
            nextButton.title = "Continue"
            nextButton.isEnabled = attemptedSafariSettings
            nextButton.keyEquivalent = attemptedSafariSettings ? "\r" : ""
        default:
            page = readyPage()
            backButton.isHidden = true
            nextButton.title = "Open Safari"
            nextButton.isEnabled = true
            nextButton.keyEquivalent = "\r"
        }
        page.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            page.topAnchor.constraint(equalTo: content.topAnchor),
            page.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    private func welcomePage() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 82),
            icon.heightAnchor.constraint(equalToConstant: 82)
        ])
        return centeredPage(
            views: [icon, heading("Welcome to Umete"), body("Umete remembers answers you choose and fills similar web forms automatically.")],
            spacing: 13
        )
    }

    private func providerPage() -> NSView {
        if provider.numberOfItems == 0 {
            provider.addItems(withTitles: aiProviderTitles)
            provider.target = self
            provider.action = #selector(providerChanged)
            let settings = SettingsStore.load()
            provider.selectItem(at: aiProviderIndex(settings?.provider))
            model.stringValue = settings?.model ?? defaultModel
            apiKey.placeholderString = settings?.apiKey.isEmpty == false ? "A key is already saved" : "Paste your API key"
            updateKeyFields(provider: selectedProvider, model: model, apiKey: apiKey)
        }
        status.stringValue = ""
        let form = NSGridView(views: [
            [NSTextField(labelWithString: "Provider:"), provider],
            [NSTextField(labelWithString: "Model:"), model],
            [NSTextField(labelWithString: "API key:"), apiKey]
        ])
        form.rowSpacing = 12
        form.columnSpacing = 16
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 0).width = 80
        form.column(at: 1).width = 330
        return centeredPage(views: [heading("Choose AI matching"), body("When local matching isn’t sure, Umete can ask an AI which saved answer fits a field. Your saved answers are never sent. Only info about the form you’re on is, like its field labels."), form, body("Umete (free) works without a key, with a daily limit. Bring your own key for unlimited use; it’s stored in Apple Keychain."), status], spacing: 10)
    }

    private func safariPage() -> NSView {
        let safariImage = symbol("safari", fallback: "Safari")?.withSymbolConfiguration(.init(pointSize: 64, weight: .regular)) ?? NSImage()
        let safariIcon = NSImageView(image: safariImage)
        safariIcon.contentTintColor = .systemBlue
        safariIcon.imageScaling = .scaleProportionallyUpOrDown
        safariIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            safariIcon.widthAnchor.constraint(equalToConstant: 78),
            safariIcon.heightAnchor.constraint(equalToConstant: 78)
        ])
        safariSettingsButton.target = self
        safariSettingsButton.action = #selector(openSafariSettings)
        safariSettingsButton.bezelStyle = .rounded
        safariSettingsButton.keyEquivalent = attemptedSafariSettings ? "" : "\r"
        return centeredPage(views: [safariIcon, heading("Enable Umete in Safari"), safariSettingsButton, body("If the button doesn’t work, open Safari → Settings → Extensions and turn on Umete."), body("Return here after Umete is enabled.")], spacing: 12)
    }

    private func readyPage() -> NSView {
        let checkImage = symbol("checkmark.circle.fill", fallback: "Ready")?.withSymbolConfiguration(.init(pointSize: 52, weight: .regular)) ?? NSImage()
        let image = NSImageView(image: checkImage)
        image.contentTintColor = .systemGreen
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 62),
            image.heightAnchor.constraint(equalToConstant: 62)
        ])
        return centeredPage(views: [image, heading("Umete is ready"), body("Use Remember my answers on a completed form. Later, choose Fill this form to reuse them.")], spacing: 14)
    }

    private func centeredPage(views: [NSView], spacing: CGFloat) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor)
        ])
        return container
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 25, weight: .bold)
        label.alignment = .center
        return label
    }

    private func body(_ text: String) -> NSTextField {
        let label = descriptionLabel(text)
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.widthAnchor.constraint(equalToConstant: 470).isActive = true
        return label
    }

    private var selectedProvider: String { aiProviderIDs[max(0, min(provider.indexOfSelectedItem, aiProviderIDs.count - 1))] }
    private var defaultModel: String { aiDefaultModels[selectedProvider] ?? "" }

    @objc private func providerChanged() {
        model.stringValue = defaultModel
        if apiKey.placeholderString == "Not needed" { apiKey.placeholderString = "Paste your API key" }
        updateKeyFields(provider: selectedProvider, model: model, apiKey: apiKey)
    }

    @objc private func openSafariSettings() {
        attemptedSafariSettings = true
        safariSettingsButton.keyEquivalent = ""
        nextButton.isEnabled = true
        nextButton.keyEquivalent = "\r"
        openSafariExtensionSettings { [weak self] error in
            if let error {
                self?.status.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func goBack() {
        if step > 0 { showStep(step - 1) }
    }

    @objc private func goForward() {
        if step == 0 {
            showStep(1)
        } else if step == 1 {
            saveProvider()
        } else if step == 2 {
            showStep(3)
        } else {
            OnboardingStore.isComplete = true
            completion()
        }
    }

    private func saveProvider() {
        let trimmedModel = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let suppliedKey = apiKey.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = suppliedKey.isEmpty ? SettingsStore.load()?.apiKey ?? "" : suppliedKey
        let needsKey = SafariWebExtensionHandlerProviders.requiresKey(selectedProvider)
        guard !needsKey || (!trimmedModel.isEmpty && !key.isEmpty) else {
            status.stringValue = "Enter a model and API key to continue."
            return
        }
        do {
            try SettingsStore.save(AISettings(provider: selectedProvider, model: needsKey ? trimmedModel : "", apiKey: needsKey ? key : ""))
            showStep(2)
        } catch {
            status.stringValue = error.localizedDescription
        }
    }
}

final class SettingsTabViewController: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = settingsPaneSize
        tabStyle = .toolbar
        transitionOptions = []
        addTabViewItem(item(GeneralSettingsViewController(), label: "General", image: "gearshape"))
        addTabViewItem(item(AISettingsViewController(), label: "AI Provider", image: "sparkles"))
        addTabViewItem(item(SavedDataViewController(), label: "Saved Data", image: "tray.full"))
    }

    override func tabView(_ tabView: NSTabView, willSelect tabViewItem: NSTabViewItem?) {
        // NSTabViewController resizes the window to each pane's preferredContentSize when
        // switching tabs. Hand the incoming pane the window's current content size so the
        // window keeps whatever size it has, including any resizing the user has done.
        let current = view.bounds.size
        if current.width > 0, current.height > 0 {
            tabViewItem?.viewController?.preferredContentSize = current
        }
        super.tabView(tabView, willSelect: tabViewItem)
    }

    private func item(_ controller: NSViewController, label: String, image: String) -> NSTabViewItem {
        controller.preferredContentSize = settingsPaneSize
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = symbol(image, fallback: label)
        return item
    }
}

final class GeneralSettingsViewController: NSViewController {
    private let stateIcon = NSImageView()
    private let stateLabel = descriptionLabel("Checking Safari extension status…")
    private let syncToggle = NSButton(checkboxWithTitle: "Sync saved answers across your devices with iCloud", target: nil, action: nil)
    private let syncStatus = descriptionLabel("Checking iCloud…")
    private let syncNowButton = NSButton(title: "Sync Now", target: nil, action: nil)
    private var syncObservers: [NSObjectProtocol] = []

    override func loadView() {
        view = settingsPaneView()
        let extensionTitle = titleLabel("Safari Extension")
        extensionTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        stateIcon.imageScaling = .scaleProportionallyUpOrDown
        stateIcon.translatesAutoresizingMaskIntoConstraints = false
        let stateRow = NSStackView(views: [stateIcon, stateLabel])
        stateRow.orientation = .horizontal
        stateRow.alignment = .centerY
        stateRow.spacing = 6
        let openButton = NSButton(title: "Open Safari Settings…", target: self, action: #selector(openSafariSettings))
        openButton.bezelStyle = .rounded
        let extensionRow = NSStackView(views: [extensionTitle, stateRow, openButton])
        extensionRow.orientation = .vertical
        extensionRow.alignment = .leading
        extensionRow.spacing = 7

        let syncTitle = titleLabel("iCloud Sync")
        syncTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        syncToggle.target = self
        syncToggle.action = #selector(syncToggled)
        syncToggle.state = CloudSync.isEnabled ? .on : .off
        let syncNote = descriptionLabel("Answers are encrypted on your devices with a key that lives only in your iCloud Keychain. Apple cannot read them.")
        syncNote.lineBreakMode = .byWordWrapping
        syncNote.maximumNumberOfLines = 0
        syncNowButton.target = self
        syncNowButton.action = #selector(syncNow)
        syncNowButton.bezelStyle = .rounded
        syncNowButton.isEnabled = CloudSync.isEnabled
        let syncRow = NSStackView(views: [syncTitle, syncToggle, syncNote, syncStatus, syncNowButton])
        syncRow.orientation = .vertical
        syncRow.alignment = .leading
        syncRow.spacing = 7

        let column = NSStackView(views: [extensionRow, syncRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 26
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            column.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            syncNote.widthAnchor.constraint(equalTo: column.widthAnchor),
            syncStatus.widthAnchor.constraint(equalTo: column.widthAnchor),
            stateIcon.widthAnchor.constraint(equalToConstant: 15),
            stateIcon.heightAnchor.constraint(equalToConstant: 15)
        ])
        syncStatus.lineBreakMode = .byWordWrapping
        syncStatus.maximumNumberOfLines = 0
        syncObservers = [CloudSync.didFinishSync, CloudSync.didApplyRemoteChanges].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshSyncStatus()
            }
        }
    }

    deinit {
        syncObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshState()
        refreshSyncStatus()
    }

    private func refreshSyncStatus() {
        syncToggle.state = CloudSync.isEnabled ? .on : .off
        syncNowButton.isEnabled = CloudSync.isEnabled
        Task { @MainActor in
            syncStatus.stringValue = await CloudSync.shared.statusDescription()
        }
    }

    @objc private func syncToggled() {
        CloudSync.isEnabled = syncToggle.state == .on
        syncNowButton.isEnabled = CloudSync.isEnabled
        if CloudSync.isEnabled {
            syncStatus.stringValue = "Syncing…"
            CloudSync.shared.syncInBackground(reason: .manual)
        } else {
            refreshSyncStatus()
        }
    }

    @objc private func syncNow() {
        syncStatus.stringValue = "Syncing…"
        syncNowButton.isEnabled = false
        Task { @MainActor in
            _ = try? await CloudSync.shared.sync(reason: .manual)
            syncNowButton.isEnabled = CloudSync.isEnabled
            refreshSyncStatus()
        }
    }

    private func refreshState() {
        stateIcon.image = nil
        guard isInstalledInApplicationsDirectory else {
            stateLabel.stringValue = SafariSettingsError.appNotInApplications.localizedDescription
            stateIcon.image = NSImage(systemSymbolName: "folder.fill.badge.questionmark", accessibilityDescription: "Move to Applications")
            stateIcon.contentTintColor = .systemOrange
            return
        }
        stateLabel.stringValue = "Checking Safari extension status…"
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { [weak self] state, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let isEnabled = state?.isEnabled == true
                self.stateLabel.stringValue = isEnabled
                    ? "Umete is enabled and ready in Safari."
                    : "Umete is disabled. Enable it in Safari Settings → Extensions."
                self.stateIcon.image = NSImage(
                    systemSymbolName: isEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    accessibilityDescription: isEnabled ? "Enabled" : "Disabled"
                )
                self.stateIcon.contentTintColor = isEnabled ? .systemGreen : .systemOrange
            }
        }
    }

    @objc private func openSafariSettings() {
        stateLabel.stringValue = "Opening Safari extension settings…"
        openSafariExtensionSettings { [weak self] error in
            guard let self else { return }
            if let error {
                self.stateLabel.stringValue = error.localizedDescription
            } else {
                self.refreshState()
            }
        }
    }
}

final class AISettingsViewController: NSViewController, NSTextFieldDelegate {
    private let provider = NSPopUpButton()
    private let model = NSTextField()
    private let apiKey = NSSecureTextField()
    private let status = descriptionLabel("")
    private let debugLogging = NSButton(checkboxWithTitle: "Enable logging for bug reports", target: nil, action: nil)
    private let debugNote = descriptionLabel("Your logs are never sent automatically. Open Debug Logs… in the Safari extension to review or email them.")
    private let hideSensitive = NSButton(checkboxWithTitle: "Hide potentially sensitive info in AI debug logs", target: nil, action: nil)
    private let debugButtons = NSStackView()

    override func loadView() {
        view = settingsPaneView()
        provider.addItems(withTitles: aiProviderTitles)
        provider.target = self
        provider.action = #selector(providerChanged)
        model.placeholderString = "Provider model name"
        model.delegate = self
        apiKey.placeholderString = "Leave blank to keep the saved key"
        apiKey.delegate = self

        let form = NSGridView(views: [
            [NSTextField(labelWithString: "Provider:"), provider],
            [NSTextField(labelWithString: "Model:"), model],
            [NSTextField(labelWithString: "API key:"), apiKey]
        ])
        form.rowSpacing = 12
        form.columnSpacing = 18
        form.column(at: 0).xPlacement = .leading
        form.column(at: 0).width = 96
        form.column(at: 1).width = 420
        for rowIndex in 0..<form.numberOfRows {
            form.row(at: rowIndex).yPlacement = .center
        }

        let delete = NSButton(title: "Delete Saved Key", target: self, action: #selector(deleteKey))
        delete.bezelStyle = .rounded
        let buttons = NSStackView(views: [delete])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.distribution = .gravityAreas

        debugLogging.target = self
        debugLogging.action = #selector(debugLoggingChanged)
        hideSensitive.target = self
        hideSensitive.action = #selector(hideSensitiveChanged)
        let viewLog = NSButton(title: "View Log…", target: self, action: #selector(viewDebugLog))
        let clearLog = NSButton(title: "Clear Log", target: self, action: #selector(clearDebugLog))
        debugButtons.addArrangedSubview(viewLog)
        debugButtons.addArrangedSubview(clearLog)
        debugButtons.orientation = .horizontal
        debugButtons.spacing = 8
        let debugSection = NSStackView(views: [debugLogging, debugNote, hideSensitive, debugButtons])
        debugSection.orientation = .vertical
        debugSection.alignment = .leading
        debugSection.spacing = 7

        let stack = paneStack(title: "AI Provider", description: "Used only when on-device matching cannot identify a field confidently.")
        stack.spacing = 18
        stack.addArrangedSubview(form)
        stack.addArrangedSubview(status)
        stack.addArrangedSubview(buttons)
        stack.addArrangedSubview(debugSection)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            form.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -60),
            status.widthAnchor.constraint(equalTo: form.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: form.widthAnchor),
            debugSection.widthAnchor.constraint(equalTo: form.widthAnchor)
        ])
        loadSettings()
    }

    private func loadSettings() {
        let settings = SettingsStore.load()
        provider.selectItem(at: aiProviderIndex(settings?.provider))
        model.stringValue = settings?.model ?? defaultModel
        updateKeyFields(provider: selectedProvider, model: model, apiKey: apiKey)
        if !SafariWebExtensionHandlerProviders.requiresKey(selectedProvider) {
            status.stringValue = "Free, with a daily limit. No key needed."
        } else {
            status.stringValue = settings?.apiKey.isEmpty == false ? "A key is saved in Apple Keychain." : "No key is saved."
        }
        debugLogging.state = AIDebugLogStore.isEnabled ? .on : .off
        hideSensitive.state = AIDebugLogStore.hidesSensitiveInfo ? .on : .off
        updateDebugDependentControls()
    }

    private func updateDebugDependentControls() {
        let enabled = debugLogging.state == .on
        debugNote.isHidden = !enabled
        hideSensitive.isHidden = !enabled
        debugButtons.isHidden = !enabled
    }

    private var selectedProvider: String { aiProviderIDs[max(0, min(provider.indexOfSelectedItem, aiProviderIDs.count - 1))] }
    private var defaultModel: String { aiDefaultModels[selectedProvider] ?? "" }

    @objc private func providerChanged() {
        if model.stringValue.isEmpty || ["gpt-5.6-terra", "gpt-5.6-sol", "gpt-6-luna", "claude-haiku-4-5", "claude-opus-5"].contains(model.stringValue) {
            model.stringValue = defaultModel
        }
        if apiKey.placeholderString == "Not needed" { apiKey.placeholderString = "Leave blank to keep the saved key" }
        model.placeholderString = "Provider model name"
        updateKeyFields(provider: selectedProvider, model: model, apiKey: apiKey)
        autosave()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        autosave()
    }

    private func autosave() {
        if !SafariWebExtensionHandlerProviders.requiresKey(selectedProvider) {
            // Keep any saved key so switching back to a key-based provider doesn't lose it.
            let existingKey = SettingsStore.load()?.apiKey ?? ""
            do {
                try SettingsStore.save(AISettings(provider: selectedProvider, model: "", apiKey: existingKey))
                status.stringValue = "Free, with a daily limit. No key needed."
            } catch {
                status.stringValue = error.localizedDescription
            }
            return
        }
        let key = apiKey.stringValue.isEmpty ? SettingsStore.load()?.apiKey ?? "" : apiKey.stringValue
        let trimmedModel = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            status.stringValue = "Enter a model name."
            return
        }
        guard !key.isEmpty else {
            status.stringValue = "Enter an API key to finish setup."
            return
        }
        do {
            try SettingsStore.save(AISettings(provider: selectedProvider, model: trimmedModel, apiKey: key))
            apiKey.stringValue = ""
            status.stringValue = "Saved automatically in Apple Keychain."
        } catch {
            status.stringValue = error.localizedDescription
        }
    }

    @objc private func debugLoggingChanged() {
        let enabled = debugLogging.state == .on
        AIDebugLogStore.isEnabled = enabled
        if !enabled {
            do {
                try AIDebugLogStore.clear()
                status.stringValue = "Logging disabled and saved logs deleted."
            } catch {
                status.stringValue = "Logging disabled, but saved logs could not be deleted: \(error.localizedDescription)"
            }
        }
        updateDebugDependentControls()
    }

    @objc private func hideSensitiveChanged() {
        AIDebugLogStore.hidesSensitiveInfo = hideSensitive.state == .on
    }

    private var logWindowController: NSWindowController?

    @objc private func viewDebugLog() {
        let controller = DebugLogWindowController()
        logWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func clearDebugLog() {
        do {
            try AIDebugLogStore.clear()
            status.stringValue = "AI debug log cleared."
        } catch {
            status.stringValue = error.localizedDescription
        }
    }

    @objc private func deleteKey() {
        SettingsStore.delete()
        loadSettings()
    }
}

final class SavedDataViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let table = NSTableView()
    private let deleteButton = NSButton()
    private let addMenu = NSPopUpButton(frame: .zero, pullsDown: true)
    private var answers: [[String: Any]] = []
    private var draftAnswer: [String: Any]?
    private var navigatingCells = false
    private var discardingDraft = false
    private var keyMonitor: Any?
    private var draftEditorObserver: NSObjectProtocol?
    private var remoteChangeObserver: NSObjectProtocol?
    private static let answerTypes = ["", "address", "contact", "date", "gender", "phone"]
    private static let typeTitles = ["Auto", "Address", "Contact", "Date", "Gender", "Phone"]
    private static let aggregateTypes = AnswerStore.aggregateTypes

    override func loadView() {
        view = settingsPaneView()
        let labelColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
        labelColumn.title = "Label"
        labelColumn.width = 220
        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueColumn.title = "Value"
        valueColumn.width = 300
        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = "Type"
        typeColumn.width = 110
        table.addTableColumn(typeColumn)
        table.addTableColumn(labelColumn)
        table.addTableColumn(valueColumn)
        table.headerView = NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(beginInlineEditing)
        table.rowHeight = 24
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleTableKey(event) else { return event }
            return nil
        }
        remoteChangeObserver = NotificationCenter.default.addObserver(forName: CloudSync.didApplyRemoteChanges, object: nil, queue: .main) { [weak self] _ in
            // Don't yank the table out from under an in-progress edit.
            guard let self, self.draftAnswer == nil, !(self.view.window?.firstResponder is NSTextView) else { return }
            self.reload()
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        addMenu.bezelStyle = .rounded
        addMenu.addItem(withTitle: "Add")
        let addItems: [(String, Selector)] = [
            ("Text Answer…", #selector(addAnswer)),
            ("Address…", #selector(addAddress)),
            ("Doctor…", #selector(addDoctor)),
            ("Emergency Contact…", #selector(addEmergencyContact))
        ]
        for (title, action) in addItems {
            addMenu.addItem(withTitle: title)
            addMenu.lastItem?.target = self
            addMenu.lastItem?.action = action
        }
        deleteButton.title = "Delete"
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.bezelStyle = .rounded
        deleteButton.isEnabled = false
        let clear = NSButton(title: "Clear All Answers…", target: self, action: #selector(clearAll))
        let buttons = NSStackView(views: [addMenu, deleteButton, NSView(), clear])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = paneStack(title: "Saved Data", description: "Double-click a label or value to edit; click a type to change it. A value with several lines, like a medication list, opens in a larger editor; press Option-Return while editing a value to give it more lines. Phone, Address, and Contact use structured editors so Umete can fill related fields automatically. Add each doctor or emergency contact once and Umete fills their name, phone, and other details wherever a form asks for them.")
        stack.addArrangedSubview(scroll)
        stack.addArrangedSubview(buttons)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -60),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 280),
            buttons.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])
        reload()
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let remoteChangeObserver {
            NotificationCenter.default.removeObserver(remoteChangeObserver)
        }
    }

    private func reload() {
        answers = (try? AnswerStore.load()) ?? []
        table.reloadData()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        discardEmptyDraft()
    }

    private var displayedAnswers: [[String: Any]] {
        answers + (draftAnswer.map { [$0] } ?? [])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedAnswers.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateDeleteButton()
        if !navigatingCells && draftAnswer != nil && table.selectedRow != answers.count && table.selectedRow >= 0 {
            discardEmptyDraft()
        }
    }

    private func updateDeleteButton() {
        deleteButton.isEnabled = table.selectedRow >= 0 && displayedAnswers.indices.contains(table.selectedRow)
    }

    private func isDraftEmpty(_ draft: [String: Any]) -> Bool {
        let label = (draft["userLabel"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (draft["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty && value.isEmpty
    }

    private func discardEmptyDraft() {
        guard let draft = draftAnswer, isDraftEmpty(draft) else { return }
        discardDraft()
    }

    @discardableResult
    private func commitDraftIfComplete() -> Bool {
        guard let draft = draftAnswer, !Self.aggregateTypes.contains(draft["answerType"] as? String ?? "") else { return false }
        let label = (draft["userLabel"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (draft["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, !value.isEmpty else { return false }
        do {
            let type = draft["answerType"] as? String
            try AnswerStore.add(userLabel: label, value: value, answerType: type?.isEmpty == false ? type : nil)
            if let code = draft["countryCode"] as? String, !code.isEmpty {
                var all = try AnswerStore.load()
                if let last = all.indices.last { all[last]["countryCode"] = code }
                try AnswerStore.save(all)
            }
            draftAnswer = nil
            reload()
            if !answers.isEmpty {
                table.selectRowIndexes(IndexSet(integer: answers.count - 1), byExtendingSelection: false)
            }
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func discardDraft() {
        guard draftAnswer != nil else { return }
        discardingDraft = true
        draftAnswer = nil
        view.window?.makeFirstResponder(table)
        table.reloadData()
        discardingDraft = false
        updateDeleteButton()
    }

    private func focusDraft() {
        let row = answers.count
        guard draftAnswer != nil, displayedAnswers.indices.contains(row) else { return }
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        switch draftAnswer?["answerType"] as? String {
        case "address":
            presentAddressEditor(row: row)
        case "contact":
            presentContactEditor(row: row)
        default:
            startEditing(row: row, column: columnIndex("label"))
        }
    }

    private func columnIndex(_ identifier: String) -> Int {
        table.tableColumns.firstIndex { $0.identifier.rawValue == identifier } ?? 0
    }

    private func columnIdentifier(_ column: Int) -> String {
        guard table.tableColumns.indices.contains(column) else { return "" }
        return table.tableColumns[column].identifier.rawValue
    }

    private func handleTableKey(_ event: NSEvent) -> Bool {
        guard let window = view.window, event.window === window,
              window.firstResponder === table,
              table.selectedRow >= 0 else { return false }
        let row = table.selectedRow
        switch event.keyCode {
        case 51, 117:
            deleteSelected()
            return true
        case 36, 76:
            startEditing(row: row, column: columnIndex("label"))
            return true
        default:
            return false
        }
    }

    private func startEditing(row: Int, column: Int) {
        guard displayedAnswers.indices.contains(row) else { return }
        let answer = displayedAnswers[row]
        let type = answer["answerType"] as? String ?? detectedType(answer)
        let identifier = columnIdentifier(column)
        if identifier == "type" { return }
        if identifier == "value", type == "address" {
            presentAddressEditor(row: row)
        } else if identifier == "value", type == "contact" {
            presentContactEditor(row: row)
        } else if identifier == "value", type == "phone" {
            presentPhonePopover(row: row)
        } else if identifier == "value", type == "date" {
            presentDatePopover(row: row)
        } else if identifier == "value", let text = answer["value"] as? String, text.contains(where: \.isNewline) {
            presentMultilineEditor(row: row)
        } else {
            editCell(row: row, column: column)
        }
    }

    /// Edits a text value in a text view: for values that already have several
    /// lines, and for a one-line value when Option-Return is pressed in its field.
    private func presentMultilineEditor(row: Int, text: String? = nil) {
        guard let answer = answerForRow(row) else { return }
        let controller = MultilineValuePopoverViewController(text: text ?? (answer["value"] as? String ?? ""))
        controller.onApply = { [weak self, weak controller] in
            guard let self, let controller else { return }
            let value = controller.text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.persistChanges(row: row) { answer in answer["value"] = value }
        }
        present(controller, row: row)
    }

    @objc private func beginInlineEditing() {
        startEditing(row: table.clickedRow, column: table.clickedColumn)
    }

    private func editCell(row: Int, column: Int) {
        guard displayedAnswers.indices.contains(row), column >= 0, column < table.numberOfColumns,
              ["label", "value"].contains(columnIdentifier(column)),
              let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView else { return }
        guard let field = cell.textField else { return }
        field.isEditable = true
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        view.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    @objc private func typeChanged(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard displayedAnswers.indices.contains(row),
              Self.answerTypes.indices.contains(sender.indexOfSelectedItem) else { return }
        let type = Self.answerTypes[sender.indexOfSelectedItem]
        let currentType = displayedAnswers[row]["answerType"] as? String ?? detectedType(displayedAnswers[row])
        if type == currentType { return }
        if Self.aggregateTypes.contains(currentType) {
            // Addresses and contacts hold structured values; delete and re-add to change their type.
            NSSound.beep()
            table.reloadData()
            return
        }
        if type == "address" {
            table.reloadData()
            DispatchQueue.main.async { self.presentAddressEditor(row: row) }
            return
        }
        if type == "contact" {
            table.reloadData()
            DispatchQueue.main.async { self.presentContactEditor(row: row, category: "doctor") }
            return
        }
        if row == answers.count {
            draftAnswer?["answerType"] = type.isEmpty ? nil : type
            return
        }
        guard let id = answers[row]["answerID"] as? String else { return }
        do {
            var all = try AnswerStore.load()
            guard let index = all.firstIndex(where: { $0["answerID"] as? String == id }) else { return }
            all[index]["answerType"] = type.isEmpty ? nil : type
            try AnswerStore.save(all)
            answers = all
        } catch {
            present(error)
            reload()
        }
    }

    private func answerForRow(_ row: Int) -> [String: Any]? {
        displayedAnswers[safe: row]
    }

    private func persistChanges(row: Int, mutate: (inout [String: Any]) -> Void) {
        if row == answers.count {
            guard var draft = draftAnswer else { return }
            mutate(&draft)
            draftAnswer = draft
            if !commitDraftIfComplete() {
                table.reloadData()
            }
            return
        }
        guard answers.indices.contains(row), let id = answers[row]["answerID"] as? String else { return }
        do {
            var all = try AnswerStore.load()
            guard let index = all.firstIndex(where: { $0["answerID"] as? String == id }) else { return }
            mutate(&all[index])
            try AnswerStore.save(all)
            answers = all
            table.reloadData()
        } catch {
            present(error)
            reload()
        }
    }

    private func anchorCellView(row: Int, column: Int) -> NSView {
        table.view(atColumn: column, row: row, makeIfNecessary: true) ?? table
    }

    private func present(_ controller: NSViewController, row: Int, column: Int? = nil) {
        let column = column ?? columnIndex("value")
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        if row == answers.count, draftAnswer != nil {
            // A new address or contact only exists once its editor saves; cancelling,
            // pressing Escape, or clicking away should not leave an empty row behind.
            if let draftEditorObserver { NotificationCenter.default.removeObserver(draftEditorObserver) }
            draftEditorObserver = NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { [weak self] _ in
                guard let self else { return }
                if let observer = self.draftEditorObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.draftEditorObserver = nil
                }
                self.discardEmptyDraft()
            }
        }
        popover.show(relativeTo: anchorCellView(row: row, column: column).bounds, of: anchorCellView(row: row, column: column), preferredEdge: .maxY)
    }

    private func presentAddressEditor(row: Int) {
        guard let answer = answerForRow(row) else { return }
        let address = answer["value"] as? [String: Any] ?? [:]
        let existingLabel = answer["userLabel"] as? String
            ?? answer["accessibleName"] as? String
            ?? answer["label"] as? String
            ?? ""
        let controller = AddressEditorViewController(label: existingLabel, address: address)
        controller.onSave = { [weak self] label, address in
            guard let self else { return }
            do {
                if self.answers.indices.contains(row), let id = self.answers[row]["answerID"] as? String {
                    try AnswerStore.updateAddress(id: id, userLabel: label, value: address)
                } else {
                    try AnswerStore.addAddress(userLabel: label, value: address)
                    self.draftAnswer = nil
                }
                self.reload()
                if !self.answers.isEmpty {
                    let selected = min(row, self.answers.count - 1)
                    self.table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
                }
            } catch {
                self.present(error)
                self.reload()
            }
        }
        present(controller, row: row)
    }

    private func presentContactEditor(row: Int, category: String? = nil) {
        guard let answer = answerForRow(row) else { return }
        let isContact = (answer["answerType"] as? String) == "contact"
        var contact = answer["value"] as? [String: Any] ?? [:]
        if !isContact, let text = answer["value"] as? String, !text.isEmpty {
            // Converting a plain text answer: keep its value as the contact's name.
            contact["name"] = text
        }
        if contact["category"] == nil {
            contact["category"] = category ?? "doctor"
        }
        let existingLabel = answer["userLabel"] as? String
            ?? (isContact ? (answer["accessibleName"] as? String ?? answer["label"] as? String) : nil)
            ?? ""
        let controller = ContactEditorViewController(label: existingLabel, contact: contact)
        controller.onSave = { [weak self] label, contact in
            guard let self else { return }
            do {
                if self.answers.indices.contains(row), let id = self.answers[row]["answerID"] as? String {
                    try AnswerStore.updateContact(id: id, userLabel: label, value: contact)
                } else {
                    try AnswerStore.addContact(userLabel: label, value: contact)
                    self.draftAnswer = nil
                }
                self.reload()
                if !self.answers.isEmpty {
                    let selected = min(row, self.answers.count - 1)
                    self.table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
                }
            } catch {
                self.present(error)
                self.reload()
            }
        }
        present(controller, row: row)
    }

    private func presentPhonePopover(row: Int) {
        guard let answer = answerForRow(row) else { return }
        let countryField = NSTextField()
        countryField.placeholderString = "e.g. 81"
        countryField.stringValue = Self.inferredCallingCode(from: answer)
        let numberField = NSTextField()
        numberField.placeholderString = "Local number"
        numberField.stringValue = answer["value"] as? String ?? ""
        let controller = PhonePopoverViewController(countryField: countryField, numberField: numberField)
        controller.onApply = { [weak self] in
            self?.persistChanges(row: row) { answer in
                answer["countryCode"] = countryField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty ? nil : countryField.stringValue.filter(\.isNumber)
                answer["value"] = numberField.stringValue
            }
        }
        present(controller, row: row)
    }

    private func presentDatePopover(row: Int) {
        guard let answer = answerForRow(row) else { return }
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay]
        picker.dateValue = Self.parseDate(answer["value"] as? String) ?? Date()
        let controller = DatePopoverViewController(picker: picker)
        controller.onApply = { [weak self] in
            self?.persistChanges(row: row) { answer in
                answer["value"] = Self.formatDate(picker.dateValue)
            }
        }
        present(controller, row: row)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static func parseDate(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let date = dateFormatter.date(from: string) { return date }
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        return iso.date(from: string)
    }

    private static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static func inferredCallingCode(from answer: [String: Any]) -> String {
        let stored = (answer["countryCode"] as? String ?? "").filter { $0.isNumber }
        if !stored.isEmpty { return stored }
        if let value = answer["value"] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("+") {
                let digits = trimmed.dropFirst().prefix(while: \.isNumber)
                if (1...3).contains(digits.count) { return String(digits) }
            }
        }
        return regionCallingCode()
    }

    private static func regionCallingCode() -> String {
        let region: String
        if #available(macOS 13.0, *) {
            region = Locale.current.region?.identifier ?? ""
        } else {
            region = Locale.current.regionCode ?? ""
        }
        return callingCodeDigits(forRegion: region)
    }

    private static func callingCodeDigits(forRegion region: String) -> String {
        let code = region.uppercased()
        if ["US", "CA", "AG", "AI", "AS", "BB", "BM", "BS", "DM", "DO", "GD", "GU", "JM", "KN", "KY", "LC", "MP", "MS", "PR", "SX", "TC", "TT", "VC", "VG", "VI"].contains(code) {
            return "1"
        }
        let codes: [String: String] = [
            "JP": "81", "KR": "82", "CN": "86", "TW": "886", "HK": "852", "MO": "853",
            "GB": "44", "IE": "353", "FR": "33", "DE": "49", "IT": "39", "ES": "34", "PT": "351",
            "NL": "31", "BE": "32", "LU": "352", "CH": "41", "AT": "43", "SE": "46", "NO": "47",
            "DK": "45", "FI": "358", "IS": "354", "PL": "48", "CZ": "420", "SK": "421", "HU": "36",
            "RO": "40", "BG": "359", "GR": "30", "TR": "90", "RU": "7", "UA": "380",
            "AU": "61", "NZ": "64", "IN": "91", "ID": "62", "MY": "60", "SG": "65", "TH": "66",
            "VN": "84", "PH": "63", "PK": "92", "BD": "880", "LK": "94", "NP": "977",
            "AE": "971", "SA": "966", "IL": "972", "QA": "974", "KW": "965", "BH": "973", "OM": "968",
            "EG": "20", "ZA": "27", "NG": "234", "KE": "254", "MA": "212",
            "BR": "55", "MX": "52", "AR": "54", "CL": "56", "CO": "57", "PE": "51"
        ]
        return codes[code] ?? ""
    }

    private func detectedType(_ answer: [String: Any]) -> String {
        if let explicit = answer["answerType"] as? String, Self.answerTypes.contains(explicit) { return explicit }
        let text = " " + ([answer["userLabel"], answer["accessibleName"], answer["label"], answer["name"], answer["autocomplete"]]
            .compactMap { $0 as? String }.joined(separator: " "))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression) + " "
        if text.range(of: #" (country (phone )?code|phone country|calling code|dial code) "#, options: .regularExpression) != nil { return "phone" }
        if text.range(of: #" (phone|telephone|tel|mobile|cell) "#, options: .regularExpression) != nil { return "phone" }
        if text.range(of: #" (birth ?day|birth ?date|date of birth|d o b) "#, options: .regularExpression) != nil { return "date" }
        if text.range(of: #" (gender|sex) "#, options: .regularExpression) != nil { return "gender" }
        return ""
    }

    private func advance(from row: Int, current: Int) {
        if current == 0 {
            view.window?.makeFirstResponder(nil)
            startEditing(row: row, column: columnIndex("value"))
        } else if row + 1 < displayedAnswers.count {
            view.window?.makeFirstResponder(nil)
            startEditing(row: row + 1, column: columnIndex("label"))
        } else {
            view.window?.makeFirstResponder(nil)
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let answer = displayedAnswers[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")

        if identifier.rawValue == "type" {
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
            var popup = cell.viewWithTag(701) as? NSPopUpButton
            if popup == nil {
                let button = NSPopUpButton(frame: .zero, pullsDown: false)
                button.addItems(withTitles: Self.typeTitles)
                button.isBordered = false
                button.font = .systemFont(ofSize: NSFont.systemFontSize)
                button.target = self
                button.action = #selector(typeChanged(_:))
                button.tag = 701
                button.translatesAutoresizingMaskIntoConstraints = false
                cell.identifier = identifier
                cell.addSubview(button)
                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    button.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: 2),
                    button.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
                popup = button
            }
            popup?.tag = row
            let explicit = answer["answerType"] as? String
            let type = (explicit.map { Self.answerTypes.contains($0) ? $0 : "" } ?? detectedType(answer))
            popup?.selectItem(at: Self.answerTypes.firstIndex(of: type) ?? 0)
            return cell
        }

        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        if cell.textField == nil {
            let text = NSTextField()
            text.isBordered = false
            text.drawsBackground = false
            text.focusRingType = .none
            text.isEditable = false
            text.lineBreakMode = .byTruncatingTail
            text.delegate = self
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.identifier = identifier
            cell.textField = text
            cell.addSubview(text)
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.tag = row
        cell.textField?.identifier = identifier
        cell.textField?.isEditable = false
        if identifier.rawValue == "label" {
            cell.textField?.stringValue = answer["userLabel"] as? String ?? displayLabel(answer, row: row)
            cell.textField?.placeholderString = "Label"
        } else {
            cell.textField?.stringValue = displayValue(answer)
            cell.textField?.placeholderString = answer["value"] is Bool ? "Yes or No" : "Value"
        }
        return cell
    }

    private func displayLabel(_ answer: [String: Any], row: Int) -> String {
        for key in ["userLabel", "accessibleName", "label", "placeholder", "name", "autocomplete"] {
            if let value = answer[key] as? String, !value.isEmpty { return value }
        }
        return "Saved answer \(row + 1)"
    }

    private func valueString(_ value: Any?) -> String {
        if let bool = value as? Bool { return bool ? "Yes" : "No" }
        return value.map(String.init(describing:)) ?? ""
    }

    private func displayValue(_ answer: [String: Any]) -> String {
        if detectedType(answer) == "address", let address = answer["value"] as? [String: Any] {
            return ["addressLine1", "addressLine2", "locality", "administrativeArea", "postalCode", "countryName"]
                .compactMap { address[$0] as? String }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        if detectedType(answer) == "contact", let contact = answer["value"] as? [String: Any] {
            return ["name", "role", "phone"]
                .compactMap { contact[$0] as? String }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
        if let text = answer["value"] as? String, text.contains(where: \.isNewline) {
            return text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
        let value = valueString(answer["value"])
        guard detectedType(answer) == "phone",
              let code = answer["countryCode"] as? String else { return value }
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { return value }
        return value.isEmpty ? "+\(digits)" : "+\(digits) \(value)"
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? NSTextField else { return false }
        if field.tag == answers.count, draftAnswer != nil {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                discardDraft()
                return true
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:))
                || commandSelector == #selector(NSResponder.deleteForward(_:)),
               field.stringValue.isEmpty,
               let draft = draftAnswer, isDraftEmpty(draft) {
                discardDraft()
                return true
            }
        }
        if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
           field.identifier?.rawValue == "value",
           let answer = displayedAnswers[safe: field.tag],
           !(answer["value"] is Bool),
           !Self.aggregateTypes.contains(detectedType(answer)) {
            let row = field.tag
            let text = field.stringValue
            field.abortEditing()
            field.isEditable = false
            view.window?.makeFirstResponder(table)
            DispatchQueue.main.async { self.presentMultilineEditor(row: row, text: text) }
            return true
        }
        guard commandSelector == #selector(NSResponder.insertTab(_:)) else { return false }
        let row: Int
        let current: Int
        guard displayedAnswers.indices.contains(field.tag),
              let raw = field.identifier?.rawValue, raw == "label" || raw == "value" else { return false }
        row = field.tag
        current = raw == "label" ? 0 : 1
        navigatingCells = true
        defer { navigatingCells = false }
        advance(from: row, current: current)
        return true
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        field.isEditable = true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if discardingDraft {
            field.isEditable = false
            return
        }
        guard displayedAnswers.indices.contains(field.tag) else { return }
        if field.tag == answers.count, var draft = draftAnswer {
            let editedLabel = field.identifier?.rawValue == "label"
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if editedLabel {
                draft["userLabel"] = text
                draft["accessibleName"] = text
                draft["label"] = text
            } else {
                draft["value"] = text
            }
            draftAnswer = draft
            field.isEditable = false
            commitDraftIfComplete()
            return
        }

        guard answers.indices.contains(field.tag),
              let id = answers[field.tag]["answerID"] as? String else { return }
        let answer = answers[field.tag]
        let editedLabel = field.identifier?.rawValue == "label"
        let userLabel = editedLabel ? field.stringValue : displayLabel(answer, row: field.tag)
        let value: Any
        if editedLabel {
            value = answer["value"] ?? ""
        } else if answer["value"] is Bool {
            let normalized = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["yes", "no", "true", "false", "1", "0", "on", "off"].contains(normalized) else {
                field.stringValue = valueString(answer["value"])
                NSSound.beep()
                return
            }
            value = ["yes", "true", "1", "on"].contains(normalized)
        } else {
            value = field.stringValue
        }
        do {
            try AnswerStore.update(id: id, userLabel: userLabel, value: value)
            field.isEditable = false
            reload()
        } catch {
            field.stringValue = editedLabel ? displayLabel(answer, row: field.tag) : valueString(answer["value"])
            field.isEditable = false
            present(error)
        }
    }

    @objc private func addAddress() {
        if draftAnswer != nil && !commitDraftIfComplete() {
            focusDraft()
            return
        }
        draftAnswer = [
            "answerID": UUID().uuidString,
            "answerType": "address",
            "kind": "aggregate",
            "inputType": ""
        ]
        table.reloadData()
        let row = answers.count
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        DispatchQueue.main.async { self.presentAddressEditor(row: row) }
    }

    @objc private func addDoctor() {
        addContact(category: "doctor")
    }

    @objc private func addEmergencyContact() {
        addContact(category: "emergencyContact")
    }

    private func addContact(category: String) {
        if draftAnswer != nil && !commitDraftIfComplete() {
            focusDraft()
            return
        }
        draftAnswer = [
            "answerID": UUID().uuidString,
            "answerType": "contact",
            "kind": "aggregate",
            "inputType": "",
            "value": ["category": category]
        ]
        table.reloadData()
        let row = answers.count
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        DispatchQueue.main.async { self.presentContactEditor(row: row, category: category) }
    }

    @objc private func addAnswer() {
        if draftAnswer != nil && !commitDraftIfComplete() {
            focusDraft()
            return
        }
        draftAnswer = [
            "answerID": UUID().uuidString,
            "kind": "text",
            "inputType": "text"
        ]
        table.reloadData()
        let row = answers.count
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        DispatchQueue.main.async {
            guard let cell = self.table.view(atColumn: self.columnIndex("label"), row: row, makeIfNecessary: true) as? NSTableCellView,
                  let field = cell.textField else { return }
            field.isEditable = true
            self.view.window?.makeFirstResponder(field)
        }
    }

    @objc private func deleteSelected() {
        let row = table.selectedRow
        if draftAnswer != nil && row == answers.count {
            discardDraft()
            return
        }
        guard answers.indices.contains(row), let id = answers[row]["answerID"] as? String else { return }
        do { try AnswerStore.delete(id: id); reload() } catch { present(error) }
    }

    @objc private func clearAll() {
        let alert = NSAlert()
        alert.messageText = CloudSync.isEnabled ? "Clear all saved answers on all your devices?" : "Clear all saved answers?"
        alert.informativeText = CloudSync.isEnabled
            ? "Answers synced through iCloud will be removed from your other devices too. Your AI provider, model, and API key will be kept. This cannot be undone."
            : "Your AI provider, model, and API key will be kept. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All Answers")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try AnswerStore.clear(); reload() } catch { present(error) }
    }

    private func present(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
