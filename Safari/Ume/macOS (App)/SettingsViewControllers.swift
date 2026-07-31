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

private func settingsPaneView() -> NSView {
    let view = NSView(frame: NSRect(origin: .zero, size: settingsPaneSize))
    NSLayoutConstraint.activate([
        view.widthAnchor.constraint(greaterThanOrEqualToConstant: settingsPaneSize.width),
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: settingsPaneSize.height)
    ])
    return view
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
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/Safari.app"),
            configuration: configuration
        ) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
                    if error != nil {
                        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first?
                            .activate(options: [.activateAllWindows])
                    }
                }
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
        transitionOptions = [.crossfade]
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
        let stack = paneStack(title: "General", description: "Manage Ume’s Safari extension and form-filling behavior.")
        let extensionTitle = NSTextField(labelWithString: "Safari Extension")
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

        stack.addArrangedSubview(extensionRow)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            extensionRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -60),
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
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { _ in }
    }
}

final class AISettingsViewController: NSViewController, NSTextFieldDelegate {
    private let provider = NSPopUpButton()
    private let model = NSTextField()
    private let apiKey = NSSecureTextField()
    private let status = descriptionLabel("")

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

        let delete = NSButton(title: "Delete Saved Key", target: self, action: #selector(deleteKey))
        delete.bezelStyle = .rounded
        let buttons = NSStackView(views: [delete])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.distribution = .gravityAreas

        let stack = paneStack(title: "AI Provider", description: "Used only when on-device matching cannot identify a field confidently.")
        stack.spacing = 18
        stack.addArrangedSubview(form)
        stack.addArrangedSubview(status)
        stack.addArrangedSubview(buttons)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            form.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -60),
            status.widthAnchor.constraint(equalTo: form.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: form.widthAnchor)
        ])
        loadSettings()
    }

    private func loadSettings() {
        let settings = SettingsStore.load()
        provider.selectItem(at: settings?.provider == "anthropic" ? 1 : 0)
        model.stringValue = settings?.model ?? defaultModel
        status.stringValue = settings?.apiKey.isEmpty == false ? "A key is saved in Apple Keychain." : "No key is saved."
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

    @objc private func deleteKey() {
        SettingsStore.delete()
        loadSettings()
    }
}

final class SavedDataViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let table = NSTableView()
    private let summary = descriptionLabel("")
    private let deleteButton = NSButton()
    private var answers: [[String: Any]] = []

    override func loadView() {
        view = settingsPaneView()
        let labelColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("label"))
        labelColumn.title = "Label"
        labelColumn.width = 260
        let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))
        valueColumn.title = "Value"
        valueColumn.width = 340
        table.addTableColumn(labelColumn)
        table.addTableColumn(valueColumn)
        table.headerView = NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(beginInlineEditing)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        deleteButton.title = "Delete"
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.bezelStyle = .rounded
        deleteButton.isEnabled = false
        let clear = NSButton(title: "Clear All Answers…", target: self, action: #selector(clearAll))
        let buttons = NSStackView(views: [deleteButton, NSView(), clear])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = paneStack(title: "Saved Data", description: "Double-click any label or value to edit it. Changes save when you press Return or leave the field.")
        stack.addArrangedSubview(summary)
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
        summary.stringValue = answers.isEmpty ? "No saved answers." : "\(answers.count) saved answer\(answers.count == 1 ? "" : "s")."
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { answers.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        deleteButton.isEnabled = answers.indices.contains(table.selectedRow)
    }

    @objc private func beginInlineEditing() {
        let row = table.clickedRow
        let column = table.clickedColumn
        guard answers.indices.contains(row), column >= 0,
              let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        field.isEditable = true
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        view.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let answer = answers[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
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
            cell.textField?.stringValue = displayLabel(answer, row: row)
            cell.textField?.placeholderString = "Label"
        } else {
            cell.textField?.stringValue = valueString(answer["value"])
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

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              answers.indices.contains(field.tag),
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
