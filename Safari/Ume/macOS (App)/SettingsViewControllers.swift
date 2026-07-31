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

private func paneStack(title: String, description: String) -> NSStackView {
    let stack = NSStackView(views: [titleLabel(title), descriptionLabel(description)])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 5
    stack.edgeInsets = NSEdgeInsets(top: 28, left: 30, bottom: 28, right: 30)
    stack.translatesAutoresizingMaskIntoConstraints = false
    return stack
}

final class SettingsTabViewController: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        transitionOptions = [.crossfade]
        addTabViewItem(item(GeneralSettingsViewController(), label: "General", image: "gearshape"))
        addTabViewItem(item(AISettingsViewController(), label: "AI Mapping", image: "sparkles"))
        addTabViewItem(item(SavedDataViewController(), label: "Saved Data", image: "tray.full"))
    }

    private func item(_ controller: NSViewController, label: String, image: String) -> NSTabViewItem {
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = symbol(image, fallback: label)
        return item
    }
}

final class GeneralSettingsViewController: NSViewController {
    private let stateLabel = descriptionLabel("Checking Safari extension status…")

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 500))
        let stack = paneStack(title: "General", description: "Manage Ume’s Safari extension and form-filling behavior.")
        let extensionTitle = NSTextField(labelWithString: "Safari Extension")
        extensionTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let openButton = NSButton(title: "Open Safari Settings…", target: self, action: #selector(openSafariSettings))
        openButton.bezelStyle = .rounded
        let extensionRow = NSStackView(views: [extensionTitle, stateLabel, openButton])
        extensionRow.orientation = .vertical
        extensionRow.alignment = .leading
        extensionRow.spacing = 7
        extensionRow.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        extensionRow.wantsLayer = true
        extensionRow.layer?.cornerRadius = 9
        extensionRow.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let behaviorTitle = NSTextField(labelWithString: "Private matching first")
        behaviorTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        let behavior = descriptionLabel("Ume matches fields on your device first. Your AI provider is contacted only for fields that cannot be matched confidently.")
        let behaviorRow = NSStackView(views: [behaviorTitle, behavior])
        behaviorRow.orientation = .vertical
        behaviorRow.alignment = .leading
        behaviorRow.spacing = 5
        behaviorRow.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        behaviorRow.wantsLayer = true
        behaviorRow.layer?.cornerRadius = 9
        behaviorRow.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        stack.addArrangedSubview(extensionRow)
        stack.addArrangedSubview(behaviorRow)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            extensionRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -60),
            behaviorRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -60)
        ])
        refreshState()
    }

    private func refreshState() {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { [weak self] state, _ in
            DispatchQueue.main.async {
                self?.stateLabel.stringValue = state?.isEnabled == true
                    ? "Ume is enabled and ready in Safari."
                    : "Ume is disabled. Enable it in Safari Settings → Extensions."
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
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 500))
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

        let stack = paneStack(title: "AI Mapping", description: "Used only when on-device matching cannot identify a field confidently.")
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
        view = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 500))
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
