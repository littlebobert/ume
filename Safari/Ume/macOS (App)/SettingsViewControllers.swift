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

private func openSafariExtensionSettings(completion: @escaping (Error?) -> Void) {
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
            textView.string = "Ume attempted to write the AI debug log, but it failed:\n\n\(error)"
        } else if let attempt = AIDebugLogStore.lastAttempt {
            textView.string = "Ume attempted to write the AI debug log at \(attempt.formatted()), but no entries could be read."
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
        window.title = "Get Started with Ume"
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
            views: [icon, heading("Welcome to Ume"), body("Ume remembers answers you choose and fills similar web forms automatically.")],
            spacing: 13
        )
    }

    private func providerPage() -> NSView {
        if provider.numberOfItems == 0 {
            provider.addItems(withTitles: ["OpenAI", "Anthropic"])
            provider.target = self
            provider.action = #selector(providerChanged)
            let settings = SettingsStore.load()
            provider.selectItem(at: settings?.provider == "anthropic" ? 1 : 0)
            model.stringValue = settings?.model ?? defaultModel
            apiKey.placeholderString = settings?.apiKey.isEmpty == false ? "A key is already saved" : "Paste your API key"
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
        return centeredPage(views: [heading("Connect an AI provider"), body("Your personal saved answers are never sent to the API provider. Ume only sends info about the form you’re on, like its field labels."), form, body("Your API key is stored in Apple Keychain."), status], spacing: 10)
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
        return centeredPage(views: [safariIcon, heading("Enable Ume in Safari"), safariSettingsButton, body("If the button doesn’t work, open Safari → Settings → Extensions and turn on Ume."), body("Return here after Ume is enabled.")], spacing: 12)
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
        return centeredPage(views: [image, heading("Ume is ready"), body("Use Remember my answers on a completed form. Later, choose Fill this form to reuse them.")], spacing: 14)
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

    private var selectedProvider: String { provider.indexOfSelectedItem == 1 ? "anthropic" : "openai" }
    private var defaultModel: String { selectedProvider == "anthropic" ? "claude-opus-5" : "gpt-5.6-terra" }

    @objc private func providerChanged() {
        model.stringValue = defaultModel
    }

    @objc private func openSafariSettings() {
        attemptedSafariSettings = true
        safariSettingsButton.keyEquivalent = ""
        nextButton.isEnabled = true
        nextButton.keyEquivalent = "\r"
        openSafariExtensionSettings { [weak self] error in
            if error != nil {
                self?.status.stringValue = "Safari opened. Choose Safari → Settings → Extensions and enable Ume."
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
        guard !trimmedModel.isEmpty, !key.isEmpty else {
            status.stringValue = "Enter a model and API key to continue."
            return
        }
        do {
            try SettingsStore.save(AISettings(provider: selectedProvider, model: trimmedModel, apiKey: key))
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

        extensionRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(extensionRow)
        NSLayoutConstraint.activate([
            extensionRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            extensionRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            extensionRow.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            stateIcon.widthAnchor.constraint(equalToConstant: 15),
            stateIcon.heightAnchor.constraint(equalToConstant: 15)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshState()
    }

    private func refreshState() {
        stateIcon.image = nil
        stateLabel.stringValue = "Checking Safari extension status…"
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { [weak self] state, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let isEnabled = state?.isEnabled == true
                self.stateLabel.stringValue = isEnabled
                    ? "Ume is enabled and ready in Safari."
                    : "Ume is disabled. Enable it in Safari Settings → Extensions."
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
            if error != nil {
                self.stateLabel.stringValue = "Safari opened. Choose Safari → Settings → Extensions and enable Ume."
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
    private let debugNote = descriptionLabel("Your logs are never sent automatically. They are only sent if you manually send them in via the Report a Bug button.")
    private let hideSensitive = NSButton(checkboxWithTitle: "Hide potentially sensitive info in AI debug logs", target: nil, action: nil)
    private let debugButtons = NSStackView()

    override func loadView() {
        view = settingsPaneView()
        provider.addItems(withTitles: ["OpenAI", "Anthropic"])
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
        provider.selectItem(at: settings?.provider == "anthropic" ? 1 : 0)
        model.stringValue = settings?.model ?? defaultModel
        status.stringValue = settings?.apiKey.isEmpty == false ? "A key is saved in Apple Keychain." : "No key is saved."
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

    private var selectedProvider: String { provider.indexOfSelectedItem == 1 ? "anthropic" : "openai" }
    private var defaultModel: String { selectedProvider == "anthropic" ? "claude-opus-5" : "gpt-5.6-terra" }

    @objc private func providerChanged() {
        if model.stringValue.isEmpty || ["gpt-5.6-terra", "claude-haiku-4-5", "claude-opus-5"].contains(model.stringValue) {
            model.stringValue = defaultModel
        }
        autosave()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        autosave()
    }

    private func autosave() {
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
    private let addButton = NSButton()
    private let addAddressButton = NSButton()
    private var answers: [[String: Any]] = []
    private var draftAnswer: [String: Any]?
    private var navigatingCells = false
    private static let answerTypes = ["", "address", "date", "gender", "phone"]
    private static let typeTitles = ["Auto", "Address", "Date", "Gender", "Phone"]

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
        table.addTableColumn(labelColumn)
        table.addTableColumn(valueColumn)
        table.addTableColumn(typeColumn)
        table.headerView = NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(beginInlineEditing)
        table.rowHeight = 24
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleTableKey(event) else { return event }
            return nil
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        addButton.title = "Add…"
        addButton.target = self
        addButton.action = #selector(addAnswer)
        addButton.bezelStyle = .rounded
        addAddressButton.title = "Add Address…"
        addAddressButton.target = self
        addAddressButton.action = #selector(addAddress)
        addAddressButton.bezelStyle = .rounded
        deleteButton.title = "Delete"
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.bezelStyle = .rounded
        deleteButton.isEnabled = false
        let clear = NSButton(title: "Clear All Answers…", target: self, action: #selector(clearAll))
        let buttons = NSStackView(views: [addButton, addAddressButton, deleteButton, NSView(), clear])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = paneStack(title: "Saved Data", description: "Double-click a label or value to edit; click a type to change it. Phone and Address use structured editors so Ume can fill related fields automatically.")
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
        deleteButton.isEnabled = answers.indices.contains(table.selectedRow)
        if !navigatingCells && draftAnswer != nil && table.selectedRow != answers.count && table.selectedRow >= 0 {
            discardEmptyDraft()
        }
    }

    private func discardEmptyDraft() {
        guard let draft = draftAnswer else { return }
        let label = (draft["userLabel"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (draft["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty && value.isEmpty {
            draftAnswer = nil
            table.reloadData()
        }
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
            startEditing(row: row, column: 0)
            return true
        default:
            return false
        }
    }

    private func startEditing(row: Int, column: Int) {
        guard displayedAnswers.indices.contains(row) else { return }
        let answer = displayedAnswers[row]
        let type = answer["answerType"] as? String ?? detectedType(answer)
        if column == 1, type == "address" {
            presentAddressEditor(row: row)
        } else if column == 1, type == "phone" {
            presentPhonePopover(row: row)
        } else if column == 1, type == "date" {
            presentDatePopover(row: row)
        } else {
            editCell(row: row, column: column)
        }
    }

    @objc private func beginInlineEditing() {
        let column = table.clickedColumn == 2 ? 0 : table.clickedColumn
        startEditing(row: table.clickedRow, column: column)
    }

    private func editCell(row: Int, column: Int) {
        guard displayedAnswers.indices.contains(row), column >= 0, column < table.numberOfColumns,
              let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView else { return }
        guard column < 2, let field = cell.textField else { return }
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
        if type == "address" {
            if currentType == "address" { return }
            table.reloadData()
            DispatchQueue.main.async { self.presentAddressEditor(row: row) }
            return
        }
        if currentType == "address" {
            NSSound.beep()
            table.reloadData()
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
            table.reloadData()
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

    private func present(_ controller: NSViewController, row: Int, column: Int = 1) {
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
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

    private func presentPhonePopover(row: Int) {
        guard let answer = answerForRow(row) else { return }
        let countryField = NSTextField()
        countryField.placeholderString = "e.g. 81"
        countryField.stringValue = answer["countryCode"] as? String ?? ""
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
            startEditing(row: row, column: 1)
        } else if row + 1 < displayedAnswers.count {
            view.window?.makeFirstResponder(nil)
            startEditing(row: row + 1, column: 0)
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
                    button.leadingAnchor.constraint(greaterThanOrEqualTo: cell.leadingAnchor),
                    button.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: 2),
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
        let value = valueString(answer["value"])
        guard detectedType(answer) == "phone",
              let code = answer["countryCode"] as? String else { return value }
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty else { return value }
        return value.isEmpty ? "+\(digits)" : "+\(digits) \(value)"
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertTab(_:)),
              let field = control as? NSTextField else { return false }
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
        guard let field = notification.object as? NSTextField,
              displayedAnswers.indices.contains(field.tag) else { return }
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

            let label = (draft["userLabel"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let value = (draft["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            field.isEditable = false
            if !label.isEmpty && !value.isEmpty {
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
                    table.selectRowIndexes(IndexSet(integer: answers.count - 1), byExtendingSelection: false)
                } catch {
                    present(error)
                }
            }
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
        guard draftAnswer == nil else { NSSound.beep(); return }
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

    @objc private func addAnswer() {
        guard draftAnswer == nil else { return }
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
            guard let cell = self.table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let field = cell.textField else { return }
            field.isEditable = true
            self.view.window?.makeFirstResponder(field)
        }
    }

    @objc private func deleteSelected() {
        let row = table.selectedRow
        guard answers.indices.contains(row), let id = answers[row]["answerID"] as? String else { NSSound.beep(); return }
        do { try AnswerStore.delete(id: id); reload() } catch { present(error) }
    }

    @objc private func clearAll() {
        let alert = NSAlert()
        alert.messageText = "Clear all saved answers?"
        alert.informativeText = "Your AI provider, model, and API key will be kept. This cannot be undone."
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
